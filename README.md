
# 🧾 Receiptly

**A smarter way to track supplier prices.**

Receiptly is an iOS receipt-scanning and price-tracking application built with Flutter. It helps businesses organize supplier invoices, extract product information using OCR, and monitor price changes across different suppliers.

Designed with a modern, minimal interface, Receiptly makes tracking product prices faster, simpler, and more organized.

---

## ✨ Features

### 📁 1. Supplier Management

Keep your suppliers and their product records organized in one place.

- Create and manage supplier folders.
- Scan and save receipts directly under each supplier.
- View products and their latest recorded unit prices.
- Add, edit, and remove product entries.
- Maintain supplier-specific product information.
- Store records securely using Supabase.

### 📷 2. Smart Receipt Scanning

Digitize supplier receipts using on-device Optical Character Recognition (OCR).

- Capture receipts using your camera or import images from your gallery.
- Crop receipt images before processing.
- Automatically detect product descriptions and unit prices.
- Review detected products before saving.
- Edit incorrect descriptions or prices.
- Remove unwanted product entries.
- Save scanned products to their respective suppliers.

**OCR Focus:** Receiptly extracts product descriptions and unit prices rather than unnecessary receipt columns such as barcodes, area codes, and totals.

### 📈 3. Price Comparison

Identify product price increases and compare pricing across suppliers.

- Compare current and previously recorded product prices.
- Detect price increases within the same supplier.
- Compare similar products from different suppliers.
- Automatically match product descriptions using normalization and fuzzy matching.
- Display price differences in a clean, receipt-inspired layout.
- View supplier information, product descriptions, unit prices, and price changes.

### 🔎 4. Product Search

Find and compare products without browsing individual supplier folders.

- Search products across all suppliers.
- View the latest recorded unit prices.
- Sort and browse matching products.
- Select products manually for comparison.
- Compare selected products from multiple suppliers.

---

## 📱 Application Navigation

Receiptly uses three main tabs:

| Tab | Description |
|-----|-------------|
| **Suppliers** | Manage suppliers, scan receipts, and view products. |
| **Compare** | Monitor product price changes and compare suppliers. |
| **Search** | Search products and manually compare selected entries. |

---

## 🎨 User Interface

Receiptly features a modern, premium design focused on usability.

- Signature orange and charcoal color palette.
- Clean typography and compact layouts.
- Rounded supplier cards and refined navigation.
- Receipt-inspired product tables.
- Readable product descriptions and unit prices.
- Simple three-tab navigation.

The interface is designed to make supplier management and price tracking straightforward without unnecessary complexity.

---

## 🛠️ Built With

| Technology | Purpose |
|------------|---------|
| Flutter & Dart | Mobile application development |
| Supabase | Database and backend services |
| Google ML Kit | On-device text recognition |
| Image Picker | Camera and gallery image selection |
| Image Processing | Receipt image preparation |
| Codemagic | iOS build automation |

---

## 📂 Project Structure

```text
receiptly_flutter_mvp/
│
├── assets/
│
├── delivery_receipt_tracker/
│   └── lib/
│       ├── main.dart
│       ├── receipt_crop_page.dart
│       └── receipt_ocr_service.dart
│
├── ios/
├── android/
├── pubspec.yaml
└── README.md
```

### Main Files

**`main.dart`**  
Contains the application's main interface, navigation, supplier management, product search, and price comparison functionality.

**`receipt_crop_page.dart`**  
Handles cropping receipt images before OCR processing.

**`receipt_ocr_service.dart`**  
Processes receipt images and extracts product descriptions and unit prices using Google ML Kit.

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK
- Dart SDK
- VS Code or Android Studio
- Supabase project configuration
- macOS/Xcode or a cloud build service for iOS builds

### 1. Clone the Repository

```bash
git clone https://github.com/mnsling/Receiptly.git
cd Receiptly
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run Flutter Analysis

```bash
flutter analyze
```

### 4. Run the Application

Receiptly's application entry point is located in the `delivery_receipt_tracker` directory.

```bash
flutter run -t delivery_receipt_tracker/lib/main.dart
```

Configure the required Supabase credentials before running the application.

---

## 🍎 iOS Build

Receiptly is currently developed primarily for iOS.

The application can be built using Codemagic with the following configuration:

| Setting | Configuration |
|---------|---------------|
| Platform | iOS |
| Project path | `.` |
| Build mode | Release |
| Flutter target | `delivery_receipt_tracker/lib/main.dart` |
| Minimum iOS version | 15.5 |

Build command:

```bash
flutter build ios --release --no-codesign -t delivery_receipt_tracker/lib/main.dart
```

Unsigned builds require code signing before installation on a physical iPhone.

---

## ⚠️ Current Limitations

- OCR accuracy depends on receipt image quality, lighting, orientation, and text clarity.
- Some scanned descriptions and prices may require manual correction.
- Product matching may not always identify differently named products as identical.
- Supplier comparison accuracy depends on the quality of recorded product data.
- The application is primarily tested for iOS.

---

## 🎯 Project Goal

Receiptly aims to simplify product price monitoring for businesses that regularly purchase inventory from multiple suppliers.

Instead of manually checking old receipts, users can scan invoices, organize supplier products, and identify price changes from one application.

**Scan receipts. Track prices. Compare smarter.**

---

## 👨‍💻 Development

Receiptly is an independently developed Flutter project focused on practical inventory purchasing workflows and supplier price monitoring.

The application is under active development, with ongoing improvements to OCR accuracy, product matching, performance, and user experience.

---

**Receiptly — Every receipt. Every price.**
