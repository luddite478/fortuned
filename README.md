# Niyya

A Flutter project with iOS deployment instructions.

## Development Setup

### Prerequisites
- Flutter SDK
- Xcode
- iOS Simulator (for development)
- Apple Developer account (for physical device deployment)
- Homebrew (for installing additional tools)

### Initial Setup
1. Clone the repository
2. Run `flutter pub get` to install dependencies

## Running on iOS Simulator

1. Open iOS Simulator:
   ```bash
   open -a Simulator
   ```

2. Run the app in debug mode:
   ```bash
   flutter run
   ```

## Deploying to Physical iOS Device

### One-time Setup
1. Install ios-deploy tool:
   ```bash
   brew install ios-deploy
   ```

2. Open the Xcode workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```

3. In Xcode:
   - Select your development team
   - Update bundle identifier (e.g., from com.example.niyya to com.your.name)
   - Trust the development certificate on your iPhone (Settings > General > Device Management)

### Deployment Steps
1. Connect your iPhone via USB

2. Build release version:
   ```bash
   flutter build ios --release
   ```

3. Install on device:
   ```bash
   ios-deploy --bundle build/ios/iphoneos/Runner.app
   ```

### Troubleshooting
- If the app doesn't install, make sure your iPhone is unlocked and trusted
- Verify your development team is properly set in Xcode
- Check that your device is recognized by running `flutter devices`

## Additional Resources

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
