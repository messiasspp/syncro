# Keep device_calendar Gson models and recurrence classes from R8 obfuscation in release builds
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class org.dmfs.rfc5545.** { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod
