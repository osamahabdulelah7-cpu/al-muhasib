import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AccountProvider()..loadInitialData(),
      child: const AlMuhasibApp(),
    ),
  );
}

// ----------------------------------------------------
// 1. قاعدة البيانات (Database Helper)
// ----------------------------------------------------
class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _db;

  DBHelper._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB('al_muhasib_unified.db');
    return _db!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE currencies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        currency TEXT NOT NULL,
        category_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        details TEXT,
        date TEXT NOT NULL
      )
    ''');

    await db.insert('categories', {'name': 'عام'});
    await db.insert('categories', {'name': 'عملاء'});
    await db.insert('categories', {'name': 'موردون'});

    await db.insert('currencies', {'name': 'ريال يمني', 'symbol': 'ر.ي'});
    await db.insert('currencies', {'name': 'ريال سعودي', 'symbol': 'ر.س'});
    await db.insert('currencies', {'name': 'دولار أمريكي', 'symbol': '\$'});
  }
}

// ----------------------------------------------------
// 2. إدارة البيانات (Account Provider)
// ----------------------------------------------------
class AccountProvider extends ChangeNotifier {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> currencies = [];
  List<Map<String, dynamic>> currentTransactions = [];

  Future<void> loadInitialData() async {
    await loadCategories();
    await loadCurrencies();
    await loadCustomers();
  }

  Future<void> loadCategories() async {
    final db = await DBHelper.instance.database;
    categories = await db.query('categories');
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final db = await DBHelper.instance.database;
    await db.insert('categories', {'name': name});
    await loadCategories();
  }

  Future<void> deleteCategory(int id) async {
    final db = await DBHelper.instance.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await loadCategories();
  }

  Future<void> loadCurrencies() async {
    final db = await DBHelper.instance.database;
    currencies = await db.query('currencies');
    notifyListeners();
  }

  Future<void> addCurrency(String name, String symbol) async {
    final db = await DBHelper.instance.database;
    await db.insert('currencies', {'name': name, 'symbol': symbol});
    await loadCurrencies();
  }

  Future<void> loadCustomers() async {
    final db = await DBHelper.instance.database;
    customers = await db.query('customers');
    notifyListeners();
  }

  Future<void> addCustomer(String name, String phone, String currency, int categoryId) async {
    final db = await DBHelper.instance.database;
    await db.insert('customers', {
      'name': name,
      'phone': phone,
      'currency': currency,
      'category_id': categoryId,
    });
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    final db = await DBHelper.instance.database;
    await db.delete('transactions', where: 'customer_id = ?', whereArgs: [id]);
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    await loadCustomers();
  }

  Future<void> loadTransactions(int customerId) async {
    final db = await DBHelper.instance.database;
    currentTransactions = await db.query('transactions', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id DESC');
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, double amount, String type, String details, String date) async {
    final db = await DBHelper.instance.database;
    await db.insert('transactions', {
      'customer_id': customerId,
      'amount': amount,
      'type': type,
      'details': details,
      'date': date,
    });
    await loadTransactions(customerId);
  }

  Future<void> deleteTransaction(int id, int customerId) async {
    final db = await DBHelper.instance.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await loadTransactions(customerId);
  }

  double getCustomerBalance(List<Map<String, dynamic>> txs) {
    double total = 0.0;
    for (var tx in txs) {
      double amt = (tx['amount'] as num).toDouble();
      if (tx['type'] == 'give') {
        total += amt;
      } else {
        total -= amt;
      }
    }
    return total;
  }
}

// ----------------------------------------------------
// 3. التطبيق الرئيسي (Main App)
// ----------------------------------------------------
class AlMuhasibApp extends StatelessWidget {
  const AlMuhasibApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق المحاسب',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', ''),
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}

// ----------------------------------------------------
// 4. الشاشة الرئيسية (Home Screen)
// ----------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);

    List<Map<String, dynamic>> filteredCustomers = provider.customers.where((c) {
      final String name = (c['name'] ?? '').toString();
      final String phone = (c['phone'] ?? '').toString();
      return name.contains(searchQuery) || phone.contains(searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر المحاسب الشامل'),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Center(child: Text('تطبيق المحاسب', style: TextStyle(color: Colors.white, fontSize: 22))),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('إدارة التصنيفات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.attach_money),
              title: const Text('إدارة العملات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CurrenciesScreen())),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'بحث عن حساب...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
          Expanded(
            child: filteredCustomers.isEmpty
                ? const Center(child: Text('لا توجد حسابات مضافة'))
                : ListView.builder(
                    itemCount: filteredCustomers.length,
                    itemBuilder: (ctx, i) {
                      final customer = filteredCustomers[i];
                      final String custName = (customer['name'] ?? 'حساب').toString();
                      final String firstLetter = custName.isNotEmpty ? custName[0] : '?';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(firstLetter)),
                          title: Text(custName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('العملة: ${customer['currency']} \vert{}${customer['phone'] ?? ''}'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailsScreen(customer: customer),
                              ),
                            );
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            onPressed: () => provider.deleteCustomer(customer['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCustomerDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedCurrency = provider.currencies.isNotEmpty ? provider.currencies.first['name'].toString() : 'ريال يمني';
    int selectedCat = provider.categories.isNotEmpty ? provider.categories.first['id'] as int : 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة حساب جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الحساب/العميل')),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: provider.currencies.map((c) {
                    final String cName = c['name'].toString();
                    return DropdownMenuItem<String>(value: cName, child: Text(cName));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCurrency = val);
                  },
                ),
                DropdownButtonFormField<int>(
                  value: selectedCat,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: provider.categories.map((c) {
                    return DropdownMenuItem<int>(value: c['id'] as int, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCat = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  provider.addCustomer(nameCtrl.text.trim(), phoneCtrl.text.trim(), selectedCurrency, selectedCat);
                  Navigator.pop(ctx);
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

// ----------------------------------------------------
// 5. شاشة تفاصيل الحساب والعمليات
// ----------------------------------------------------
class CustomerDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> customer;
  const CustomerDetailsScreen({super.key, required this.customer});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<AccountProvider>(context, listen: false).loadTransactions(widget.customer['id']));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);
    final transactions = provider.currentTransactions;
    final balance = provider.getCustomerBalance(transactions);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer['name'].toString()),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _sendWhatsApp(widget.customer['phone']?.toString(), balance),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الرصيد الإجمالي:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '${balance.abs()} ${widget.customer['currency']} (${balance >= 0 ? "له" : "عليه"})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: balance >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? const Center(child: Text('لا توجد عمليات مسجلة'))
                : ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (ctx, i) {
                      final tx = transactions[i];
                      final isGive = tx['type'] == 'give';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isGive ? Colors.green.shade100 : Colors.red.shade100,
                            child: Icon(
                              isGive ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isGive ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text('${tx['amount']}${widget.customer['currency']}'),
                          subtitle: Text('${tx['details'] ?? ''}\n${tx['date']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => provider.deleteTransaction(tx['id'], widget.customer['id']),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('له (قبض)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () => _showAddTransactionDialog(context, 'give'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.remove, color: Colors.white),
                    label: const Text('عليه (دفع)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () => _showAddTransactionDialog(context, 'take'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context, String type) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'give' ? 'إضافة مبلغ (له)' : 'إضافة مبلغ (عليه)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
            TextField(controller: detailsCtrl, decoration: const InputDecoration(labelText: 'التفاصيل / البيان')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text);
              if (amount != null) {
                final dateStr = DateTime.now().toString().split('.')[0];
                Provider.of<AccountProvider>(context, listen: false).addTransaction(
                  widget.customer['id'],
                  amount,
                  type,
                  detailsCtrl.text,
                  dateStr,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendWhatsApp(String? phone, double balance) async {
    if (phone == null || phone.isEmpty) return;
    String status = balance >= 0 ? "لك في حسابنا" : "عليكم لحسابنا";
    String message = "كشف حساب من تطبيق المحاسب:\n"
        "العميل: ${widget.customer['name']}\n"
        "المبلغ الحالي: ${balance.abs()} ${widget.customer['currency']} ($status)";
    final Uri url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

// ----------------------------------------------------
// 6. شاشة إدارة التصنيفات
// ----------------------------------------------------
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AccountProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة التصنيفات'), centerTitle: true),
      body: ListView.builder(
        itemCount: provider.categories.length,
        itemBuilder: (ctx, i) {
          final cat = provider.categories[i];
          return ListTile(
            title: Text(cat['name'].toString()),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => provider.deleteCategory(cat['id']),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child

