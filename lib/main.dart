import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Replace these placeholders with your Supabase Project URL and anon/publishable key.
// Never put your Supabase service_role key in a Flutter app.
const supabaseUrl = 'https://djzxjupdpvxpuyfbdpuz.supabase.co';
const supabaseAnonKey = 'sb_publishable_n4OxKgiO8xKcfS2gUXP61A_OJMyjzZG';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );
  runApp(const ReceiptTrackerApp());
}

const ink = Color(0xFF232020);
const green = Color(0xFFFF7315);
const canvas = Color(0xFFF4F4F4);
const muted = Color(0xFF3A3535);
final money =
    NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
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
        colorScheme: ColorScheme.fromSeed(
                seedColor: green, brightness: Brightness.light)
            .copyWith(primary: ink, secondary: green, surface: Colors.white),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F5F1),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class ReceiptStore {
  ReceiptStore._();
  static final instance = ReceiptStore._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, Object?>>> receipts() async {
    final rows = await _client
        .from('receipts')
        .select()
        .order('receipt_date', ascending: false)
        .order('id', ascending: false);
    return rows
        .map<Map<String, Object?>>((row) => Map<String, Object?>.from(row))
        .toList();
  }

  Future<List<Map<String, Object?>>> itemsFor(int receiptId) async {
    final rows = await _client
        .from('receipt_items')
        .select()
        .eq('receipt_id', receiptId)
        .order('name');
    return rows
        .map<Map<String, Object?>>((row) => Map<String, Object?>.from(row))
        .toList();
  }

  Future<List<Map<String, Object?>>> allItems() async {
    final rows = await _client
        .from('price_comparison_items')
        .select()
        .order('receipt_date', ascending: false)
        .order('id', ascending: false);
    return rows
        .map<Map<String, Object?>>((row) => Map<String, Object?>.from(row))
        .toList();
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
    final inserted = await _client
        .from('receipts')
        .insert({
          'supplier': supplier.trim(),
          'invoice_no': invoice.trim().isEmpty ? null : invoice.trim(),
          'receipt_date': DateFormat('yyyy-MM-dd').format(date),
          'total': total,
          // This is the local device path, not a cloud image URL. Cloud image storage can be added later.
          'image_path': imagePath,
          'raw_text': rawText,
        })
        .select('id')
        .single();

    final receiptId = inserted['id'] as int;
    final rows = items
        .where((item) => item.name.trim().isNotEmpty)
        .map((item) => <String, Object?>{
              'receipt_id': receiptId,
              'code': item.code.trim().isEmpty ? null : item.code.trim(),
              'name': item.name.trim(),
              'unit': item.unit.trim().isEmpty ? 'unit' : item.unit.trim(),
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
            })
        .toList();

    if (rows.isNotEmpty) {
      try {
        await _client.from('receipt_items').insert(rows);
      } catch (_) {
        // Avoid leaving an orphan receipt if its item rows fail to save.
        await _client.from('receipts').delete().eq('id', receiptId);
        rethrow;
      }
    }
  }

  Future<void> deleteReceipt(int id) async {
    await _client.from('receipts').delete().eq('id', id);
    // receipt_items are removed by the database's ON DELETE CASCADE constraint.
  }
}

