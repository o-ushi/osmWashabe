package com.osamushikubo.osmWashabe

import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val TTS_CHANNEL        = "com.osamushikubo.osm_washabe/tts"
    private val VOICES_CHANNEL     = "com.osamushikubo.osm_washabe/speech_voices"
    private val SOUND_CHANNEL      = "com.osamushikubo.osm_washabe/system_sound"
    private val RINGTONE_CHANNEL   = "com.osamushikubo.osm_washabe/ringtones"
    private val AUDIO_CHANNEL      = "com.osamushikubo.osm_washabe/audio_utils"
    private val LOG_SHARE_CHANNEL  = "com.osamushikubo.osm_washabe/log_share"
    private val CRASH_LOG_FILE     = "osm_crash_log.txt"

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var japaneseAvailable = true

    // Currently active speak() call
    private var pendingResult: MethodChannel.Result? = null
    private var currentUtteranceId: String? = null
    private var activeCallbackEnabled = false

    // MediaPlayer for ringtone preview
    private var ringtonePlayer: MediaPlayer? = null

    private var offlineSpeechCapture: OfflineSpeechCapture? = null
    private var offlineSpeechProgressSink: EventChannel.EventSink? = null


    // TTS 初期化完了前に届いた speak リクエストをキューイングする。
    // 古いデバイスでは初期化に時間がかかる場合がある。
    private data class PendingSpeakRequest(
        val text: String,
        val gender: String,
        val rate: Float,
        val pitch: Float,
        val result: MethodChannel.Result,
    )
    private var pendingSpeak: PendingSpeakRequest? = null

    // Stored for pause→resume re-speech
    private var pausedText: String? = null
    private var pausedGender: String = "female"
    private var pausedRate: Float = 1.0f
    private var pausedPitch: Float = 1.0f

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // JVM レベルの未キャッチ例外（Error / Exception）をファイルに記録する。
        // JNI SIGSEGV はここでは捕捉できないが、OutOfMemoryError など Error 系は捕捉できる。
        val prevUncaught = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            saveNativeCrashLog(e)
            prevUncaught?.uncaughtException(thread, e)
        }

        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                // 日本語データが端末に入っているか確認
                val langResult = tts?.setLanguage(Locale.JAPANESE)
                japaneseAvailable = langResult != TextToSpeech.LANG_MISSING_DATA &&
                    langResult != TextToSpeech.LANG_NOT_SUPPORTED
                // AudioAttributes を明示しないと、一部端末（Samsung One UI など）で
                // TTS の出力ストリームが無音のストリームにルーティングされ、
                // コールバックは正常に発火するのに音だけ出ないことがある。
                try {
                    tts?.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                } catch (_: Exception) {}
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}

                    override fun onDone(utteranceId: String?) {
                        if (utteranceId == currentUtteranceId && activeCallbackEnabled) {
                            activeCallbackEnabled = false
                            pausedText = null
                            val r = pendingResult
                            pendingResult = null
                            currentUtteranceId = null
                            runOnUiThread { r?.success(true) }
                        }
                    }

                    @Deprecated("Deprecated in API 21")
                    override fun onError(utteranceId: String?) {
                        if (utteranceId == currentUtteranceId && activeCallbackEnabled) {
                            activeCallbackEnabled = false
                            pausedText = null
                            val r = pendingResult
                            pendingResult = null
                            currentUtteranceId = null
                            runOnUiThread { r?.success(false) }
                        }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        onError(utteranceId)
                    }
                })
                // 初期化前にキューイングされた speak リクエストを実行
                val pending = pendingSpeak
                pendingSpeak = null
                if (pending != null) {
                    runOnUiThread {
                        startSpeech(pending.text, pending.gender, pending.rate, pending.pitch, pending.result)
                    }
                }
            } else {
                // TTS エンジン初期化失敗 — キューイングされたリクエストを失敗として返す
                val pending = pendingSpeak
                pendingSpeak = null
                runOnUiThread { pending?.result?.success(false) }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureReady" -> {
                        if (ttsReady) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        val handler = Handler(Looper.getMainLooper())
                        var attempts = 0
                        val poll = object : Runnable {
                            override fun run() {
                                if (ttsReady) {
                                    result.success(true)
                                } else if (attempts++ < 80) {
                                    handler.postDelayed(this, 100)
                                } else {
                                    result.success(false)
                                }
                            }
                        }
                        handler.post(poll)
                    }
                    "speak" -> {
                        val args = call.arguments as? Map<*, *>
                        val text = args?.get("text") as? String
                        if (text == null) {
                            result.error("INVALID_ARGS", "text required", null)
                            return@setMethodCallHandler
                        }
                        val gender = args["gender"] as? String ?: "female"
                        val rate = ((args["rate"] as? Double) ?: 0.5).toFloat()
                        val pitch = ((args["pitch"] as? Double) ?: 1.0).toFloat()
                        startSpeech(text, gender, rate, pitch, result)
                    }
                    "stop" -> {
                        // キューイング中の初期化待ちリクエストもキャンセル
                        val queued = pendingSpeak
                        pendingSpeak = null
                        queued?.result?.success(false)
                        val prev = pendingResult
                        activeCallbackEnabled = false
                        pendingResult = null
                        currentUtteranceId = null
                        pausedText = null
                        tts?.stop()
                        prev?.success(false)
                        result.success(null)
                    }
                    "pause" -> {
                        // Android has no native pause: stop audio, hold pendingResult for resume
                        activeCallbackEnabled = false
                        tts?.stop()
                        result.success(null)
                    }
                    "resume" -> {
                        // Re-speak the paused chunk so Dart's await can complete
                        val text = pausedText
                        val prev = pendingResult
                        pendingResult = null
                        if (text != null && prev != null) {
                            startSpeech(text, pausedGender, pausedRate, pausedPitch, prev)
                        } else {
                            prev?.success(true)
                        }
                        result.success(null)
                    }
                    "openSettings" -> result.success(openTtsSettings())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getJapaneseVoices" -> result.success(japaneseVoiceList())
                    "getVoiceInfoForGender" -> {
                        val gender = call.arguments as? String ?: "female"
                        result.success(voiceInfoForGender(gender))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "play") {
                    playNotificationSound()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "muteForSttStart") {
                    muteForSttStart()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        offlineSpeechCapture = OfflineSpeechCapture(
            this,
            Handler(Looper.getMainLooper()),
        ) { progress ->
            offlineSpeechProgressSink?.success(progress)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OfflineSpeechCapture.CHANNEL,
        ).setMethodCallHandler { call, result ->
            offlineSpeechCapture?.handle(call, result) ?: result.notImplemented()
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OfflineSpeechCapture.PROGRESS_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                offlineSpeechProgressSink = events
            }

            override fun onCancel(arguments: Any?) {
                offlineSpeechProgressSink = null
            }
        })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRingtones" -> result.success(getAlarmRingtones())
                    "play" -> {
                        val uri = call.arguments as? String ?: run {
                            result.success(null); return@setMethodCallHandler
                        }
                        playRingtoneUri(uri)
                        result.success(null)
                    }
                    "stop" -> {
                        stopRingtonePlayer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareLog" -> {
                        val args = call.arguments as? Map<*, *>
                        val email = args?.get("email") as? String ?: ""
                        val content = args?.get("content") as? String ?: ""
                        val subject = args?.get("subject") as? String ?: "osmWashabe crash log"
                        val chooserTitle = args?.get("chooserTitle") as? String ?: "Send log"
                        val truncationPrefix = args?.get("truncationPrefix") as? String ?: "...(truncated)\n"
                        result.success(
                            shareLogText(email, content, subject, chooserTitle, truncationPrefix),
                        )
                    }
                    "getNativeCrashLog" -> {
                        result.success(readNativeCrashLog())
                    }
                    "clearNativeCrashLog" -> {
                        result.success(clearNativeCrashLog())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // SpeechRecognizer が listen() 開始時に鳴らすシステムビープを抑制する。
    // STREAM_MUSIC は TTS と共有するためミュートしない（TTS マスク＋認識精度維持）。
    private fun muteForSttStart() {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val streams = listOf(
            AudioManager.STREAM_NOTIFICATION,
            AudioManager.STREAM_SYSTEM,
        )
        for (stream in streams) {
            try { am.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0) } catch (_: Exception) {}
        }
        Handler(Looper.getMainLooper()).postDelayed({
            for (stream in streams) {
                try { am.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0) } catch (_: Exception) {}
            }
        }, 500)
    }

    private fun startSpeech(
        text: String,
        gender: String,
        rate: Float,
        pitch: Float,
        result: MethodChannel.Result,
    ) {
        if (!ttsReady || tts == null) {
            // TTS がまだ初期化中 — リクエストをキューイングして完了後に実行
            // 既存のキューがあればキャンセルして上書き
            pendingSpeak?.result?.success(false)
            pendingSpeak = PendingSpeakRequest(text, gender, rate, pitch, result)
            return
        }

        if (!japaneseAvailable) {
            // 日本語 TTS 未インストール — null を返してタイマーのみ開始させる
            // （Dart 側で null = 音声スキップとして扱い、タイマーは通常通り動作）
            result.success(null)
            return
        }

        // Abandon any in-flight result (stop() from Dart side precedes new speak(), but be safe)
        val prev = pendingResult
        activeCallbackEnabled = false
        tts?.stop()
        prev?.success(false)

        applyVoiceForGender(gender)

        // iOS rate 0.5 = normal; Android rate 1.0 = normal → multiply by 2
        tts?.setSpeechRate((rate * 2.0f).coerceIn(0.5f, 2.0f))
        // Android has no male voice; simulate with lower pitch
        val effectivePitch = if (gender == "male") 0.65f else pitch.coerceIn(0.5f, 2.0f)
        tts?.setPitch(effectivePitch)

        val uid = UUID.randomUUID().toString()
        currentUtteranceId = uid
        activeCallbackEnabled = true
        pendingResult = result
        pausedText = text
        pausedGender = gender
        pausedRate = rate
        pausedPitch = pitch

        // null params は全 API バージョンで安定して動作する（空 Bundle は一部端末で問題あり）
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, uid)
    }

    // 端末の「テキスト読み上げの出力」設定画面を開く（日本語音声データの追加・エンジン切替用）。
    private fun openTtsSettings(): Boolean {
        val intents = listOf(
            Intent("com.android.settings.TTS_SETTINGS"),
            Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (_: Exception) {}
        }
        return false
    }

    private fun applyVoiceForGender(gender: String) {
        val engine = tts ?: return
        try {
            val voices = engine.voices
            if (voices == null) {
                engine.language = Locale.JAPANESE
                return
            }

            // Prefer offline Japanese voices
            val jaLocal = voices.filter { it.locale.language == "ja" && !it.isNetworkConnectionRequired }
            val jaAll   = voices.filter { it.locale.language == "ja" }
            val pool    = jaLocal.ifEmpty { jaAll }

            if (pool.isEmpty()) {
                engine.language = Locale.JAPANESE
                return
            }

            val keywords = if (gender == "male") listOf("male", "man") else listOf("female", "woman")
            val matched = pool.firstOrNull { v -> keywords.any { v.name.lowercase().contains(it) } }
                ?: pool.first()

            try {
                engine.voice = matched
            } catch (_: Exception) {
                // voice 代入が失敗した場合（旧エンジン）は言語設定にフォールバック
                try { engine.language = Locale.JAPANESE } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            try { engine.language = Locale.JAPANESE } catch (_: Exception) {}
        }
    }

    private fun japaneseVoiceList(): List<Map<String, String>> {
        val engine = tts ?: return emptyList()
        return try {
            engine.voices
                ?.filter { it.locale.language == "ja" }
                ?.map { v ->
                    val lower = v.name.lowercase()
                    val g = when {
                        lower.contains("female") || lower.contains("woman") -> "female"
                        lower.contains("male")   || lower.contains("man")   -> "male"
                        else -> "unspecified"
                    }
                    mapOf(
                        "identifier" to v.name,
                        "name"       to v.name,
                        "locale"     to v.locale.toLanguageTag(),
                        "gender"     to g,
                        "quality"    to "default",
                    )
                } ?: emptyList()
        } catch (_: Exception) { emptyList() }
    }

    private fun voiceInfoForGender(gender: String): Map<String, String> {
        val engine = tts ?: return mapOf("name" to "Android TTS", "quality" to "default")
        return try {
            val voices = engine.voices?.filter { it.locale.language == "ja" }
            if (voices.isNullOrEmpty()) return mapOf("name" to "Android TTS", "quality" to "default")
            val keywords = if (gender == "male") listOf("male", "man") else listOf("female", "woman")
            val v = voices.firstOrNull { keywords.any { k -> it.name.lowercase().contains(k) } }
                ?: voices.first()
            mapOf("name" to v.name, "quality" to "default", "identifier" to v.name)
        } catch (_: Exception) {
            mapOf("name" to "Android TTS", "quality" to "default")
        }
    }

    private fun getAlarmRingtones(): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        try {
            val mgr = RingtoneManager(applicationContext)
            mgr.setType(RingtoneManager.TYPE_NOTIFICATION)
            val cursor = mgr.cursor
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri   = mgr.getRingtoneUri(cursor.position).toString()
                list.add(mapOf("uri" to uri, "title" to title))
            }
            cursor.close()
        } catch (_: Exception) {}
        return list
    }

    private fun playRingtoneUri(uriString: String) {
        stopRingtonePlayer()
        try {
            ringtonePlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(applicationContext, Uri.parse(uriString))
                setVolume(1.0f, 1.0f)
                prepare()
                setOnCompletionListener { mp ->
                    mp.release()
                    ringtonePlayer = null
                }
                start()
            }
        } catch (_: Exception) {
            ringtonePlayer = null
        }
    }

    private fun stopRingtonePlayer() {
        ringtonePlayer?.stop()
        ringtonePlayer?.release()
        ringtonePlayer = null
    }

    private fun playNotificationSound() {
        try {
            // ToneGenerator on STREAM_MUSIC matches TTS volume exactly
            val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
            toneGen.startTone(ToneGenerator.TONE_PROP_BEEP2, 700)
            Handler(Looper.getMainLooper()).postDelayed({ toneGen.release() }, 1200)
        } catch (_: Exception) {}
    }

    private fun saveNativeCrashLog(e: Throwable) {
        try {
            val file = File(filesDir, CRASH_LOG_FILE)
            val timestamp = java.time.Instant.now().toString().take(19)
            val lines = e.stackTraceToString().lines().take(30).joinToString("\n")
            val msg = "$timestamp === NATIVE CRASH ===\n${e}\n$lines\n$timestamp === END NATIVE CRASH ===\n"
            file.appendText(msg)
        } catch (_: Exception) {}
    }

    private fun readNativeCrashLog(): String {
        return try {
            val file = File(filesDir, CRASH_LOG_FILE)
            if (file.exists()) file.readText() else ""
        } catch (_: Exception) { "" }
    }

    private fun clearNativeCrashLog(): Boolean {
        return try {
            val file = File(filesDir, CRASH_LOG_FILE)
            !file.exists() || file.delete()
        } catch (_: Exception) { false }
    }

    private fun shareLogText(
        email: String,
        content: String,
        subject: String,
        chooserTitle: String,
        truncationPrefix: String,
    ): Boolean {
        val recipient = email.trim()
        if (recipient.isEmpty()) return false

        // 1) Gmail を Chooser なしで直接起動
        if (launchEmailComposer("com.google.android.gm", recipient, subject, content)) {
            return true
        }

        // 2) 他のメールアプリを順に試す
        val emailPackages = listOf(
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail",
            "com.samsung.android.email.provider",
        )
        for (pkg in emailPackages) {
            if (launchEmailComposer(pkg, recipient, subject, content)) {
                return true
            }
        }

        // 3) mailto: でメールアプリを起動（本文は短い場合のみ URI に含める）
        if (launchMailtoComposer(recipient, subject, content, truncationPrefix)) {
            return true
        }

        // 4) メール専用 Chooser（text/plain の汎用共有は使わない）
        return launchEmailChooser(recipient, subject, content, chooserTitle)
    }

    private fun buildEmailIntent(
        recipient: String,
        subject: String,
        content: String,
        packageName: String? = null,
    ): Intent =
        Intent(Intent.ACTION_SEND).apply {
            type = "message/rfc822"
            if (!packageName.isNullOrEmpty()) setPackage(packageName)
            putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, content)
        }

    private fun launchEmailComposer(
        packageName: String,
        recipient: String,
        subject: String,
        content: String,
    ): Boolean =
        try {
            startActivity(buildEmailIntent(recipient, subject, content, packageName))
            true
        } catch (_: Exception) {
            false
        }

    private fun launchMailtoComposer(
        recipient: String,
        subject: String,
        content: String,
        truncationPrefix: String = "...(truncated)\n",
    ): Boolean =
        try {
            // mailto URI は長さ制限があるため本文は最大 3500 文字
            val clipped = if (content.length > 3500) {
                truncationPrefix + content.takeLast(3500)
            } else {
                content
            }
            val uri = Uri.parse(
                "mailto:" + Uri.encode(recipient) +
                    "?subject=" + Uri.encode(subject) +
                    "&body=" + Uri.encode(clipped),
            )
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }

    private fun launchEmailChooser(
        recipient: String,
        subject: String,
        content: String,
        chooserTitle: String,
    ): Boolean =
        try {
            val emailIntent = buildEmailIntent(recipient, subject, content)
            startActivity(Intent.createChooser(emailIntent, chooserTitle))
            true
        } catch (_: Exception) {
            false
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        offlineSpeechCapture?.onRequestPermissionsResult(requestCode, grantResults)
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        pendingSpeak?.result?.success(false)
        pendingSpeak = null
        tts?.stop()
        tts?.shutdown()
        stopRingtonePlayer()
        offlineSpeechCapture?.dispose()
        offlineSpeechCapture = null
        offlineSpeechProgressSink = null
        super.onDestroy()
    }
}
