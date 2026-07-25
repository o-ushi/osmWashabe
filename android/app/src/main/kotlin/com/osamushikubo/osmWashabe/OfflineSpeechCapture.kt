package com.osamushikubo.osmWashabe

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min

/**
 * Android 採点用: 無音録音（16kHz mono WAV）→ まずオンラインの SpeechRecognizer に
 * 録音済みファイルを渡して文字起こしを試み、ダメなら Vosk オフライン文字起こしにフォールバック。
 * 録音そのものをリアルタイム STT にすると開始/終了のシステムビープが録音中に鳴ってしまうため、
 * 録音は無音のまま行い、SpeechRecognizer は録音停止後にファイル入力（EXTRA_AUDIO_SOURCE）で使う。
 * このタイミングのビープは処理待ち中に鳴るだけなので問題ない。
 */
class OfflineSpeechCapture(
    private val activity: FlutterActivity,
    private val handler: Handler,
    private val onTranscribeProgress: (Double) -> Unit,
) {
    companion object {
        const val CHANNEL = "com.osamushikubo.osm_washabe/offline_speech"
        const val PROGRESS_CHANNEL = "com.osamushikubo.osm_washabe/offline_speech_progress"
        private const val PERMISSION_REQUEST = 9101
        private const val SAMPLE_RATE = 16000
        private const val CHUNK_GAP_SECONDS = 1.5
        private const val ONLINE_RECOGNITION_TIMEOUT_MS = 15_000L
        private const val WAV_HEADER_BYTES = 44L
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val isRecording = AtomicBoolean(false)
    private var wavFile: File? = null
    private var wavWriter: WavWriter? = null

    private var cachedModelPath: String? = null
    private var cachedModel: Model? = null

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasRecordPermission" -> {
                result.success(hasRecordPermission())
            }
            "requestRecordPermission" -> {
                requestRecordPermission(result)
            }
            "startRecording" -> {
                startRecording(result)
            }
            "stopRecording" -> {
                stopRecording(result)
            }
            "cancelRecording" -> {
                cancelRecording()
                result.success(null)
            }
            "transcribe" -> {
                val args = call.arguments as? Map<*, *>
                val modelPath = args?.get("modelPath") as? String
                val wavPath = args?.get("wavPath") as? String
                if (modelPath.isNullOrBlank() || wavPath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "modelPath and wavPath required", null)
                    return
                }
                transcribeAsync(modelPath, wavPath, result)
            }
            "recognizeOnline" -> {
                val args = call.arguments as? Map<*, *>
                val wavPath = args?.get("wavPath") as? String
                if (wavPath.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "wavPath required", null)
                    return
                }
                recognizeOnline(wavPath, result)
            }
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ) {
        if (requestCode != PERMISSION_REQUEST) return
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        handler.post { pending?.success(granted) }
    }

    fun dispose() {
        cancelRecording()
        try {
            cachedModel?.close()
        } catch (_: Exception) {
        }
        cachedModel = null
        cachedModelPath = null
    }

    private fun hasRecordPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestRecordPermission(result: MethodChannel.Result) {
        if (hasRecordPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult?.error("CANCELLED", "superseded", null)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST,
        )
    }

    private fun startRecording(result: MethodChannel.Result) {
        if (!hasRecordPermission()) {
            result.error("PERMISSION_DENIED", "RECORD_AUDIO not granted", null)
            return
        }
        if (isRecording.get()) {
            result.success(true)
            return
        }

        cancelRecording()

        val file = File(activity.cacheDir, "osm_speech_${System.currentTimeMillis()}.wav")
        wavFile = file
        try {
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuffer <= 0) {
                result.error("AUDIO_INIT_FAILED", "getMinBufferSize failed", null)
                return
            }
            val bufferSize = minBuffer * 2
            val record = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                result.error("AUDIO_INIT_FAILED", "AudioRecord not initialized", null)
                return
            }

            val writer = WavWriter(file, SAMPLE_RATE)
            wavWriter = writer
            audioRecord = record
            isRecording.set(true)

            val thread = Thread {
                val buffer = ByteArray(bufferSize)
                record.startRecording()
                try {
                    while (isRecording.get()) {
                        val read = record.read(buffer, 0, buffer.size)
                        if (read > 0) {
                            writer.write(buffer, read)
                        } else if (read < 0) {
                            break
                        }
                    }
                } catch (_: Exception) {
                } finally {
                    try {
                        record.stop()
                    } catch (_: Exception) {
                    }
                    record.release()
                    try {
                        writer.close()
                    } catch (_: Exception) {
                    }
                }
            }
            recordingThread = thread
            thread.start()
            result.success(true)
        } catch (e: Exception) {
            cancelRecording()
            result.error("RECORDING_FAILED", e.message, null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        if (!isRecording.getAndSet(false)) {
            result.success(wavFile?.absolutePath)
            return
        }
        val thread = recordingThread
        val file = wavFile
        recordingThread = null
        audioRecord = null
        wavWriter = null
        Thread {
            try {
                thread?.join(3000)
            } catch (_: Exception) {
            }
            if (file != null) normalizeWav(file)
            handler.post {
                result.success(file?.absolutePath)
            }
        }.start()
    }

    // ピーク値を計測して -1 dBFS まで引き上げる。既に十分大きければそのまま。
    private fun normalizeWav(file: File) {
        if (!file.exists() || file.length() <= 44) return
        var peak = 0
        FileInputStream(file).use { input ->
            input.skip(44)
            val buf = ByteArray(8192)
            var read: Int
            while (input.read(buf).also { read = it } > 0) {
                var i = 0
                while (i + 1 < read) {
                    val lo = buf[i].toInt() and 0xff
                    val hi = buf[i + 1].toInt() shl 8
                    val s = ((lo or hi).toShort()).toInt()
                    val abs = if (s < 0) -s else s
                    if (abs > peak) peak = abs
                    i += 2
                }
            }
        }
        if (peak == 0) return
        val gain = 32440.0 / peak  // target ≈ −1 dBFS
        if (gain <= 1.0) return    // already loud enough
        val raf = RandomAccessFile(file, "rw")
        try {
            raf.seek(44)
            val buf = ByteArray(8192)
            var read: Int
            while (raf.read(buf).also { read = it } > 0) {
                val pos = raf.filePointer - read
                var i = 0
                while (i + 1 < read) {
                    val lo = buf[i].toInt() and 0xff
                    val hi = buf[i + 1].toInt() shl 8
                    val s = ((lo or hi).toShort()).toInt()
                    val boosted = (s * gain).toInt().coerceIn(-32768, 32767)
                    buf[i] = (boosted and 0xff).toByte()
                    buf[i + 1] = ((boosted shr 8) and 0xff).toByte()
                    i += 2
                }
                raf.seek(pos)
                raf.write(buf, 0, read)
            }
        } finally {
            raf.close()
        }
    }

    fun cancelRecording() {
        isRecording.set(false)
        val thread = recordingThread
        recordingThread = null
        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null
        try {
            wavWriter?.close()
        } catch (_: Exception) {
        }
        wavWriter = null
        try {
            thread?.join(1500)
        } catch (_: Exception) {
        }
        wavFile?.delete()
        wavFile = null
    }

    /**
     * 録音済み WAV を SpeechRecognizer に EXTRA_AUDIO_SOURCE 経由で渡し、
     * オンライン（端末内 or クラウド）認識を試みる。結果が取れなければ null を返し、
     * 呼び出し側（Dart）で Vosk オフライン文字起こしにフォールバックする。
     */
    private fun speechErrorName(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "ERROR_AUDIO"
        SpeechRecognizer.ERROR_CLIENT -> "ERROR_CLIENT"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "ERROR_INSUFFICIENT_PERMISSIONS"
        SpeechRecognizer.ERROR_NETWORK -> "ERROR_NETWORK"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ERROR_NETWORK_TIMEOUT"
        SpeechRecognizer.ERROR_NO_MATCH -> "ERROR_NO_MATCH"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "ERROR_RECOGNIZER_BUSY"
        SpeechRecognizer.ERROR_SERVER -> "ERROR_SERVER"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "ERROR_SPEECH_TIMEOUT"
        else -> "ERROR_UNKNOWN($error)"
    }

    private fun recognizeOnline(wavPath: String, result: MethodChannel.Result) {
        val wav = File(wavPath)
        if (!wav.exists() || wav.length() <= WAV_HEADER_BYTES) {
            result.success(mapOf("text" to null, "reason" to "invalid_wav"))
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            result.success(mapOf("text" to null, "reason" to "recognizer_unavailable"))
            return
        }

        handler.post {
            val recognizer = try {
                SpeechRecognizer.createSpeechRecognizer(activity)
            } catch (e: Exception) {
                result.success(mapOf("text" to null, "reason" to "create_failed:${e.message}"))
                return@post
            }

            var finished = false
            val watchdog = Handler(Looper.getMainLooper())
            var readEnd: ParcelFileDescriptor? = null

            fun finish(text: String?, reason: String? = null) {
                if (finished) return
                finished = true
                watchdog.removeCallbacksAndMessages(null)
                try {
                    recognizer.destroy()
                } catch (_: Exception) {
                }
                try {
                    readEnd?.close()
                } catch (_: Exception) {
                }
                result.success(mapOf("text" to text, "reason" to reason))
            }

            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle) {
                    val matches =
                        results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                    finish(text, if (text == null) "empty_result" else null)
                }

                override fun onError(error: Int) = finish(null, "recognizer_error:${speechErrorName(error)}")
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            val pipe = try {
                ParcelFileDescriptor.createPipe()
            } catch (e: Exception) {
                finish(null, "pipe_failed:${e.message}")
                return@post
            }
            readEnd = pipe[0]
            val writeEnd = pipe[1]

            Thread {
                try {
                    ParcelFileDescriptor.AutoCloseOutputStream(writeEnd).use { out ->
                        FileInputStream(wav).use { input ->
                            input.skip(WAV_HEADER_BYTES)
                            input.copyTo(out)
                        }
                    }
                } catch (_: Exception) {
                }
            }.start()

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ja-JP")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readEnd)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            }

            watchdog.postDelayed({ finish(null, "timeout") }, ONLINE_RECOGNITION_TIMEOUT_MS)

            try {
                recognizer.startListening(intent)
            } catch (e: Exception) {
                finish(null, "start_listening_failed:${e.message}")
            }
        }
    }

    private fun transcribeAsync(
        modelPath: String,
        wavPath: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val segments = transcribe(modelPath, wavPath)
                handler.post { result.success(segments) }
            } catch (e: Throwable) {
                handler.post {
                    result.error("TRANSCRIBE_FAILED", e.message ?: e.toString(), null)
                }
            }
        }.start()
    }

    private fun transcribe(modelPath: String, wavPath: String): List<Map<String, Any>> {
        val wav = File(wavPath)
        if (!wav.exists() || wav.length() <= 44) {
            return emptyList()
        }

        emitTranscribeProgress(2.0) // sentinel: model loading phase
        val model = loadModel(modelPath)
        val recognizer = Recognizer(model, SAMPLE_RATE.toFloat())
        val totalBytes = (wav.length() - 44).coerceAtLeast(1)
        var processedBytes = 0L
        emitTranscribeProgress(0.0)
        FileInputStream(wav).use { input ->
            val header = ByteArray(44)
            val headerRead = input.read(header)
            if (headerRead < 44) return emptyList()

            val byteBuffer = ByteArray(8192)
            val shortBuffer = ShortArray(4096)
            var read: Int
            while (input.read(byteBuffer).also { read = it } > 0) {
                val sampleCount = read / 2
                for (i in 0 until sampleCount) {
                    val lo = byteBuffer[i * 2].toInt() and 0xff
                    val hi = byteBuffer[i * 2 + 1].toInt() shl 8
                    shortBuffer[i] = (lo or hi).toShort()
                }
                recognizer.acceptWaveForm(shortBuffer, sampleCount)
                processedBytes += read
                val fraction =
                    (processedBytes.toDouble() / totalBytes.toDouble()).coerceIn(0.0, 1.0)
                emitTranscribeProgress(fraction)
            }
        }

        emitTranscribeProgress(1.0)

        val json = JSONObject(recognizer.finalResult)
        recognizer.close()
        return segmentsFromVoskJson(json)
    }

    private fun loadModel(modelPath: String): Model {
        if (cachedModel != null && cachedModelPath == modelPath) {
            return cachedModel!!
        }
        try {
            cachedModel?.close()
        } catch (_: Exception) {
        }
        val model = Model(modelPath)
        cachedModel = model
        cachedModelPath = modelPath
        return model
    }

    private fun segmentsFromVoskJson(json: JSONObject): List<Map<String, Any>> {
        val words = json.optJSONArray("result") ?: JSONArray()
        if (words.length() == 0) {
            val text = json.optString("text", "").trim()
            if (text.isEmpty()) return emptyList()
            return listOf(mapOf("text" to text, "startSec" to 0.0))
        }

        val segments = mutableListOf<Map<String, Any>>()
        var chunkText = StringBuilder()
        var chunkStart = -1.0
        var previousEnd = -1.0

        for (i in 0 until words.length()) {
            val wordObj = words.optJSONObject(i) ?: continue
            val word = wordObj.optString("word", "").trim()
            if (word.isEmpty()) continue
            val start = wordObj.optDouble("start", 0.0)
            val end = wordObj.optDouble("end", start)

            val gap = if (previousEnd < 0) 0.0 else start - previousEnd
            val shouldSplit = chunkText.isNotEmpty() && gap >= CHUNK_GAP_SECONDS

            if (shouldSplit) {
                segments.add(
                    mapOf(
                        "text" to chunkText.toString().trim(),
                        "startSec" to chunkStart,
                    ),
                )
                chunkText = StringBuilder()
                chunkStart = -1.0
            }

            if (chunkStart < 0) chunkStart = start
            if (chunkText.isNotEmpty()) chunkText.append(' ')
            chunkText.append(word)
            previousEnd = end
        }

        if (chunkText.isNotEmpty()) {
            segments.add(
                mapOf(
                    "text" to chunkText.toString().trim(),
                    "startSec" to if (chunkStart < 0) 0.0 else chunkStart,
                ),
            )
        }
        return segments
    }

    private fun emitTranscribeProgress(value: Double) {
        val clamped = value.coerceIn(0.0, 1.0)
        handler.post { onTranscribeProgress(clamped) }
    }

    private class WavWriter(file: File, private val sampleRate: Int) {
        private val stream = RandomAccessFile(file, "rw")
        private var dataBytes = 0

        init {
            stream.setLength(0)
            writeHeader(0)
        }

        fun write(buffer: ByteArray, length: Int) {
            stream.write(buffer, 0, length)
            dataBytes += length
        }

        fun close() {
            writeHeader(dataBytes)
            stream.close()
        }

        private fun writeHeader(dataSize: Int) {
            val totalDataLen = dataSize + 36
            val byteRate = sampleRate * 2
            stream.seek(0)
            stream.writeBytes("RIFF")
            stream.write(intLe(totalDataLen))
            stream.writeBytes("WAVE")
            stream.writeBytes("fmt ")
            stream.write(intLe(16))
            stream.write(shortLe(1))
            stream.write(shortLe(1)) // mono
            stream.write(intLe(sampleRate))
            stream.write(intLe(byteRate))
            stream.write(shortLe(2)) // block align
            stream.write(shortLe(16)) // bits per sample
            stream.writeBytes("data")
            stream.write(intLe(dataSize))
        }

        private fun intLe(value: Int): ByteArray {
            return byteArrayOf(
                (value and 0xff).toByte(),
                ((value shr 8) and 0xff).toByte(),
                ((value shr 16) and 0xff).toByte(),
                ((value shr 24) and 0xff).toByte(),
            )
        }

        private fun shortLe(value: Int): ByteArray {
            return byteArrayOf(
                (value and 0xff).toByte(),
                ((value shr 8) and 0xff).toByte(),
            )
        }
    }
}
