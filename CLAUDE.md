# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter Android app that reads a parcel/shipping label with the camera, extracts the tracking ID, carton count, and delivery address, generates a new label with a re-formatted tracking number + QR code, and prints it to an HPRT HM-T3 Pro thermal printer over Bluetooth Classic. Built primarily for Android — there is no maintained iOS path (Bluetooth Classic SPP is unavailable to non-MFi iOS apps).

## Commands

```bash
flutter pub get                              # install dependencies
flutter analyze                              # lint (flutter_lints rules)
flutter build apk --debug --no-tree-shake-icons   # build installable debug APK
flutter test                                 # run tests (no test files exist yet)
flutter run                                  # run on a connected device
```

Debug APK output: `build/app/outputs/flutter-apk/app-debug.apk`. The release build type reuses the debug signing config, so `--debug` and `--release` are both installable without a keystore.

CI (`.github/workflows/build.yml`) builds the debug APK on every push to `main`/`master` and uploads it as the `parcel-scanner-debug` artifact. Flutter 3.19.0, Java 17.

Toolchain is pinned: AGP 8.1.0, Gradle 8.3, Kotlin 1.9.10, `compileSdk`/`targetSdk` 34, `minSdk` 21. `android/build.gradle` has a defensive `subprojects` block that forces `compileSdkVersion 34` on any plugin subproject that lacks one — keep it; some plugins rely on it.

## Architecture

### Screen flow (linear `Navigator` stack)

`HomeScreen` → `ScanScreen` → `ReviewScreen` → `LabelScreen`, with `SettingsScreen` reachable from Home. `ScanScreen` → `ReviewScreen` uses `pushReplacement` so Back returns to Home. All screens live in `lib/screens/`.

### State

There is no state management library. The single `SharedPreferences` instance is created in `main.dart` and passed by constructor into every screen — it is the app's global config store. Keys:

- `prefix` — string prepended to every tracking number
- `selected_ai` — `ocr` | `gemini` | `claude` (label-reading engine)
- `gemini_api_key`, `claude_api_key` — API keys for the AI engines
- `printer_address` — last-connected Bluetooth device address (MAC)

### Label-reading pipeline

Three interchangeable engines extract the same fields (TID, carton current/total, address lines) from a captured/gallery image. `ScanScreen._processFile` dispatches on the `selected_ai` pref:

- `OcrService` (`ocr_service.dart`) — on-device Google ML Kit text recognition + regex/heuristic field extraction. Always free/offline. Also returns `allTokens` so the user can manually pick the TID in `ReviewScreen`.
- `GeminiService` / `ClaudeService` — send the image to a vision model with an identical prompt that demands a fixed 6-line `TID:/CARTON_*:/ADDRESS_*:` response, then parse it line-by-line.

If an AI engine throws, the pipeline silently falls back to on-device OCR. The three result classes (`OcrResult`, `GeminiResult`, `ClaudeResult`) are deliberately parallel but not unified — they all funnel into a single `ParcelData`.

### ParcelData

`models/parcel_data.dart` is the immutable record carried from Review to Label. The derived `newTrackingNumber` getter is the core business rule:

```
newTrackingNumber = prefix + trackingNumber + cartonCurrent + "/" + cartonTotal
```

e.g. prefix `AU` + tracking `123456789012345` + carton `15/17` → `AU12345678901234515/17`. This string is what gets printed as text and encoded in the QR code.

### Printing

The HPRT HM-T3 Pro prints from **ZPL only** over **Bluetooth Classic SPP (RFCOMM)** — it silently ignores ESC/POS and CPCL, and BLE is not used. The print path has three layers:

- **`lib/printing/zpl_builder.dart`** — pure-Dart ZPL generator. `parcelLabel()` builds the 30×75 mm label (tracking text + QR + address + carton count); `minimalTest()` is a diagnostic label for verifying the link. Coordinates are in dots (203 dpi, 8 dots/mm); label is 240×600 dots.
- **`lib/printing/printer_service.dart`** — Dart-side `PrinterService`. Lists bonded devices, connects, prints (ZPL as UTF-8 bytes), all via a `MethodChannel`. `printParcelLabel` concatenates the label N times for copies.
- **`android/.../HprtPrinterChannel.kt`** — native Kotlin handler for the `hprt_printer` channel. Opens a plain `BluetoothSocket` (SPP UUID `00001101-...`) to a *bonded* device, streams bytes in 2 KB chunks with a 20 ms inter-chunk delay. All calls run off the main thread. **The socket is process-wide native state**, so a printer connected from `SettingsScreen` is the same connection `LabelScreen` prints with — `PrinterService.isConnected()` (a native query) is the source of truth, not any Dart-side flag.

The printer must be **paired in Android Settings** first; the app connects to bonded devices, it does not pair or scan. `LabelScreen` also offers a PDF path (`Printing.layoutPdf`) — a 30×75 mm `pdf` document through the system print dialog, independent of the Bluetooth printer.

The label layout is rendered independently in three places — `ZplBuilder.parcelLabel` (printed output), `LabelScreen._buildLabelPreview` (on-screen preview), and `LabelScreen._printToPdf` (PDF). A layout change must be applied to all three. The ZPL dot coordinates are tuned for 30×75 mm stock and may need adjustment on real hardware.
