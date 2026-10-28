
# Receiptly

**Receipt scanning and supplier price tracking, simplified.**

Receiptly is an iOS application built with Flutter that helps businesses digitize supplier receipts, organize product records, and monitor price changes across suppliers.

Using on-device OCR, Receiptly extracts product descriptions and unit prices from receipts, reducing manual data entry and making price comparisons easier.

<!-- Replace this image with a screenshot of your application. -->
![Receiptly App Preview](assets/receiptly-preview.png)

## Features

### Supplier Management
- Create and manage supplier folders.
- Scan and save receipt data under each supplier.
- View and update recorded products and unit prices.
- Maintain the latest recorded price for each product.

### Receipt Scanning
- Capture receipts using the camera or import images.
- Crop images before processing.
- Extract product descriptions and unit prices using Google ML Kit.
- Review, edit, add, or remove detected products before saving.

### Price Comparison
- Track product price increases over time.
- Compare product prices across different suppliers.
- Identify similar products through automatic description matching.
- View price changes in a receipt-inspired layout.

### Product Search
- Search recorded products across suppliers.
- View the latest available unit prices.
- Select products for manual comparison.
- Compare selected product entries side by side.

## Application

Receiptly uses a simple three-tab navigation system.

| Tab | Function |
| --- | --- |
| Suppliers | Manage suppliers, receipts, and product records. |
| Compare | Review price increases and supplier comparisons. |
| Search | Find products and compare selected entries. |

## Technology

- **Flutter / Dart** — Application development
- **Supabase** — Database and backend
- **Google ML Kit** — On-device text recognition
- **Image Picker** — Camera and gallery access
- **Codemagic** — iOS build automation

## Project Structure

```text
receiptly_flutter_mvp/
├── assets/
├── delivery_receipt_tracker/
│   └── lib/
│       ├── main.dart
│       ├── receipt_crop_page.dart
│       └── receipt_ocr_service.dart
├── ios/
├── android/
├── pubspec.yaml
└── README.md
```

## Getting Started

Clone the repository:

```bash
git clone https://github.com/mnsling/Receiptly.git
cd Receiptly
```

Install dependencies:

```bash
flutter pub get
```

Configure the required Supabase credentials, then run:

```bash
flutter run -t delivery_receipt_tracker/lib/main.dart
```

## iOS Build

Receiptly is currently developed primarily for iOS, with a minimum deployment target of iOS 15.5.

Release build command:

```bash
flutter build ios --release --no-codesign -t delivery_receipt_tracker/lib/main.dart
```

iOS builds can be generated through Codemagic. Unsigned builds require signing before installation on a physical device.

## Notes

OCR accuracy may vary depending on image quality, receipt layout, and text clarity. Detected product information should be reviewed before saving.

Automatic product matching may require manual verification when descriptions differ significantly between suppliers.

## Development Status

Receiptly is under active development, with ongoing improvements to receipt recognition, product matching, and user experience.

---

**Receiptly** — Every receipt. Every price.
