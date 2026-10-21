import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://djzxjupdpvxpuyfbdpuz.supabase.co';
const supabasePublishableKey = 'sb_publishable_n4OxKgiO8xKcfS2gUXP61A_OJMyjzZG';
const receiptBucket = 'receipts';

final supabase = Supabase.instance.client;

String _itemNameFromRow(Map<String, dynamic> row, [String fallback = '']) =>
    (row['product_name'] ??
            row['name'] ??
            row['item_name'] ??
            row['product'] ??
            fallback)
        .toString();

double _itemPriceFromRow(Map<String, dynamic> row, [double fallback = 0]) =>
    _toDouble(row['unit_price'] ??
        row['price'] ??
        row['item_price'] ??
        row['amount'] ??
        fallback);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const ReceiptlyApp());
}

class AppColors {
  static const orange = Color(0xFFE85014);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFF9F9F9);
  static const gray = Color(0xFF646464);
  static const lightGray = Color(0xFFA7A7A7);
  static const darkGray = Color(0xFF333333);
  static const background = Color(0xFFF4F4F4);
  static const border = Color(0xFFE8E8E8);
  static const decrease = Color(0xFF21865B);
}

class ReceiptProduct {
  ReceiptProduct({
    required this.name,
    required this.price,
    this.id,
  });

  final String name;
  final double price;
  final dynamic id;
}

class ReceiptInvoice {
  ReceiptInvoice({
    required this.id,
    required this.number,
    required this.date,
    required this.total,
    this.imagePath,
    this.imageUrl,
  });

  final dynamic id;
  String number;
  DateTime date;
  double total;
  String? imagePath;
  String? imageUrl;
  final List<ReceiptProduct> products = [];
}

class Supplier {
  Supplier({required this.name, this.id});

  final dynamic id;
  String name;
  final List<ReceiptInvoice> invoices = [];
}

class ReceiptlyApp extends StatelessWidget {
  const ReceiptlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receiptly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.orange,
          primary: AppColors.orange,
          surface: AppColors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.black,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.white,
          hintStyle: const TextStyle(color: AppColors.lightGray),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
          ),
        ),
      ),
      home: const ReceiptlyHome(),
    );
  }
}

class ReceiptlyHome extends StatefulWidget {
  const ReceiptlyHome({super.key});

  @override
  State<ReceiptlyHome> createState() => _ReceiptlyHomeState();
}

class _ReceiptlyHomeState extends State<ReceiptlyHome> {
  int _selectedTab = 0;
  bool _loading = true;
  final List<Supplier> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Expected columns:
      // suppliers: id, name
      // Actual schema: receipts(id, supplier, invoice_no, receipt_date, total, image_path, raw_text, created_at)
      // receipt_items(id, receipt_id, code, name, unit, quantity, unit_price, created_at)
      final supplierRows = await supabase.from('suppliers').select();
      final receiptRows = await supabase.from('receipts').select();
      final itemRows = await supabase.from('receipt_items').select();

