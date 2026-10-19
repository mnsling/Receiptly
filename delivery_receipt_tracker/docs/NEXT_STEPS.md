# Development notes

## Data model
- `receipts`: supplier, invoice number, printed receipt date, total, image path, OCR text
- `items`: product code, description, unit/pack, quantity, unit price
- Price comparison currently groups on supplier + code (when available) + unit.

## Why manual review matters
A receipt may have both an individual unit price and a case/line amount. For example, a carton may contain 100 packs. Comparing a carton total with a single-pack price would create a false alert. Keep unit price, pack size, quantity, and line total as separate fields in the next iteration.

## Before using for business-critical records
- Validate OCR and parser output against several real receipts per supplier.
- Add CSV/Excel export and a tested backup strategy.
- Add unit tests for supplier-specific parsers and price comparison.
- Ensure image files are copied into app-managed storage and deleted only with explicit user consent.
- Add local notifications only after verifying alert logic and user preferences.
