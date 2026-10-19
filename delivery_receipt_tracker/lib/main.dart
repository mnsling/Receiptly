import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReceiptStore.instance.database;
  runApp(const ReceiptTrackerApp());
}

const ink = Color(0xFF17231D);
const green = Color(0xFFB8E65B);
const canvas = Color(0xFFF6F7F3);
const muted = Color(0xFF737C75);
final money = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final dateFormat = DateFormat('MMM d, yyyy');

class ReceiptTrackerApp extends StatelessWidget {
  const ReceiptTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receiptly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.light)
            .copyWith(primary: ink, secondary: green, surface: Colors.white),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas, foregroundColor: ink, elevation: 0,
          centerTitle: false, surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white, elevation: 0, margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: const Color(0xFFF4F5F1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class ReceiptStore {
  ReceiptStore._();
  static final instance = ReceiptStore._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'receiptly.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            supplier TEXT NOT NULL,
            invoice_no TEXT,
            receipt_date TEXT NOT NULL,
            total REAL NOT NULL DEFAULT 0,
            image_path TEXT,
            raw_text TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            receipt_id INTEGER NOT NULL,
            code TEXT,
            name TEXT NOT NULL,
            unit TEXT NOT NULL DEFAULT 'unit',
            quantity REAL NOT NULL DEFAULT 1,
            unit_price REAL NOT NULL DEFAULT 0,
            FOREIGN KEY(receipt_id) REFERENCES receipts(id) ON DELETE CASCADE
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Map<String, Object?>>> receipts() async {
    final db = await database;
    return db.query('receipts', orderBy: 'receipt_date DESC, id DESC');
  }

  Future<List<Map<String, Object?>>> itemsFor(int receiptId) async {
    final db = await database;
    return db.query('items', where: 'receipt_id = ?', whereArgs: [receiptId], orderBy: 'name');
  }

  Future<List<Map<String, Object?>>> allItems() async {
    final db = await database;
    return db.rawQuery('''
      SELECT i.*, r.supplier, r.receipt_date, r.invoice_no
      FROM items i JOIN receipts r ON r.id = i.receipt_id
      ORDER BY r.receipt_date DESC, i.id DESC
    ''');
  }

  Future<void> saveReceipt({
    required String supplier,
    required String invoice,
    required DateTime date,
    required double total,
    required String rawText,
    String? imagePath,
    required List<ReceiptItemDraft> items,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final receiptId = await txn.insert('receipts', {
        'supplier': supplier.trim(),
        'invoice_no': invoice.trim(),
        'receipt_date': DateFormat('yyyy-MM-dd').format(date),
        'total': total,
        'image_path': imagePath,
        'raw_text': rawText,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final item in items) {
        if (item.name.trim().isEmpty) continue;
        await txn.insert('items', {
          'receipt_id': receiptId,
          'code': item.code.trim(),
          'name': item.name.trim(),
          'unit': item.unit.trim().isEmpty ? 'unit' : item.unit.trim(),
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
        });
      }
    });
  }

  Future<void> deleteReceipt(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('items', where: 'receipt_id = ?', whereArgs: [id]);
      await txn.delete('receipts', where: 'id = ?', whereArgs: [id]);
    });
  }
}

class ReceiptItemDraft {
  ReceiptItemDraft({this.code = '', required this.name, this.unit = 'unit', this.quantity = 1, this.unitPrice = 0});
  String code;
  String name;
  String unit;
  double quantity;
  double unitPrice;
  double get lineTotal => quantity * unitPrice;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selected = 0;
  int refresh = 0;

