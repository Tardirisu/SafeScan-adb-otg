
##  Setup & Compile
To build and run this Flutter project locally:

### 1. Clone the repository
```bash
git clone https://github.com/Tardirisu/SafeScan-adb-otg.git
cd test connect

````

### 2. Clean previous builds

```bash
flutter clean
```

### 3. Get dependencies

```bash
flutter pub get
```

### 4. Build APK

```bash
flutter build apk
```

APK will be generated at:

```
build/app/outputs/flutter-apk/app-release.apk
```

### 5. Run on a connected device

```bash
flutter run
```
You will be prompted to select a connected device or emulator.

**USB Host Mode Requirement**
  When connecting, make sure the target device’s USB settings choose **“controlled by → this device”** .


## Development Environment

This project was developed and tested with:

* **Flutter**: `3.32.1-0.0.pre.41`

  * Channel: `stable`
  * Dart: `3.8.0`
  * DevTools: `2.45.1`
* **Java**: `Java 21.0.2 (LTS)`

  * Vendor: Oracle
  * Build: `21.0.2+13-LTS-58`
    

 ## Project Structure & Dependencies

- **Frontend** (Flutter UI):  
  Located in the [`lib/`](lib) directory. Contains all UI pages and Dart code for communication via platform channels.

- **Backend** (Android native logic):  
  Located in [`android/app/src/main/java/com/htetznaing/adbotg`](android/app/src/main/java/com/htetznaing/adbotg).  
  Handles USB permission requests, ADB communication, and device management through Java code.

This project is built upon and inspired by the following open-source projects:

- [KhunHtetzNaing/ADB-OTG](https://github.com/KhunHtetzNaing/ADB-OTG)  
- [cgutman/AdbLib](https://github.com/cgutman/AdbLib)


* **Current Progress & Next Steps**
  • Connection and scanning via ADB-OTG are fully implemented.
  • We’re now migrating additional ADB-SafeScan features into this codebase, and adding wireless connection & scan support through Termux.
