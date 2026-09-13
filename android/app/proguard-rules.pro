# Release builds run R8 (isMinifyEnabled + isShrinkResources in build.gradle.kts),
# so anything reached only by reflection needs a keep rule here.

# --- flutter_local_notifications: scheduled reminders ("صفحة اليوم") ---
#
# A scheduled notification is stored as JSON in shared preferences and read back
# by ScheduledNotificationReceiver when the alarm fires:
#
#     Type type = new TypeToken<NotificationDetails>() {}.getType();
#
# TypeToken recovers <NotificationDetails> from the anonymous subclass's generic
# signature. R8 drops the Signature attribute by default, so the lookup throws
#
#     java.lang.RuntimeException: Missing type parameter.
#
# inside onReceive — which crashes the app the moment a reminder fires, in
# release builds only, with the app in the background. (Seen on a Galaxy S7 /
# Android 8; the plugin ships no consumer-rules.pro of its own.)
#
# Signature is the rule that fixes the crash. The rest keep Gson able to map
# JSON back onto the plugin's model classes: without them R8 renames the fields
# and enum constants, and every scheduled notification quietly deserializes to
# nulls instead of throwing.
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
