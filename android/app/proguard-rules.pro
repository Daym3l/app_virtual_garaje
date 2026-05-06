# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components — clases opcionales, suprimir warnings R8)
-dontwarn com.google.android.play.core.**

# Supabase / OkHttp / Kotlin
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn okhttp3.**
-dontwarn okio.**

# Google Sign-In
-keep class com.google.android.gms.** { *; }

# Firebase / FCM
-keep class com.google.firebase.** { *; }
