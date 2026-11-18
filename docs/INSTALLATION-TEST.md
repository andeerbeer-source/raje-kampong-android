# Android APK installation checks

The GitHub Actions workflow now verifies the release APK metadata and signature, then installs and launches it on an Android API 35 emulator before uploading the APK artifact.

The Android debug signing keystore is cached between workflow runs so builds from this repository can retain a consistent signing certificate while the cache remains available.

Minimum supported Android version configured by the workflow: Android 6.0 (API 23).

Application ID: `id.go.beltim.dprd.rajekampong`.
