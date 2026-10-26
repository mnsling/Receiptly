import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'receipt_ocr_service.dart';
import 'receipt_crop_page.dart';
const supabaseUrl = 'https://djzxjupdpvxpuyfbdpuz.supabase.co';
const supabasePublishableKey =
    'sb_publishable_n4OxKgiO8xKcfS2gUXP61A_OJMyjzZG';
const receiptBucket = 'receipts';
final supabase = Supabase.instance.client;
String _itemNameFromRow(Map<String, dynamic> row, [String fallback = '']) =>
    (row['product_name'] ?? row['name'] ?? row['item_name'] ?? row['product'] ?? fallback).toString();
double _itemPriceFromRow(Map<String, dynamic> row, [double fallback = 0]) =>
    _toDouble(row['unit_price'] ?? row['price'] ?? row['item_price'] ?? row['amount'] ?? fallback);
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
    this.createdAt,
    this.imagePath,
    this.imageUrl,
  });
  final dynamic id;
  String number;
  DateTime date;
  double total;
  final DateTime? createdAt;
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
            borderSide:
                const BorderSide(color: AppColors.orange, width: 1.5),
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
  String _supplierSearch = '';
  String _productSearch = '';
  bool _productSortByPrice = true;
  final Set<String> _selectedSearchProducts = <String>{};
  String _searchRowKey(_SupplierLatestPrice item) =>
      '${item.supplier.toLowerCase()}\u001f${item.product.toLowerCase()}';
  final TextEditingController _supplierSearchController = TextEditingController();
  bool _loading = true;
  final List<Supplier> _suppliers = [];
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  @override
  void dispose() {
    _supplierSearchController.dispose();
    super.dispose();
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
        byName[name.toLowerCase()] =
            Supplier(name: name, id: row['id']);
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
          createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()),
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
      }
      if (!mounted) return;
      setState(() {
        _suppliers
          ..clear()
          ..addAll(byName.values.toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Could not load Receiptly data. Check your table columns and RLS policies.\n$error');
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
      _showError('Could not create supplier. Check suppliers.name and RLS.\n$error');
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
                : _selectedTab == 1
                    ? _buildComparisonPage()
                    : _buildProductSearchPage(),
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
            selectedIcon:
                Icon(Icons.folder_rounded, color: AppColors.orange),
            label: 'Suppliers',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_rounded),
            selectedIcon:
                Icon(Icons.compare_arrows_rounded, color: AppColors.orange),
            label: 'Compare',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded, color: AppColors.orange),
            label: 'Search',
          ),
        ],
      ),
    );
  }
  Widget _buildSuppliersPage() {
    final productCount = _suppliers.fold<int>(0,
        (sum, supplier) => sum + _latestSupplierPrices(supplier).length);
    final filteredSuppliers = _suppliers
        .where((supplier) => supplier.name
            .toLowerCase()
            .contains(_supplierSearch.trim().toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
          'Scan receipts to keep each supplier’s product prices up to date.',
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
                label: 'PRODUCTS',
                value: '$productCount',
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
        TextField(
          controller: _supplierSearchController,
          onChanged: (value) => setState(() => _supplierSearch = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search suppliers...',
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gray),
            suffixIcon: _supplierSearch.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _supplierSearchController.clear();
                      setState(() => _supplierSearch = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${filteredSuppliers.length} ${filteredSuppliers.length == 1 ? 'supplier' : 'suppliers'}',
                style: const TextStyle(color: AppColors.gray, fontSize: 12)),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort_by_alpha_rounded, size: 16, color: AppColors.gray),
                SizedBox(width: 5),
                Text('A–Z', style: TextStyle(color: AppColors.gray, fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_suppliers.isEmpty)
          EmptyState(
            icon: Icons.folder_open_rounded,
            title: 'Nothing here yet',
            message: 'Create a supplier to start tracking product prices.',
            buttonLabel: 'Create supplier',
            onPressed: _createSupplier,
          )
        else if (filteredSuppliers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('No matching suppliers found.',
                style: TextStyle(color: AppColors.gray))),
          )
        else
          ...filteredSuppliers.map((supplier) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SupplierCard(
                  supplier: supplier,
                  onTap: () => _openSupplier(supplier),
                ),
              )),
      ],
    );
  }
  void _compareSelectedSearchProducts(List<_SupplierLatestPrice> allRows) {
    final selected = allRows.where(
      (item) => _selectedSearchProducts.contains(_searchRowKey(item)),
    ).toList()..sort((a, b) => a.price.compareTo(b.price));
    final suppliers = selected.map((item) => item.supplier.toLowerCase()).toSet();
    if (selected.length < 2 || suppliers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Select at least two products from different suppliers to compare.',
        )),
      );
      return;
    }
    final lowest = selected.first.price;
    final highest = selected.last.price;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18, 8, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Selected product comparison',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('${selected.length} products from ${suppliers.length} suppliers',
                    style: const TextStyle(color: AppColors.gray)),
                const SizedBox(height: 16),
                const Row(children: [
                  Expanded(flex: 5, child: Text('DESCRIPTION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                  Expanded(flex: 3, child: Text('SUPPLIER',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                  Expanded(flex: 2, child: Text('PRICE',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                ]),
                const Divider(),
                ...selected.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 5, child: Text(item.product,
                        style: const TextStyle(fontSize: 11))),
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: Text(item.supplier,
                        style: const TextStyle(fontSize: 11))),
                    const SizedBox(width: 6),
                    Expanded(flex: 2, child: Text('₱${item.price.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: item.price == lowest
                              ? AppColors.decrease : AppColors.black,
                        ))),
                  ]),
                )),
                const Divider(),
                Text('Recorded price range: ₱${(highest - lowest).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'These are manually selected descriptions, not verified identical products. '
                  'Only compare prices when products and purchase units are equivalent.',
                  style: TextStyle(fontSize: 12, color: AppColors.gray),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSearchPage() {
    // Reuse the latest-per-supplier price calculation. Search never changes
    // product identities or merges similar descriptions into one result.
    final rows = <_SupplierLatestPrice>[];
    for (final supplier in _suppliers) {
      for (final product in _latestSupplierPrices(supplier)) {
        rows.add(_SupplierLatestPrice(
          supplier.name,
          product.name,
          product.price,
          product.previous != null && product.price > product.previous!
              ? product.price - product.previous!
              : 0,
        ));
      }
    }
    // Multiple keywords can appear in any order; supplier names are searchable.
    final terms = _productSearch.toLowerCase().trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final filtered = rows.where((item) {
      final searchable = '${item.product} ${item.supplier}'.toLowerCase();
      return terms.every(searchable.contains);
    }).toList();
    filtered.sort((a, b) {
      if (_productSortByPrice) {
        final byPrice = a.price.compareTo(b.price);
        if (byPrice != 0) return byPrice;
      }
      final byName = a.product.toLowerCase().compareTo(b.product.toLowerCase());
      if (byName != 0) return byName;
      return a.supplier.toLowerCase().compareTo(b.supplier.toLowerCase());
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const Text('Product Search',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Search products across suppliers using their latest recorded prices.',
            style: TextStyle(color: AppColors.gray)),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => _productSearch = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search product or supplier',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('${filtered.length} matching products',
                  style: const TextStyle(fontSize: 12, color: AppColors.gray)),
            ),
            DropdownButton<bool>(
              value: _productSortByPrice,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: true, child: Text('Lowest price')),
                DropdownMenuItem(value: false, child: Text('Product A–Z')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _productSortByPrice = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text('${_selectedSearchProducts.length} selected',
                style: const TextStyle(fontSize: 12, color: AppColors.gray)),
          ),
          TextButton(
            onPressed: _selectedSearchProducts.isEmpty
                ? null
                : () => setState(_selectedSearchProducts.clear),
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selectedSearchProducts.length < 2
                ? null
                : () => _compareSelectedSearchProducts(rows),
            icon: const Icon(Icons.compare_arrows_rounded, size: 17),
            label: const Text('Compare'),
          ),
        ]),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No products found',
            message: 'Try another keyword or add products to your suppliers.',
          )
        else
          Card(
            color: AppColors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 36),
                        Expanded(flex: 5, child: Text('DESCRIPTION',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                        Expanded(flex: 3, child: Text('SUPPLIER',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                        Expanded(flex: 2, child: Text('PRICE', textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...filtered.map((item) => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 36,
                              child: Checkbox(
                                value: _selectedSearchProducts.contains(_searchRowKey(item)),
                                onChanged: (checked) => setState(() {
                                  if (checked == true) {
                                    _selectedSearchProducts.add(_searchRowKey(item));
                                  } else {
                                    _selectedSearchProducts.remove(_searchRowKey(item));
                                  }
                                }),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            Expanded(flex: 5, child: Text(item.product,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                            const SizedBox(width: 6),
                            Expanded(flex: 3, child: Text(item.supplier,
                                style: const TextStyle(fontSize: 11))),
                            const SizedBox(width: 6),
                            Expanded(flex: 2, child: Text('₱${item.price.toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  )),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text('Prices are recorded supplier prices. Verify equivalent units before comparing.',
            style: TextStyle(fontSize: 11, color: AppColors.gray)),
      ],
    );
  }
  Widget _buildComparisonPage() {
    // Match descriptions across suppliers without changing receipt history.
    // A group is formed only when identity, size and variant checks agree.
    final candidates = <_SupplierLatestPrice>[];
    for (final supplier in _suppliers) {
      for (final item in _latestSupplierPrices(supplier)) {
        candidates.add(_SupplierLatestPrice(
          supplier.name, item.name, item.price,
          item.previous != null && item.price > item.previous!
              ? item.price - item.previous! : 0,
        ));
      }
    }
    final clusters = <List<_SupplierLatestPrice>>[];
    for (final candidate in candidates) {
      final matches = clusters.where((cluster) =>
          cluster.every((existing) => _sameProductVariant(
              existing.product, candidate.product))).toList();
      if (matches.length == 1) {
        matches.single.add(candidate);
      } else {
        // Ambiguous matches remain separate instead of merging products.
        clusters.add([candidate]);
      }
    }
    final groups = clusters.where((cluster) =>
        cluster.map((offer) => offer.supplier.toLowerCase()).toSet().length >= 2)
        .toList()
      ..sort((a, b) => a.first.product.compareTo(b.first.product));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        const Text('Compare suppliers',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Automatically match similar descriptions across suppliers. Prices are comparable only when their receipt units are equivalent.',
            style: TextStyle(color: AppColors.gray)),
        const SizedBox(height: 20),
        if (groups.isEmpty)
          const EmptyState(
            icon: Icons.compare_arrows_rounded,
            title: 'No shared products yet',
            message: 'Add or scan the same product from at least two suppliers. Different descriptions can be matched automatically.',
          )
        else
          ...groups.map((group) {
            // One latest offer per supplier in a matched group.
            final bySupplier = <String, _SupplierLatestPrice>{};
            for (final offer in group) {
              final key = offer.supplier.toLowerCase();
              if (!bySupplier.containsKey(key) ||
                  offer.price < bySupplier[key]!.price) {
                bySupplier[key] = offer;
              }
            }
            final offers = bySupplier.values.toList()
              ..sort((a, b) => a.price.compareTo(b.price));
            final lowest = offers.first.price;
            final highest = offers.last.price;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: AppColors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offers.first.product,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    ...offers.map((offer) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(child: Text(offer.supplier)),
                          Text('₱${offer.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: offer.price == lowest
                                    ? AppColors.decrease : AppColors.black,
                              )),
                          if (offer.increase > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text('+₱${offer.increase.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.decrease)),
                            ),
                          if (offer.price == lowest)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.check_circle_outline,
                                  size: 17, color: AppColors.decrease),
                            ),
                        ],
                      ),
                    )),
                    if (highest > lowest) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Recorded unit-price difference: ₱${(highest - lowest).toStringAsFixed(2)} (verify equivalent units)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.decrease,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
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
                  fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
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
                      '${_latestSupplierPrices(supplier).length} ${_latestSupplierPrices(supplier).length == 1 ? 'product' : 'products'}',
                      style: const TextStyle(color: AppColors.gray, fontSize: 12),
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
// Own text controllers inside the dialog, not in the caller. This avoids
// disposing a TextField controller while the closing dialog still animates.
class _ManualProductDialog extends StatefulWidget {
  const _ManualProductDialog();

  @override
  State<_ManualProductDialog> createState() => _ManualProductDialogState();
}

class _ManualProductDialogState extends State<_ManualProductDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final price = double.tryParse(
      _priceController.text.trim().replaceAll(',', ''),
    );
    if (name.isEmpty || price == null || !price.isFinite || price <= 0) {
      setState(() => _error = 'Enter a product name and a price greater than zero.');
      return;
    }
    Navigator.of(context).pop(ReceiptProduct(name: name, price: price));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Product description'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unit price', prefixText: '₱'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
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
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedProductKeys = <String>{};
  String _searchText = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addManualProduct() async {
    try {
      final product = await showDialog<ReceiptProduct>(
        context: context,
        builder: (_) => const _ManualProductDialog(),
      );
      if (!mounted || product == null) return;
      setState(() => _busy = true);
      // Manual entries use a normal receipt record so they survive restart and
      // participate in the same latest-price comparison as scanned items.
      final now = DateTime.now();
      final receiptRow = await supabase.from('receipts').insert({
        'supplier': widget.supplier.name,
        'invoice_no': 'MANUAL-${now.microsecondsSinceEpoch}',
        'receipt_date': now.toIso8601String().split('T').first,
        'total': 0,
        'image_path': '',
      }).select().single();
      final invoice = ReceiptInvoice(
        id: receiptRow['id'],
        number: (receiptRow['invoice_no'] ?? '').toString(),
        date: now,
        createdAt: DateTime.tryParse((receiptRow['created_at'] ?? '').toString()) ?? now,
        total: 0,
      );
      await _insertReceiptProduct(invoice, product);
      if (!mounted) return;
      setState(() {
        widget.supplier.invoices.add(invoice);
      });
      widget.onChanged();
      _message('Product saved.');
    } catch (error) {
      _message('Could not add product. Check Supabase permissions.\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeSelectedProducts() async {
    if (_selectedProductKeys.isEmpty) return;
    final count = _selectedProductKeys.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $count product${count == 1 ? '' : 's'}?'),
        content: const Text(
          'This permanently removes all saved price entries for the selected '
          'products from this supplier, including their past prices. '
          'The scanned receipt images will remain stored. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final selected = Set<String>.from(_selectedProductKeys);
      final ids = <dynamic>[];
      for (final invoice in widget.supplier.invoices) {
        for (final product in invoice.products) {
          if (selected.contains(_productComparisonKey(product.name))) {
            if (product.id == null) {
              throw StateError('A selected item has no database ID.');
            }
            ids.add(product.id);
          }
        }
      }
      // Delete database rows before updating the on-screen list.
      for (final id in ids) {
        final deleted = await supabase.from('receipt_items')
            .delete().eq('id', id).select('id');
        if (deleted.isEmpty) {
          throw StateError('Delete was blocked for item $id. Check RLS.');
        }
      }
      if (!mounted) return;
      setState(() {
        for (final invoice in widget.supplier.invoices) {
          invoice.products.removeWhere(
              (product) => selected.contains(_productComparisonKey(product.name)));
        }
        _selectedProductKeys.clear();
      });
      widget.onChanged();
      _message('Removed $count product${count == 1 ? '' : 's'}.');
    } catch (error) {
      // Reload authoritative data if only part of the operation succeeded.
      widget.onChanged();
      _message('Could not remove all products. Refresh and check permissions.\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


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
              const Text('Scan receipt',
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
      XFile? picked;
      try {
        picked = await _picker.pickImage(
          source: source,
          imageQuality: 92,
          maxWidth: 3000,
          maxHeight: 4000,
          requestFullMetadata: false,
        );
      } catch (cameraError) {
        if (!mounted) return;
        if (source == ImageSource.camera) {
          _message('Camera could not open. Check iPhone Settings > Privacy & Security > Camera > Receiptly. You can select a photo from your library instead. $cameraError');
          try {
            picked = await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 92,
              maxWidth: 3000,
              maxHeight: 4000,
              requestFullMetadata: false,
            );
          } catch (galleryError) {
            _message('Could not open Photos: $galleryError');
            return;
          }
        } else {
          _message('Could not open Photos: $cameraError');
          return;
        }
      }
      if (picked == null || !mounted) return;
      final croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ReceiptCropPage(imagePath: picked!.path)),
      );
      if (croppedPath == null || !mounted) return;
      final scanPath = croppedPath;
      // Number invoices sequentially within this supplier folder. Dates are
      // assigned automatically when the photo is selected.
      final invoiceNumber = '#${_nextInvoiceNumber()}';
      final invoiceDate = DateTime.now();
      setState(() => _busy = true);
      final file = File(scanPath);
      final storagePath =
          '${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(invoiceNumber)}${_extensionFor(scanPath)}';
      await supabase.storage.from(receiptBucket).upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFor(scanPath),
            ),
          );
      try {
        final row = await supabase.from('receipts').insert({
          'supplier': widget.supplier.name,
          'invoice_no': invoiceNumber,
          'receipt_date': invoiceDate.toIso8601String().split('T').first,
          'total': 0,
          'image_path': storagePath,
        }).select().single();
        final invoice = ReceiptInvoice(
          id: row['id'],
          number: (row['invoice_no'] ?? invoiceNumber).toString(),
          date: DateTime.tryParse((row['receipt_date'] ?? '').toString()) ?? invoiceDate,
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
        await _scanAndReviewProducts(scanPath, invoice);
      } catch (_) {
        // Avoid leaving an orphaned object if receipt insertion fails.
        await supabase.storage.from(receiptBucket).remove([storagePath]);
        rethrow;
      }
    } catch (error) {
      _message('Could not scan receipt. Check schema, bucket access, and RLS.\n$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _scanAndReviewProducts(
    String imagePath,
    ReceiptInvoice invoice,
  ) async {
    final ocr = ReceiptOcrService();
    try {
      if (mounted) {
        setState(() => _busy = true);
        _message('Reading product descriptions and unit prices...');
      }
      final result = await ocr.scanFile(imagePath);
      if (!mounted) return;
      if (result.products.isEmpty) {
        final details = result.warnings.isEmpty
            ? 'No products were detected. You can add them manually.'
            : result.warnings.join('\n');
        _message('OCR could not identify product rows. $details');
        return;
      }
      final reviewed = await showDialog<List<ReceiptProduct>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OcrReviewDialog(
          products: result.products,
          warnings: result.warnings,
        ),
      );
      if (!mounted) return;
      if (reviewed != null && reviewed.isNotEmpty) {
        setState(() => _busy = true);
        var savedCount = 0;
        for (final product in reviewed) {
          await _insertReceiptProduct(invoice, product);
          savedCount++;
        }
        _message('Saved $savedCount reviewed product${savedCount == 1 ? '' : 's'}.');
        widget.onChanged();
      } else {
        _message('No OCR products saved. You can add products manually.');
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      _message('Could not read this image with OCR. You can add products manually.\n$error');
    } finally {
      await ocr.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _insertReceiptProduct(
    ReceiptInvoice invoice,
    ReceiptProduct product,
  ) async {
    Map<String, dynamic>? row;
    Object? lastInsertError;
    for (final nameColumn in ['name', 'product_name', 'item_name', 'product']) {
      for (final priceColumn in ['unit_price', 'price', 'item_price', 'amount']) {
        try {
          row = await supabase.from('receipt_items').insert({
            'receipt_id': invoice.id,
            nameColumn: product.name,
            priceColumn: product.price,
            'unit': 'unit',
            'quantity': 1,
          }).select().single();
          break;
        } catch (error) {
          lastInsertError = error;
        }
      }
      if (row != null) break;
    }
    if (row == null) {
      throw Exception('Could not save "${product.name}". Check receipt_items columns and RLS. $lastInsertError');
    }
    invoice.products.add(ReceiptProduct(
      id: row['id'],
      name: _itemNameFromRow(row, product.name),
      price: _itemPriceFromRow(row, product.price),
    ));
    // Invoice totals are intentionally not calculated or written. Receiptly
    // tracks individual unit prices only.
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
    return ['png', 'webp', 'heic', 'jpg', 'jpeg'].contains(ext) ? '.$ext' : '.jpg';
  }
  String _contentTypeFor(String path) {
    switch (path.split('.').last.toLowerCase()) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'heic': return 'image/heic';
      default: return 'image/jpeg';
    }
  }
  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
  @override
  Widget build(BuildContext context) {
    final products = _latestSupplierPrices(widget.supplier);
    final visible = products.where((product) =>
        product.name.toLowerCase().contains(_searchText.toLowerCase())).toList();
    final allVisibleSelected = visible.isNotEmpty &&
        visible.every((product) => _selectedProductKeys.contains(product.key));
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
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.document_scanner_outlined),
        label: Text(_busy ? 'Saving...' : 'Scan receipt'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text('${products.length} products · Latest recorded prices',
              style: const TextStyle(color: AppColors.gray)),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchText = value),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search products',
              suffixIcon: _searchText.isEmpty ? null : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchText = '');
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: allVisibleSelected,
                onChanged: _busy || visible.isEmpty ? null : (checked) {
                  setState(() {
                    for (final product in visible) {
                      if (checked == true) {
                        _selectedProductKeys.add(product.key);
                      } else {
                        _selectedProductKeys.remove(product.key);
                      }
                    }
                  });
                },
              ),
              Expanded(child: Text('${_selectedProductKeys.length} selected',
                  style: const TextStyle(fontSize: 12, color: AppColors.gray))),
              if (_selectedProductKeys.isNotEmpty)
                IconButton(
                  tooltip: 'Remove selected products',
                  onPressed: _busy ? null : _removeSelectedProducts,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
              TextButton.icon(
                onPressed: _busy ? null : _addManualProduct,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add row'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No products yet',
              message: 'Scan a delivery receipt or add a product manually.',
            )
          else if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No matching products.')),
            )
          else
            Card(
              color: AppColors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(width: 36),
                          Expanded(flex: 5, child: Text('PRODUCT',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                          Expanded(flex: 2, child: Text('PRICE',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                          Expanded(flex: 2, child: Text('INCREASE',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ...visible.map((product) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          SizedBox(width: 36, child: Checkbox(
                            value: _selectedProductKeys.contains(product.key),
                            onChanged: _busy ? null : (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedProductKeys.add(product.key);
                                } else {
                                  _selectedProductKeys.remove(product.key);
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          )),
                          Expanded(flex: 5, child: Text(product.name,
                              style: const TextStyle(fontSize: 12))),
                          Expanded(flex: 2, child: Text(
                              '₱${product.price.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                          Expanded(flex: 2, child: Text(
                              product.previous != null && product.price > product.previous!
                                  ? '+₱${(product.price - product.previous!).toStringAsFixed(2)}'
                                  : '—',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: product.previous != null &&
                                          product.price > product.previous!
                                      ? AppColors.decrease : AppColors.gray))),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

}
class OcrReviewDialog extends StatefulWidget {
  const OcrReviewDialog({
    super.key,
    required this.products,
    required this.warnings,
  });
  final List<ReceiptOcrProduct> products;
  final List<String> warnings;
  @override
  State<OcrReviewDialog> createState() => _OcrReviewDialogState();
}
class _OcrReviewDialogState extends State<OcrReviewDialog> {
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _priceControllers;
  String? _validationMessage;
  @override
  void initState() {
    super.initState();
    _nameControllers = widget.products
        .map((product) => TextEditingController(text: product.name))
        .toList();
    _priceControllers = widget.products
        .map((product) => TextEditingController(
              text: product.unitPrice.toStringAsFixed(2),
            ))
        .toList();
  }
  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _priceControllers) {
      controller.dispose();
    }
    super.dispose();
  }
  void _removeRow(int index) {
    setState(() {
      _nameControllers.removeAt(index).dispose();
      _priceControllers.removeAt(index).dispose();
    });
  }
  void _addRow() {
    setState(() {
      _nameControllers.add(TextEditingController());
      _priceControllers.add(TextEditingController());
    });
  }
  void _save() {
    final reviewed = <ReceiptProduct>[];
    for (var i = 0; i < _nameControllers.length; i++) {
      final name = _nameControllers[i].text.trim();
      final priceText = _priceControllers[i].text.trim().replaceAll(',', '');
      final price = double.tryParse(priceText);
      if (name.isEmpty || price == null || price < 0) {
        setState(() => _validationMessage =
            'Enter a product name and a valid unit price for every row.');
        return;
      }
      reviewed.add(ReceiptProduct(name: name, price: price));
    }
    if (reviewed.isEmpty) {
      setState(() => _validationMessage =
          'Add at least one product, or cancel to enter products manually.');
      return;
    }
    Navigator.of(context).pop(reviewed);
  }
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: screenHeight * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review products',
                          style: TextStyle(
                            fontSize: 21,
                            height: 1.15,
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkGray,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${_nameControllers.length} detected · Verify names and unit prices',
                          style: const TextStyle(
                            color: AppColors.gray,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel review',
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: AppColors.gray),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Invoice totals are ignored. Review each product and its unit price before saving.',
                            style: TextStyle(
                                color: AppColors.gray, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.warnings.join('\n'),
                      style: const TextStyle(
                          color: AppColors.gray, fontSize: 11, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('PRODUCT DESCRIPTION',
                            style: TextStyle(
                                color: AppColors.gray,
                                fontSize: 9,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 112,
                        child: Text('UNIT PRICE',
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                                color: AppColors.gray,
                                fontSize: 9,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 30),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _nameControllers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: i < widget.products.length &&
                                    widget.products[i].needsReview
                                ? AppColors.orange.withValues(alpha: .45)
                                : AppColors.border,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: SizedBox(
                                width: 20,
                                child: Text(
                                  '${i + 1}.',
                                  style: const TextStyle(
                                    color: AppColors.lightGray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _nameControllers[i],
                                textCapitalization: TextCapitalization.words,
                                minLines: 1,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Product name',
                                  isDense: true,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 104,
                              child: TextField(
                                controller: _priceControllers[i],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(
                                  prefixText: '₱',
                                  hintText: '0.00',
                                  isDense: true,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 10),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              height: 32,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: IconButton(
                                  tooltip: 'Remove product row',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 28, height: 28),
                                  onPressed: () => _removeRow(i),
                                  icon: const Icon(Icons.close_rounded,
                                      size: 17, color: AppColors.lightGray),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add product'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                  ),
                  if (_validationMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_validationMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save products'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Compare products using their receipt descriptions without user-defined aliases.
// Whitespace and punctuation differences are ignored, but distinct descriptions
// are not manually merged.
String _productComparisonKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// Automatic, conservative receipt-description matching (no user aliases).
// Keeps each supplier's original wording and receipt prices unchanged.
// IMPORTANT: unit-price columns can represent different purchase units;
// a description match alone cannot prove equal pricing units.
String _matchNormalize(String text) {
  var s = text.toUpperCase().trim();
  // Remove leading supplier stock codes, but never strip product brand "555".
  s = s.replaceFirst(RegExp(r'^M1\s+'), '');
  s = s.replaceFirst(RegExp(r'^\d{4,8}\s+(?=[A-Z])'), '');
  s = s.replaceFirst(RegExp(r'^\d{4,8}(?=[A-Z])'), '');

  // Standardize measurements before handling cartons.
  s = s.replaceAllMapped(
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:GRAMS?|GMS?)\b'),
      (m) => '${m.group(1)}G');
  s = s.replaceAllMapped(
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:MILLILITERS?|MILLILITRES?|MLS?)\b'),
      (m) => '${m.group(1)}ML');

  // 4/6/220ML means 24 units of 220ML; 10/8/20G means 80 of 20G.
  s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*[/X]\s*(\d+)\s*[/X]\s*(\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L))\b'),
      (m) => 'CASE ${int.parse(m.group(1)!) * int.parse(m.group(2)!)} ${m.group(3)}');
  // 100/155G, 14X640G, and 42X150G denote carton count and unit size.
  s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*[/X]\s*(\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L))\b'),
      (m) => 'CASE ${m.group(1)} ${m.group(2)}');
  // 155G 100PCS or 640G CASE 14: preserve the same canonical carton count.
  s = s.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L))\s+(?:CASE\s+(?:OF\s+)?)?(\d+)\s*(?:PCS|PIECES|UNITS)\b'),
      (m) => 'CASE ${m.group(2)} ${m.group(1)}');
  s = s.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L))\s+CASE\s+(?:OF\s+)?(\d+)\b'),
      (m) => 'CASE ${m.group(2)} ${m.group(1)}');
  s = s.replaceAllMapped(
      RegExp(r'\b(\d+)\s*(?:PCS|PIECES|UNITS)\b'),
      (m) => 'CASE ${m.group(1)}');

  s = s.replaceAll(RegExp(r'\bNESTLE\s+(?=MILO\b)'), '');
  s = s.replaceAll(RegExp(r'\bMILO\s+CHOCO\s+MALT\s+DRINK\b'),
      'MILO MILK DRINK');
  s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), ' ').trim();

  const words = <String, String>{
    'CHPY':'CHIPPY', 'CHIPY':'CHIPPY', 'CHPPY':'CHIPPY',
    'RD':'RED', 'GRN':'GREEN', 'GR':'GREEN', 'SM':'SMALL',
    'S':'SMALL', 'LG':'LARGE',
    'SARD':'SARDINES', 'SARDINE':'SARDINES',
    'PWD':'POWDER', 'POWDERED':'POWDER',
    'JCE':'JUICE', 'JUC':'JUICE', 'PINE':'PINEAPPLE',
    'SWT':'SWEET', 'EO':'EASYOPEN',
    'DM':'DELMONTE', 'DEL':'DELMONTE',
    'CHDR':'CHEDDAR', 'CHDOR':'CHEDDAR', 'CHMY':'CHICHARON',
  };
  final tokens = s.split(RegExp(r'\s+'));
  final expanded = tokens.map((t) => words[t] ?? t).join(' ');
  return expanded
      .replaceAll(RegExp(r'\bBEAR BRAND\b'), 'BEARBRAND')
      .replaceAll(RegExp(r'\bDEL MONTE\b'), 'DELMONTE')
      .replaceAll(RegExp(r'\bEASY OPEN\b'), 'EASYOPEN');
}

class _MatchIdentity {
  _MatchIdentity(String description)
      : normalized = _matchNormalize(description) {
    // Keep exact package/weight values; don't mistake 20g for 80g.
    final sizeMatches = RegExp(r'\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L)\b')
        .allMatches(normalized);
    sizes = sizeMatches.map((m) => m.group(0)!.replaceAll(' ', '')).toSet();
    final caseMatch = RegExp(r'\bCASE\s+(\d+)\b').firstMatch(normalized);
    caseCount = caseMatch == null ? null : int.tryParse(caseMatch.group(1)!);
    // Number immediately before / or X can be a carton quantity.
    // Do not remove the individual weight or volume.
    final withoutSizes = normalized.replaceAll(
        RegExp(r'\d+(?:\.\d+)?\s*(?:KG|MG|G|ML|L)\b'), ' ');
    final withoutPacks = withoutSizes
        .replaceAll(RegExp(r'\bCASE\s+\d+\b'), ' ')
        .replaceAll(RegExp(r'\b\d+(?:\s*[X/]\s*\d+)+\b'), ' ');
    tokens = withoutPacks.split(RegExp(r'\s+'))
        .where((t) => t.length > 1 && !RegExp(r'^\d+$').hasMatch(t))
        .where((t) => !const {'PH','PCS','CS','SAVE','PROMO','PACK','PK','M1','CASE','PASS','FAIL','GRAMS','OF','PHILIPPINES'}
            .contains(t)).toSet();
  }
  final String normalized;
  late final Set<String> sizes;
  late final int? caseCount;
  late final Set<String> tokens;
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      current[j] = [deletion, insertion, substitution]
          .reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous[b.length];
}

bool _similarToken(String a, String b) {
  if (a == b) { return true; }
  if (a.length < 5 || b.length < 5) { return false; }
  final longer = a.length > b.length ? a.length : b.length;
  return _editDistance(a, b) <= (longer >= 9 ? 2 : 1);
}

bool _sameProductVariant(String first, String second) {
  final a = _MatchIdentity(first);
  final b = _MatchIdentity(second);
  if (a.normalized == b.normalized) { return true; }
  // Conflicting known case quantities should not be compared as equal units.
  if (a.caseCount != null && b.caseCount != null &&
      a.caseCount != b.caseCount) {
    return false;
  }
  // Missing size is not proof of the same SKU; conflicting sizes are rejected.
  if (a.sizes.isEmpty != b.sizes.isEmpty ||
      (a.sizes.isNotEmpty && !a.sizes.containsAll(b.sizes)) ||
      (b.sizes.isNotEmpty && !b.sizes.containsAll(a.sizes))) {
    return false;
  }
  const variants = <Set<String>>[
    {'RED','GREEN','BLUE','YELLOW','ORANGE'},
    {'SMALL','MEDIUM','LARGE'},
    {'SWEET','SOUR'},
    {'SLICES','CRUSHED','CHUNKS'},
    {'ORIGINAL','BBQ','BARBECUE','CHEESE','SPICY','HOT'},
    {'POWDER','LIQUID'},
  ];
  for (final family in variants) {
    final av = a.tokens.intersection(family);
    final bv = b.tokens.intersection(family);
    if (av.isNotEmpty && bv.isNotEmpty &&
        av.intersection(bv).isEmpty) {
      return false;
    }
    // Don't merge a specified variant with an unspecified variant.
    if (av.isEmpty != bv.isEmpty) {
      return false;
    }
  }
  if (a.tokens.isEmpty || b.tokens.isEmpty) { return false; }
  final left = a.tokens.toList();
  final right = b.tokens.toList();
  final used = <int>{};
  var matched = 0;
  for (final token in left) {
    for (var i = 0; i < right.length; i++) {
      if (!used.contains(i) && _similarToken(token, right[i])) {
        used.add(i);
        matched++;
        break;
      }
    }
  }
  // High overlap in BOTH directions prevents generic-brand-only matches.
  return matched >= 2 &&
      matched / left.length >= 0.80 &&
      matched / right.length >= 0.80;
}

class _LatestSupplierProduct {
  const _LatestSupplierProduct(this.key, this.name, this.price, this.previous);
  final String key;
  final String name;
  final double price;
  final double? previous;
}
class _SupplierLatestPrice {
  const _SupplierLatestPrice(this.supplier, this.product, this.price, this.increase);
  final String supplier;
  final String product;
  final double price;
  final double increase;
}
List<_LatestSupplierProduct> _latestSupplierPrices(Supplier supplier) {
  // Retain receipt history internally, but display one latest price per item.
  final invoices = [...supplier.invoices]..sort((a, b) {
    final at = a.createdAt ?? a.date;
    final bt = b.createdAt ?? b.date;
    final comparison = at.compareTo(bt);
    if (comparison != 0) return comparison;
    return a.id.toString().compareTo(b.id.toString());
  });
  final history = <String, List<ReceiptProduct>>{};
  for (final invoice in invoices) {
    // Last occurrence per receipt, to avoid duplicates within one scan.
    final items = <String, ReceiptProduct>{};
    for (final product in invoice.products) {
      if (product.name.trim().isEmpty || product.price <= 0) continue;
      final key = _productComparisonKey(product.name);
      if (key.isEmpty) continue;
      items[key] = product;
    }
    for (final entry in items.entries) {
      history.putIfAbsent(entry.key, () => []).add(entry.value);
    }
  }
  return [
    for (final entry in history.entries)
      _LatestSupplierProduct(
        entry.key,
        entry.value.last.name,
        entry.value.last.price,
        entry.value.length > 1
            ? entry.value[entry.value.length - 2].price : null,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
String formatPeso(double value) => '₱${value.toStringAsFixed(2)}';