class ReceiptItemDraft {
  ReceiptItemDraft(
      {this.code = '',
      required this.name,
      this.unit = 'unit',
      this.quantity = 1,
      this.unitPrice = 0});
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
      DashboardPage(
          key: ValueKey('home$refresh'), onScan: () => openScan(context)),
      RecordsPage(
          key: ValueKey('records$refresh'),
          onChanged: reload,
          onAddReceipt: (supplier) => openScan(context, supplier: supplier)),
      PricesPage(key: ValueKey('prices$refresh')),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: selected, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        backgroundColor: Colors.white,
        indicatorColor: green.withValues(alpha: .45),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'Overview'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded), label: 'Records'),
          NavigationDestination(
              icon: Icon(Icons.trending_up_rounded), label: 'Price watch'),
        ],
      ),
    );
  }

  Future<void> openScan(BuildContext context, {String? supplier}) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ScanReviewPage(supplierName: supplier)));
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
        return RefreshIndicator(
          onRefresh: () async => (context as Element).markNeedsBuild(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
            children: [
              Row(children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: green, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: ink, size: 24)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('RECEIPTLY',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: muted)),
                      SizedBox(height: 3),
                      Text('Good morning.',
                          style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                    ])),
                CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person_outline_rounded, color: ink)),
              ]),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: ink, borderRadius: BorderRadius.circular(26)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('YOUR DELIVERY DESK',
                          style: TextStyle(
                              color: green,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 12),
                      const Text('Every receipt.\nEvery price change.',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              height: 1.15,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(
                          'Keep supplier deliveries organized and catch changes before they get missed.',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .7),
                              height: 1.45)),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: onScan,
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Scan a receipt'),
                            style: FilledButton.styleFrom(
                                backgroundColor: green,
                                foregroundColor: ink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16)),
                          )),
                    ]),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: _MetricCard(
                        label: 'Receipts saved',
                        value: '${receipts.length}',
                        icon: Icons.inventory_2_outlined)),
              ]),
              const SizedBox(height: 25),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Recent deliveries',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                Text('${receipts.length} total',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Your records start here',
                    subtitle:
                        'Scan your first supplier receipt to build a searchable delivery history.')
              else
                ...receipts.take(4).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ReceiptTile(receipt: r),
                    )),
              const SizedBox(height: 10),
              const Text('TIP',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: muted)),
              const SizedBox(height: 6),
              const Text(
                  'For reliable price comparisons, check the product name, pack size and unit price before saving OCR results.',
                  style: TextStyle(color: muted, height: 1.45)),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: muted, size: 20),
          const SizedBox(height: 16),
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: ink)),
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
    final date =
        DateTime.tryParse('${receipt['receipt_date']}') ?? DateTime.now();
    return Card(
        child: ListTile(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReceiptDetailsPage(
            receipt: receipt,
            supplier: '${receipt['supplier']}'.trim().isEmpty
                ? 'Unknown supplier'
                : '${receipt['supplier']}'.trim(),
          ),
        ));
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: canvas, borderRadius: BorderRadius.circular(13)),
          child: const Icon(Icons.receipt_outlined, color: ink)),
      title: Text('${receipt['supplier']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Invoice: ${receipt['invoice_no']?.toString().trim().isNotEmpty == true ? receipt['invoice_no'] : 'No invoice number'}',
              style: const TextStyle(
                  color: ink, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(dateFormat.format(date),
              style: const TextStyle(color: muted, fontSize: 11)),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: muted),
    ));
  }
}

