import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AccountantApp());
}

class DatabaseHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  static Future<Database> initDb() async {
    String path = p.join(await getDatabasesPath(), 'al_muhasib_v2.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            amount REAL,
            category TEXT,
            details TEXT,
            type TEXT
          )
        ''');
      },
    );
  }

  static Future<int> insertAccount(Map<String, dynamic> row) async {
    Database dbClient = await db;
    return await dbClient.insert('accounts', row);
  }

  static Future<List<Map<String, dynamic>>> getAccounts(String category) async {
    Database dbClient = await db;
    return await dbClient.query('accounts', where: 'category = ?', whereArgs: [category]);
  }

  static Future<int> deleteAccount(int id) async {
    Database dbClient = await db;
    return await dbClient.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, double>> getTotals() async {
    Database dbClient = await db;
    var resLaho = await dbClient.rawQuery("SELECT SUM(amount) as total FROM accounts WHERE type = 'له'");
    var resAleyhi = await dbClient.rawQuery("SELECT SUM(amount) as total FROM accounts WHERE type = 'عليه'");

    double laho = resLaho.first['total'] != null ? (resLaho.first['total'] as num).toDouble() : 0.0;
    double aleyhi = resAleyhi.first['total'] != null ? (resAleyhi.first['total'] as num).toDouble() : 0.0;

    return {'laho': laho, 'aleyhi': aleyhi};
  }
}

class AccountantApp extends StatelessWidget {
  const AccountantApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'المحاسب',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      theme: ThemeData(
        primaryColor: const Color(0xFF1976D2),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF1976D2),
          secondary: const Color(0xFF388E3C),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> categories = ['عام', 'البقايل', 'العائلة', 'منوع'];
  double totalLaho = 0.0;
  double totalAleyhi = 0.0;

  @override
  void initState() {
    super.initState();
    _refreshTotals();
  }

  void _refreshTotals() async {
    var totals = await DatabaseHelper.getTotals();
    setState(() {
      totalLaho = totals['laho']!;
      totalAleyhi = totals['aleyhi']!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحاسب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).primaryColor,
          bottom: TabBar(
            isScrollable: true,
            labelColor: Colors.yellowAccent, // لون النص عند اختيار التبويب لضمان الوضوح
            unselectedLabelColor: Colors.white, // لون باقي التبويبات الغير محددة
            indicatorColor: Colors.yellowAccent, // لون الخط السفلي التوضيحي
            indicatorWeight: 3.0,
            tabs: categories.map((cat) => Tab(child: Text(cat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))).toList(),
          ),
        ),
        body: TabBarView(
          children: categories.map((cat) => AccountsTab(category: cat, onDataChanged: _refreshTotals)).toList(),
        ),
        bottomNavigationBar: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('له: ${totalLaho.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('عليه: ${totalAleyhi.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Theme.of(context).primaryColor,
          child: const Icon(Icons.add, color: Colors.white),
          onPressed: () => _showAddDialog(context),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final detailsController = TextEditingController();
    String selectedCategory = 'عام';
    String selectedType = 'عليه';

    showDialog(
      context: context,
      builder: (context) => StatefulWidget(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة حساب جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'اسم الحساب')),
                TextField(controller: amountController, decoration: const InputDecoration(labelText: 'المبلغ'), keyboardType: TextInputType.number),
                TextField(controller: detailsController, decoration: const InputDecoration(labelText: 'التفاصيل')),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategory = v!),
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('عليه'),
                        value: 'عليه',
                        groupValue: selectedType,
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('له'),
                        value: 'له',
                        groupValue: selectedType,
                        onChanged: (v) => setDialogState(() => selectedType = v!),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await DatabaseHelper.insertAccount({
                    'name': nameController.text,
                    'amount': double.tryParse(amountController.text) ?? 0.0,
                    'category': selectedCategory,
                    'details': detailsController.text,
                    'type': selectedType,
                  });
                  Navigator.pop(context);
                  setState(() {
                    _refreshTotals();
                  });
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountsTab extends StatefulWidget {
  final String category;
  final VoidCallback onDataChanged;
  const AccountsTab({Key? key, required this.category, required this.onDataChanged}) : super(key: key);

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseHelper.getAccounts(widget.category),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final accounts = snapshot.data!;
        if (accounts.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد حسابات مضافة هنا\nاضغط على زر (+) لإنشاء حساب جديد',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: accounts.length,
          itemBuilder: (context, index) {
            final acc = accounts[index];
            bool isAleyhi = acc['type'] == 'عليه';
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isAleyhi ? Colors.red.shade100 : Colors.green.shade100,
                  child: Icon(Icons.person, color: isAleyhi ? Colors.red : Colors.green),
                ),
                title: Text(acc['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(acc['details'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${acc['amount']}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isAleyhi ? Colors.red : Colors.green,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () async {
                        await DatabaseHelper.deleteAccount(acc['id']);
                        widget.onDataChanged();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
