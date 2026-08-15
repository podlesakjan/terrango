# Fix afterEvaluate Regression and Re-apply minSdk Change

This plan fixes the recurring `afterEvaluate` error by applying the lifecycle check to the CMake configuration logic and ensures the `minSdk` is correctly set to 21.

## Proposed Changes

### Android Build Configuration

#### [MODIFY] [build.gradle.kts](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/build.gradle.kts)
- Wrap the CMake version configuration in a lifecycle-aware block, similar to the namespace fix. This prevents the `Cannot run Project.afterEvaluate(Action) when the project is already evaluated` error.

#### [MODIFY] [app/build.gradle.kts](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/android/app/build.gradle.kts)
- Re-apply `minSdk = 21` to satisfy the requirements of native plugins like `h3_flutter`.

## Verification Plan

### Manual Verification
- Run `flutter build apk`. The build should no longer fail with the `afterEvaluate` exception and should successfully compile native components using CMake 3.22.1.
