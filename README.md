# Niyya - Flutter FFI + Miniaudio Integration Project

A Flutter project demonstrating FFI (Foreign Function Interface) integration with native C code on iOS, specifically designed for audio applications. This project includes file picker functionality and a complete FFI chain setup with miniaudio integration.

## 🎯 **Project Overview**
- Low latency audio playback using miniaudio
- Cross-platform support (iOS focus)
- Native audio performance through FFI
- File picker for audio files

## 📋 **Current Status**

✅ **WORKING:** Complete FFI chain (Flutter → Dart → C → Return)  
✅ **WORKING:** File picker for audio files  
✅ **WORKING:** iOS build and deployment (simulator and physical device)  
✅ **WORKING:** Miniaudio integration with CoreAudio backend  
✅ **WORKING:** Audio playback with proper lifecycle management

## 🔄 **Complete Step-by-Step Setup Guide**

### 1. **Project Setup**
```bash
flutter create your_project_name
cd your_project_name
```

### 2. **Add Dependencies**
Update `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  path: ^1.9.0
  file_picker: ^8.0.7

dev_dependencies:
  flutter_test:
    sdk: flutter
  ffigen: ^13.0.0
  flutter_lints: ^3.0.0
```

### 3. **iOS Configuration**
- Update `ios/Podfile` with Flutter CocoaPods setup
- Add files to Xcode project (native/*.c and native/*.h)  
- Configure Build Settings: Strip Style → "Non-Global Symbols"
- Add permissions to `ios/Runner/Info.plist`:
```xml
<key>NSDocumentPickerUsageDescription</key>
<string>This app needs access to files to select audio files for playback.</string>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

### 4. **Building and Running**

#### **Simulator Setup**
```bash
# Install pods
cd ios && pod install && cd ..

# Run on simulator
flutter run
```

#### **Simulator Testing Guide**

**Step 1: Find Your Simulator Device ID**
```bash
xcrun simctl list devices
```
Look for your running simulator (e.g., "iPhone 15 (E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF) (Booted)")

**Step 2: Add Test Audio Files to Simulator**
```bash
# Replace DEVICE_ID with your actual device ID
xcrun simctl addmedia E84AFBA4-AB0D-4EEE-9C13-5D7F0004BFFF ~/path/to/your/audio.wav
```

**Step 3: Verify File Access**
Files will be accessible in:
- **Files app → On My iPhone → [Your App Name]**
- **Files app → iCloud Drive** (if iCloud is enabled)
- **Documents directory** of your app

#### **Physical Device Deployment**

1. **Build Release Version**:
```bash
flutter build ios --release
```

2. **Install ios-deploy** (if not already installed):
```bash
npm install -g ios-deploy
```

3. **List Connected Devices**:
```bash
ios-deploy -c
```
This will show your connected iPhone with its ID (e.g., `00008110-000251422E02601E`)

4. **Deploy the Release Build**:
```bash
ios-deploy --bundle build/ios/iphoneos/Runner.app --id <YOUR_DEVICE_ID>
```
Replace `<YOUR_DEVICE_ID>` with your actual device ID from step 3.

**Note**: Make sure your iPhone is:
- Connected via USB
- Unlocked
- Trusts your development computer
- Has developer mode enabled in Settings → Privacy & Security → Developer Mode

## 🚨 **Common Issues & Solutions**

### 1. **iOS Integration Challenges**

#### **Foundation Framework Conflicts**
**Problem**: When integrating miniaudio library, iOS Foundation framework conflicts:
```
Parse Issue (Xcode): Could not build module 'Foundation'
Parse Issue (Xcode): Could not build module 'AVFoundation'
```

**Solution**: 
- Use `.mm` extension for Objective-C++ files
- Define `MA_NO_AVFOUNDATION` to disable AVFoundation
- Define `MA_NO_RUNTIME_LINKING` to disable runtime linking
- Use CoreAudio backend only

#### **Duplicate Symbol Errors**
**Problem**: Duplicate symbols when including miniaudio in multiple files.

**Solution**: 
- Only define `MINIAUDIO_IMPLEMENTATION` in one file (`miniaudio_wrapper.mm`)
- Use forward declarations in wrapper files
- Separate compilation units properly

### 2. **File Access Issues**

#### **File Picker iOS Permissions**
**Problem**: File picker not working without proper iOS permissions.

**Solution**: Added to `ios/Runner/Info.plist`:
```xml
<key>NSDocumentPickerUsageDescription</key>
<string>This app needs access to files to select audio files for playback.</string>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

### 3. **Build Issues**

#### **Podfile Configuration**
**Problem**: CocoaPods not installing Flutter plugins properly.

**Solution**: Updated `ios/Podfile` with proper Flutter configuration:
```ruby
platform :ios, '12.0'
# ... full Flutter podfile setup
flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
```

## 🛠️ **Technical Notes**

### FFI Type Mapping
- Dart `int` → C `int`
- Dart `bool` → C `int` (0=false, 1=true)
- String conversion requires manual memory management

### Symbol Visibility
C functions must be declared with proper visibility attributes for iOS:
```c
__attribute__((visibility("default"))) __attribute__((used))
int your_function_name() {
    // implementation
}
```

### Memory Management
Always free allocated memory for string conversions:
```dart
final Pointer<Int8> cString = malloc(utf8Bytes.length + 1).cast<Int8>();
try {
  // Use cString
} finally {
  free(cString.cast());
}
```

## Resources

- [Flutter FFI Documentation](https://dart.dev/guides/libraries/c-interop)
- [iOS FFI Integration Guide](https://docs.flutter.dev/platform-integration/ios/c-interop)
- [package:ffigen Documentation](https://pub.dev/packages/ffigen)
- [Miniaudio Library](https://github.com/mackron/miniaudio)