  void reload() => setState(() => refresh++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(key: ValueKey('home$refresh'), onScan: () => openScan(context)),
      RecordsPage(key: ValueKey('records$refresh'), onChanged: reload),
      PricesPage(key: ValueKey('prices$refresh')),
      const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: selected, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        backgroundColor: Colors.white,
        indicatorColor: green.withValues(alpha: .45),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.trending_up_rounded), label: 'Price watch'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Future<void> openScan(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanReviewPage()));
    reload();
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onScan});
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: ReceiptStore.instance.receipts(),
      builder: (context, snapshot) {
        final receipts = snapshot.data ?? [];
        final total = receipts.fold<double>(0, (sum, r) => sum + ((r['total'] as num?)?.toDouble() ?? 0));
        return RefreshIndicator(
          onRefresh: () async => (context as Element).markNeedsBuild(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
            children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.receipt_long_rounded, color: ink, size: 24)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('RECEIPTLY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: muted)),
                  SizedBox(height: 3),
                  Text('Good morning.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: ink)),
                ])),
                CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person_outline_rounded, color: ink)),
              ]),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(26)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR DELIVERY DESK', style: TextStyle(color: green, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  const Text('Every receipt.\nEvery price change.', style: TextStyle(color: Colors.white, fontSize: 27, height: 1.15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('Keep supplier deliveries organized and catch changes before they get missed.',
                    style: TextStyle(color: Colors.white.withValues(alpha: .7), height: 1.45)),
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: onScan, icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan a receipt'),
                    style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
                ]),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _MetricCard(label: 'Receipts saved', value: '${receipts.length}', icon: Icons.inventory_2_outlined)),
                const SizedBox(width: 12),
                Expanded(child: _MetricCard(label: 'Recorded spend', value: money.format(total), icon: Icons.payments_outlined)),
              ]),
              const SizedBox(height: 25),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Recent deliveries', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                Text('${receipts.length} total', style: const TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, title: 'Your records start here',
                  subtitle: 'Scan your first supplier receipt to build a searchable delivery history.')
              else
                ...receipts.take(4).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReceiptTile(receipt: r),
                )),
              const SizedBox(height: 10),
              const Text('TIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: muted)),
              const SizedBox(height: 6),
              const Text('For reliable price comparisons, check the product name, pack size and unit price before saving OCR results.',
                style: TextStyle(color: muted, height: 1.45)),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: muted, size: 20),
      const SizedBox(height: 16),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
    ]),
  ));
}

class ReceiptTile extends StatelessWidget {
  const ReceiptTile({super.key, required this.receipt});
  final Map<String, Object?> receipt;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${receipt['receipt_date']}') ?? DateTime.now();
    return Card(child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: canvas, borderRadius: BorderRadius.circular(13)),
        child: const Icon(Icons.receipt_outlined, color: ink)),
      title: Text('${receipt['supplier']}', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
      subtitle: Text('${dateFormat.format(date)} • ${receipt['invoice_no'] ?? 'No invoice number'}',
        style: const TextStyle(color: muted, fontSize: 12)),
      trailing: Text(money.format((receipt['total'] as num?)?.toDouble() ?? 0),
        style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
    ));
  }
}

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: ReceiptStore.instance.receipts(),
    builder: (context, snapshot) {
      final records = (snapshot.data ?? []).where((r) =>
        '${r['supplier']} ${r['invoice_no']} ${r['receipt_date']}'.toLowerCase().contains(query.toLowerCase())).toList();
      return ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 24), children: [
        const Text('Your records', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 6),
        const Text('Search and revisit saved supplier deliveries.', style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(
          hintText: 'Search supplier, invoice or date', prefixIcon: Icon(Icons.search_rounded))),
        const SizedBox(height: 16),
        if (snapshot.connectionState == ConnectionState.waiting)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else if (records.isEmpty)
          const EmptyState(icon: Icons.search_off_rounded, title: 'No matching records', subtitle: 'Try another search or scan a new receipt.')
        else
          ...records.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey(r['id']),
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.delete_outline, color: Colors.red)),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async => await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('Delete this receipt?'),
                content: const Text('This removes the saved receipt record and its product rows from this device.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              )) ?? false,
              onDismissed: (_) async {
                await ReceiptStore.instance.deleteReceipt(r['id'] as int);
                widget.onChanged();
                setState(() {});
              },
              child: ReceiptTile(receipt: r),
            ),
          )),
      ]);
    },
  );
}

