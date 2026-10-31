import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

// DukaBook — offline-first shop register. No cloud account is required.
const green = Color(0xFF009C55);
const deepGreen = Color(0xFF087A48);
const orange = Color(0xFFF66B11);
const ink = Color(0xFF1D2635);
const background = Color(0xFFF7F8F7);
const brandGold = Color(0xFF946C20); // TILLERN LABS attribution accent

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DukaBook());
}

class DukaBook extends StatelessWidget {
  const DukaBook({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DukaBook',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: background,
          colorScheme: ColorScheme.fromSeed(seedColor: green),
          appBarTheme: const AppBarTheme(
            backgroundColor: background,
            foregroundColor: ink,
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardTheme(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          ),
        ),
        home: const DukaScreen(),
      );
}

class DukaScreen extends StatefulWidget {
  const DukaScreen({super.key});
  @override
  State<DukaScreen> createState() => _DukaScreenState();
}

class _DukaScreenState extends State<DukaScreen> {
  Database? _db;
  bool _loading = true;
  bool _showWelcome = true;
  String? _error;
  int _tab = 0;
  String? _subPage;
  String _owner = 'Owner';
  String _shop = 'My Shop';
  String _query = '';
  String _payment = 'Cash';
  bool _sortDueFirst = false;
  final Map<int, int> _cart = {};
  final _searchController = TextEditingController();

  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _sales = [];
  List<Map<String, Object?>> _debts = [];
  List<Map<String, Object?>> _customers = [];
  List<Map<String, Object?>> _collections = [];
  int _todaySales = 0;
  int _todayCash = 0;
  int _todayMpesa = 0;
  int _todayCredit = 0;

