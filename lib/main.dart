import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final provider = AppAccountProvider();
  try {
    await provider.loadInitialData();
  } catch (e) {
    debugPrint("خطأ في تحميل البيانات الأولية: $e");
  }

  runApp(
    ChangeNotifierProvider<AppAccountProvider>.value(
      value: provider,
      child: const AlMuhasibApp(),
    ),
  );
}

// ----------------------------------------------------
// 1. قاعدة البيانات (Database Helper)
// ----------------------------------------------------
class AppDBHelper {
  static final AppDBHelper instance = AppDBHelper._init();
  static Database? _db;

  AppDBHelper._init();

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDB('al_muhasib_final_v6.db');
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

  Future<void> restoreDatabase(File newDbFile) async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'al_muhasib_final_v6.db');

    await newDbFile.copy(path);
    _db = await openDatabase(path);
  }
}

// ----------------------------------------------------
// 2. إدارة البيانات (App Account Provider)
// ----------------------------------------------------
class AppAccountProvider extends ChangeNotifier {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> currencies = [];
  List<Map<String, dynamic>> currentTransactions = [];
  Map<int, double> customerBalances = {};

  Future<void> loadInitialData() async {
    await loadCategories();
    await loadCurrencies();
    await loadCustomers();
  }

  Future<void> loadCategories() async {
    final db = await AppDBHelper.instance.database;
    categories = await db.query('categories');
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('categories', {'name': name});
    await loadCategories();
  }

  Future<void> deleteCategory(int id) async {
    final db = await AppDBHelper.instance.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await loadCategories();
  }

  Future<void> loadCurrencies() async {
    final db = await AppDBHelper.instance.database;
    currencies = await db.query('currencies');
    notifyListeners();
  }

