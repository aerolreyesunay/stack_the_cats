# Extra rules for the release build's code shrinker (R8).

# Google Mobile Ads uses WorkManager, which creates its Room database by
# reflection. Without these, the shrinker removes it and the release app
# crashes at startup ("Failed to create an instance of WorkDatabase").
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
