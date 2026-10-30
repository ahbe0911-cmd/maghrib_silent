# Maghrib Silent

Flutter + native Android starter project that calculates Maghrib with the Adhan Dart package and schedules Android DND activation/restoration.

Default coordinates: Minoudasht, Golestan, Iran (37.2289, 55.3725).

## Build

The GitHub Actions workflow at `.github/workflows/build-apk.yml` builds a release APK and uploads it as an artifact.

## Important limitations

- Enter coordinates for a location; the city field is a display label and does not geocode city names.
- Prayer-time calculation currently uses the device's local timezone. Set the phone timezone to the selected location.
- The current scheduler stores only a limited pair of upcoming Maghrib dates. Reopen the app to refresh scheduling. This starter is not yet an unattended indefinite daily scheduler.
- Android exact alarms and battery behavior vary by OS version and manufacturer. DND permission must be granted manually in Android settings.
- The app has not yet been validated on a physical device. Test before relying on it.

## Source layout

- `lib/main.dart`: Flutter UI and Adhan calculation
- `android/app/src/main`: native Android manifest, MethodChannel and alarm receivers
- `.github/workflows/build-apk.yml`: CI build