  Future<void> addCurrency(String name, String symbol) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('currencies', {'name': name, 'symbol': symbol});
    await loadCurrencies();
  }

  Future<void> loadCustomers() async {
    final db = await AppDBHelper.instance.database;
    customers = await db.query('customers');
    await calculateAllCustomerBalances();
    notifyListeners();
  }

  Future<void> calculateAllCustomerBalances() async {
    final db = await AppDBHelper.instance.database;
    customerBalances.clear();
    for (var cust in customers) {
      int cId = int.parse(cust['id'].toString());
      final txs = await db.query('transactions', where: 'customer_id = ?', whereArgs: [cId]);
      double total = 0.0;
      for (var tx in txs) {
        double amt = (tx['amount'] as num).toDouble();
        if (tx['type'] == 'give') {
          total += amt;
        } else {
          total -= amt;
        }
      }
      customerBalances[cId] = total;
    }
  }

  Future<void> addCustomer(String name, String phone, String currency, int categoryId) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('customers', {
      'name': name,
      'phone': phone,
      'currency': currency,
      'category_id': categoryId,
    });
    await loadCustomers();
  }

  Future<void> updateCustomer(int id, String name, String phone, String currency, int categoryId) async {
    final db = await AppDBHelper.instance.database;
    await db.update(
      'customers',
      {
        'name': name,
        'phone': phone,
        'currency': currency,
        'category_id': categoryId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadCustomers();
  }

  Future<void> deleteCustomer(int id) async {
    final db = await AppDBHelper.instance.database;
    await db.delete('transactions', where: 'customer_id = ?', whereArgs: [id]);
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    await loadCustomers();
  }

  Future<void> loadTransactions(int customerId) async {
    final db = await AppDBHelper.instance.database;
    currentTransactions = await db.query('transactions', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id ASC');
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, double amount, String type, String details, String date) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('transactions', {
      'customer_id': customerId,
      'amount': amount,
      'type': type,
      'details': details,
      'date': date,
    });
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> updateTransaction(int id, int customerId, double amount, String type, String details) async {
    final db = await AppDBHelper.instance.database;
    await db.update(
      'transactions',
      {
        'amount': amount,
        'type': type,
        'details': details,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> deleteTransaction(int id, int customerId) async {
    final db = await AppDBHelper.instance.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> exportBackup() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'al_muhasib_final_v6.db');
    final file = File(path);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(path)], text: 'نسخة احتياطية - تطبيق المحاسب');
    }
  }

  Future<bool> importBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        File selectedFile = File(result.files.single.path!);
        await AppDBHelper.instance.restoreDatabase(selectedFile);
        await loadInitialData();
        return true;
      }
    } catch (e) {
      debugPrint('خطأ أثناء الاستعادة: $e');
    }
    return false;
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
      title: 'دفتر المحاسب الشامل',
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

  void _showBackupDialog(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        content: const Text('اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من الهاتف.'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('استعادة نسخة'),
            onPressed: () async {
              Navigator.pop(ctx);
              bool success = await provider.importBackup();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'تمت استعادة البيانات بنجاح' : 'تعذر استعادة الملف (تأكد من اختيار ملف قاعدة بيانات صحيح)',
                    ),
                  ),
                );
              }
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.upload),
            label: const Text('حفظ نسخة'),
            onPressed: () {
              Navigator.pop(ctx);
              provider.exportBackup();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final categories = provider.categories;

    if (categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('دفتر المحاسب الشامل'), centerTitle: true),
        body: const Center(child: Text('لا توجد تصنيفات مضافة')),
      );
    }

    return DefaultTabController(
      length: categories.length,
      child: Builder(
        builder: (context) {
          final TabController tabController = DefaultTabController.of(context);

          return Scaffold(
            appBar: AppBar(
              title: const Text('دفتر المحاسب الشامل'),
              centerTitle: true,
              bottom: TabBar(
                isScrollable: true,
                tabs: categories.map((cat) => Tab(text: cat['name'].toString())).toList(),
              ),
            ),
            drawer: Drawer(
              child: ListView(
                children: [
                  const DrawerHeader(
                    decoration: BoxDecoration(color: Colors.indigo),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'تطبيق المحاسب',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'المهندس : اسامه الاضرعي',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '770638276',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
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
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.backup, color: Colors.indigo),
                    title: const Text('النسخ الاحتياطي والاستعادة'),
                    onTap: () {
                      Navigator.pop(context);
                      _showBackupDialog(context);
                    },
                  ),
                ],
              ),
            ),
            body: AnimatedBuilder(
              animation: tabController,
              builder: (context, _) {
                final activeIndex = tabController.index < categories.length ? tabController.index : 0;
                final currentCatId = int.parse(categories[activeIndex]['id'].toString());

                final categoryCustomers = provider.customers.where((c) {
                  final int customerCatId = int.parse(c['category_id'].toString());
                  final matchesCategory = customerCatId == currentCatId;
                  final String name = (c['name'] ?? '').toString();
                  final String phone = (c['phone'] ?? '').toString();
                  final matchesSearch = name.contains(searchQuery) || phone.contains(searchQuery);
                  return matchesCategory && matchesSearch;
                }).toList();

                double totalGive = 0.0;
                double totalTake = 0.0;
                for (var cust in categoryCustomers) {
                  int cId = int.parse(cust['id'].toString());
                  double bal = provider.customerBalances[cId] ?? 0.0;
                  if (bal > 0) {
                    totalGive += bal;
                  } else {
                    totalTake += bal.abs();
                  }
                }
                double netBalance = totalGive - totalTake;

                return Column(
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
                      child: categoryCustomers.isEmpty
                          ? const Center(child: Text('لا توجد حسابات مضافة في هذا التصنيف'))
                          : ListView.builder(
                              itemCount: categoryCustomers.length,
                              itemBuilder: (ctx, i) {
                                final customer = categoryCustomers[i];
                                final int cId = int.parse(customer['id'].toString());
                                final String custName = (customer['name'] ?? 'حساب').toString();
                                final String firstLetter = custName.isNotEmpty ? custName[0] : '?';
                                final double bal = provider.customerBalances[cId] ?? 0.0;
                                final bool isGive = bal >= 0;

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  elevation: 2,
                                  child: ListTile(
                                    leading: CircleAvatar(child: Text(firstLetter)),
                                    title: Text(
                                      custName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(
                                      bal.abs().toStringAsFixed(1),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: isGive ? Colors.green.shade700 : Colors.red.shade700,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailsScreen(customer: customer),
                                        ),
                                      );
                                    },
                                    onLongPress: () {
                                      _showCustomerOptionsModal(context, provider, customer);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      color: Colors.indigo.shade50,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text('له : ${totalGive.toStringAsFixed(1)}', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('عليه : ${totalTake.toStringAsFixed(1)}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الرصيد : ${netBalance.abs().toStringAsFixed(1)} (${netBalance >= 0 ? "له" : "عليه"})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: netBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                final activeIndex = tabController.index < categories.length ? tabController.index : 0;
                final activeCategoryId = int.parse(categories[activeIndex]['id'].toString());
                _showAddCustomerDialog(context, activeCategoryId);
              },
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  void _showCustomerOptionsModal(BuildContext context, AppAccountProvider provider, Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('تعديل الحساب'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditCustomerDialog(context, customer);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف الحساب'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteCustomer(context, provider, int.parse(customer['id'].toString()));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditCustomerDialog(BuildContext context, Map<String, dynamic> customer) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController(text: customer['name'].toString());
    final phoneCtrl = TextEditingController(text: customer['phone']?.toString() ?? '');
    String selectedCurrency = customer['currency'].toString();
    int selectedCat = int.parse(customer['category_id'].toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الحساب'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الحساب/العميل')),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: provider.currencies.any((c) => c['name'].toString() == selectedCurrency)
                      ? selectedCurrency
                      : (provider.currencies.isNotEmpty ? provider.currencies.first['name'].toString() : 'ريال يمني'),
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
                  value: provider.categories.any((c) => int.parse(c['id'].toString()) == selectedCat)
                      ? selectedCat
                      : (provider.categories.isNotEmpty ? int.parse(provider.categories.first['id'].toString()) : selectedCat),
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: provider.categories.map((c) {
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(value: cId, child: Text(c['name'].toString()));
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
                  provider.updateCustomer(
                    int.parse(customer['id'].toString()),
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    selectedCurrency,
                    selectedCat,
                  );
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

  void _confirmDeleteCustomer(BuildContext context, AppAccountProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من عملية الحذف؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              provider.deleteCustomer(id);
              Navigator.pop(ctx);
            },
            child: const Text('حذف'),
          )
        ],
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, int defaultCatId) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedCurrency = provider.currencies.isNotEmpty ? provider.currencies.first['name'].toString() : 'ريال يمني';
    int selectedCat = defaultCatId;

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
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(value: cId, child: Text(c['name'].toString()));
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
// 5. شاشة تفاصيل الحساب
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
        Provider.of<AppAccountProvider>(context, listen: false).loadTransactions(int.parse(widget.customer['id'].toString())));
  }

  Map<String, String> _formatDateTime(String rawDateTime) {
    try {
      DateTime dt = DateTime.parse(rawDateTime);
      String dateStr = "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      
      int hour = dt.hour;
      String period = hour >= 12 ? 'م' : 'ص';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      
      String timeStr = "$hour:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} $period";
      return {'date': dateStr, 'time': timeStr};
    } catch (e) {
      List<String> parts = rawDateTime.split(' ');
      if (parts.length >= 2) {
        return {'date': parts[0], 'time': parts.sublist(1).join(' ')};
      }
      return {'date': rawDateTime, 'time': ''};
    }
  }

  void _showTransactionOptionsModal(BuildContext context, AppAccountProvider provider, Map<String, dynamic> tx) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('تعديل العملية'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditTransactionDialog(context, tx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف العملية'),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.deleteTransaction(
                    int.parse(tx['id'].toString()),
                    int.parse(widget.customer['id'].toString()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditTransactionDialog(BuildContext context, Map<String, dynamic> tx) {
    final amountCtrl = TextEditingController(text: (tx['amount'] as num).toString());
    final detailsCtrl = TextEditingController(text: tx['details']?.toString() ?? '');
    String selectedType = tx['type'].toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل العملية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ')),
              TextField(controller: detailsCtrl, decoration: const InputDecoration(labelText: 'التفاصيل / البيان')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'نوع العملية'),
                items: const [
                  DropdownMenuItem(value: 'give', child: Text('له (قبض)')),
                  DropdownMenuItem(value: 'take', child: Text('عليه (دفع)')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text);
                if (amount != null) {
                  Provider.of<AppAccountProvider>(context, listen: false).updateTransaction(
                    int.parse(tx['id'].toString()),
                    int.parse(widget.customer['id'].toString()),
                    amount,
                    selectedType,
                    detailsCtrl.text,
                  );
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final rawTransactions = provider.currentTransactions;

    double cumulative = 0.0;
    double totalGive = 0.0;
    double totalTake = 0.0;

    List<Map<String, dynamic>> processedTransactions = [];
    for (var tx in rawTransactions) {
      double amt = (tx['amount'] as num).toDouble();
      if (tx['type'] == 'give') {
        cumulative += amt;
        totalGive += amt;
      } else {
        cumulative -= amt;
        totalTake += amt;
      }
      processedTransactions.add({
        ...tx,
        'running_balance': cumulative,
      });
    }

    final double finalBalance = cumulative;
    final displayTransactions = processedTransactions.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customer['name'].toString(), style: const TextStyle(fontSize: 18)),
            if (widget.customer['phone'] != null && widget.customer['phone'].toString().trim().isNotEmpty)
              Text(
                widget.customer['phone'].toString(),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _exportToPdf(processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendWhatsApp(widget.customer['phone']?.toString(), finalBalance),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: displayTransactions.isEmpty
                ? const Center(child: Text('لا توجد عمليات مسجلة'))
                : Column(
                    children: [
                      Container(
                        color: Colors.lightBlue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        child: const Row(
                          children: [
                            Expanded(flex: 2, child: Text('التاريخ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 2, child: Text('المبلغ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 4, child: Text('التفاصيل', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 2, child: Text('الرصيد', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: displayTransactions.length,
                          separatorBuilder: (ctx, index) => const Divider(height: 1, color: Colors.grey),
                          itemBuilder: (ctx, i) {
                            final tx = displayTransactions[i];
                            final bool isGive = tx['type'] == 'give';
                            final double runBal = tx['running_balance'];
                            final double amt = (tx['amount'] as num).toDouble();
                            final dateTimeFormatted = _formatDateTime(tx['date'].toString());

                            return InkWell(
                              onLongPress: () {
                                _showTransactionOptionsModal(context, provider, tx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            dateTimeFormatted['date']!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                                          ),
                                          if (dateTimeFormatted['time']!.isNotEmpty)
                                            Text(
                                              dateTimeFormatted['time']!,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 9, color: Colors.grey),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: isGive ? Colors.green : Colors.red.shade400,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          amt.toStringAsFixed(0),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        (tx['details'] ?? '').toString(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: runBal >= 0 ? Colors.green.shade100 : Colors.red.shade200,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          runBal.abs().toStringAsFixed(0),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: runBal >= 0 ? Colors.green.shade900 : Colors.red.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.grey.shade200,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('له: ${totalGive.toStringAsFixed(1)}', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('عليه: ${totalTake.toStringAsFixed(1)}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'الرصيد النهائي: ${finalBalance.abs().toStringAsFixed(1)} (${finalBalance >= 0 ? "له" : "عليه"})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: finalBalance >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('له (قبض)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    onPressed: () => _showAddTransactionDialog(context, 'give'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(vertical: 12)),
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
                Provider.of<AppAccountProvider>(context, listen: false).addTransaction(
                  int.parse(widget.customer['id'].toString()),
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

  Future<void> _exportToPdf(List<Map<String, dynamic>> txs, double totalGive, double totalTake, double finalBal) async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');

      final font = pw.Font.ttf(fontData);
      final fontBold = pw.Font.ttf(fontBoldData);

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
      );

      final greenColor = PdfColor.fromHex("#2F855A");
      final redColor = PdfColor.fromHex("#C53030");

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Column(
              cross: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('كشف حساب: ${widget.customer['name']}', style: pw.TextStyle(font: fontBold, fontSize: 18)),
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الهاتف: ${widget.customer['phone'] ?? "غير مسجل"}', style: pw.TextStyle(font: font, fontSize: 12)),
                    pw.Text('العملة: ${widget.customer['currency']}', style: pw.TextStyle(font: font, fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  context: context,
                  border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
                  headerStyle: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
                  cellStyle: pw.TextStyle(font: font, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                  headers: ['التاريخ', 'التفاصيل', 'عليه', 'له', 'الرصيد التراكمي'],
                  data: txs.map((tx) {
                    bool isGive = tx['type'] == 'give';
                    double amt = (tx['amount'] as num).toDouble();
                    double runBal = tx['running_balance'];

                    return [
                      tx['date'].toString(),
                      tx['details'].toString(),
                      isGive ? pw.Text('-', style: pw.TextStyle(font: font)) : pw.Text(amt.toStringAsFixed(1), style: pw.TextStyle(font: fontBold, color: redColor)),
                      isGive ? pw.Text(amt.toStringAsFixed(1), style: pw.TextStyle(font: fontBold, color: greenColor)) : pw.Text('-', style: pw.TextStyle(font: font)),
                      pw.Text(
                        '${runBal.abs().toStringAsFixed(1)} (${runBal >= 0 ? "له" : "عليه"})',
                        style: pw.TextStyle(font: fontBold, color: runBal >= 0 ? greenColor : redColor),
                      ),
                    ];
                  }).toList(),
                ),
                pw.SizedBox(height: 15),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey500)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Text('إجمالي له: ${totalGive.toStringAsFixed(1)}', style: pw.TextStyle(font: fontBold, fontSize: 11, color: greenColor)),
                      pw.Text('إجمالي عليه: ${totalTake.toStringAsFixed(1)}', style: pw.TextStyle(font: fontBold, fontSize: 11, color: redColor)),
                      pw.Text(
                        'الرصيد النهائي: ${finalBal.abs().toStringAsFixed(1)} (${finalBal >= 0 ? "له" : "عليه"})',
                        style: pw.TextStyle(font: fontBold, fontSize: 11, color: finalBal >= 0 ? greenColor : redColor),
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('بواسطة دفتر المحاسب الشامل', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text(DateTime.now().toString().split(' ')[0], style: pw.TextStyle(font: font, fontSize: 9)),
                  ],
                )
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنتاج ملف الـ PDF: $e')),
        );
      }
    }
  }

  Future<void> _sendWhatsApp(String? rawPhone, double balance) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رقم هاتف مضاف لهذا الحساب')),
      );
      return;
    }
    
    String phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    String status = balance >= 0 ? "لك في حسابنا" : "عليكم لحسابنا";
    String message = "كشف حساب من تطبيق المحاسب:\n"
        "العميل: ${widget.customer['name']}\n"
        "المبلغ الحالي: ${balance.abs().toStringAsFixed(1)} ${widget.customer['currency']} ($status)";
        
    final Uri url = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('عذراً، تعذر فتح تطبيق واتساب')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطأ أثناء تشغيل رابط واتساب')),
        );
      }
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
    final provider = Provider.of<AppAccountProvider>(context);

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
              onPressed: () => provider.deleteCategory(int.parse(cat['id'].toString())),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة تصنيف جديد'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'اسم التصنيف')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false).addCategory(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );
  }
}

// ----------------------------------------------------
// 7. شاشة إدارة العملات
// ----------------------------------------------------
class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('إدارة العملات'), centerTitle: true),
      body: ListView.builder(
        itemCount: provider.currencies.length,
        itemBuilder: (ctx, i) {
          final curr = provider.currencies[i];
          return ListTile(
            title: Text(curr['name'].toString()),
            subtitle: Text('الرمز: ${curr['symbol']}'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة عملة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم العملة')),
            TextField(controller: symbolCtrl, decoration: const InputDecoration(labelText: 'رمز العملة (مثل: ر.ي)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && symbolCtrl.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false).addCurrency(nameCtrl.text.trim(), symbolCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );
  }
}
