# Development setup

## Dev container (recommended)
Use the provided dev container (`.devcontainer/`). Flutter, the Android SDK, `protoc` and `protoc-gen-dart` are pre-installed, and `postCreateCommand` applies the Flutter config below.

If you are **not** using the dev container, run this once after cloning to prevent Flutter from listing Linux as a target device:

```sh
flutter config --no-enable-linux-desktop
```

This setting is user-level (`~/.config/flutter/settings`) — there is no project-level equivalent.

## Running on Android (wireless debugging)
The dev container has no USB passthrough, so use ADB over Wi-Fi.

1.  On the phone, enable **Developer options → Wireless debugging** and tap **Pair device with pairing code**.
2.  In the terminal, pair once using the pairing port and code shown on the phone:
    ```sh
    adb pair <phone-ip>:<pairing-port>
    ```
3.  Connect using the main wireless debugging port (different from the pairing port, also shown on the phone):
    ```sh
    adb connect <phone-ip>:<port>
    ```
4.  Verify the device is listed:
    ```sh
    flutter devices
    ```
5.  Run the app:
    ```sh
    flutter run
    ```

The pairing step (1–2) is only needed once per network session. The `adb connect` (3) must be repeated each time the dev container restarts.

## Native Windows setup (optional)
While the dev container is recommended, you can set up a local Windows environment directly:

1.  **Android Studio:** download and install [Android Studio](https://developer.android.com/studio).
2.  **Android SDK:** open Android Studio's SDK Manager and install:
    *   Android SDK Platform 36
    *   Android SDK Build-Tools 36.0.0
    *   Android SDK Command-line Tools (latest)
3.  **Flutter SDK:** download the version pinned in `.flutter-version` (currently `3.41.6`) from [flutter.dev](https://docs.flutter.dev/release/archive) or clone it via git. Extract it (e.g. to `C:\flutter`) and add `C:\flutter\bin` to your system `PATH`.
4.  **Java JDK:** Java 21 is required. If Android Studio's bundled JDK is not Java 21, install OpenJDK 21 manually.
5.  **Protoc plugin:** install the Dart protocol buffers plugin globally:
    ```powershell
    dart pub global activate protoc_plugin 21.1.2
    ```
    Add your pub-cache bin to your system `PATH` if it isn't already (e.g. `C:\Users\<user>\AppData\Local\Pub\Cache\bin`).