  String get _today => DateTime.now().toIso8601String().substring(0, 10);
  int _number(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  String _kes(int n) {
    final digits = n.abs().toString();
    final parts = <String>[];
    for (var i = digits.length; i > 0; i -= 3) {
      parts.insert(0, digits.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return 'KES ${n < 0 ? '-' : ''}${parts.join(',')}';
  }

  // All owner-facing greetings stay in English. The first launch can greet
  // someone even before they configure their name in Shop settings.
  String get _englishGreeting {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final name = _owner.trim();
    return name.isEmpty || name == 'Owner'
        ? '$greeting! 👋'
        : '$greeting, $name! 👋';
  }

  String _prettyDate() {
    final d = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    // Show a short offline-first brand welcome. Database initialization happens
    // at the same time so the animation does not postpone data loading.
    _openDatabase();
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _db?.close();
    super.dispose();
  }

  Future<void> _openDatabase() async {
    try {
      final dbFile = path.join(await getDatabasesPath(), 'duka.db');
      _db = await openDatabase(
        dbFile,
        version: 3,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, stock INTEGER NOT NULL, price INTEGER NOT NULL)');
          await db.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT NOT NULL, amount INTEGER NOT NULL, date TEXT NOT NULL, product_id INTEGER, quantity INTEGER DEFAULT 1, payment_method TEXT DEFAULT \'Cash\', created_at TEXT, receipt_id TEXT)');
          await db.execute('CREATE TABLE debts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, amount INTEGER NOT NULL, date TEXT NOT NULL, status TEXT DEFAULT \'Unpaid\', notes TEXT, phone TEXT, due_date TEXT)');
          await _createSupportingTables(db);
        },
        onUpgrade: (db, old, next) async {
          if (old < 2) {
            await db.execute('ALTER TABLE sales ADD COLUMN product_id INTEGER');
            await db.execute('ALTER TABLE sales ADD COLUMN quantity INTEGER DEFAULT 1');
            await db.execute('ALTER TABLE sales ADD COLUMN payment_method TEXT DEFAULT \'Cash\'');
            await db.execute('ALTER TABLE sales ADD COLUMN created_at TEXT');
            await db.execute('ALTER TABLE debts ADD COLUMN status TEXT DEFAULT \'Unpaid\'');
            await db.execute('ALTER TABLE debts ADD COLUMN notes TEXT');
          }
          if (old < 3) {
            await db.execute('ALTER TABLE sales ADD COLUMN receipt_id TEXT');
            await db.execute('ALTER TABLE debts ADD COLUMN phone TEXT');
            await db.execute('ALTER TABLE debts ADD COLUMN due_date TEXT');
            await _createSupportingTables(db);
          }
        },
      );
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open shop database: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createSupportingTables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS collections(id INTEGER PRIMARY KEY AUTOINCREMENT, debt_id INTEGER NOT NULL, amount INTEGER NOT NULL, payment_method TEXT NOT NULL, date TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  Future<void> _refresh() async {
    final db = _db;
    if (db == null) return;
    final products = await db.query('products', orderBy: 'name COLLATE NOCASE');
    final sales = await db.query('sales', orderBy: 'date DESC, id DESC', limit: 250);
    final debts = await db.query('debts', orderBy: 'id DESC');
    final customers = await db.query('customers', orderBy: 'name COLLATE NOCASE');
    final collections = await db.query('collections', orderBy: 'id DESC', limit: 100);
    final settings = await db.query('settings');
    final totals = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS total, "
      "COALESCE(SUM(CASE WHEN payment_method = 'Cash' THEN amount ELSE 0 END),0) AS cash, "
      "COALESCE(SUM(CASE WHEN payment_method = 'M-Pesa' THEN amount ELSE 0 END),0) AS mpesa, "
      "COALESCE(SUM(CASE WHEN payment_method = 'Credit' THEN amount ELSE 0 END),0) AS credit "
      'FROM sales WHERE date = ?', [_today],
    );
    final prefs = <String, String>{for (final row in settings) row['key'].toString(): row['value'].toString()};
    if (!mounted) return;
    setState(() {
      _products = products;
      _sales = sales;
      _debts = debts;
      _customers = customers;
      _collections = collections;
      _owner = prefs['owner']?.trim().isNotEmpty == true ? prefs['owner']! : 'Owner';
      _shop = prefs['shop']?.trim().isNotEmpty == true ? prefs['shop']! : 'My Shop';
      _todaySales = _number(totals.first['total']);
      _todayCash = _number(totals.first['cash']);
      _todayMpesa = _number(totals.first['mpesa']);
      _todayCredit = _number(totals.first['credit']);
      // A stock edit or sale might have reduced stock since an item entered the basket.
      for (final id in _cart.keys.toList()) {
        final matching = products.where((p) => _number(p['id']) == id);
        if (matching.isEmpty || _number(matching.first['stock']) < 1) {
          _cart.remove(id);
        } else if (_cart[id]! > _number(matching.first['stock'])) {
          _cart[id] = _number(matching.first['stock']);
        }
      }
    });
  }

  void _alert(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, {String success = 'Saved'}) async {
    try {
      await action();
      await _refresh();
      _alert(success);
    } catch (e) {
      _alert('Could not save: $e');
    }
  }

  String? _validAmount(String? text, {bool allowZero = false}) {
    final value = int.tryParse(text?.trim() ?? '');
    return value == null || (allowZero ? value < 0 : value <= 0)
        ? (allowZero ? 'Enter 0 or a positive whole number' : 'Enter a positive whole number')
        : null;
  }

  Future<bool> _confirm(String title, String content, {String action = 'Confirm'}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ?? false;

  Future<void> _editProduct([Map<String, Object?>? product]) async {
    final name = TextEditingController(text: product?['name']?.toString() ?? '');
    final price = TextEditingController(text: product?['price']?.toString() ?? '');
    final stock = TextEditingController(text: product?['stock']?.toString() ?? '0');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(product == null ? 'Add product' : 'Edit product'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Product name'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit price (KES)'), validator: _validAmount),
            const SizedBox(height: 10),
            TextFormField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity in stock'), validator: (v) => _validAmount(v, allowZero: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save')),
        ],
      ),
    );
    final values = <String, Object?>{'name': name.text.trim(), 'price': int.tryParse(price.text.trim()), 'stock': int.tryParse(stock.text.trim())};
    name.dispose(); price.dispose(); stock.dispose();
    if (ok != true) return;
    await _run(() async {
      if (product == null) {
        await _db!.insert('products', values);
      } else {
        await _db!.update('products', values, where: 'id = ?', whereArgs: [product['id']]);
      }
    }, success: 'Product saved');
  }

  Future<void> _deleteProduct(Map<String, Object?> item) async {
    if (!await _confirm('Remove product?', '${item['name']} will be removed from stock. Recorded sales will remain.', action: 'Remove')) return;
    await _run(() async { await _db!.delete('products', where: 'id = ?', whereArgs: [item['id']]); }, success: 'Product removed');
  }

  void _changeCart(Map<String, Object?> product, int delta) {
    final id = _number(product['id']);
    final limit = _number(product['stock']);
    final qty = (_cart[id] ?? 0) + delta;
    if (qty > limit) { _alert('Only $limit available in stock'); return; }
    setState(() {
      if (qty <= 0) { _cart.remove(id); } else { _cart[id] = qty; }
    });
  }

  int get _cartCount => _cart.values.fold(0, (a, b) => a + b);
  int get _cartTotal {
    var value = 0;
    for (final product in _products) {
      value += _number(product['price']) * (_cart[_number(product['id'])] ?? 0);
    }
    return value;
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) { _alert('Choose a product to sell first'); return; }
    final total = _cartTotal;
    final isCredit = _payment == 'Credit';
    String customerName = '';
    String customerPhone = '';
    String? dueDate;
    if (isCredit) {
      final name = TextEditingController();
      final phone = TextEditingController();
      final form = GlobalKey<FormState>();
      DateTime chosenDue = DateTime.now().add(const Duration(days: 7));
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, update) => AlertDialog(
          title: const Text('Sell on debt'),
          content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Amount owed: ${_kes(total)}'),
            const SizedBox(height: 12),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Customer name'), validator: (v) => v == null || v.trim().isEmpty ? 'Customer name required' : null),
            const SizedBox(height: 10),
            TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional for reminders)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('Due: ${chosenDue.day}/${chosenDue.month}/${chosenDue.year}'),
              onPressed: () async {
                final picked = await showDatePicker(context: c, initialDate: chosenDue, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
                if (picked != null) update(() => chosenDue = picked);
              },
            ),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save credit sale')),
          ],
        )),
      );
      customerName = name.text.trim();
      customerPhone = phone.text.trim();
      dueDate = chosenDue.toIso8601String().substring(0, 10);
      name.dispose(); phone.dispose();
      if (ok != true) return;
    } else {
      final proceed = await _confirm('Complete sale?', 'Record ${_kes(total)} paid using $_payment?', action: 'Sell now');
      if (!proceed) return;
    }
    // Copy the basket before the asynchronous transaction.
    final items = Map<int, int>.of(_cart);
    final payment = _payment;
    final name = customerName;
    final phone = customerPhone;
    final due = dueDate;
    try {
      await _db!.transaction((txn) async {
        final receipt = DateTime.now().microsecondsSinceEpoch.toString();
        var verifiedTotal = 0;
        final now = DateTime.now().toIso8601String();
        for (final entry in items.entries) {
          final rows = await txn.query('products', where: 'id = ?', whereArgs: [entry.key]);
          if (rows.isEmpty) throw StateError('A product has been removed. Refresh and try again.');
          final product = rows.first;
          final changed = await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?', [entry.value, entry.key, entry.value]);
          if (changed != 1) throw StateError('Not enough stock for ${product['name']}');
          final amount = _number(product['price']) * entry.value;
          verifiedTotal += amount;
          await txn.insert('sales', {
            'item': product['name'], 'amount': amount, 'date': _today,
            'product_id': entry.key, 'quantity': entry.value,
            'payment_method': payment, 'created_at': now, 'receipt_id': receipt,
          });
        }
        if (payment == 'Credit') {
          await txn.insert('debts', {
            'name': name, 'amount': verifiedTotal, 'date': _today, 'status': 'Unpaid',
            'notes': 'Sale receipt $receipt', 'phone': phone, 'due_date': due,
          });
          final found = await txn.query('customers', where: 'name = ? COLLATE NOCASE', whereArgs: [name], limit: 1);
          if (found.isEmpty) await txn.insert('customers', {'name': name, 'phone': phone});
        }
      });
      if (!mounted) return;
      setState(() => _cart.clear());
      await _refresh();
      _alert('Sale recorded • ${_kes(total)} ($_payment)');
    } catch (e) {
      _alert('Sale not completed: $e');
    }
  }

  Future<void> _addDebt() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final phone = TextEditingController();
    final form = GlobalKey<FormState>();
    DateTime due = DateTime.now().add(const Duration(days: 7));
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, update) => AlertDialog(
      title: const Text('Add debt (deni)'),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Customer name'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null),
        const SizedBox(height: 10),
        TextFormField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount owed (KES)'), validator: _validAmount),
        const SizedBox(height: 10),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
        const SizedBox(height: 10),
        OutlinedButton.icon(icon: const Icon(Icons.event), label: Text('Due: ${due.day}/${due.month}/${due.year}'), onPressed: () async {
          final picked = await showDatePicker(context: c, initialDate: due, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
          if (picked != null) update(() => due = picked);
        }),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save')),
      ],
    )));
    final n = name.text.trim(); final a = int.tryParse(amount.text.trim()); final p = phone.text.trim();
    final dueString = due.toIso8601String().substring(0, 10);
    name.dispose(); amount.dispose(); phone.dispose();
    if (ok != true || a == null) return;
    await _run(() async => _db!.transaction((txn) async {
      await txn.insert('debts', {'name': n, 'amount': a, 'date': _today, 'status': 'Unpaid', 'phone': p, 'due_date': dueString});
      final old = await txn.query('customers', where: 'name = ? COLLATE NOCASE', whereArgs: [n], limit: 1);
      if (old.isEmpty) await txn.insert('customers', {'name': n, 'phone': p});
    }), success: 'Debt saved');
  }

  Future<void> _markPaid(Map<String, Object?> debt) async {
    String method = 'Cash';
    final confirmed = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, update) => AlertDialog(
      title: const Text('Record debt repayment'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${debt['name']} owes ${_kes(_number(debt['amount']))}.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(labelText: 'Received via'), items: const [
          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
          DropdownMenuItem(value: 'M-Pesa', child: Text('M-Pesa')),
        ], onChanged: (v) => update(() => method = v ?? 'Cash')),
        const SizedBox(height: 8),
        const Text('This records a collection, not a second sale.', style: TextStyle(color: Colors.black54, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mark paid')),
      ],
    )));
    if (confirmed != true) return;
    await _run(() async => _db!.transaction((txn) async {
      final updated = await txn.update('debts', {'status': 'Paid'}, where: "id = ? AND COALESCE(status, 'Unpaid') != 'Paid'", whereArgs: [debt['id']]);
      if (updated != 1) throw StateError('Already paid or missing');
      await txn.insert('collections', {'debt_id': debt['id'], 'amount': _number(debt['amount']), 'payment_method': method, 'date': _today});
    }), success: 'Debt marked paid');
  }

  String? _kenyanPhone(String source) {
    final digits = source.replaceAll(RegExp(r'[^0-9]'), '');
    if (RegExp(r'^254[17]\d{8}$').hasMatch(digits)) return digits;
    if (RegExp(r'^0[17]\d{8}$').hasMatch(digits)) return '254${digits.substring(1)}';
    if (RegExp(r'^[17]\d{8}$').hasMatch(digits)) return '254$digits';
    return null;
  }

  Future<String?> _ensurePhone(Map<String, Object?> debt) async {
    final existing = _kenyanPhone(debt['phone']?.toString() ?? '');
    if (existing != null) return existing;
    final phone = TextEditingController(text: debt['phone']?.toString() ?? '');
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Phone for ${debt['name']}'),
      content: Form(key: form, child: TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Kenyan phone number'), validator: (v) => _kenyanPhone(v ?? '') == null ? 'Enter a valid Kenyan mobile number' : null)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save phone')),
      ],
    ));
    final value = _kenyanPhone(phone.text);
    phone.dispose();
    if (ok != true || value == null) return null;
    try {
      await _db!.update('debts', {'phone': value}, where: 'id = ?', whereArgs: [debt['id']]);
      await _refresh();
      return value;
    } catch (e) {
      _alert('Could not save phone: $e');
      return null;
    }
  }

  Future<void> _contact(Map<String, Object?> debt, {required bool whatsapp}) async {
    final phone = await _ensurePhone(debt);
    if (phone == null) return;
    final uri = whatsapp
        ? Uri.https('wa.me', '/$phone', {'text': 'Hello ${debt['name']}, this is a friendly reminder of your DukaBook balance of ${_kes(_number(debt['amount']))} at $_shop. Thank you.'})
        : Uri(scheme: 'tel', path: '+$phone');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _alert('No app available to open this contact');
    } catch (e) {
      _alert('Could not open contact: $e');
    }
  }

  Future<void> _remindAll() async {
    final outstanding = _debts.where((d) => d['status'] != 'Paid').toList();
    if (outstanding.isEmpty) { _alert('No outstanding debts'); return; }
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (c) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Send reminders individually', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Choose each customer to open a WhatsApp draft. Messages are never sent automatically.', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SizedBox(height: 250, child: ListView(children: outstanding.map((d) => ListTile(
          title: Text(d['name'].toString()),
          subtitle: Text(_kes(_number(d['amount']))),
          trailing: IconButton(tooltip: 'Open WhatsApp draft', icon: const Icon(Icons.chat, color: green), onPressed: () {
            Navigator.pop(c);
            _contact(d, whatsapp: true);
          }),
        )).toList())),
      ]),
    )));
  }

  Future<void> _customerDialog() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('New customer'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null),
        const SizedBox(height: 10),
        TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(c, true); }, child: const Text('Save')),
      ],
    ));
    final values = {'name': name.text.trim(), 'phone': phone.text.trim()};
    name.dispose(); phone.dispose();
    if (ok == true) await _run(() async { await _db!.insert('customers', values); }, success: 'Customer saved');
  }

  Future<void> _settingsDialog() async {
    final name = TextEditingController(text: _owner == 'Owner' ? '' : _owner);
    final shop = TextEditingController(text: _shop == 'My Shop' ? '' : _shop);
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Shop settings'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
        const SizedBox(height: 10),
        TextField(controller: shop, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name')),
        const SizedBox(height: 8),
        const Text('Saved only on this device.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
      ],
    ));
    final ownerValue = name.text.trim(); final shopValue = shop.text.trim();
    name.dispose(); shop.dispose();
    if (ok != true) return;
    await _run(() async => _db!.transaction((txn) async {
      await txn.insert('settings', {'key': 'owner', 'value': ownerValue}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {'key': 'shop', 'value': shopValue}, conflictAlgorithm: ConflictAlgorithm.replace);
    }), success: 'Settings saved');
  }

  // Portable offline backups. Share only when the shop owner deliberately chooses
  // a destination; no backups are sent to TILLERN LABS or any server.
  static const _backupFormat = 'dukabook-offline-json';
  static const _backupTables = <String>[
    'products', 'sales', 'debts', 'customers', 'collections', 'settings',
  ];
  static const _backupColumns = <String, Set<String>>{
    'products': {'id', 'name', 'stock', 'price'},
    'sales': {'id', 'item', 'amount', 'date', 'product_id', 'quantity',
      'payment_method', 'created_at', 'receipt_id'},
    'debts': {'id', 'name', 'amount', 'date', 'status', 'notes',
      'phone', 'due_date'},
    'customers': {'id', 'name', 'phone'},
    'collections': {'id', 'debt_id', 'amount', 'payment_method', 'date'},
    'settings': {'key', 'value'},
  };

  // Numeric fields must remain numeric. Never let a malformed JSON backup
  // silently turn prices, stock or payments into text in SQLite.
  static const _backupNumbers = <String, Set<String>>{
    'products': {'id', 'stock', 'price'},
    'sales': {'id', 'amount', 'product_id', 'quantity'},
    'debts': {'id', 'amount'},
    'customers': {'id'},
    'collections': {'id', 'debt_id', 'amount'},
    'settings': <String>{},
  };

  Future<Map<String, Object?>> _backupSnapshot() async {
    final db = _db;
    if (db == null) throw StateError('Shop database is not ready');
    final tables = <String, List<Map<String, Object?>>>{};
    // Read all tables inside one consistent transaction. This is important
    // when sales or stock records might change during an export.
    await db.transaction((txn) async {
      for (final name in _backupTables) {
        tables[name] = await txn.query(name);
      }
    }, exclusive: false);
    return {
      'format': _backupFormat,
      'schema': 1,
      'created_at': DateTime.now().toIso8601String(),
      'app_version': '2.1.0-beta',
      'shop_name': _shop,
      'tables': tables,
    };
  }

  Future<void> _exportBackup() async {
    if (_db == null) return;
    final proceed = await _confirm(
      'Export shop backup?',
      'This file contains customer names, phone numbers, sales and debts. '
      'It is NOT encrypted. Save it in a private place you control. '
      'Anyone with the file can read it.',
      action: 'Create backup',
    );
    if (!proceed) return;
    try {
      final backup = await _backupSnapshot();
      final temp = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final file = File(path.join(temp.path, 'DukaBook_Backup_$stamp.json'));
      await file.writeAsString(jsonEncode(backup), flush: true);
      if (!mounted) return;
      _alert('Choose Files, Drive, or another private destination to save your backup.');
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
          subject: 'DukaBook offline shop backup');
      // Opening the share sheet is not proof the user saved a backup.
    } catch (e) {
      _alert('Backup could not be shared: $e');
    }
  }

  Map<String, List<Map<String, Object?>>> _validatedBackup(Object? decoded) {
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _backupFormat || decoded['schema'] != 1) {
      throw const FormatException('Not a supported DukaBook backup');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic> ||
        rawTables.length != _backupTables.length ||
        rawTables.keys.any((key) => !_backupTables.contains(key))) {
      throw const FormatException('Backup tables are missing or unsupported');
    }
    final verified = <String, List<Map<String, Object?>>>{};
    for (final table in _backupTables) {
      final rawRows = rawTables[table];
      if (rawRows is! List || rawRows.length > 50000) {
        throw FormatException('Invalid or oversized $table backup');
      }
      final rows = <Map<String, Object?>>[];
      for (final entry in rawRows) {
        if (entry is! Map<String, dynamic> ||
            entry.keys.toSet().length != _backupColumns[table]!.length ||
            entry.keys.any((key) => !_backupColumns[table]!.contains(key)) ||
            entry.values.any((v) => v != null && v is! String && v is! int)) {
          throw FormatException('Invalid $table record');
        }
        for (final column in _backupColumns[table]!) {
          final value = entry[column];
          if (value != null && _backupNumbers[table]!.contains(column) &&
              (value is! int || value < 0)) {
            throw FormatException('Invalid $table numeric value');
          }
          if (value != null && !_backupNumbers[table]!.contains(column) &&
              value is! String) {
            throw FormatException('Invalid $table text value');
          }
          if ((column == 'id' || column == 'debt_id') && value is int && value == 0) {
            throw FormatException('Invalid $table record ID');
          }
        }
        rows.add(Map<String, Object?>.from(entry));
      }
      verified[table] = rows;
    }
    return verified;
  }

  Future<void> _restoreBackup() async {
    if (_db == null) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final selected = picked.files.single;
      if (selected.size > 20 * 1024 * 1024) {
        throw const FormatException('Backup is too large (maximum 20 MB)');
      }
      final bytes = selected.bytes ??
          (selected.path == null ? null : await File(selected.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('Cannot read the selected backup file');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final validated = _validatedBackup(decoded);
      final meta = decoded as Map<String, dynamic>;
      if (!mounted) return;
      final shopName = meta['shop_name']?.toString() ?? 'Unknown shop';
      final sales = validated['sales']!.length;
      final debts = validated['debts']!.length;
      final confirmed = await _confirm(
        'Replace ALL local records?',
        'Backup shop: $shopName\nSales lines: $sales\nDebt records: $debts\n\n'
        'THIS WILL REPLACE your current products, sales, debts, '
        'customers, collections and settings. This cannot be undone. '
        'Export and securely save your current data first.',
        action: 'Replace records',
      );
      if (!confirmed) return;
      // SQLite transaction rolls back the entire restore if any insert fails.
      // The existing database is never deleted or closed during this process.
      await _db!.transaction((txn) async {
        for (final table in _backupTables.reversed) {
          await txn.delete(table);
        }
        for (final table in _backupTables) {
          for (final row in validated[table]!) {
            await txn.insert(table, row);
          }
        }
      });
      if (!mounted) return;
      setState(() { _cart.clear(); _tab = 0; _subPage = null; });
      await _refresh();
      _alert('Backup restored. Check your sales, stock and debts.');
    } catch (e) {
      _alert('Restore failed; your existing records were kept: $e');
    }
  }

  void _switchTab(int index) => setState(() { _tab = index; _subPage = null; });
  void _goTo(String page) => setState(() => _subPage = page);

  Widget _heading(String title, {VoidCallback? onView}) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink))),
      if (onView != null) TextButton(onPressed: onView, child: const Text('View all ›')),
    ]),
  );

  Widget _empty(String label, {IconData icon = Icons.inbox_outlined}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(children: [Icon(icon, color: Colors.black26, size: 35), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))]),
  );

  Widget _stat(String title, String value, IconData icon, Color accent, Color fill) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18), border: Border.all(color: accent.withOpacity(.45))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(backgroundColor: accent, radius: 18, child: Icon(icon, color: Colors.white, size: 19)),
      const SizedBox(height: 11),
      Text(title, style: const TextStyle(color: ink, fontSize: 13)),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w800))),
    ]),
  ));

  Widget _saleTile(Map<String, Object?> sale) => Card(child: ListTile(
    leading: const CircleAvatar(backgroundColor: Color(0xFFD9F6E6), child: Icon(Icons.storefront, color: green)),
    title: Text(sale['item']?.toString() ?? 'Sale', style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text('${sale['date']} • ${sale['payment_method'] ?? 'Cash'} • Qty ${sale['quantity'] ?? 1}'),
    trailing: Text(_kes(_number(sale['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
  ));

  Widget _home() {
    final low = _products.where((p) => _number(p['stock']) <= 5).toList();
    final open = _debts.where((d) => d['status'] != 'Paid').toList();
    final outstanding = open.fold<int>(0, (a, d) => a + _number(d['amount']));
    return RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 24), children: [
      Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('assets/branding/storefront_icon.png', width: 40, height: 40, fit: BoxFit.cover),
        ),
        const SizedBox(width: 9),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Duka', style: TextStyle(color: deepGreen)),
            TextSpan(text: 'Book', style: TextStyle(color: orange)),
          ]), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
          Text('by TILLERN LABS', style: TextStyle(fontSize: 10, color: brandGold, fontWeight: FontWeight.w800, letterSpacing: .8)),
        ])),
        IconButton(tooltip: 'Low stock alerts', onPressed: () => _switchTab(1), icon: const Icon(Icons.notifications_none)),
        IconButton(tooltip: 'Shop settings', onPressed: _settingsDialog, icon: const Icon(Icons.account_circle, color: green)),
      ]),
      const SizedBox(height: 19),
      Text(_englishGreeting, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
      const SizedBox(height: 3),
      const Text('Welcome back! Your shop is ready for business.',
          style: TextStyle(fontSize: 13, color: Colors.black54)),
      const SizedBox(height: 5),
      Text('${_prettyDate()} • $_shop', style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 19),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stat("Today's Sales", _kes(_todaySales), Icons.trending_up, green, const Color(0xFFDCF5DB)),
        const SizedBox(width: 10),
        _stat('Debt to Collect', _kes(outstanding), Icons.account_balance_wallet_outlined, orange, const Color(0xFFFFE3BC)),
      ]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Wrap(spacing: 15, runSpacing: 5, children: [
        Text('Cash: ${_kes(_todayCash)}', style: const TextStyle(color: deepGreen)),
        Text('M-Pesa: ${_kes(_todayMpesa)}', style: const TextStyle(color: deepGreen)),
        Text('Credit: ${_kes(_todayCredit)}', style: const TextStyle(color: orange)),
      ]))),
      _heading('Low Stock Items', onView: () => _switchTab(1)),
      if (low.isEmpty) _empty('No low-stock items. Add products to begin.', icon: Icons.inventory_2_outlined)
      else Card(child: Column(children: low.take(5).map((p) => ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFE9D2), child: Icon(Icons.inventory_2_outlined, color: orange)),
        title: Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${p['stock']} left • Restock soon'),
        trailing: const Text('Low Stock', style: TextStyle(color: orange, fontWeight: FontWeight.w700, fontSize: 11)),
        onTap: () => _editProduct(p),
      )).toList())),
      _heading('Recent Sales', onView: () => _goTo('Sales history')),
      if (_sales.isEmpty) _empty('No sales recorded yet. Tap Sell to begin.', icon: Icons.receipt_long_outlined)
      else ..._sales.take(5).map(_saleTile),
      const SizedBox(height: 9),
      FilledButton.icon(onPressed: () => _switchTab(2), icon: const Icon(Icons.shopping_cart_checkout), label: const Text('Sell a product')),
    ]));
  }

  IconData _productIcon(String name) {
    final value = name.toLowerCase();
    if (value.contains('bread') || value.contains('cake')) return Icons.bakery_dining;
    if (value.contains('milk') || value.contains('juice')) return Icons.local_drink_outlined;
    if (value.contains('sugar')) return Icons.breakfast_dining;
    if (value.contains('blueband') || value.contains('margarine')) return Icons.shopping_basket_outlined;
    return Icons.inventory_2_outlined;
  }

  Widget _stock() => ListView(padding: const EdgeInsets.all(16), children: [
    _heading('Products & Stock'),
    Text('${_products.length} products • Tap a row to edit', style: const TextStyle(color: Colors.black54)),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: () => _editProduct(), icon: const Icon(Icons.add), label: const Text('Add product')),
    if (_products.isEmpty) _empty('Add your first product to start selling.'),
    ..._products.map((p) => Card(child: ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFFFFEBD6), child: Icon(_productIcon(p['name'].toString()), color: orange)),
      title: Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${_kes(_number(p['price']))} each • ${p['stock']} in stock'),
      trailing: PopupMenuButton<String>(onSelected: (a) => a == 'edit' ? _editProduct(p) : _deleteProduct(p), itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit / Restock')),
        PopupMenuItem(value: 'delete', child: Text('Remove product')),
      ]),
      onTap: () => _editProduct(p),
    ))),
  ]);

  Widget _productTile(Map<String, Object?> p) {
    final id = _number(p['id']);
    final available = _number(p['stock']);
    final qty = _cart[id] ?? 0;
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Align(alignment: Alignment.centerLeft, child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF8E8D6), borderRadius: BorderRadius.circular(12)),
        child: Icon(_productIcon(p['name'].toString()), color: const Color(0xFF8D5F30), size: 29),
      )),
      const Spacer(),
      Text(p['name'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      Text(_kes(_number(p['price'])), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      Text('$available in stock', style: TextStyle(color: available <= 5 ? orange : Colors.black54, fontSize: 11)),
      const SizedBox(height: 7),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton.filledTonal(onPressed: qty > 0 ? () => _changeCart(p, -1) : null, icon: const Icon(Icons.remove, size: 20), tooltip: 'Remove one', visualDensity: VisualDensity.compact),
        Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        IconButton.filled(onPressed: qty < available ? () => _changeCart(p, 1) : null, icon: const Icon(Icons.add, size: 20), tooltip: 'Add one', style: IconButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white), visualDensity: VisualDensity.compact),
      ]),
    ])));
  }

  Widget _sell() {
    final filtered = _products.where((p) => p['name'].toString().toLowerCase().contains(_query.toLowerCase())).toList();
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 2, 16, 10), children: [
        Row(children: [
          const Icon(Icons.storefront, color: green, size: 28),
          const SizedBox(width: 10),
          const Expanded(child: Text('Sell', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 29, color: ink))),
          Badge(label: Text('$_cartCount'), isLabelVisible: _cartCount > 0, child: IconButton(onPressed: () => _alert('$_cartCount items in your cart • ${_kes(_cartTotal)}'), tooltip: 'Cart total', icon: const Icon(Icons.shopping_cart_outlined))),
        ]),
        const SizedBox(height: 4),
        Text('$_shop • ${_prettyDate()}', style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 15),
        TextField(controller: _searchController, onChanged: (value) => setState(() => _query = value), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products...')),
        _heading('Products'),
        if (_products.isEmpty) _empty('No products yet. Open Stock to add products.')
        else if (filtered.isEmpty) _empty('No products match this search.')
        else LayoutBuilder(builder: (c, limits) => GridView.builder(
          itemCount: filtered.length,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 10, mainAxisExtent: 220),
          itemBuilder: (c, i) => _productTile(filtered[i]),
        )),
      ])),
      Container(
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 13),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE8EBE9)))),
        child: SafeArea(top: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Order Summary', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Row(children: [Text('Subtotal • $_cartCount items'), const Spacer(), Text(_kes(_cartTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))]),
          const SizedBox(height: 8),
          const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Row(children: ['Cash', 'M-Pesa', 'Credit'].map((method) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 5), child: ChoiceChip(
            selected: _payment == method,
            onSelected: (_) => setState(() => _payment = method),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(method == 'Credit' ? 'Debt' : method)),
          )))).toList()),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: green, padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _cart.isEmpty ? null : _checkout,
            icon: const Icon(Icons.storefront),
            label: Text('Sell • ${_kes(_cartTotal)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          )),
        ])),
      ),
    ]);
  }

  Widget _debtCard(Map<String, Object?> debt) {
    final due = DateTime.tryParse(debt['due_date']?.toString() ?? '');
    final date = DateTime.now();
    final currentDay = DateTime(date.year, date.month, date.day);
    final days = due == null ? null : currentDay.difference(DateTime(due.year, due.month, due.day)).inDays;
    final label = days == null ? 'No due date' : days > 0 ? '$days days overdue' : days == 0 ? 'Due today' : 'Due in ${-days} days';
    final badgeColor = days != null && days > 0 ? orange : deepGreen;
    final name = debt['name']?.toString() ?? '';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((s) => s[0].toUpperCase()).join();
    return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(radius: 25, backgroundColor: const Color(0xFFFF8D29), foregroundColor: Colors.white, child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Owes ${_kes(_number(debt['amount']))}', style: const TextStyle(fontSize: 13)),
        ])),
      ]),
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 12), child: Text(label, style: TextStyle(color: badgeColor, fontWeight: FontWeight.w700, fontSize: 12))),
      Wrap(spacing: 7, runSpacing: 7, children: [
        OutlinedButton.icon(onPressed: () => _contact(debt, whatsapp: false), icon: const Icon(Icons.call_outlined, size: 16), label: const Text('Call')),
        OutlinedButton.icon(onPressed: () => _contact(debt, whatsapp: true), icon: const Icon(Icons.chat_outlined, size: 16), label: const Text('WhatsApp')),
        FilledButton.icon(onPressed: () => _markPaid(debt), style: FilledButton.styleFrom(backgroundColor: orange), icon: const Icon(Icons.check_circle_outline, size: 16), label: const Text('Mark Paid')),
      ]),
    ])));
  }

  Widget _debtPage() {
    final open = _debts.where((d) => d['status'] != 'Paid').toList();
    if (_sortDueFirst) {
      open.sort((a, b) => (a['due_date']?.toString() ?? '9999').compareTo(b['due_date']?.toString() ?? '9999'));
    }
    final total = open.fold<int>(0, (sum, debt) => sum + _number(debt['amount']));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Icon(Icons.menu_book_rounded, color: orange, size: 29),
        const SizedBox(width: 10),
        const Expanded(child: Text('Debts', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
        IconButton(tooltip: 'Add debt', onPressed: _addDebt, icon: const Icon(Icons.add, size: 30)),
      ]),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF9037), Color(0xFFFF6600)]), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.white),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total to Collect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(_kes(total), style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800))),
            Text('${open.length} outstanding debt records', style: const TextStyle(color: Colors.white)),
          ])),
        ]),
      ),
      const SizedBox(height: 13),
      Row(children: [
        const Expanded(child: Text('Customers who owe money', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
        TextButton.icon(onPressed: () => setState(() => _sortDueFirst = !_sortDueFirst), icon: const Icon(Icons.sort), label: Text(_sortDueFirst ? 'Due first' : 'Recent')),
      ]),
      if (open.isEmpty) _empty('No outstanding debts!') else ...open.map(_debtCard),
      const SizedBox(height: 12),
      if (open.isNotEmpty) FilledButton.icon(onPressed: _remindAll, style: FilledButton.styleFrom(backgroundColor: orange, padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.mark_chat_unread_outlined), label: const Text('Remind All')),
      if (_debts.any((d) => d['status'] == 'Paid')) ...[
        _heading('Paid debts'),
        ..._debts.where((d) => d['status'] == 'Paid').map((d) => Card(child: ListTile(
          leading: const Icon(Icons.check_circle, color: green),
          title: Text(d['name'].toString()),
          subtitle: const Text('Paid'),
          trailing: Text(_kes(_number(d['amount']))),
        ))),
      ],
    ]);
  }

  Widget _more() => ListView(padding: const EdgeInsets.all(16), children: [
    _heading('More'),
    Card(child: Column(children: [
      ListTile(leading: const Icon(Icons.receipt_long, color: green), title: const Text('Sales history'), subtitle: const Text('All recent sale items'), trailing: const Icon(Icons.chevron_right), onTap: () => _goTo('Sales history')),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.people_alt_outlined, color: green), title: const Text('Customers'), subtitle: const Text('Saved customer names and numbers'), trailing: const Icon(Icons.chevron_right), onTap: () => _goTo('Customers')),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.payments_outlined, color: green), title: const Text('Debt collections'), subtitle: const Text('Repayments, kept separate from sales'), trailing: const Icon(Icons.chevron_right), onTap: () => _goTo('Collections')),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.settings_outlined, color: green), title: const Text('Shop settings'), subtitle: const Text('Your name and shop name'), trailing: const Icon(Icons.chevron_right), onTap: _settingsDialog),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.ios_share, color: green), title: const Text('Export offline backup'), subtitle: const Text('Save a copy of ALL shop records as a JSON file'), trailing: const Icon(Icons.chevron_right), onTap: _exportBackup),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.restore, color: orange), title: const Text('Restore from backup'), subtitle: const Text('REPLACES all local records after confirmation'), trailing: const Icon(Icons.chevron_right), onTap: _restoreBackup),
    ])),
    const SizedBox(height: 16),
    Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Image.asset('assets/branding/dukabook_logo.png', height: 135, fit: BoxFit.contain),
    )),
    const SizedBox(height: 10),
    const Text('DukaBook • Powered by TILLERN LABS', textAlign: TextAlign.center, style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    const Text('Building Ideas Into Digital Reality', textAlign: TextAlign.center, style: TextStyle(color: brandGold, fontSize: 12)),
    const SizedBox(height: 4),
    const Text('Offline on this phone • shop data stays on this device unless you export it', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 11)),
    const SizedBox(height: 8),
    const Text('Beta 2.1 • Offline backup files are unencrypted. Keep copies somewhere private and verify restore on a test device before trusting them with shop records.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
  ]);

  Widget _detailPage() {
    if (_subPage == 'Customers') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: _customerDialog, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add customer')),
        if (_customers.isEmpty) _empty('No customers saved yet'),
        ..._customers.map((c) => Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(c['name'].toString()),
          subtitle: Text((c['phone']?.toString() ?? '').isEmpty ? 'No phone number' : c['phone'].toString()),
        ))),
      ]);
    }
    if (_subPage == 'Collections') {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Repayments are separate from sales to prevent double-counting.', style: TextStyle(color: Colors.black54)),
        if (_collections.isEmpty) _empty('No debt repayments yet'),
        ..._collections.map((c) => Card(child: ListTile(
          leading: const Icon(Icons.check_circle, color: green),
          title: Text(_kes(_number(c['amount']))),
          subtitle: Text('${c['date']} • ${c['payment_method']} • Debt #${c['debt_id']}'),
        ))),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${_sales.length} latest sale lines', style: const TextStyle(color: Colors.black54)),
      if (_sales.isEmpty) _empty('No sales recorded yet') else ..._sales.map(_saleTile),
      if (_sales.length == 250) const Text('Showing the latest 250 entries only.'),
    ]);
  }

  Widget _welcomeSplash() {
    const splashBackground = Color(0xFF092C21);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('welcome-splash'),
      value: const SystemUiOverlayStyle(
        statusBarColor: splashBackground,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: splashBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: splashBackground,
        body: SafeArea(
          child: SizedBox(
            // Fill the entire display. Centering Text alone does not center
            // the whole splash when an ancestor gives the Column a narrow width.
            width: MediaQuery.sizeOf(context).width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(27),
                            child: Image.asset(
                              'assets/branding/storefront_icon.png',
                              width: 118,
                              height: 118,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'DukaBook',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 35,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Run Your Duka Smarter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: Color(0xFFD1E9DC)),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Welcome to smarter shop management!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFFB3CFC1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'POWERED BY TILLERN LABS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                          color: Color(0xFFE7C77A),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Building Ideas Into Digital Reality',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFA5BDB0), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Home', 'Stock', 'Sell', 'Debts', 'More'];
    Widget page = _home();
    if (_tab == 1) page = _stock();
    if (_tab == 2) page = _sell();
    if (_tab == 3) page = _debtPage();
    if (_tab == 4) page = _more();
    if (_subPage != null) page = _detailPage();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showWelcome ? _welcomeSplash() : AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('dukabook-home'),
      value: const SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
      appBar: _loading || _error != null || (_tab == 0 && _subPage == null) ? null : AppBar(
        leading: _subPage == null ? null : IconButton(onPressed: () => setState(() => _subPage = null), icon: const Icon(Icons.arrow_back)),
        title: Text(_subPage ?? titles[_tab], style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [if (_subPage == null) IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(top: _loading || _error != null || (_tab == 0 && _subPage == null), bottom: false, child: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(18), child: Text(_error!))) : page),
      bottomNavigationBar: _loading || _error != null ? null : NavigationBar(
        height: 67,
        selectedIndex: _tab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _switchTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: green), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2, color: green), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart, color: green), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet, color: orange), label: 'Debts'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    )));
  }
}
