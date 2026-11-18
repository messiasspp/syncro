# Keep device_calendar Gson models and recurrence classes from R8 obfuscation in release builds
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class org.dmfs.rfc5545.** { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod

# Keep Google Play Services Auth classes in release builds
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
