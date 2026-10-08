# Release (R8) keep rules. Picked up automatically by the Flutter Gradle plugin.

# google_mobile_ads pulls in androidx.work (WorkManager), whose Room database
# implementation (WorkDatabase_Impl) is instantiated reflectively at startup.
# Without these rules R8 strips it and the release app crashes on launch with
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# region WP-5b — versus backend (PRD-2 §3.13): Firebase Auth / Firestore /
# App Check / Functions. The FlutterFire plugins ship consumer rules; these
# cover what R8 still trips over in Firestore's gRPC + protobuf-lite stack,
# the Play Games auth provider and Play Integrity.
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class com.google.firestore.v1.** { *; }
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.firebase.functions.** { *; }
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.games.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn org.checkerframework.**
-dontwarn javax.annotation.**
-dontwarn com.squareup.okhttp.**
# endregion WP-5b
