import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

// DukaBook — offline-first shop register. No cloud account is required.
const green = Color(0xFF009C55);
const deepGreen = Color(0xFF087A48);
const orange = Color(0xFFF66B11);
const ink = Color(0xFF1D2635);
const background = Color(0xFFF7F8F7);

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

  String _prettyDate() {
    final d = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _openDatabase();
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
        DropdownButtonFormField<String>(value: method, decoration: const InputDecoration(l