class PricesPage extends StatelessWidget {
  const PricesPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: ReceiptStore.instance.allItems(),
    builder: (context, snapshot) {
      final all = snapshot.data ?? [];
      final groups = <String, List<Map<String, Object?>>>{};
      for (final item in all) {
        final key = '${item['supplier']}|${(item['code'] ?? '').toString().trim().isNotEmpty ? item['code'] : item['name']}|${item['unit']}';
        groups.putIfAbsent(key, () => []).add(item);
      }
      final changes = <({Map<String, Object?> current, Map<String, Object?> previous, double delta})>[];
      for (final group in groups.values) {
        if (group.length < 2) continue;
        group.sort((a, b) => '${a['receipt_date']}'.compareTo('${b['receipt_date']}'));
        final old = (group[group.length - 2]['unit_price'] as num).toDouble();
        final now = (group.last['unit_price'] as num).toDouble();
        if ((now - old).abs() > 0.0001) changes.add((current: group.last, previous: group[group.length - 2], delta: now - old));
      }
      changes.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
      return ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 24), children: [
        const Text('Price watch', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 6),
        const Text('Changes found across saved deliveries.', style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: green.withValues(alpha: .27), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: ink, size: 25),
            const SizedBox(width: 12),
            Expanded(child: Text('${changes.length} price change${changes.length == 1 ? '' : 's'} detected in saved item history.',
              style: const TextStyle(color: ink, fontWeight: FontWeight.w700))),
          ])),
        const SizedBox(height: 16),
        if (snapshot.connectionState == ConnectionState.waiting)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else if (changes.isEmpty)
          const EmptyState(icon: Icons.show_chart_rounded, title: 'No price changes yet',
            subtitle: 'Save at least two deliveries containing the same supplier and product to compare prices.')
        else
          ...changes.map((change) {
            final up = change.delta > 0;
            final old = (change.previous['unit_price'] as num).toDouble();
            final now = (change.current['unit_price'] as num).toDouble();
            final percent = old == 0 ? 0.0 : (change.delta / old) * 100;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${change.current['name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: ink))),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(color: up ? const Color(0xFFFFE9E6) : const Color(0xFFE5F5D8), borderRadius: BorderRadius.circular(10)),
                    child: Text('${up ? '+' : ''}${percent.toStringAsFixed(1)}%',
                      style: TextStyle(color: up ? const Color(0xFFB23B2D) : const Color(0xFF316B27), fontWeight: FontWeight.w800, fontSize: 12))),
                ]),
                const SizedBox(height: 7),
                Text('${change.current['supplier']} • ${change.current['unit']}', style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 12),
                Row(children: [
                  Text(money.format(old), style: const TextStyle(color: muted, decoration: TextDecoration.lineThrough)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted)),
                  Text(money.format(now), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: ink)),
                  const Spacer(),
                  Text('${up ? '+' : ''}${money.format(change.delta)}', style: TextStyle(fontWeight: FontWeight.w800, color: up ? const Color(0xFFB23B2D) : const Color(0xFF316B27))),
                ]),
                const SizedBox(height: 7),
                Text('${change.previous['receipt_date']} → ${change.current['receipt_date']}', style: const TextStyle(color: muted, fontSize: 11)),
              ]),
            )));
          }),
        const SizedBox(height: 8),
        const Text('Matching uses supplier + product code (when available) + unit. Check descriptions and pack sizes to avoid false matches.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
      ]);
    },
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(22, 22, 22, 24), children: [
    const Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 6),
    const Text('Manage your local receipt workspace.', style: TextStyle(color: muted)),
    const SizedBox(height: 22),
    Card(child: Column(children: const [
      ListTile(leading: Icon(Icons.phone_iphone_rounded), title: Text('Stored on this device'), subtitle: Text('Receipt records are kept locally in SQLite.')),
      Divider(height: 1, indent: 16, endIndent: 16),
      ListTile(leading: Icon(Icons.document_scanner_outlined), title: Text('OCR receipt scanning'), subtitle: Text('Uses on-device text recognition on iOS and Android.')),
      Divider(height: 1, indent: 16, endIndent: 16),
      ListTile(leading: Icon(Icons.notifications_none_rounded), title: Text('Price alerts'), subtitle: Text('Current MVP shows detected changes in Price watch. Push/local alerts can be added next.')),
    ])),
    const SizedBox(height: 18),
    const Text('Next improvements', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
    const SizedBox(height: 8),
    const Text('Supplier management, editable OCR table, receipt photo archive, export to CSV/Excel, and phone notifications are natural next steps.',
      style: TextStyle(color: muted, height: 1.5)),
  ]);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: Column(children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: canvas, borderRadius: BorderRadius.circular(17)),
        child: Icon(icon, color: ink, size: 26)),
      const SizedBox(height: 13),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 16)),
      const SizedBox(height: 7),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: muted, height: 1.45, fontSize: 13)),
    ]),
  );
}

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({super.key});
  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  final supplierController = TextEditingController(text: 'Suy Sing Commercial Corporation');
  final invoiceController = TextEditingController();
  final totalController = TextEditingController();
  final rawController = TextEditingController();
  final picker = ImagePicker();
  DateTime selectedDate = DateTime.now();
  String? imagePath;
  bool scanning = false;
  bool saving = false;
  String? error;
  final List<ReceiptItemDraft> items = [];

  @override
  void dispose() {
    supplierController.dispose();
    invoiceController.dispose();
    totalController.dispose();
    rawController.dispose();
    super.dispose();
  }

  Future<void> scan(ImageSource source) async {
    try {
      final image = await picker.pickImage(source: source, imageQuality: 90);
      if (image == null) return;
      setState(() { scanning = true; error = null; imagePath = image.path; });
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
        final text = result.text;
        rawController.text = text;
        final dateMatch = RegExp(r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{4})\b').firstMatch(text);
        if (dateMatch != null) {
          final parsed = _parseDate(dateMatch.group(1)!);
          if (parsed != null) selectedDate = parsed;
        }
        final invoiceMatch = RegExp(r'(?:invoice\s*(?:no\.?|#)?|inv\.?\s*#?)\s*[:\-]?\s*([A-Z0-9-]{6,})', caseSensitive: false).firstMatch(text);
        if (invoiceMatch != null) invoiceController.text = invoiceMatch.group(1)!;
        final totalMatch = RegExp(r'(?:net\s*amount|gross\s*amount|total\s*amount|grand\s*total)\s*[:\s]*₱?\s*([\d,]+\.\d{2})', caseSensitive: false).firstMatch(text);
        if (totalMatch != null) totalController.text = totalMatch.group(1)!.replaceAll(',', '');
        _parseProductRows(text);
      } finally {
        await recognizer.close();
      }
      setState(() { scanning = false; });
    } catch (e) {
      setState(() { scanning = false; error = 'Could not scan this image. You can still enter the receipt details manually.'; });
    }
  }

  DateTime? _parseDate(String value) {
    for (final format in ['M/d/yyyy', 'd/M/yyyy', 'M-d-yyyy', 'd-M-yyyy']) {
      try { return DateFormat(format).parseStrict(value); } catch (_) {}
    }
    return null;
  }

  void _parseProductRows(String text) {
    // Receipt layouts vary. This deliberately conservative parser only suggests rows
    // where a product-like description and trailing numeric amount are visible.
    final parsed = <ReceiptItemDraft>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.length < 12) continue;
      if (RegExp(r'^(qty|uom|code|description|invoice|date|gross|net|total|amount|page)\b', caseSensitive: false).hasMatch(trimmed)) continue;
      final match = RegExp(r'^(\d{3,8})\s+(.+?)\s+(\d+(?:\.\d{1,3})?)\s+(?:CS|PC|PCS|BOX|BTL|PK|UNIT)\s+.*?([\d,]+\.\d{2})\s*$', caseSensitive: false).firstMatch(trimmed);
      if (match != null) {
        final amount = double.tryParse(match.group(4)!.replaceAll(',', '')) ?? 0;
        if (amount > 0) parsed.add(ReceiptItemDraft(
          code: match.group(1)!, name: match.group(2)!.trim(),
          quantity: double.tryParse(match.group(3)!) ?? 1, unit: 'unit price',
          unitPrice: amount,
        ));
      }
    }
    if (parsed.isNotEmpty) {
      items
        ..clear()
        ..addAll(parsed);
    }
  }

  Future<void> chooseDate() async {
    final picked = await showDatePicker(context: context, initialDate: selectedDate,
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> addItem() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final unit = TextEditingController(text: 'unit');
    final qty = TextEditingController(text: '1');
    final price = TextEditingController();
    final result = await showDialog<ReceiptItemDraft>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add product row'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: code, decoration: const InputDecoration(labelText: 'Product code (optional)')),
        const SizedBox(height: 8),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Product name')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit / pack'))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Comparable unit price (₱)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final parsedQty = double.tryParse(qty.text) ?? 1;
          final parsedPrice = double.tryParse(price.text.replaceAll(',', '')) ?? 0;
          if (name.text.trim().isEmpty || parsedPrice <= 0) return;
          Navigator.pop(ctx, ReceiptItemDraft(code: code.text, name: name.text, unit: unit.text,
            quantity: parsedQty, unitPrice: parsedPrice));
        }, child: const Text('Add')),
      ],
    ));
    name.dispose(); code.dispose(); unit.dispose(); qty.dispose(); price.dispose();
    if (result != null) setState(() => items.add(result));
  }

  Future<void> save() async {
    if (supplierController.text.trim().isEmpty) {
      setState(() => error = 'Enter the supplier name before saving.');
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      await ReceiptStore.instance.saveReceipt(
        supplier: supplierController.text,
        invoice: invoiceController.text,
        date: selectedDate,
        total: double.tryParse(totalController.text.replaceAll(',', '')) ?? items.fold<double>(0, (s, i) => s + i.lineTotal),
        rawText: rawController.text,
        imagePath: imagePath,
        items: items,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt saved to your records.')));
      Navigator.pop(context);
    } catch (e) {
      setState(() { error = 'Could not save this receipt: $e'; saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan receipt', style: TextStyle(fontWeight: FontWeight.w800))),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CAPTURE & REVIEW', style: TextStyle(color: green, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          const Text('Start with the paper.\nWe’ll help with the details.', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: scanning ? null : () => scan(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: .4))))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(onPressed: scanning ? null : () => scan(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose image'),
              style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: ink))),
          ]),
          if (scanning) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
        ]),
      ),
      if (imagePath != null) ...[
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(imagePath!), height: 150, fit: BoxFit.cover)),
      ],
      const SizedBox(height: 20),
      const Text('Receipt details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 12),
      TextField(controller: supplierController, decoration: const InputDecoration(labelText: 'Supplier name', prefixIcon: Icon(Icons.storefront_outlined))),
      const SizedBox(height: 10),
      TextField(controller: invoiceController, decoration: const InputDecoration(labelText: 'Invoice number', prefixIcon: Icon(Icons.numbers_rounded))),
      const SizedBox(height: 10),
      InkWell(onTap: chooseDate, borderRadius: BorderRadius.circular(14), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16), decoration: BoxDecoration(color: const Color(0xFFF4F5F1), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [const Icon(Icons.calendar_today_outlined, color: muted), const SizedBox(width: 12),
          const Expanded(child: Text('Receipt date', style: TextStyle(color: muted))),
          Text(dateFormat.format(selectedDate), style: const TextStyle(color: ink, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6), const Icon(Icons.chevron_right_rounded, color: muted)]),
      )),
      const SizedBox(height: 10),
      TextField(controller: totalController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Invoice total (₱)', prefixIcon: Icon(Icons.payments_outlined))),
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Text('Product rows', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink))),
        Text('${items.length} added', style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: addItem, icon: const Icon(Icons.add_rounded)),
      ]),
      const SizedBox(height: 6),
      if (items.isEmpty)
        const EmptyState(icon: Icons.inventory_2_outlined, title: 'Review products here',
          subtitle: 'OCR text is extracted from the image. Add or verify product rows and unit prices before saving for comparisons.')
      else
        ...items.asMap().entries.map((entry) {
          final i = entry.key; final item = entry.value;
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
            subtitle: Text('Code: ${item.code.isEmpty ? '—' : item.code} • Qty ${item.quantity} ${item.unit}\nUnit price: ${money.format(item.unitPrice)}',
              style: const TextStyle(color: muted, height: 1.5, fontSize: 12)),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => items.removeAt(i))),
          )));
        }),
      const SizedBox(height: 14),
      if (rawController.text.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('View extracted OCR text', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          subtitle: const Text('Use this to verify details if the scan misread anything.'),
          children: [TextField(controller: rawController, minLines: 5, maxLines: 12, decoration: const InputDecoration(hintText: 'Recognized text'))],
        ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 18),
      SizedBox(height: 54, child: FilledButton.icon(
        onPressed: saving ? null : save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink)) : const Icon(Icons.check_rounded),
        label: Text(saving ? 'Saving…' : 'Save delivery record'),
        style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: ink, textStyle: const TextStyle(fontWeight: FontWeight.w800)),
      )),
      const SizedBox(height: 10),
      const Text('Always verify extracted prices before saving. Receipt layouts differ, and unit price is not always the same as case total.',
        textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11, height: 1.45)),
    ]),
  );
}
