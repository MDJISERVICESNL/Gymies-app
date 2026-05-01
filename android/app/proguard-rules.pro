# ──────────────────────────────────────────────────────────────
# Gymies App — ProGuard/R8 Rules
# ──────────────────────────────────────────────────────────────

# ── Flutter Engine ────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── Firebase ──────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Firebase Messaging ────────────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }

# ── OkHttp / Retrofit (indien gebruikt door plugins) ─────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# ── Gson (used by Firebase and various plugins) ──────────────
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# ── Kotlin ────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── AndroidX ──────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**

# ── Geolocator ────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ── Permission Handler ────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── Image Picker ──────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }

# ── WebView ───────────────────────────────────────────────────
-keep class io.flutter.plugins.webviewflutter.** { *; }

# ── Mobile Scanner (ML Kit Barcode) ──────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# ── Secure Storage ────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ── Flutter Local Notifications ──────────────────────────────
-keep class com.dexterous.** { *; }

# ── Share Plus ────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }

# ── Mollie Payment (WebView-based) ───────────────────────────
# Mollie SDK classes (als ze via native zijn geïntegreerd)
-keep class com.mollie.** { *; }
-dontwarn com.mollie.**

# ── General Rules ─────────────────────────────────────────────
# Prevent stripping of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Preserve annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses,EnclosingMethod

# ── UX packages ──────────────────────────────────────────────
# connectivity_plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# local_auth (biometrics)
-keep class io.flutter.plugins.localauth.** { *; }

# in_app_review
-keep class dev.britannio.in_app_review.** { *; }

# dynamic_color (Material You)
-keep class io.material.** { *; }

# shimmer
-keep class com.aagarwal.shimmer.** { *; }

# AndroidX Core (WindowCompat, edge-to-edge)
-keep class androidx.core.view.** { *; }
