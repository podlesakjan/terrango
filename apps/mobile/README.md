# Terrango Mobile

Flutter client for the Terrango geo-strategy game.

## Implemented Map Stack

- `mapbox_maps_flutter` as the tactical map renderer.
- `h3_flutter` for converting H3 indices into polygon vertices and GeoJSON layers.
- `geolocator` for GPS updates and active hex highlighting.
- `google_mobile_ads` for bottom banner monetization.

## Quick Start

1. Install Flutter dependencies.
2. Run tests.
3. Start the app on Android or iOS device/emulator.

```bash
flutter pub get
flutter test
flutter run
```

## Optional Runtime Overrides

You can override environment values with `--dart-define`:

```bash
flutter run --dart-define MAPBOX_ACCESS_TOKEN=<your_token>
flutter run --dart-define MAPBOX_DARK_STYLE_URI=mapbox://styles/mapbox/dark-v11
flutter run --dart-define ADMOB_BANNER_ANDROID_UNIT_ID=<android_banner_unit_id>
flutter run --dart-define ADMOB_BANNER_IOS_UNIT_ID=<ios_banner_unit_id>
```

## Native Setup Notes

- Android and iOS contain native Mapbox token entries for SDK bootstrap.
- Android and iOS contain location permission declarations.
- Android and iOS include AdMob application IDs using Google test values.