      final byName = <String, Supplier>{};
      for (final row in supplierRows) {
        final name = (row['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        byName[name.toLowerCase()] = Supplier(name: name, id: row['id']);
      }

      for (final row in receiptRows) {
        final name = (row['supplier'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final supplier = byName.putIfAbsent(
          name.toLowerCase(),
          () => Supplier(name: name),
        );
        final imagePath = row['image_path']?.toString();
        final invoice = ReceiptInvoice(
          id: row['id'],
          number: (row['invoice_no'] ?? '').toString(),
          date: DateTime.tryParse(
                (row['receipt_date'] ?? '').toString(),
              ) ??
              DateTime.now(),
          total: _toDouble(row['total']),
          imagePath: imagePath,
          imageUrl: await _signedImageUrl(imagePath),
        );
        supplier.invoices.add(invoice);
      }

      final invoicesById = <String, ReceiptInvoice>{};
      for (final supplier in byName.values) {
        for (final invoice in supplier.invoices) {
          invoicesById[invoice.id.toString()] = invoice;
        }
      }
      for (final row in itemRows) {
        final invoice = invoicesById[(row['receipt_id'] ?? '').toString()];
        if (invoice == null) continue;
        invoice.products.add(
          ReceiptProduct(
            id: row['id'],
            name: _itemNameFromRow(row),
            price: _itemPriceFromRow(row),
          ),
        );
      }
      for (final supplier in byName.values) {
        supplier.invoices.sort((a, b) => b.date.compareTo(a.date));
        for (final invoice in supplier.invoices) {
          // Recalculate from saved items for display consistency.
          if (invoice.products.isNotEmpty) {
            invoice.total =
                invoice.products.fold(0, (sum, item) => sum + item.price);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _suppliers
          ..clear()
          ..addAll(byName.values.toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase())));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(
          'Could not load Receiptly data. Check your table columns and RLS policies.\n$error');
    }
  }

  Future<String?> _signedImageUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await supabase.storage
          .from(receiptBucket)
          .createSignedUrl(path, 60 * 60);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createSupplier() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CreateSupplierDialog(),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    final trimmed = name.trim();
    if (_suppliers.any((s) => s.name.toLowerCase() == trimmed.toLowerCase())) {
      _showError('This supplier already exists.');
      return;
    }
    try {
      final row = await supabase
          .from('suppliers')
          .insert({'name': trimmed})
          .select()
          .single();
      if (!mounted) return;
      setState(() => _suppliers.add(Supplier(name: trimmed, id: row['id'])));
    } catch (error) {
      _showError(
          'Could not create supplier. Check suppliers.name and RLS.\n$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openSupplier(Supplier supplier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierDetailPage(
          supplier: supplier,
          onChanged: _loadData,
        ),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.white, size: 21),
            ),
            const SizedBox(width: 10),
            const Text('receiptly',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    letterSpacing: -1)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _selectedTab == 0
                ? _buildSuppliersPage()
                : _buildComparisonPage(),
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: _createSupplier,
              backgroundColor: AppColors.orange,
              foregroundColor: AppColors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New supplier'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.orange.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded, color: AppColors.orange),
            label: 'Suppliers',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_rounded),
            selectedIcon:
                Icon(Icons.compare_arrows_rounded, color: AppColors.orange),
            label: 'Compare',
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersPage() {
    final invoiceCount = _suppliers.fold<int>(
        0, (sum, supplier) => sum + supplier.invoices.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        const Text('Your inventory,\nwithout the guesswork.',
            style: TextStyle(
                fontSize: 28,
                height: 1.15,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text(
          'Track supplier invoices and spot price changes over time.',
          style: TextStyle(color: AppColors.gray, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: SummaryCard(
                label: 'SUPPLIERS',
                value: '${_suppliers.length}',
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SummaryCard(
                label: 'INVOICES',
                value: '$invoiceCount',
                icon: Icons.receipt_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Supplier folders',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${_suppliers.length} total',
                style: const TextStyle(color: AppColors.gray, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 14),
        if (_suppliers.isEmpty)
          EmptyState(
            icon: Icons.folder_open_rounded,
            title: 'Nothing here yet',
            message:
                'Create a supplier folder to start organizing your invoices.',
            buttonLabel: 'Create supplier',
            onPressed: _createSupplier,
          )
        else
          ..._suppliers.map((supplier) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SupplierCard(
                  supplier: supplier,
                  onTap: () => _openSupplier(supplier),
                ),
              )),
      ],
    );
  }

  Widget _buildComparisonPage() {
    final available =
        _suppliers.where((supplier) => supplier.invoices.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const Text('Price comparison',
            style: TextStyle(
                fontSize: 28,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'See how product prices change between invoices from the same supplier.',
          style: TextStyle(color: AppColors.gray, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (available.isEmpty)
          const EmptyState(
            icon: Icons.compare_arrows_rounded,
            title: 'Nothing to compare yet',
            message:
                'Add invoices to your supplier folders. Price changes will appear here.',
          )
        else
          ...available.map((supplier) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: SupplierComparison(supplier: supplier),
              )),
      ],
    );
  }
}

class CreateSupplierDialog extends StatefulWidget {
  const CreateSupplierDialog({super.key});

  @override
  State<CreateSupplierDialog> createState() => _CreateSupplierDialogState();
}

class _CreateSupplierDialogState extends State<CreateSupplierDialog> {
  final _controller = TextEditingController();

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: const Text('New supplier',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Supplier name',
          hintText: 'e.g. Suysing Company',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.gray)),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create folder')),
      ],
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 22),
          const SizedBox(height: 18),
          Text(value,
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray)),
        ],
      ),
    );
  }
}

