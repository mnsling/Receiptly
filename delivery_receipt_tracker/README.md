# Receiptly — Delivery Receipt Tracker (Flutter MVP)

A clean, local-first Flutter starter for recording supplier receipts, extracting text from receipt photos, and comparing saved product prices.

## What's included

- Modern mobile dashboard and bottom navigation
- Receipt history with search and delete
- Receipt photo capture or import
- On-device OCR using Google ML Kit (iOS/Android)
- Receipt date, supplier, invoice number and total fields
- Manual product-row entry and verification
- Local SQLite storage
- Price watch comparing historical item prices by supplier + code/name + unit

## Important MVP limits

This is a starter MVP, not a production-ready receipt parser. OCR can read text, but supplier invoices arrange columns differently. Product-row auto-parsing is intentionally conservative and may not identify all rows from a Suy Sing invoice. Verify each unit price and pack size before saving. The product rows you add are the rows used for price comparisons.

- Records are stored on this device; there is no cloud sync or automatic backup yet.
- Price changes appear in the app's **Price watch** tab. Operating-system notifications are not included yet.
- Original image path is recorded, but image retention/archiving should be hardened before production.
- Product matching needs a review/edit screen and supplier-specific parser for dependable automated comparisons.

## Setup on Windows

1. Install Git for Windows and Visual Studio Code.
2. Install the Flutter SDK and the Flutter/Dart VS Code extensions:
   https://docs.flutter.dev/install/with-vs-code
3. Extract this ZIP.
4. Open the extracted folder in VS Code.
5. Open Terminal > New Terminal and run:

   ```powershell
   flutter create . --platforms=android,ios
   flutter pub get
   flutter doctor -v
   ```

   If Flutter reports that the directory already contains a project, that is expected after platform files are generated; continue with `flutter pub get`.

6. To run on Android, enable USB debugging on an Android phone or start an Android emulator, then run:

   ```powershell
   flutter devices
   flutter run
   ```

You can also use `flutter run -d chrome` only after temporarily removing the mobile-only ML Kit integration or adding platform guards; this starter targets iOS and Android.

## iPhone testing from a Windows PC

Flutter can edit the code on Windows, but a native iOS build requires macOS/Xcode. You can keep the source in GitHub and use a Mac or a macOS CI runner to build/sign the iOS app. Free Apple Account signing usually requires periodic re-signing and has limits. This project ZIP does not contain a signed iOS app.

## Permissions

`image_picker` normally handles the camera/photo library prompts. Review the generated native project files after running `flutter create`. For iOS, the generated `ios/Runner/Info.plist` should include camera and photo-library usage descriptions if they are not added automatically:

- `NSCameraUsageDescription`: Take a photo of a supplier receipt.
- `NSPhotoLibraryUsageDescription`: Select a supplier receipt image.

Google ML Kit Text Recognition currently supports Android and iOS, not Flutter Web. See:
https://pub.dev/packages/google_mlkit_text_recognition

## Suggested next development steps

1. Build a supplier-specific parser for the Suy Sing invoice layout.
2. Add an editable grid for code, product description, pack size, quantity, unit price and line amount.
3. Save a managed copy of the original receipt photo.
4. Add product aliases and pack-size matching to avoid false comparisons.
5. Add local notifications when a saved receipt reveals a price change.
6. Add CSV/Excel export and encrypted backup/sync.
