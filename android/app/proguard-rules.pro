# Vosk が依存する JNA のフィールドを R8 に削除させない
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }

# JNA が参照する AWT クラスは Android 未搭載のため警告を抑制
-dontwarn java.awt.Component
-dontwarn java.awt.GraphicsEnvironment
-dontwarn java.awt.HeadlessException
-dontwarn java.awt.Window

# Vosk クラスは Kotlin から直接呼ぶだけでなく、ネイティブ側から JNI 経由で
# Recognizer/Model にコールバックするため、R8 のリネーム/削除対象から外す。
-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { *; }