class RecordsPage extends StatefulWidget {
  const RecordsPage(
      {super.key, required this.onChanged, required this.onAddReceipt});
  final VoidCallback onChanged;
  final ValueChanged<String> onAddReceipt;
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String query = '';

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, Object?>>>(
        future: ReceiptStore.instance.receipts(),
        builder: (context, snapshot) {
          final records = (snapshot.data ?? [])
              .where((r) =>
                  '${r['supplier']} ${r['invoice_no']} ${r['receipt_date']}'
                      .toLowerCase()
                      .contains(query.toLowerCase()))
              .toList();
          final folders = <String, List<Map<String, Object?>>>{};
          for (final receipt in records) {
            final supplier = '${receipt['supplier']}'.trim().isEmpty
                ? 'Unknown supplier'
                : '${receipt['supplier']}'.trim();
            folders.putIfAbsent(supplier, () => []).add(receipt);
          }
          final folderNames = folders.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              children: [
                const Text('Suppliers',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 6),
                const Text(
                    'Each company has its own folder of delivery receipts.',
                    style: TextStyle(color: muted)),
                const SizedBox(height: 20),
                TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                        hintText: 'Search companies, invoices or dates',
                        prefixIcon: Icon(Icons.search_rounded))),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator()))
                else if (records.isEmpty)
                  const EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'No supplier folders yet',
                      subtitle:
                          'Scan your first delivery receipt. It will be filed under its supplier.')
                else
                  ...folderNames.map((supplier) {
                    final folderReceipts = folders[supplier]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                          child: Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 5),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: green.withValues(alpha: .3),
                                  borderRadius: BorderRadius.circular(13)),
                              child:
                                  const Icon(Icons.folder_rounded, color: ink)),
                          title: Text(supplier,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: ink)),
                          subtitle: Text(
                              '${folderReceipts.length} receipt${folderReceipts.length == 1 ? '' : 's'}',
                              style:
                                  const TextStyle(color: muted, fontSize: 12)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      widget.onAddReceipt(supplier),
                                  icon: const Icon(Icons.add_rounded),
                                  label:
                                      const Text('Add receipt to this folder'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: green,
                                      foregroundColor: ink),
                                ),
                              ),
                            ),
                            ...folderReceipts.map((receipt) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Dismissible(
                                    key: ValueKey(receipt['id']),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                        alignment: Alignment.centerRight,
                                        padding:
                                            const EdgeInsets.only(right: 18),
                                        decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        child: const Icon(Icons.delete_outline,
                                            color: Colors.red)),
                                    confirmDismiss: (_) async {
                                      final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                    'Delete this receipt?'),
                                                content: const Text(
                                                    'This removes the receipt and its product rows from this device.'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child:
                                                          const Text('Cancel')),
                                                  FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      child:
                                                          const Text('Delete')),
                                                ],
                                              ));
                                      return confirmed ?? false;
                                    },
                                    onDismissed: (_) async {
                                      await ReceiptStore.instance
                                          .deleteReceipt(receipt['id'] as int);
                                      widget.onChanged();
                                      if (mounted) setState(() {});
                                    },
                                    child: Material(
                                      color: canvas,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          Navigator.of(context)
                                              .push(MaterialPageRoute(
                                            builder: (_) => ReceiptDetailsPage(
                                              receipt: receipt,
                                              supplier: supplier,
                                            ),
                                          ));
                                        },
                                        child: ListTile(
                                          dense: true,
                                          leading: const Icon(
                                              Icons.receipt_long_outlined,
                                              color: ink),
                                          title: Text(
                                              '${receipt['invoice_no'] ?? ''}'
                                                      .trim()
                                                      .isEmpty
                                                  ? 'Delivery receipt'
                                                  : 'Invoice ${receipt['invoice_no']}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: ink)),
                                          subtitle: Text(
                                              '${receipt['receipt_date']} · Tap to view products',
                                              style: const TextStyle(
                                                  color: muted, fontSize: 12)),
                                          trailing: const Icon(
                                              Icons.chevron_right_rounded,
                                              color: muted),
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      )),
                    );
                  }),
              ]);
        },
      );
}

class ReceiptDetailsPage extends StatelessWidget {
  const ReceiptDetailsPage(
      {super.key, required this.receipt, required this.supplier});

