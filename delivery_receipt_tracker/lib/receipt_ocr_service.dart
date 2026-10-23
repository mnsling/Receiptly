import 'dart:io';
import 'package:image/image.dart' as img;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Extracts product descriptions and UNIT PRICE values from photographed
/// delivery receipts using on-device Google ML Kit text recognition.
///
/// This is a heuristic parser: always show results in an editable review screen
/// before saving them. It intentionally does not extract line totals or invoice
/// totals.
class ReceiptOcrProduct {
  const ReceiptOcrProduct({
    required this.name,
    required this.unitPrice,
    this.needsReview = false,
  });

  final String name;
  final double unitPrice;
  final bool needsReview;

  @override
  String toString() => '$name — ${unitPrice.toStringAsFixed(2)}';
}

class ReceiptOcrResult {
  const ReceiptOcrResult({
    required this.products,
    required this.fullText,
    required this.detectedDescriptionHeader,
    required this.detectedUnitPriceHeader,
    required this.warnings,
  });

  final List<ReceiptOcrProduct> products;
  final String fullText;
  final bool detectedDescriptionHeader;
  final bool detectedUnitPriceHeader;
  final List<String> warnings;
}

class ReceiptOcrService {
  ReceiptOcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<ReceiptOcrResult> scanFile(String imagePath) async {
    if (!await File(imagePath).exists()) {
      throw Exception('The selected receipt image could not be found.');
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    var recognized = await _recognizer.processImage(inputImage);
    // On angled, low-contrast photos try a second, enhanced full-image pass
    // only when the original pass cannot locate the table headers.
    // Preserve original geometry for the normal (more accurate) path.
    if (!_hasTableHeaders(recognized)) {
      final enhanced = await _recognizeEnhancedFullImage(imagePath);
      if (enhanced != null && _hasTableHeaders(enhanced)) {
        recognized = enhanced;
      }
    }

    final lines = <_OcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        final box = line.boundingBox;
        lines.add(_OcrLine(
          text: text,
          left: box.left,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
        ));
      }
    }
    lines.sort((a, b) {
      final byTop = a.centerY.compareTo(b.centerY);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    });

    if (lines.isEmpty) {
      return ReceiptOcrResult(
        products: const [],
        fullText: recognized.text,
        detectedDescriptionHeader: false,
        detectedUnitPriceHeader: false,
        warnings: const ['No readable text was found. Try a sharper, brighter photo.'],
      );
    }

    final header = _findHeader(lines);
    if (header == null) {
      return ReceiptOcrResult(
        products: const [],
        fullText: recognized.text,
        detectedDescriptionHeader: false,
        detectedUnitPriceHeader: false,
        warnings: const [
          'Could not confidently find both the description and unit-price columns. '
              'This receipt may need a supplier-specific layout rule.',
        ],
      );
    }

    // Read the DESCRIPTION column independently. Full-image OCR often joins
    // DESCRIPTION, BCODE and AREA into one ML Kit line. A physical crop
    // prevents adjacent-column characters from entering the description.
    final descriptionLines = await _scanDescriptionColumn(imagePath, header);
    final parsedLines = <_OcrLine>[
      ...lines.where((l) => l.centerX < header.descriptionLeft ||
          l.centerX >= header.descriptionRight),
      ...descriptionLines,
    ]..sort((a, b) => a.centerY.compareTo(b.centerY));

    // A printed item code is a much stronger row boundary than text height.
    // Prefer code-anchored extraction for delivery receipts with ITEM CODE.
    final secondPass = await _scanEnhancedPriceColumn(imagePath, header);
    final anchored = _extractCodeAnchored(parsedLines, header, secondPass);
    if (anchored != null) {
      return ReceiptOcrResult(
        products: anchored.products,
        fullText: recognized.text,
        detectedDescriptionHeader: true,
        detectedUnitPriceHeader: true,
        warnings: anchored.warnings,
      );
    }

