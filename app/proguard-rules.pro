# Zachowaj nazwy parametrów i metadane refleksji Kotlin dla bezpiecznej serializacji/korutyn
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations

# Pakiet aplikacji pl.tomaszewski.aiweb
-keep class pl.tomaszewski.aiweb.** { *; }

# OkHttp 4 & Okio
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Kotlin Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.coroutines.** {
    volatile <fields>;
}

# AndroidX / WebView
-dontwarn androidx.webkit.**
-keep class androidx.webkit.** { *; }