  final Map<String, Object?> receipt;
  final String supplier;

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse('${receipt['receipt_date']}');
    final dateText = parsedDate == null
        ? '${receipt['receipt_date']}'
        : dateFormat.format(parsedDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(supplier,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: ReceiptStore.instance.itemsFor(receipt['id'] as int),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                  'Could not load products. Please check your Supabase receipt_items access policy.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted)),
            ));
          }
          final items = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            children: [
              const Text('RECEIPT DETAILS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: muted)),
              const SizedBox(height: 5),
              const Text('Products and prices',
                  style: TextStyle(
                      fontSize: 27, fontWeight: FontWeight.w900, color: ink)),
              const SizedBox(height: 6),
              Text('$supplier · $dateText',
                  style: const TextStyle(color: muted)),
              const SizedBox(height: 22),
              if (items.isEmpty)
                const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products saved',
                    subtitle:
                        'This receipt has no product rows in Supabase. Scan and save it again to record the products.')
              else ...[
                Row(children: [
                  const Expanded(
                      child: Text('DETECTED PRODUCTS',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: ink))),
                  Text('${items.length} rows',
                      style: const TextStyle(fontSize: 11, color: muted)),
                ]),
                const SizedBox(height: 10),
                Card(
                    child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(children: [
                      Expanded(
                          child: Text('PRODUCT',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: muted))),
                      Text('UNIT PRICE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: muted)),
                    ]),
                  ),
                  const Divider(height: 1),
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 15),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(
                                      '${item['name'] ?? 'Unnamed product'}',
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          height: 1.45,
                                          color: ink,
                                          fontWeight: FontWeight.w500))),
                              const SizedBox(width: 12),
                              Text(
                                  money.format((item['unit_price'] as num?)
                                          ?.toDouble() ??
                                      0),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: ink)),
                            ]),
                      )),
                ])),
              ],
              const SizedBox(height: 18),
              const Text('PRICE COMPARISON',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: muted)),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, Object?>>>(
                future: ReceiptStore.instance.allItems(),
                builder: (context, comparisonSnapshot) {
                  if (comparisonSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (comparisonSnapshot.hasError) {
                    return const Text('Price comparison could not be loaded.',
                        style: TextStyle(color: muted));
                  }
                  final all = (comparisonSnapshot.data ?? [])
                      .where((row) =>
                          '${row['supplier']}'.trim().toLowerCase() ==
                          supplier.toLowerCase())
                      .toList();
                  final comparisons = <Map<String, Object?>>[];
                  for (final item in items) {
                    final name = '${item['name']}'.trim().toLowerCase();
                    final matches = all
                        .where((row) =>
                            '${row['name']}'.trim().toLowerCase() == name)
                        .toList()
                      ..sort((a, b) => '${b['receipt_date']}'
                          .compareTo('${a['receipt_date']}'));
                    final currentId = receipt['id'];
                    final previous = matches
                        .where((row) => row['receipt_id'] != currentId)
                        .toList();
                    if (previous.isNotEmpty) {
                      comparisons.add({
                        'name': item['name'],
                        'old': previous.first['unit_price'],
                        'new': item['unit_price'],
                        'date': previous.first['receipt_date']
                      });
                    }
                  }
                  if (comparisons.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Text(
                          'No earlier matching product prices yet. Save another receipt from this supplier to compare prices.',
                          style: TextStyle(color: muted, height: 1.4)),
                    );
                  }
                  return Column(
                      children: comparisons.map((comparison) {
                    final oldPrice =
                        (comparison['old'] as num?)?.toDouble() ?? 0;
                    final newPrice =
                        (comparison['new'] as num?)?.toDouble() ?? 0;
                    final delta = newPrice - oldPrice;
                    final percent =
                        oldPrice == 0 ? 0.0 : delta / oldPrice * 100;
                    final color = delta > 0
                        ? Colors.red.shade700
                        : delta < 0
                            ? Colors.green.shade700
                            : muted;
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                            child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${comparison['name']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: ink)),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          'Previous  ${money.format(oldPrice)}',
                                          style: const TextStyle(
                                              color: muted, fontSize: 12))),
                                  Expanded(
                                      child: Text(
                                          'Latest  ${money.format(newPrice)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                              color: ink,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12))),
                                ]),
                                const SizedBox(height: 7),
                                Text(
                                    '${delta > 0 ? '+' : ''}${money.format(delta)} (${delta > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%)',
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12)),
                              ]),
                        )));
                  }).toList());
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class PricesPage extends StatelessWidget {
  const PricesPage({super.key});
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, Object?>>>(
        future: ReceiptStore.instance.allItems(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? [];
          final groups = <String, List<Map<String, Object?>>>{};
          for (final item in all) {
            final key =
                '${item['supplier']}|${(item['code'] ?? '').toString().trim().isNotEmpty ? item['code'] : item['name']}|${item['unit']}';
            groups.putIfAbsent(key, () => []).add(item);
          }
          final changes = <({
            Map<String, Object?> current,
            Map<String, Object?> previous,
            double delta
          })>[];
          for (final group in groups.values) {
            if (group.length < 2) continue;
            group.sort((a, b) =>
                '${a['receipt_date']}'.compareTo('${b['receipt_date']}'));
            final old =
                (group[group.length - 2]['unit_price'] as num).toDouble();
            final now = (group.last['unit_price'] as num).toDouble();
            if ((now - old).abs() > 0.0001) {
              changes.add((
                current: group.last,
                previous: group[group.length - 2],
                delta: now - old
              ));
            }
          }
          changes.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
          return ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
              children: [
                const Text('Price watch',
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 6),
                const Text('Changes found across saved deliveries.',
                    style: TextStyle(color: muted)),
                const SizedBox(height: 20),
                Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                        color: green.withValues(alpha: .27),
                        borderRadius: BorderRadius.circular(18)),
                    child: Row(children: [
                      const Icon(Icons.notifications_active_outlined,
                          color: ink, size: 25),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              '${changes.length} price change${changes.length == 1 ? '' : 's'} detected in saved item history.',
                              style: const TextStyle(
                                  color: ink, fontWeight: FontWeight.w700))),
                    ])),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator()))
                else if (changes.isEmpty)
                  const EmptyState(
                      icon: Icons.show_chart_rounded,
                      title: 'No price changes yet',
                      subtitle:
                          'Save at least two deliveries containing the same supplier and product to compare prices.')
                else
                  ...changes.map((change) {
                    final up = change.delta > 0;
                    final old =
                        (change.previous['unit_price'] as num).toDouble();
                    final now =
                        (change.current['unit_price'] as num).toDouble();
                    final percent = old == 0 ? 0.0 : (change.delta / old) * 100;
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                            child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text('${change.current['name']}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: ink))),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: up
                                              ? const Color(0xFFFFE9E6)
                                              : const Color(0xFFFFE9D9),
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Text(
                                          '${up ? '+' : ''}${percent.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                              color: up
                                                  ? const Color(0xFFB23B2D)
                                                  : const Color(0xFFB94C00),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12))),
                                ]),
                                const SizedBox(height: 7),
                                Text(
                                    '${change.current['supplier']} • ${change.current['unit']}',
                                    style: const TextStyle(
                                        color: muted, fontSize: 12)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Text(money.format(old),
                                      style: const TextStyle(
                                          color: muted,
                                          decoration:
                                              TextDecoration.lineThrough)),
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(Icons.arrow_forward_rounded,
                                          size: 16, color: muted)),
                                  Text(money.format(now),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                          color: ink)),
                                  const Spacer(),
                                  Text(
                                      '${up ? '+' : ''}${money.format(change.delta)}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: up
                                              ? const Color(0xFFB23B2D)
                                              : const Color(0xFFB94C00))),
                                ]),
                                const SizedBox(height: 7),
                                Text(
                                    '${change.previous['receipt_date']} → ${change.current['receipt_date']}',
                                    style: const TextStyle(
                                        color: muted, fontSize: 11)),
                              ]),
                        )));
                  }),
                const SizedBox(height: 8),
                const Text(
                    'Matching uses supplier + product code (when available) + unit. Check descriptions and pack sizes to avoid false matches.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
              ]);
        },
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  color: canvas, borderRadius: BorderRadius.circular(17)),
              child: Icon(icon, color: ink, size: 26)),
          const SizedBox(height: 13),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: ink, fontSize: 16)),
          const SizedBox(height: 7),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.45, fontSize: 13)),
        ]),
      );
}

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({super.key, this.supplierName});
  final String? supplierName;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  final picker = ImagePicker();
  String? supplierName;
  String? imagePath;
  String? statusMessage;
  String? error;
  bool scanning = false;
  bool saved = false;
  bool choosingImage = false;
  List<ReceiptItemDraft> items = [];
  DateTime receiptDate = DateTime.now();
  String invoiceNumber = '';
  String rawText = '';

  @override
  void initState() {
    super.initState();
    supplierName = widget.supplierName?.trim().isNotEmpty == true
        ? widget.supplierName!.trim()
        : null;
  }

  Future<String?> _askSupplierName() async {
    final client = Supabase.instance.client;
    List<String> existing = [];
    try {
      final rows = await client.from('suppliers').select('name').order('name');
      existing = rows
          .map<String>((r) => '${r['name']}'.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      // Older projects may only have supplier names saved on receipts.
      try {
        final rows =
            await client.from('receipts').select('supplier').order('supplier');
        existing = rows
            .map<String>((r) => '${r['supplier']}'.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();
      } catch (_) {}
    }
    if (supplierName != null &&
        supplierName!.trim().isNotEmpty &&
        !existing.contains(supplierName!.trim())) {
      existing.insert(0, supplierName!.trim());
    }
    final controller = TextEditingController();
    String? dialogError;
    bool creatingFolder = false;
    String? selected = supplierName != null && existing.contains(supplierName)
        ? supplierName
        : (existing.isNotEmpty ? existing.first : null);
    bool createNew = existing.isEmpty;
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose company folder'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null) ...[
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                if (!createNew && existing.isNotEmpty) ...[
                  const Text('Select an existing company'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    items: existing
                        .map((name) => DropdownMenuItem(
                            value: name,
                            child: Text(name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (name) => setDialogState(() => selected = name),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.folder_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => setDialogState(() => createNew = true),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Create another company folder'),
                  ),
                ],
                if (createNew) ...[
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'New company name',
                        hintText: 'e.g. Buy Sing Commercial Corporation',
                        prefixIcon: Icon(Icons.create_new_folder_outlined)),
                  ),
                  if (existing.isNotEmpty)
                    TextButton(
                        onPressed: () =>
                            setDialogState(() => createNew = false),
                        child: const Text('Select an existing folder')),
                ],
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: creatingFolder
                  ? null
                  : () async {
                      final name = createNew
                          ? controller.text.trim()
                          : (selected ?? '').trim();
                      if (name.isEmpty) {
                        setDialogState(() => dialogError =
                            'Enter a company name or select a folder.');
                        return;
                      }
                      if (createNew) {
                        setDialogState(() {
                          creatingFolder = true;
                          dialogError = null;
                        });
                        try {
                          await client
                              .from('suppliers')
                              .upsert({'name': name}, onConflict: 'name');
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              creatingFolder = false;
                              dialogError =
                                  'Could not create company folder. Check Supabase permissions. $e';
                            });
                          }
                          return;
                        }
                      }
                      if (dialogContext.mounted)
                        Navigator.of(dialogContext).pop(name);
                    },
              style: FilledButton.styleFrom(
                  backgroundColor: green, foregroundColor: ink),
              child: creatingFolder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(createNew
                      ? 'Create folder & continue'
                      : 'Use this folder'),
            ),
          ],
        ),
      ),
    );
    // The dialog route has finished closing before its text controller is disposed.
    controller.dispose();
    return value?.trim().isNotEmpty == true ? value!.trim() : null;
  }

  Future<void> scan(ImageSource source) async {
    // Prevent overlapping picker launches, which can leave Android's activity
    // and Flutter's widget tree in an inconsistent state.
    if (choosingImage || scanning) return;
    setState(() => choosingImage = true);
    try {
      if (supplierName == null || supplierName!.isEmpty) {
        final chosen = await _askSupplierName();
        if (!mounted || chosen == null) return;
        setState(() => supplierName = chosen);
      }

      if (!mounted) return;
      final image = await picker.pickImage(source: source, imageQuality: 100);
      if (!mounted || image == null) return;
      setState(() {
        scanning = true;
        saved = false;
        error = null;
        statusMessage = 'Reading the receipt and finding product prices…';
        imagePath = image.path;
        items = [];
      });

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      List<ReceiptItemDraft> extracted;
      try {
        final result =
            await recognizer.processImage(InputImage.fromFilePath(image.path));
        rawText = result.text;
        extracted = _parseProductRows(result);
        final dateMatch = RegExp(
          r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{4})\b',
        ).firstMatch(rawText);
        if (dateMatch != null) {
          receiptDate = _parseDate(dateMatch.group(1)!) ?? DateTime.now();
        } else {
          receiptDate = DateTime.now();
        }
        final invoiceMatch = RegExp(
          r'(?:sales\s+invoice\s+no\.?|invoice\s*(?:no\.?|#)?|inv\.?\s*#?)\s*[:\-]?\s*([A-Z0-9-]{5,})',
          caseSensitive: false,
        ).firstMatch(rawText);
        invoiceNumber = invoiceMatch?.group(1) ?? '';
      } finally {
        await recognizer.close();
      }

      if (!mounted) return;
      if (extracted.isEmpty) {
        setState(() {
          scanning = false;
          error =
              'Receiptly could not confidently identify the product rows in this photo. Try a sharper photo taken straight above the receipt.';
          statusMessage = null;
        });
        return;
      }

      setState(() {
        items = extracted;
        statusMessage =
            'Detected ${items.length} product${items.length == 1 ? '' : 's'}. Saving to $supplierName…';
      });

      // Save automatically after OCR. No receipt-detail forms or manual product entry.
      final receiptTotal =
          items.fold<double>(0, (sum, item) => sum + item.lineTotal);
      await ReceiptStore.instance.saveReceipt(
        supplier: supplierName!,
        invoice: invoiceNumber,
        date: receiptDate,
        total: receiptTotal,
        rawText: rawText,
        imagePath: image.path,
        items: items,
      );

      if (!mounted) return;
      setState(() {
        scanning = false;
        saved = true;
        statusMessage = 'Saved ${items.length} products to $supplierName.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        scanning = false;
        statusMessage = null;
        error =
            'Could not process or save this receipt. Check your connection and Supabase settings, then try again. Details: $e';
      });
    } finally {
      if (mounted) setState(() => choosingImage = false);
    }
  }

  DateTime? _parseDate(String value) {
    for (final format in ['M/d/yyyy', 'd/M/yyyy', 'M-d-yyyy', 'd-M-yyyy']) {
      try {
        return DateFormat(format).parseStrict(value);
      } catch (_) {}
    }
    return null;
  }

  double? _parseMoney(String value) =>
      double.tryParse(value.replaceAll(',', '').replaceAll('₱', '').trim());

  List<ReceiptItemDraft> _parseProductRows(RecognizedText result) {
    final found = <ReceiptItemDraft>[];
    final seen = <String>{};
    final ignored = RegExp(
      r'\b(qty|uom|description|invoice|gross amount|net amount|total sales|vat amount|vatable sales|customer|sold to|ship to|page|subtotal|discount|cash|change|balance|acknowledgment|reward points)\b',
      caseSensitive: false,
    );
    final money = RegExp(r'^\d[\d,]*\.\d{2}$');
    final units = RegExp(
      r'^(CS|CASE|PC|PCS|BOX|BTL|PK|PACK|UNIT|KG|G|L|ML|BAG|CTN|DOZ)$',
      caseSensitive: false,
    );

    // Use OCR line geometry to keep product descriptions and price columns aligned.
    // This is more robust than assuming every receipt is returned as one plain-text line.
    for (final block in result.blocks) {
      for (final lineBlock in block.lines) {
        final line = lineBlock.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (line.length < 8 || ignored.hasMatch(line)) continue;
        final tokens = line.split(' ');
        if (tokens.length < 8) continue;

        // Buy Sing style: QTY UOM CODE DESCRIPTION BARCODE AREA U.PRICE PRICE AMOUNT.
        final moneyIndexes = <int>[];
        for (var i = 0; i < tokens.length; i++) {
          if (money.hasMatch(tokens[i])) moneyIndexes.add(i);
        }
        if (moneyIndexes.length < 3) continue;
        final lastThree = moneyIndexes.sublist(moneyIndexes.length - 3);
        if (lastThree[1] != lastThree[0] + 1 ||
            lastThree[2] != lastThree[1] + 1) {
          // OCR sometimes inserts a space into columns; use the last three prices
          // if the first price is still recognizable.
          if (lastThree.length != 3) continue;
        }

        final qty = double.tryParse(tokens.first.replaceAll(',', ''));
        final unit = tokens.length > 1 ? tokens[1] : '';
        if (qty == null || qty <= 0 || !units.hasMatch(unit)) continue;

        final code = tokens.length > 2 ? tokens[2] : '';
        if (!RegExp(r'^[A-Za-z0-9-]{3,}$').hasMatch(code)) continue;

        final unitPriceIndex = lastThree[0];
        // Remove leading qty/unit/code and the trailing barcode/area/price columns.
        final descriptionEnd = unitPriceIndex - 2;
        if (descriptionEnd <= 3) continue;
        final name = tokens.sublist(3, descriptionEnd).join(' ').trim();
        final unitPrice = _parseMoney(tokens[unitPriceIndex]);
        if (name.length < 3 ||
            ignored.hasMatch(name) ||
            unitPrice == null ||
            unitPrice <= 0) {
          continue;
        }

        final key =
            '${code.toLowerCase()}|${name.toLowerCase()}|${unitPrice.toStringAsFixed(2)}';
        if (!seen.add(key)) continue;
        found.add(ReceiptItemDraft(
          code: code,
          name: name,
          quantity: qty,
          unit: unit,
          unitPrice: unitPrice,
        ));
      }
    }

    // Fallback for OCR layouts where line blocks merge the columns.
    if (found.isEmpty) {
      final fallback = RegExp(
        r'^(\d{1,4})\s+(CS|CASE|PC|PCS|BOX|BTL|PK|PACK|UNIT|KG|G|L|ML|BAG|CTN|DOZ)\s+([A-Z0-9-]{3,})\s+(.+?)\s+(\d[\d,]*\.\d{2})\s+(\d[\d,]*\.\d{2})\s+(\d[\d,]*\.\d{2})$',
        caseSensitive: false,
      );
      for (final rawLine in result.text.split('\n')) {
        final line = rawLine.trim().replaceAll(RegExp(r'\s+'), ' ');
        final match = fallback.firstMatch(line);
        if (match == null) continue;
        final qty = double.tryParse(match.group(1)!) ?? 1;
        final unit = match.group(2)!;
        final code = match.group(3)!;
        final name = match.group(4)!.trim();
        final unitPrice = _parseMoney(match.group(5)!);
        if (name.length < 3 ||
            ignored.hasMatch(name) ||
            unitPrice == null ||
            unitPrice <= 0) {
          continue;
        }
        final key =
            '${code.toLowerCase()}|${name.toLowerCase()}|${unitPrice.toStringAsFixed(2)}';
        if (seen.add(key)) {
          found.add(ReceiptItemDraft(
              code: code,
              name: name,
              quantity: qty,
              unit: unit,
              unitPrice: unitPrice));
        }
      }
    }
    return found;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Scan receipt',
              style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (saved)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: ink, borderRadius: BorderRadius.circular(22)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AUTOMATIC SCAN',
                        style: TextStyle(
                            color: green,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4)),
                    const SizedBox(height: 8),
                    const Text(
                        'Choose a receipt.\nWe’ll read the product prices.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            height: 1.2)),
                    const SizedBox(height: 8),
                    Text(
                        'Supplier folder: ${supplierName ?? 'Choose a company when you scan'}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .75),
                            height: 1.4)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: (scanning || choosingImage)
                            ? null
                            : () => scan(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Take photo'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: .4))),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: FilledButton.icon(
                        onPressed: (scanning || choosingImage)
                            ? null
                            : () => scan(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose image'),
                        style: FilledButton.styleFrom(
                            backgroundColor: green, foregroundColor: ink),
                      )),
                    ]),
                    if (scanning)
                      const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: LinearProgressIndicator()),
                  ]),
            ),
            if (imagePath != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(File(imagePath!),
                      height: 190,
                      fit: BoxFit.contain,
                      alignment: Alignment.center)),
            ],
            if (statusMessage != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: saved ? const Color(0xFFFFE9D9) : Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(
                      saved
                          ? Icons.check_circle_rounded
                          : Icons.auto_awesome_rounded,
                      color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(statusMessage!,
                          style: const TextStyle(
                              color: ink, fontWeight: FontWeight.w700))),
                ]),
              ),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(
                    child: Text('Detected products',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ink))),
                Text('${items.length} found',
                    style: const TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(
                            child: Text(item.name,
                                style: const TextStyle(
                                    color: ink, fontWeight: FontWeight.w600))),
                        const SizedBox(width: 12),
                        Text(money.format(item.unitPrice),
                            style: const TextStyle(
                                color: ink, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  )),
              const SizedBox(height: 6),
              const Text(
                  'These rows were extracted automatically. Please note that OCR can still misread small or blurry print.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFFFEFEC),
                    borderRadius: BorderRadius.circular(14)),
                child: Text(error!,
                    style:
                        const TextStyle(color: Color(0xFF9D2D21), height: 1.4)),
              ),
            ],
            if (!scanning && !saved && imagePath == null) ...[
              const SizedBox(height: 22),
              const EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'Ready when you are',
                  subtitle:
                      'Choose a receipt image and Receiptly will extract product names and unit prices, then save them to the selected supplier folder.'),
            ],
          ],
        ),
      );
}