    // Receipts with short alphanumeric item codes (e.g. DEL105, CEN43)
    // are anchored by the UNIT PRICE column, not by 7-digit item codes.
    final priceAnchored = _extractPriceAnchored(parsedLines, header, secondPass);
    if (priceAnchored != null) {
      return ReceiptOcrResult(
        products: priceAnchored.products,
        fullText: recognized.text,
        detectedDescriptionHeader: true,
        detectedUnitPriceHeader: true,
        warnings: priceAnchored.warnings,
      );
    }

    // Non-item-code layouts retain the original fallback parser.
    final tableRows = _groupIntoRows(parsedLines.where((l) => l.centerY > header.bottom).toList());
    final products = <ReceiptOcrProduct>[];
    final warnings = <String>[];

    for (final row in tableRows) {
      if (_isEndOfTable(row.map((l) => l.text).join(' '))) break;

      // Use the actual horizontal location of recognized text to determine
      // which column it belongs to. Do not choose the far-right amount column.
      final descriptionParts = row
          .where((l) => _overlapsColumn(l, header.descriptionLeft, header.descriptionRight))
          .where((l) => !_looksLikeOnlyCodeOrQuantity(l.text))
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final priceLines = row.where((l) =>
          l.centerX >= header.priceLeft &&
          l.centerX < header.priceRight &&
          _parseMoney(l.text) != null).toList();

      if (descriptionParts.isEmpty || priceLines.isEmpty) continue;

      // Prefer a price close to the row's vertical center. If the OCR engine
      // splits the amount into multiple fragments, flag the row for review.
      priceLines.sort((a, b) =>
          (a.centerY - _rowCenter(row)).abs().compareTo(
              (b.centerY - _rowCenter(row)).abs()));

      final name = _removeTrailingBarcodeArea(
          _cleanDescription(descriptionParts.join(' ')));
      final price = _parseMoney(priceLines.first.text);
      if (name.length < 2 || price == null) continue;
      if (_looksLikeSummary(name)) break;

      final ambiguous = priceLines.length > 1 ||
          name.length < 3 ||
          priceLines.first.text.contains(RegExp(r'[A-Za-z]'));

      products.add(ReceiptOcrProduct(
        name: name,
        unitPrice: price,
        needsReview: ambiguous,
      ));
    }

    if (products.isEmpty) {
      warnings.add(
        'Text was recognized, but no product rows could be matched confidently. '
        'Check the photo angle, crop, and column headings.',
      );
    } else {
      warnings.add(
        'Review every row before saving. Coordinate-based extraction can still '
        'misread skewed, faint, or wrapped receipt rows.',
      );
    }