class SupplierCard extends StatelessWidget {
  const SupplierCard({super.key, required this.supplier, required this.onTap});
  final Supplier supplier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 49,
                width: 49,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.folder_rounded,
                    color: AppColors.orange, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(
                      '${supplier.invoices.length} ${supplier.invoices.length == 1 ? 'invoice' : 'invoices'}',
                      style:
                          const TextStyle(color: AppColors.gray, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.lightGray, size: 25),
            ],
          ),
        ),
      ),
    );
  }
}

class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({
    super.key,
    required this.supplier,
    required this.onChanged,
  });
  final Supplier supplier;
  final VoidCallback onChanged;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _addInvoice() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add invoice',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Take a photo or choose an existing image.',
                  style: TextStyle(color: AppColors.gray)),
              const SizedBox(height: 18),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.orange),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppColors.orange),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null || !mounted) return;
      // Avoid launching the native cropper, which was disconnecting the Android
      // process on this device. The selected original image is uploaded safely.
      if (!mounted) return;
      // Number invoices sequentially within this supplier folder. Dates are
      // assigned automatically when the photo is selected.
      final invoiceNumber = '#${_nextInvoiceNumber()}';
      final invoiceDate = DateTime.now();

      setState(() => _busy = true);
      final file = File(picked.path);
      final storagePath =
          '${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(invoiceNumber)}${_extensionFor(picked.path)}';
      await supabase.storage.from(receiptBucket).upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFor(picked.path),
            ),
          );

      try {
        final row = await supabase
            .from('receipts')
            .insert({
              'supplier': widget.supplier.name,
              'invoice_no': invoiceNumber,
              'receipt_date': invoiceDate.toIso8601String().split('T').first,
              'total': 0,
              'image_path': storagePath,
            })
            .select()
            .single();

        final invoice = ReceiptInvoice(
          id: row['id'],
          number: (row['invoice_no'] ?? invoiceNumber).toString(),
          date: DateTime.tryParse((row['receipt_date'] ?? '').toString()) ??
              invoiceDate,
          total: _toDouble(row['total']),
          imagePath: storagePath,
          imageUrl: await supabase.storage
              .from(receiptBucket)
              .createSignedUrl(storagePath, 3600),
        );
        if (!mounted) return;
        setState(() {
          widget.supplier.invoices.add(invoice);
          widget.supplier.invoices.sort((a, b) => b.date.compareTo(a.date));
        });
        widget.onChanged();
        _message('Invoice saved. Add its products next.');
        _openInvoice(invoice);
      } catch (_) {
        // Avoid leaving an orphaned object if receipt insertion fails.
        await supabase.storage.from(receiptBucket).remove([storagePath]);
        rethrow;
      }
    } catch (error) {
      _message(
          'Could not add invoice. Check schema, bucket access, and RLS.\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _nextInvoiceNumber() {
    var highest = 0;
    for (final invoice in widget.supplier.invoices) {
      final match = RegExp(r'^#?(\d+)$').firstMatch(invoice.number.trim());
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > highest) highest = number;
    }
    return highest + 1;
  }

  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _extensionFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['png', 'webp', 'heic', 'jpg', 'jpeg'].contains(ext)
        ? '.$ext'
        : '.jpg';
  }

  String _contentTypeFor(String path) {
    switch (path.split('.').last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _openInvoice(ReceiptInvoice invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(
          supplier: widget.supplier,
          invoice: invoice,
          onChanged: widget.onChanged,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoices = [...widget.supplier.invoices]
      ..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addInvoice,
        backgroundColor: AppColors.orange,
        foregroundColor: AppColors.white,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.document_scanner_outlined),
        label: Text(_busy ? 'Saving...' : 'Scan invoice'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SUPPLIER FOLDER',
                          style: TextStyle(
                              color: AppColors.lightGray,
                              fontSize: 10,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 8),
                      Text('Your invoice history.',
                          style: TextStyle(
                              color: AppColors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Icon(Icons.folder_special_outlined,
                    size: 36, color: AppColors.orange),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text('Invoices (${invoices.length})',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (invoices.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No invoices yet',
              message:
                  'Scan a receipt or invoice to start tracking this supplier’s prices.',
            )
          else
            ...invoices.map((invoice) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InvoiceCard(
                    invoice: invoice,
                    onTap: () => _openInvoice(invoice),
                  ),
                )),
        ],
      ),
    );
  }
}

class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice, required this.onTap});
  final ReceiptInvoice invoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 49,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.darkGray),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invoice ${invoice.number}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(formatDate(invoice.date),
                        style: const TextStyle(
                            color: AppColors.gray, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text('${invoice.products.length} products',
                        style: const TextStyle(
                            color: AppColors.lightGray, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.lightGray),
            ],
          ),
        ),
      ),
    );
  }
}

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({
    super.key,
    required this.supplier,
    required this.invoice,
    required this.onChanged,
  });
  final Supplier supplier;
  final ReceiptInvoice invoice;
  final VoidCallback onChanged;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool _saving = false;

  Future<void> _addProduct() async {
    final product = await showDialog<ReceiptProduct>(
      context: context,
      builder: (_) => const AddProductDialog(),
    );
    if (product == null || !mounted) return;
    setState(() => _saving = true);
    try {
      Map<String, dynamic>? row;
      Object? lastInsertError;
      // Existing projects use different naming conventions for these two fields.
      // Try common variants; PostgREST rejects unknown columns without saving a row.
      for (final nameColumn in [
        'name',
        'product_name',
        'item_name',
        'product'
      ]) {
        for (final priceColumn in [
          'unit_price',
          'price',
          'item_price',
          'amount'
        ]) {
          try {
            row = await supabase
                .from('receipt_items')
                .insert({
                  'receipt_id': widget.invoice.id,
                  nameColumn: product.name,
                  priceColumn: product.price,
                  'unit': 'unit',
                  'quantity': 1,
                })
                .select()
                .single();
            break;
          } catch (error) {
            lastInsertError = error;
          }
        }
        if (row != null) break;
      }
      if (row == null) {
        throw Exception(
            'Could not insert receipt item. Verify receipt_items columns and RLS. $lastInsertError');
      }
      final saved = ReceiptProduct(
        id: row['id'],
        name: _itemNameFromRow(row, product.name),
        price: _itemPriceFromRow(row, product.price),
      );
      final updatedTotal = widget.invoice.products.fold<double>(
            0,
            (sum, item) => sum + item.price,
          ) +
          saved.price;
      await supabase
          .from('receipts')
          .update({'total': updatedTotal}).eq('id', widget.invoice.id);
      if (!mounted) return;
      setState(() {
        widget.invoice.products.add(saved);
        widget.invoice.total = updatedTotal;
      });
      await _persistPriceComparisonItems();
      widget.onChanged();
    } catch (error) {
      _message(
          'Could not save product. Check receipt_items columns and RLS.\n$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeProduct(ReceiptProduct product) async {
    try {
      if (product.id != null) {
        await supabase.from('receipt_items').delete().eq('id', product.id);
      }
      final next = widget.invoice.products
          .where((item) => item != product)
          .fold<double>(0, (sum, item) => sum + item.price);
      await supabase
          .from('receipts')
          .update({'total': next}).eq('id', widget.invoice.id);
      if (!mounted) return;
      setState(() {
        widget.invoice.products.remove(product);
        widget.invoice.total = next;
      });
      await _persistPriceComparisonItems();
      widget.onChanged();
    } catch (error) {
      _message('Could not remove product.\n$error');
    }
  }

  Future<void> _persistPriceComparisonItems() async {
    try {
      final receipts = await supabase
          .from('receipts')
          .select('id,supplier,receipt_date,invoice_no')
          .eq('supplier', widget.supplier.name)
          .order('receipt_date', ascending: false)
          .limit(2);
      if (receipts.isEmpty) return;
      final ids = receipts.map((r) => r['id']).toList();
      final itemRows = await supabase
          .from('receipt_items')
          .select('receipt_id,code,name,unit,quantity,unit_price')
          .inFilter('receipt_id', ids);

      // Keep the comparison table aligned with the latest two invoices.
      await supabase
          .from('price_comparison_items')
          .delete()
          .eq('supplier', widget.supplier.name);
      final receiptById = <String, Map<String, dynamic>>{
        for (final receipt in receipts) receipt['id'].toString(): receipt,
      };
      final rows = <Map<String, dynamic>>[];
      for (final item in itemRows) {
        final receipt = receiptById[(item['receipt_id'] ?? '').toString()];
        if (receipt == null) continue;
        rows.add({
          'receipt_id': item['receipt_id'],
          'code': item['code'],
          'name': item['name'],
          'unit': item['unit'] ?? 'unit',
          'quantity': item['quantity'] ?? 1,
          'unit_price': item['unit_price'],
          'supplier': receipt['supplier'],
          'receipt_date': receipt['receipt_date'],
          'invoice_no': receipt['invoice_no'],
        });
      }
      if (rows.isNotEmpty) {
        await supabase.from('price_comparison_items').insert(rows);
      }
    } catch (error) {
      // Product saving should remain successful even if comparison-table RLS
      // has not been configured yet. Surface this only in debug logs.
      debugPrint('Could not refresh price comparison items: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final imageProvider = invoice.imageUrl != null
        ? NetworkImage(invoice.imageUrl!)
        : invoice.imagePath != null && File(invoice.imagePath!).existsSync()
            ? FileImage(File(invoice.imagePath!)) as ImageProvider
            : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice details',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Add product',
            onPressed: _saving ? null : _addProduct,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addProduct,
        backgroundColor: AppColors.orange,
        foregroundColor: AppColors.white,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_saving ? 'Saving...' : 'Add product'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          if (imageProvider != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                color: AppColors.white,
                child: InkWell(
                  onTap: () => _showFullImage(context, imageProvider),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image(
                        image: imageProvider,
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imageUnavailable(),
                      ),
                      Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_out_map_rounded,
                                size: 14, color: Colors.white),
                            SizedBox(width: 5),
                            Text('View image',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            _imageUnavailable(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.storefront_outlined,
                    size: 28, color: AppColors.orange),
                const SizedBox(height: 10),
                Text(widget.supplier.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                const Text('INVOICE',
                    style: TextStyle(
                        color: AppColors.gray, letterSpacing: 2, fontSize: 11)),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                ReceiptInfoRow(label: 'Invoice', value: invoice.number),
                const SizedBox(height: 10),
                ReceiptInfoRow(
                    label: 'Invoice date', value: formatDate(invoice.date)),
                const SizedBox(height: 10),
                ReceiptInfoRow(
                    label: 'Total', value: formatPeso(invoice.total)),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 15),
                const Row(
                  children: [
                    Expanded(
                      child: Text('PRODUCT',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.gray,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w700)),
                    ),
                    Text('UNIT PRICE',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.gray,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700)),
                    SizedBox(width: 34),
                  ],
                ),
                const SizedBox(height: 15),
                if (invoice.products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      'No products added yet.\nAdd items from this invoice below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray, height: 1.5),
                    ),
                  )
                else
                  ...invoice.products.map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(product.name,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(formatPeso(product.price),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          SizedBox(
                            width: 34,
                            child: IconButton(
                              tooltip: 'Remove product',
                              visualDensity: VisualDensity.compact,
                              onPressed: _saving
                                  ? null
                                  : () => _removeProduct(product),
                              icon: const Icon(Icons.close_rounded,
                                  size: 17, color: AppColors.lightGray),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(),
                const SizedBox(height: 14),
                const Text('Thank you for your business.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.lightGray,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Product details are entered manually. Automatic receipt text extraction is not implemented yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.gray, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, ImageProvider imageProvider) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image(
                    image: imageProvider,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                      'Unable to load receipt image',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 16,
              child: SafeArea(
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close image',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageUnavailable() => Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text('Receipt image unavailable'),
      );
}

class AddProductDialog extends StatefulWidget {
  const AddProductDialog({super.key});

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final price =
        double.tryParse(_priceController.text.trim().replaceAll(',', ''));
    if (name.isEmpty || price == null || price < 0) return;
    Navigator.pop(context, ReceiptProduct(name: name, price: price));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: const Text('Add product',
          style: TextStyle(
              fontSize: 22, letterSpacing: -0.5, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Product name', hintText: 'e.g. Nova'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Unit price (₱)',
                hintText: 'e.g. 8.00',
                prefixText: '₱ '),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.gray,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          child: const Text('Add product'),
        ),
      ],
    );
  }
}

class ReceiptInfoRow extends StatelessWidget {
  const ReceiptInfoRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: AppColors.gray, fontSize: 12)),
        ),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    );
  }
}

