
<div align="center">

<h1><code>RECEIPTLY</code></h1>

<code>Receipt scanning · Supplier management · Price tracking</code>

<br>

<img src="assets/Angled Supplier App Showcase.png" alt="Receiptly app preview" width="680">

<br><br>

<code>SCAN.</code> &nbsp; <code>ORGANIZE.</code> &nbsp; <code>COMPARE.</code>

</div>

---

### <code>OVERVIEW</code>

Receiptly is a Flutter-based mobile application designed to simplify supplier management and product price monitoring.

Using on-device Optical Character Recognition (OCR), the application extracts product descriptions and unit prices from scanned receipts, allowing users to organize product records and compare prices across multiple suppliers.

Built with a focus on simplicity, accuracy, and usability, Receiptly reduces manual data entry and provides a centralized way to monitor purchasing costs.

---

### <code>FEATURES</code>

**<code>01 / Supplier Management</code>**

- Create and organize supplier folders.
- Store scanned product records under their respective suppliers.
- View and manage the latest recorded product prices.
- Search and browse supplier records.
- Edit or remove product information when necessary.

**<code>02 / Smart Receipt Scanning</code>**

- Capture receipts using the device camera or photo gallery.
- Crop images before text recognition.
- Extract product descriptions and unit prices using Google ML Kit.
- Review and correct detected information before saving.
- Add or remove products manually.
- Process receipt images directly on the device.

**<code>03 / Price Comparison</code>**

- Compare recorded product prices between suppliers.
- Identify differences in unit prices.
- Automatically match similar product descriptions.
- Highlight the supplier offering the lower recorded price.
- Track product price changes using previously recorded data.
- Present comparisons in a clean, readable layout.

**<code>04 / Product Search</code>**

- Search products across all registered suppliers.
- View the latest recorded prices.
- Sort products by price.
- Select multiple products for manual comparison.
- Quickly identify available supplier options.

---

### <code>HOW IT WORKS</code>

```text
01  Add a supplier
         |
02  Capture or upload a receipt
         |
03  Crop and process the image
         |
04  Review detected products
         |
05  Save product records
         |
06  Search and compare prices
```

Receiptly focuses on extracting relevant purchasing information rather than processing every field on a receipt.

The primary data extracted includes:

- Product descriptions
- Unit prices
- Associated supplier information

---

### <code>TECHNOLOGY STACK</code>

| Technology | Purpose |
|:-----------|:--------|
| `Flutter` | Mobile application framework |
| `Dart` | Application logic and interface |
| `Supabase` | Database and backend services |
| `Google ML Kit` | On-device OCR processing |
| `Image Picker` | Camera and gallery integration |
| `Codemagic` | iOS build automation |

---

### <code>APPLICATION STRUCTURE</code>

Receiptly uses three primary navigation tabs:

| Tab | Function |
|:----|:---------|
| `Suppliers` | Manage suppliers, scan receipts, and organize product records. |
| `Compare` | Compare supplier prices and identify price differences. |
| `Search` | Find products and manually compare selected entries. |

Receipt scanning and product review are accessible through the supplier workflow.

---

### <code>PROJECT STRUCTURE</code>

```text
Receiptly/
|
|-- assets/
|
|-- delivery_receipt_tracker/
|   |-- lib/
|       |-- main.dart
|       |-- receipt_crop_page.dart
|       |-- receipt_ocr_service.dart
|
|-- ios/
|-- android/
|-- pubspec.yaml
|-- README.md
```

---

### <code>GETTING STARTED</code>

**01 / Clone the repository**

```bash
git clone https://github.com/mnsling/Receiptly.git
cd Receiptly
```

**02 / Install dependencies**

```bash
flutter pub get
```

**03 / Configure Supabase**

Set up the required Supabase project credentials and database configuration.

**04 / Run the application**

```bash
flutter run -t delivery_receipt_tracker/lib/main.dart
```

---

### <code>LIMITATIONS</code>

- OCR accuracy depends on receipt quality, lighting, and text alignment.
- Detected product information may require manual correction.
- Automatic product matching may not recognize every naming variation.
- Supplier price comparisons require equivalent product quantities and units for accurate interpretation.

---

### <code>DEVELOPMENT STATUS</code>

`In active development` · `iOS-focused`

Receiptly is continuously being refined, with emphasis on improving OCR accuracy, product matching, and the overall user experience.

---

<div align="center">

<sub>Built with Flutter · Powered by Google ML Kit and Supabase</sub>

<sub>RECEIPTLY — Every receipt. Every price.</sub>

</div>