    return ReceiptOcrResult(
      products: products,
      fullText: recognized.text,
      detectedDescriptionHeader: true,
      detectedUnitPriceHeader: true,
      warnings: warnings,
    );
  }



  bool _hasTableHeaders(RecognizedText result) {
    final texts = <String>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        texts.add(line.text);
      }
    }
    return texts.any(_isDescriptionHeader) &&
        texts.any(_isUnitPriceHeader);
  }

  // Enhanced full-page OCR fallback. Coordinates are kept at original scale
  // by using contrast adjustment without resizing or cropping.
  Future<RecognizedText?> _recognizeEnhancedFullImage(String path) async {
    File? temporary;
    try {
      final decoded = img.decodeImage(await File(path).readAsBytes());
      if (decoded == null) return null;
      final gray = img.grayscale(decoded);
      final enhanced = img.adjustColor(gray, contrast: 1.35);
      temporary = File(
          '${Directory.systemTemp.path}/receiptly_enhanced_${DateTime.now().microsecondsSinceEpoch}.png');
      await temporary.writeAsBytes(img.encodePng(enhanced));
      return await _recognizer.processImage(
          InputImage.fromFilePath(temporary.path));
    } catch (_) {
      return null;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  // OCR on the physically cropped DESCRIPTION column. Unlike regex-based
  // cleanup, this retains legitimate pack sizes (e.g. 50/155G, 10/5/155-P)
  // while excluding neighboring BCODE and AREA text before recognition.
  Future<List<_OcrLine>> _scanDescriptionColumn(
      String path, _ReceiptHeader header) async {
    File? temp;
    try {
      final source = img.decodeImage(await File(path).readAsBytes());
      if (source == null) return [];
      final left = header.descriptionLeft.floor().clamp(0, source.width - 2).toInt();
      final right = header.descriptionRight.floor()
          .clamp(left + 1, source.width).toInt();
      final top = header.bottom.floor().clamp(0, source.height - 2).toInt();
      if (right - left < 30) return [];
      final crop = img.copyCrop(source, x: left, y: top,
          width: right - left, height: source.height - top);
      const scale = 2;
      final enlarged = img.copyResize(crop, width: crop.width * scale,
          height: crop.height * scale, interpolation: img.Interpolation.linear);
      temp = File('${Directory.systemTemp.path}/receiptly_desc_${DateTime.now().microsecondsSinceEpoch}.png');
      await temp.writeAsBytes(img.encodePng(enlarged));
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(temp.path));
      final result = <_OcrLine>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isEmpty) continue;
          final b = line.boundingBox;
          result.add(_OcrLine(text: line.text.trim(),
              left: left + b.left / scale, right: left + b.right / scale,
              top: top + b.top / scale, bottom: top + b.bottom / scale));
        }
      }
      return result;
    } catch (_) {
      // Do not silently fall back to contaminated full-image descriptions.
      return [];
    } finally {
      if (temp != null && await temp.exists()) await temp.delete();
    }
  }

  // Enlarged grayscale OCR pass on the UNIT PRICE column only.
  // Image coordinates are preserved when mapping results to item-code rows.
  Future<List<_PriceCandidate>> _scanEnhancedPriceColumn(
      String path, _ReceiptHeader header) async {
    try {
      final bytes = await File(path).readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return [];
      final left = (header.priceLeft - 12).floor().clamp(0, original.width - 1).toInt();
      final right = (header.priceRight - 3).ceil().clamp(left + 1, original.width).toInt();
      final top = header.bottom.floor().clamp(0, original.height - 1).toInt();
      final cropped = img.copyCrop(original,
          x: left, y: top, width: right - left,
          height: original.height - top);
      final enlarged = img.copyResize(cropped,
          width: cropped.width * 3,
          height: cropped.height * 3,
          interpolation: img.Interpolation.linear);
      final gray = img.grayscale(enlarged);
      final temp = File(
          '${Directory.systemTemp.path}/receiptly_price_${DateTime.now().microsecondsSinceEpoch}.png');
      try {
        await temp.writeAsBytes(img.encodePng(gray));
        final result = await _recognizer.processImage(
            InputImage.fromFilePath(temp.path));
        final found = <_PriceCandidate>[];
        for (final block in result.blocks) {
          for (final line in block.lines) {
            final value = _parseMoneyStrict(line.text);
            if (value == null) continue;
            final originalY = top + line.boundingBox.center.dy / 3.0;
            found.add(_PriceCandidate(originalY, value));
          }
        }
        return found;
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    } catch (_) {
      // Second-pass failure must not break the original OCR workflow.
      return [];
    }
  }

  double? _nearestEnhancedPrice(
      List<_PriceCandidate> prices, double y, double tolerance) {
    _PriceCandidate? nearest;
    for (final candidate in prices) {
      if ((candidate.y - y).abs() > tolerance) continue;
      if (nearest == null ||
          (candidate.y - y).abs() < (nearest.y - y).abs()) {
        nearest = candidate;
      }
    }
    return nearest?.value;
  }

  // Strict formatting: missing decimal digits are not silently rounded.
  double? _parseMoneyStrict(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'[₱$ ]'), '');
    value = value.replaceAll('O', '0').replaceAll('o', '0');
    value = value.replaceAll('I', '1').replaceAll('l', '1');
    value = value.replaceAll(',', '');
    if (!RegExp(r'^\d+\.\d{2}$').hasMatch(value)) return null;
    return double.tryParse(value);
  }

  // For receipts whose CODE column contains short alphanumeric identifiers,
  // use the distinct U. PRICE values as row anchors. This avoids treating
  // QTY/UOM fragments ("1 / CS") as product descriptions.
  _AnchoredResult? _extractPriceAnchored(
      List<_OcrLine> lines, _ReceiptHeader header,
      List<_PriceCandidate> enhancedPrices) {
    final prices = lines.where((l) =>
        l.centerY > header.bottom &&
        l.centerX >= header.priceLeft &&
        l.centerX < header.priceRight &&
        _parseMoney(l.text) != null).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    if (prices.length < 3) return null;
    final anchors = <_OcrLine>[];
    for (final p in prices) {
      if (anchors.isEmpty ||
          (p.centerY - anchors.last.centerY).abs() >
              (p.height * 0.55).clamp(4.0, 14.0)) {
        anchors.add(p);
      }
    }
    if (anchors.length < 3) return null;
    final gaps = <double>[];
    for (var i = 1; i < anchors.length; i++) {
      gaps.add(anchors[i].centerY - anchors[i - 1].centerY);
    }
    gaps.sort();
    final gap = gaps[gaps.length ~/ 2];
    final products = <ReceiptOcrProduct>[];
    final warnings = <String>[
      'Found ${anchors.length} unit-price rows. Verify the number of items '
          'against the receipt and review each description.',
    ];
    for (var i = 0; i < anchors.length; i++) {
      final a = anchors[i];
      final top = i == 0 ? a.centerY - gap * 0.48 :
          (anchors[i - 1].centerY + a.centerY) / 2;
      final bottom = i == anchors.length - 1 ? a.centerY + gap * 0.48 :
          (a.centerY + anchors[i + 1].centerY) / 2;
      final row = lines.where((l) =>
          l.centerY >= top && l.centerY < bottom &&
          l.centerY > header.bottom).toList()
        ..sort((a, b) => a.left.compareTo(b.left));
      final parts = row.where((l) =>
          l.right > header.descriptionLeft &&
          l.left < header.descriptionRight &&
          l.centerX < header.descriptionRight &&
          !_isUnitPriceHeader(l.text) &&
          !_looksLikeSummary(l.text)).toList();
      var name = _cleanDescription(parts.map((l) => l.text).join(' '));
      // Strip QTY, checkmarks, UOM and short item codes when ML Kit
      // combines neighboring table cells into one text line.
      name = name.replaceFirst(RegExp(
          r'^\s*(?:\d+\s*)?[✓✔√/\\|]*\s*(?:CS|PCS|CTN|BOX|EA)\b\s*',
          caseSensitive: false), '');
      name = name.replaceFirst(RegExp(
          r'^\s*(?:[A-Z]{2,5}\d{1,4}|\d{4,7})\s+',
          caseSensitive: false), '');
      name = _removeTrailingBarcodeArea(name);
      // Never save a UOM-only result as a product.
      if (name.length < 5 || RegExp(r'^(CS|PCS|BOX|EA)$',
          caseSensitive: false).hasMatch(name)) {
        warnings.add('Row ${i + 1}: description unreadable; '
            'check the receipt before saving.');
        continue;
      }
      final first = _parseMoney(a.text);
      final second = _nearestEnhancedPrice(enhancedPrices,
          a.centerY, gap * 0.44);
      final mismatch = first != null && second != null &&
          (first - second).abs() > 0.009;
      if (mismatch) {
        warnings.add('Row ${i + 1} ($name): price OCR disagrees; '
            'verify ${first.toStringAsFixed(2)} against the receipt.');
      }
      products.add(ReceiptOcrProduct(
        name: name,
        unitPrice: first ?? second ?? 0,
        needsReview: mismatch || first == null ||
            _parseMoneyStrict(a.text) == null || parts.length > 1,
      ));
    }
    return _AnchoredResult(products, warnings);
  }

  // Uses the ITEM CODE column as the source of truth for row positions.
  // A missing/uncertain price becomes a review item instead of a silently
  // missing product. No amounts from DISCOUNT or NET AMOUNT are used.
  _AnchoredResult? _extractCodeAnchored(
      List<_OcrLine> lines, _ReceiptHeader header,
      List<_PriceCandidate> enhancedPrices) {
    final candidates = lines.where((l) =>
        l.centerY > header.bottom &&
        l.centerX < header.descriptionLeft - 8 &&
        RegExp(r'^\s*\d{7,10}\s*$').hasMatch(l.text)).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));

    if (candidates.length < 3) return null;

    final anchors = <_OcrLine>[];
    for (final code in candidates) {
      if (anchors.isEmpty ||
          (code.centerY - anchors.last.centerY).abs() >
              (code.height * 0.55).clamp(5.0, 18.0)) {
        anchors.add(code);
      }
    }
    if (anchors.length < 3) return null;

    final products = <ReceiptOcrProduct>[];
    final warnings = <String>[];
    var incomplete = 0;
    final gaps = <double>[];
    for (var i = 1; i < anchors.length; i++) {
      gaps.add(anchors[i].centerY - anchors[i - 1].centerY);
    }
    gaps.sort();
    final typicalGap = gaps[gaps.length ~/ 2];
    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final top = i == 0
          ? anchor.centerY - typicalGap * 0.48
          : (anchors[i - 1].centerY + anchor.centerY) / 2;
      final bottom = i == anchors.length - 1
          ? anchor.centerY + typicalGap * 0.48
          : (anchor.centerY + anchors[i + 1].centerY) / 2;

      final row = lines.where((l) =>
          l.centerY >= top &&
          l.centerY < bottom &&
          l.centerY > header.bottom).toList()
        ..sort((a, b) => a.left.compareTo(b.left));

      final descriptions = row.where((l) =>
          l.centerX >= header.descriptionLeft &&
          l.centerX < header.descriptionRight &&
          !_looksLikeOnlyCodeOrQuantity(l.text)).toList();
      final priceCells = row.where((l) =>
          l.centerX >= header.priceLeft &&
          l.centerX < header.priceRight).toList();

      final name = _removeTrailingBarcodeArea(_cleanDescription(
          descriptions.map((l) => l.text).join(' ')));
      // Prices are usually one recognized line, but ML Kit may split a
      // thousands group into two pieces. Try the joined cell as fallback.
      double? price;
      var ambiguousPrice = false;
      final orderedPrices = [...priceCells]
        ..sort((a, b) =>
            (a.centerY - anchor.centerY).abs().compareTo(
                (b.centerY - anchor.centerY).abs()));
      for (final cell in orderedPrices) {
        price = _parseMoney(cell.text);
        if (price != null) {
          ambiguousPrice = orderedPrices.length > 1 ||
              _parseMoneyStrict(cell.text) == null;
          break;
        }
      }
      if (price == null && priceCells.isNotEmpty) {
        priceCells.sort((a, b) => a.left.compareTo(b.left));
        price = _parseMoney(priceCells.map((l) => l.text).join(''));
        ambiguousPrice = true;
      }

      final second = _nearestEnhancedPrice(enhancedPrices, anchor.centerY,
          typicalGap * 0.46);
      final first = price;
      final disagree = first != null && second != null &&
          (first - second).abs() > 0.009;
      // Do not overwrite a valid first-pass price when OCR passes disagree.
      // A recovered missing price still needs manual confirmation.
      if (price == null && second != null) price = second;

      if (name.isEmpty) {
        incomplete++;
        warnings.add('Item code ${anchor.text}: description not recognized.');
        continue;
      }
      if (disagree) {
        warnings.add('Item code ${anchor.text}: OCR prices disagree '
            '(${first.toStringAsFixed(2)} vs '
            '${second.toStringAsFixed(2)}). Verify the original receipt.');
      }
      if (price == null) {
        incomplete++;
        warnings.add(
            'Item code ${anchor.text}: unit price missing; check and enter it.');
      }
      products.add(ReceiptOcrProduct(
        name: name,
        unitPrice: price ?? 0,
        needsReview: price == null || first == null || disagree ||
            ambiguousPrice ||
            descriptions.length > 1 ||
            name.length < 5,
      ));
    }
    warnings.insert(0,
        'Second OCR pass found ${enhancedPrices.length} possible prices. '
        'Disagreements and recovered values require review.');
    warnings.insert(0,
        'Detected ${anchors.length} item-code rows; extracted '
        '${products.length} products. Verify every unit price.');
    if (incomplete > 0) {
      warnings.add('$incomplete row(s) need manual review. '
          'A price of ₱0.00 means OCR could not read the unit price.');
    }
    return _AnchoredResult(products, warnings);
  }

  _ReceiptHeader? _findHeader(List<_OcrLine> lines) {
    // Supports the supplied layouts: DESCRIPTION + UNIT PRICE, and
    // DESCRIPTION + U. PRICE. Deliberately does not match PRICE / AMOUNT.
    for (var i = 0; i < lines.length; i++) {
      final description = lines[i];
      if (!_isDescriptionHeader(description.text)) continue;

      _OcrLine? price;
      for (final candidate in lines) {
        if ((candidate.centerY - description.centerY).abs() >
            (description.height * 2.2 + 12)) {
          continue;
        }
        if (_isUnitPriceHeader(candidate.text) &&
            candidate.left > description.left) {
          if (price == null || candidate.left < price.left) {
            price = candidate;
          }
        }
      }
      if (price == null) continue;

      // The description begins at the description header's left edge.
      // Unit-price values lie after this header but before the next numeric
      // column (discount/net amount, or price/amount). Estimate the boundary
      // using the next header on the same header band, when available.
      final sameBand = lines.where((l) =>
          (l.centerY - description.centerY).abs() <
          (description.height * 2.2 + 12)).toList()
        ..sort((a, b) => a.left.compareTo(b.left));

      var nextColumnLeft = double.infinity;
      for (final candidate in sameBand) {
        if (candidate.left > price.left &&
            _isOtherNumericColumnHeader(candidate.text)) {
          if (candidate.left < nextColumnLeft) nextColumnLeft = candidate.left;
        }
      }

      // Some receipts do not OCR the next header. Use a conservative width
      // so the far-right net amount / amount column is not selected.
      final priceRight = nextColumnLeft.isFinite
          ? nextColumnLeft
          : price.left + (price.width * 2.8).clamp(65.0, 190.0);

      final pcsHeaders = sameBand.where((l) =>
          RegExp(r'^(PCS|PCS |PCS\.|PIECES)$')
              .hasMatch(_normal(l.text))).toList();
      final descriptionStart = pcsHeaders.isNotEmpty
          ? pcsHeaders.last.right + 5
          : description.left - 8;

      // BCODE is the first column after DESCRIPTION on the supplied receipt.
      // AREA comes after BCODE. Never extend descriptions to U. PRICE.
      var descriptionRight = price.left - 12.0;
      for (final candidate in sameBand) {
        final heading = _normal(candidate.text).replaceAll(' ', '');
        if ((heading.startsWith('BCODE') || heading.startsWith('BARCODE') ||
             heading.startsWith('AREA') || heading.startsWith('BC0DE')) &&
            candidate.left > description.left &&
            candidate.left < descriptionRight) {
          descriptionRight = candidate.left - 5.0;
        }
      }
      // If BCODE and DESCRIPTION are merged into one header line, the
      // fallback remains the U. PRICE boundary, flagged for review.
      if (descriptionRight <= descriptionStart + 20) {
        descriptionRight = price.left - 12.0;
      }

      return _ReceiptHeader(
        descriptionRight: descriptionRight,
        bottom: [description.bottom, price.bottom].reduce((a, b) => a > b ? a : b),
        descriptionLeft: descriptionStart,
        priceLeft: price.left - 8,
        priceRight: priceRight - 1,
      );
    }
    return null;
  }

  bool _isDescriptionHeader(String text) {
    final s = _normal(text);
    return s == 'DESCRIPTION' || s == 'DESCRIPTIONS' || s.contains('DESCRIPTION');
  }

  bool _isUnitPriceHeader(String text) {
    final s = _normal(text).replaceAll('.', '');
    return s == 'UNIT PRICE' ||
        s == 'U PRICE' ||
        s == 'UNITPRICE' ||
        s == 'UPRICE' ||
        s == 'UNIT PRCE';
  }

  bool _isOtherNumericColumnHeader(String text) {
    final s = _normal(text);
    return s == 'DISCOUNT' ||
        s == 'NET AMOUNT' ||
        s == 'AMOUNT' ||
        s == 'PRICE' ||
        s == 'EXT PRICE' ||
        s == 'EXTENDED PRICE';
  }

  List<List<_OcrLine>> _groupIntoRows(List<_OcrLine> lines) {
    if (lines.isEmpty) return [];
    lines.sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <List<_OcrLine>>[];

    for (final line in lines) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }
      final current = rows.last;
      final center = _rowCenter(current);
      final averageHeight = current.map((l) => l.height).reduce((a, b) => a + b) /
          current.length;
      final tolerance = (averageHeight * 0.8).clamp(5.0, 18.0);

      if ((line.centerY - center).abs() <= tolerance) {
        current.add(line);
      } else {
        rows.add([line]);
      }
    }

    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  bool _overlapsColumn(_OcrLine line, double left, double right) =>
      line.centerX >= left && line.centerX < right;

  bool _looksLikeOnlyCodeOrQuantity(String text) {
    final compact = text.replaceAll(RegExp(r'[\s./-]'), '');
    if (compact.isEmpty) return true;
    return RegExp(r'^[0-9]+$').hasMatch(compact) ||
        RegExp(r'^[A-Z0-9]{5,}$').hasMatch(compact);
  }

  bool _isEndOfTable(String text) => _looksLikeSummary(text);

  bool _looksLikeSummary(String text) {
    final s = _normal(text);
    return s.contains('GROSS AMOUNT') ||
        s.contains('NET AMOUNT') ||
        s.contains('TOTAL SALES') ||
        s.contains('TOTAL AMOUNT') ||
        s.contains('TOTAL DUE') ||
        s.contains('VAT SALES') ||
        s.contains('VAT AMOUNT') ||
        s.contains('SUBTOTAL') ||
        s == 'TOTAL' ||
        s.startsWith('TERMS AND CONDITIONS');
  }

  // Some OCR lines merge DESCRIPTION, BCODE and AREA into one string.
  // Only strip a barcode when followed by an AREA token, or when a
  // standalone AREA token is at the end. Do not remove numbers in the
  // description itself (e.g. 48/95G, 100/155G, 67814NOVA).
  String _removeTrailingBarcodeArea(String value) {
    var result = value.trim();
    // AREA codes in this supplier's receipt: 1A0017, 2A0066, etc.
    final area = RegExp(r'\s+[0-9][A-Z][0-9]{4,6}\s*$',
        caseSensitive: false);
    if (area.hasMatch(result)) {
      result = result.replaceFirst(area, '').trimRight();
      // BCODE is a 6-digit numeric token immediately before AREA.
      result = result.replaceFirst(RegExp(r'\s+\d{6}\s*$'), '').trimRight();
    }
    return result.trim();
  }

  String _cleanDescription(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[|:;,\- ]+'), '')
        .replaceAll(RegExp(r'[|:;,\- ]+$'), '')
        .trim();
  }

  double? _parseMoney(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'[₱$]'), '');
    value = value.replaceAll(RegExp(r'(?<=\d)[,](?=\d{3}(\D|$))'), '');
    value = value.replaceAll(RegExp(r'\s+'), '');
    // Common OCR punctuation substitutions in a numeric column.
    value = value.replaceAll('O', '0').replaceAll('o', '0');
    value = value.replaceAll('I', '1').replaceAll('l', '1');
    value = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (value.isEmpty || !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
      return null;
    }
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 100000000) return null;
    return parsed;
  }

  String _normal(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  double _rowCenter(List<_OcrLine> row) =>
      row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;

  Future<void> dispose() async {
    await _recognizer.close();
  }
}

class _OcrLine {
  const _OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get width => right - left;
  double get height => bottom - top;
}

class _ReceiptHeader {
  const _ReceiptHeader({
    required this.bottom,
    required this.descriptionLeft,
    required this.descriptionRight,
    required this.priceLeft,
    required this.priceRight,
  });

  final double bottom;
  final double descriptionLeft;
  final double descriptionRight;
  final double priceLeft;
  final double priceRight;
}

class _AnchoredResult {
  const _AnchoredResult(this.products, this.warnings);
  final List<ReceiptOcrProduct> products;
  final List<String> warnings;
}

class _PriceCandidate {
  const _PriceCandidate(this.y, this.value);
  final double y;
  final double value;
}
