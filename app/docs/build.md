# Building and Environment Configuration

This document outlines the process for building the Fortuned app for different environments (`stage` and `prod`), with a focus on how deep linking domains are configured for each platform.

## iOS Builds

For iOS, the environment is controlled entirely by the `run-ios.sh` script.

### Usage

To build and run for a specific environment, use the following commands from the `app/` directory:

```bash
# Build for the staging environment
./run-ios.sh stage

# Build for the production environment
./run-ios.sh prod
```

### How It Works

The script automatically handles two key configurations based on the environment argument:

1.  **API Environment:** It copies the correct `.env` file (`.stage.env` or `.prod.env`) to `.env`, which the app uses to determine the backend URL.
2.  **Deep Link Domain:** It copies the correct entitlements file to `ios/Runner/Runner.entitlements`. This file configures the domain used for Universal Links (deep linking).
    *   **stage:** Uses `ios/Runner/Runner.entitlements.stage` which sets the domain to `applinks:devtest.4tnd.link`.
    *   **prod:** Uses `ios/Runner/Runner.entitlements.prod` which sets the domain to `applinks:4tnd.link`.

### One-Time Xcode Setup

For Universal Links to work correctly, the "Associated Domains" capability must be enabled in the Xcode project. This is a one-time setup:

1.  Open `ios/Runner.xcworkspace` in Xcode.
2.  Select the `Runner` target in the project navigator.
3.  Go to the **Signing & Capabilities** tab.
4.  Click **+ Capability** and add **Associated Domains**.
5.  Ensure the `Runner.entitlements` file is correctly referenced by Xcode.

---

## Android Builds

For Android, environments are managed using **Product Flavors**, which is the standard Android practice. This makes it easy to build from either the command line or directly within Android Studio.

### Building from Android Studio (Recommended)

This is the simplest method:

1.  Open the `android/` directory of the project in Android Studio.
2.  Wait for Gradle to sync.
3.  On the left side of the window, open the **Build Variants** tool window.
4.  In the `active build variant` column for the `:app` module, you will see a dropdown menu. Use this to select the desired environment and build type. The most common variants are:
    *   `prodDebug` (Production environment, debuggable)
    *   `stageDebug` (Staging environment, debuggable)
    *   `prodRelease` (Production environment, for release)
    *   `stageRelease` (Staging environment, for release)
5.  Click the **Run** button (the green play icon) to build and deploy the selected variant to your connected device or emulator.

### How It Works

The `app/android/app/build.gradle.kts` file defines two `productFlavors`: `prod` and `stage`. Each flavor defines a `manifestPlaceholders` variable named `appHost`:

*   **prod flavor:** sets `appHost` to `4tnd.link`
*   **stage flavor:** sets `appHost` to `devtest.4tnd.link`

The `AndroidManifest.xml` uses this placeholder (`${appHost}`) to set the deep link URL at build time, ensuring the correct domain is used for the chosen flavor.

### Building from the Command Line

You can also build specific flavors using the `flutter` command with the `--flavor` flag:

```bash
# Build and run the staging version
flutter run --flavor stage

# Build a release APK for production
flutter build apk --flavor prod
```
