# Flutter core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# printing
-keep class net.nfet.printing.** { *; }
-dontwarn net.nfet.printing.**

# google_sign_in
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Google Play Core (used by Play Core integrations)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# googleapis
-keep class com.google.api.services.drive.** { *; }
-dontwarn com.google.api.services.drive.**

# workmanager
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
-keep class be.tramckrijte.workmanager.** { *; }
-dontwarn be.tramckrijte.workmanager.**

# alarm manager
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }
-dontwarn dev.fluttercommunity.plus.androidalarmmanager.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# image_picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# saf
-keep class com.example.saf.** { *; }
-dontwarn com.example.saf.**

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# archive
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**

# إزالة التسجيل في release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable