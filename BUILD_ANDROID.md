# SignBridge AI Android build

Package ID: `org.signbridge.app`
Minimum Android: API 23 (Android 6.0)
Current app version: 0.5.0+5

## Build prerequisites
- Flutter stable SDK
- Android SDK / Android Studio
- Java 17+

## Commands
```bash
flutter pub get
flutter analyze
flutter build apk --release
flutter build appbundle --release
```

The current release block intentionally uses the debug signing key for local MVP testing only. Before Google Play publication, configure a private upload keystore / Play App Signing and remove debug signing from the release build.

## Privacy / permissions
The manifest declares microphone and camera permissions for planned speech/image translation. Runtime permission prompts must only be shown when the user invokes those features.

## Sign-language safety
The bundled translation content remains a technical prototype. Do not label unreviewed motions as verified Palestinian Sign Language.
