# Keep source/line info useful for crash reporting
-keepattributes SourceFile,LineNumberTable

# Keep Flutter plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep names used by JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enum methods used by reflection/serialization in some libs
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep public class com.google.android.gms.ads.** {
   public *;
}

# ML Kit Barcode Scanning (used by mobile_scanner unbundled variant)
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }

# In App Purchase (BillingClient)
-keep class com.android.billingclient.api.** { *; }

# Flutter Play Store Deferred Components (Missing classes ignore)
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn com.google.android.play.core.tasks.**
