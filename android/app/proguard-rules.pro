# Release (R8) keep rules. Picked up automatically by the Flutter Gradle plugin.

# google_mobile_ads pulls in androidx.work (WorkManager), whose Room database
# implementation (WorkDatabase_Impl) is instantiated reflectively at startup.
# Without these rules R8 strips it and the release app crashes on launch with
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
