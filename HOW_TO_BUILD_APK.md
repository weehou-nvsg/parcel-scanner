# How to Get Your APK

## Option A — GitHub Actions (Easiest, no tools needed)

1. Create a free account at https://github.com if you don't have one
2. Create a new repository (click + → New repository → name it "parcel-scanner" → Public → Create)
3. Upload all these files to the repo:
   - Drag the entire `parcel_scanner` folder contents into the GitHub upload area
   - Or use GitHub Desktop app (https://desktop.github.com) to commit and push
4. GitHub Actions will automatically start building (check the "Actions" tab)
5. Wait ~5 minutes for the build to finish
6. Click the completed workflow run → scroll down → download **parcel-scanner-debug**
7. Unzip it — you get `app-debug.apk`
8. Transfer to your phone (email it, Google Drive, USB cable)
9. On your phone: Settings → Security → Install unknown apps → allow your browser/Files app
10. Tap the APK to install

## Option B — Build locally (if you have Android Studio)

1. Install Flutter: https://docs.flutter.dev/get-started/install/windows
2. Install Android Studio: https://developer.android.com/studio
3. Open a terminal in this folder and run:
   ```
   flutter pub get
   flutter build apk --debug
   ```
4. APK is at: `build\app\outputs\flutter-apk\app-debug.apk`

---

## Phone Setup (do this before first use)

1. **Pair the HPRT HM-T3 Pro:**
   - Turn on the printer
   - Phone → Settings → Bluetooth → Scan → tap "HPRT HM-T3 Pro" or similar name
   - Accept pairing (PIN is usually 0000 or 1234)

2. **Allow installation from unknown sources:**
   - Settings → Apps → Special app access → Install unknown apps
   - Allow for whichever app you use to open the APK

3. **First app launch:**
   - Tap Settings (gear icon) → enter your prefix (e.g. "AU")
   - Tap "Scan Parcel Label" → allow camera permission
   - Point at label → tap camera button
   - Review/correct OCR results
   - On the Label screen → tap "Select HPRT Printer" → choose your printer
   - Tap Print

---

## Label Format

The generated label (30mm × 75mm) contains:
- New tracking number: `[PREFIX][ORIGINAL_TRACKING][CURRENT]/[TOTAL]`
  - Example: `AU12345678901234515/17`
- QR code encoding the same tracking number
- Delivery address (3 lines)
- Carton count in large text (e.g. `15/17`)
