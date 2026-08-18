# Fix API Base URL Normalization

The app is failing to register users with the error `Cannot POST /api/v1auth/register`. This is caused by a missing slash between the base URL (`.../api/v1`) and the endpoint path (`auth/register`).

## User Review Required

> [!IMPORTANT]
> This change modifies how the API base URL is normalized. It will now ensure that the base URL always ends with a trailing slash, which is the expected format for the Dio HTTP client when using relative paths for endpoints.

## Proposed Changes

### Core Configuration

#### [MODIFY] [app_config.dart](file:///home/jan/AndroidStudioProjects/Terrango/apps/mobile/lib/core/config/app_config.dart)
Update `_normalizeApiBaseUrl` to ensure the returned URL always ends with a slash.

## Verification Plan

### Manual Verification
- I will check the `AppConfig` logic to ensure it correctly handles various input formats:
    - `https://example.com` -> `https://example.com/api/v1/`
    - `https://example.com/` -> `https://example.com/api/v1/`
    - `https://example.com/api` -> `https://example.com/api/v1/`
    - `https://example.com/api/v1` -> `https://example.com/api/v1/`
- Since I cannot run the Flutter app directly to trigger a network request, I will rely on code analysis and potentially a small scratch script if needed to verify the normalization logic.
