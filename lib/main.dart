import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() => runApp(DukaApp());

class DukaApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DukaBook',
      theme: ThemeData(primarySwatch: Colors.green),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Database? db;
  int todaySales = 0;
  List<Map> debts = [];
  List<Map> products = [];

  @override
  void initState() {
    super.initState();
    initDb();
  }

  Future<void> initDb() async {
    String path = join(await getDatabasesPath(), 'duka.db');
    db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, amount INTEGER, date TEXT)');
      await db.execute('CREATE TABLE debts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, amount INTEGER, date TEXT)');
      await db.execute('CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, stock INTEGER, price INTEGER)');
      // sample data
      await db.insert('products', {'name': 'Bread', 'stock': 5, 'price': 60});
      await db.insert('products', {'name': 'Milk', 'stock': 12, 'price': 60});
    });
    loadData();
  }

  Future<void> loadData() async {
    if (db == null) return;
    var sales = await db!.rawQuery("SELECT SUM(amount) as total FROM sales WHERE date = ?", [DateTime.now().toIso8601String().substring(0,10)]);
    var d = await db!.query('debts');
    var p = await db!.query('products');
    setState(() {
      todaySales = sales.first['total'] as int? ?? 0;
      debts = d;
      products = p;
    });
  }

  Future<void> addSale() async {
    await db!.insert('sales', {'item': 'Sale', 'amount': 100, 'date': DateTime.now().toIso8601String().substring(0,10)});
    loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('DukaBook - Eldoret'), backgroundColor: Colors.green[700]),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.green[50],
              child: ListTile(
                title: Text('Today Sales', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('KES $todaySales', style: TextStyle(fontSize: 28, color: Colors.green[800])),
                trailing: IconButton(icon: Icon(Icons.add, size: 32), onPressed: addSale),
              ),
            ),
            SizedBox(height: 10),
            Text('Low Stock:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...products.where((p) => p['stock'] <= 5).map((p) => ListTile(
              leading: Icon(Icons.warning, color: Colors.red),
              title: Text('${p['name']} - ${p['stock']} left'),
              subtitle: Text('Price: ${p['price']}'),
            )),
            Divider(),
            Text('Debts (Deni): ${debts.length}', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: debts.length,
                itemBuilder: (_, i) => ListTile(title: Text(debts[i]['name']), trailing: Text('KES ${debts[i]['amount']}')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: addSale,
        child: Icon(Icons.point_of_sale),
        backgroundColor: Colors.green,
      ),
    );
  }
}