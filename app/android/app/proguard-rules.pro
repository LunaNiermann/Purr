# Flutter's own rules cover the engine; these keep plugins that use
# reflection / JNI from being stripped by R8.

# local_auth / BiometricPrompt
-keep class androidx.biometric.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# mobile_scanner (ML Kit / CameraX)
-keep class com.google.mlkit.** { *; }
-keep class androidx.camera.** { *; }

# Keep annotations used by the above
-keepattributes *Annotation*

# Tink (used by EncryptedSharedPreferences under flutter_secure_storage)
-keep class com.google.crypto.tink.** { *; }
