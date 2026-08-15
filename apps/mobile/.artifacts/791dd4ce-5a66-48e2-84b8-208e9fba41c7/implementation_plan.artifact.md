# Upgrade Versions and Fix NDK Build Failure

This plan re-applies the Gradle, AGP, and Kotlin upgrades as you've confirmed you have an internet connection. It also fixes the `[CXX1110]` NDK platform version error.

## User Review Required

> [!IMPORTANT]
> Since your `flutter build apk` encountered a `java.net.UnknownHostException: services.gradle.org`, please ensure that your terminal or Android Studio has permission to access the internet and that there are no proxy or DNS issues preventing Gradle from downloading the new distributions.

## Proposed Changes

### Android Build Configuration

#### [MODIFY] [gradle-wrapper.properties](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/gradle/wrapper/gradle-wrapper.properties)
- Upgrade `distributionUrl` to use Gradle 8.14.0.

#### [MODIFY] [settings.gradle.kts](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/settings.gradle.kts)
- Upgrade `com.android.application` to version `8.11.1`.
- Upgrade `org.jetbrains.kotlin.android` to version `2.2.20`.

#### [MODIFY] [gradle.properties](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/gradle.properties)
- Add `android.ndk.suppressMinSdkVersionError=21` to suppress the NDK platform version error.

#### [MODIFY] [app/build.gradle.kts](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/app/build.gradle.kts)
- Ensure `minSdk` is at least 21 to satisfy modern NDK requirements (e.g., from `h3_flutter`).

## Verification Plan

### Manual Verification
- Run `flutter build apk`. The upgrades should download, the `afterEvaluate` error should not occur, and the NDK `minSdk` error should be resolved.
