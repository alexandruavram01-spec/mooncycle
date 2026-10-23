# Rules for the release optimiser (R8), which shrinks the Play build.
#
# flutter_local_notifications (reminders) stores scheduled reminders with
# Gson, which needs generic type information that R8 removes by default.
# Without these rules every reminder call failed in the Play build with
# "Missing type parameter", and because saving a day reschedules reminders,
# Save looked broken. Taken from the plugin's release setup notes.

-keep class com.dexterous.** { *; }

## Gson
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

## Google sign-in (Credential Manager)
# Credential Manager finds Google's sign-in provider at run time. Without this
# rule R8 removes it from the Play build, and Continue with Google closed
# without doing anything. From Android's Credential Manager setup notes.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
