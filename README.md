## Download APK

A pre-built APK is available in the [Releases](https://github.com/Tardirisu/SafeScan-adb-otg/releases) section.

The current release is intended for testing and demonstration purposes.

## Setup & Compile

To build and run this Flutter project locally:

### 1. Clone the repository
```bash
git clone https://github.com/Tardirisu/SafeScan-adb-otg.git
cd SafeScan-adb-otg
```

### 2. Clean previous builds
```bash
flutter clean
```

### 3. Get dependencies
```bash
flutter pub get
```

### 4. Build APK

You can also download the pre-built APK from the [Releases](https://github.com/Tardirisu/SafeScan-adb-otg/releases) section.

```bash
flutter build apk
```

APK will be generated at:
```text
build/app/outputs/flutter-apk/app-release.apk
```

### 5. Run on a connected device
```bash
flutter run
```

You will be prompted to select a connected device or emulator.

**USB Host Mode Requirement**  
When connecting, make sure the target device’s USB settings choose **“controlled by → this device”**.

### 6. Exporting Debug Logs

This project mainly uses the following log tags: **ADB_OTG** and **ADB_DEBUG**.  
When debugging, you can filter these tags and export the logs to a file using the commands below.

### Method 1: Specify tags directly
```bash
adb logcat -s ADB_OTG ADB_DEBUG > logs.txt
```

This command captures only logs with the `ADB_OTG` and `ADB_DEBUG` tags and writes them to `logs.txt`.

---

### Method 2: Use grep for filtering
```bash
adb logcat | grep -E "ADB_OTG|ADB_DEBUG" > logs.txt
```

This command captures all logs and then filters only those containing `ADB_OTG` or `ADB_DEBUG`, writing them to `logs.txt`.

## Development Environment

This project was developed and tested with:

- **Flutter**: `3.32.1-0.0.pre.41`
  - Channel: `stable`
  - Dart: `3.8.0`
  - DevTools: `2.45.1`
- **Java**: `Java 21.0.2 (LTS)`
  - Vendor: Oracle
  - Build: `21.0.2+13-LTS-58`

## Project Structure & Dependencies

- **Frontend** (Flutter UI):  
  Located in the [lib/](lib) directory. Contains all UI pages and Dart code for communication via platform channels.

- **Backend** (Android native logic):  
  Located in [android/app/src/main/java/com/htetznaing/adbotg](android/app/src/main/java/com/htetznaing/adbotg).  
  Handles USB permission requests, ADB communication, and device management through Java code.

This project is built upon and inspired by the following open-source projects:

- [KhunHtetzNaing/ADB-OTG](https://github.com/KhunHtetzNaing/ADB-OTG)
- [cgutman/AdbLib](https://github.com/cgutman/AdbLib)

* **Current Progress & Next Steps**
  • Connection and scanning via ADB-OTG are fully implemented.
  • We’re now migrating additional ADB-SafeScan features into this codebase, and adding wireless connection & scan support through Termux.
