# Terrango mobile

Flutter client for the Terrango geo-MMO prototype.

## What is implemented

- 7 screens from `docs/mobile-screens.md`
- Dark futuristic theme and navigation shell
- Mocked game session state with onboarding, map, recruitment, barracks, bases, logs and profile
- API and real-time action shapes aligned with `docs/architecture.md`

## Run locally

```bash
cd /home/jan/AndroidStudioProjects/Terrango/apps/mobile
flutter pub get
flutter run
```

## Notes

- Mapbox, H3, BLE, GPS, ads and background-service packages are declared in `pubspec.yaml` so the project matches the target architecture.
- The current implementation uses a mock in-memory session controller so the UI is fully navigable without a backend.
- Server address is configured in `lib/config/app_config.dart` (`AppConfig.serverBaseUrl`).