class PriceChange {
  const PriceChange({
    required this.name,
    required this.previous,
    required this.current,
  });
  final String name;
  final double previous;
  final double current;
  double get difference => current - previous;
}

class SupplierComparison extends StatelessWidget {
  const SupplierComparison({super.key, required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final invoices = [...supplier.invoices]
      ..sort((a, b) => a.date.compareTo(b.date));
    final previous =
        invoices.length >= 2 ? invoices[invoices.length - 2] : null;
    final latest = invoices.isNotEmpty ? invoices.last : null;
    final comparisons = <PriceChange>[];
    if (previous != null && latest != null) {
      for (final currentProduct in latest.products) {
        ReceiptProduct? oldProduct;
        for (final product in previous.products) {
          if (product.name.trim().toLowerCase() ==
              currentProduct.name.trim().toLowerCase()) {
            oldProduct = product;
            break;
          }
        }
        if (oldProduct != null) {
          comparisons.add(PriceChange(
            name: currentProduct.name,
            previous: oldProduct.price,
            current: currentProduct.price,
          ));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.storefront_outlined,
                    color: AppColors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(supplier.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 17),
          if (previous == null || latest == null)
            const Text('Add at least two invoices to compare prices.',
                style: TextStyle(color: AppColors.gray, fontSize: 13))
          else ...[
            Row(
              children: [
                Expanded(
                    child:
                        InvoiceDateLabel(label: 'PREVIOUS', invoice: previous)),
                const SizedBox(width: 8),
                Expanded(
                    child: InvoiceDateLabel(label: 'LATEST', invoice: latest)),
              ],
            ),
            const SizedBox(height: 17),
            const Divider(),
            const SizedBox(height: 8),
            if (comparisons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('No matching products found in these two invoices.',
                    style: TextStyle(color: AppColors.gray, fontSize: 12)),
              )
            else
              ...comparisons.map((change) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(change.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatPeso(change.previous),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  color: AppColors.gray, fontSize: 11)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatPeso(change.current),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                        const SizedBox(width: 7),
                        SizedBox(
                            width: 75, child: ChangeIndicator(change: change)),
                      ],
                    ),
                  )),
            const SizedBox(height: 5),
            const Text('Only products present in both invoices are compared.',
                style: TextStyle(fontSize: 10, color: AppColors.lightGray)),
          ],
        ],
      ),
    );
  }
}

class InvoiceDateLabel extends StatelessWidget {
  const InvoiceDateLabel(
      {super.key, required this.label, required this.invoice});
  final String label;
  final ReceiptInvoice invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.gray,
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(formatDate(invoice.date),
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          Text(invoice.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.gray, fontSize: 10)),
        ],
      ),
    );
  }
}

class ChangeIndicator extends StatelessWidget {
  const ChangeIndicator({super.key, required this.change});
  final PriceChange change;

  @override
  Widget build(BuildContext context) {
    final difference = change.difference;
    final color = difference > 0
        ? AppColors.orange
        : difference < 0
            ? AppColors.decrease
            : AppColors.gray;
    final icon = difference > 0
        ? Icons.arrow_upward_rounded
        : difference < 0
            ? Icons.arrow_downward_rounded
            : Icons.remove_rounded;
    final label = difference == 0
        ? '₱0.00'
        : '${difference > 0 ? '+' : '-'}${formatPeso(difference.abs())}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AppColors.orange, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.gray, height: 1.5, fontSize: 13)),
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
          ],
        ],
      ),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String formatPeso(double value) => '₱${value.toStringAsFixed(2)}';
