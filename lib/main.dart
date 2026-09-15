import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppAccountProvider()..loadInitialData(),
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
    if (_db != null) return _db!;
    _db = await _initDB('al_muhasib_final_v5.db');
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

  Future<void> deleteTransaction(int id, int customerId) async {
    final db = await AppDBHelper.instance.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await loadTransactions(customerId);
    await loadCustomers();
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
            body: AnimatedBuilder(
              animation: tabController,
              builder: (context, _) {
                final currentCatId = int.parse(categories[tabController.index]['id'].toString());

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
                                  child: ListTile(
                                    leading: CircleAvatar(child: Text(firstLetter)),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            custName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isGive ? Colors.green.shade50 : Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isGive ? Colors.green.shade300 : Colors.red.shade300,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            '${bal.abs().toStringAsFixed(1)} (${isGive ? "له" : "عليه"})',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isGive ? Colors.green.shade800 : Colors.red.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text('العملة: ${customer['currency']} | الهاتف: ${customer['phone'] ?? "لا يوجد"}'),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                                      onPressed: () => provider.deleteCustomer(cId),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailsScreen(customer: customer),
                                        ),
                                      );
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
                final currentTabIndex = tabController.index;
                final activeCategoryId = int.parse(categories[currentTabIndex]['id'].toString());
                _showAddCustomerDialog(context, activeCategoryId);
              },
              child: const Icon(Icons.add),
            ),
          );
        },
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
// 5. شاشة تفاصيل الحساب والتصدير PDF
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer['name'].toString()),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: () => _exportToPdf(processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _sendWhatsApp(widget.customer['phone']?.toString(), finalBalance),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الرصيد الإجمالي:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  '${finalBalance.abs().toStringAsFixed(1)} ${widget.customer['currency']} (${finalBalance >= 0 ? "له" : "عليه"})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: finalBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: processedTransactions.isEmpty
                ? const Center(child: Text('لا توجد عمليات مسجلة'))
                : ListView.builder(
                    itemCount: processedTransactions.length,
                    itemBuilder: (ctx, i) {
                      final tx = processedTransactions[processedTransactions.length - 1 - i];
                      final isGive = tx['type'] == 'give';
                      final double runBal = tx['running_balance'];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isGive ? Colors.green.shade100 : Colors.red.shade100,
                            child: Icon(
                              isGive ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isGive ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                          title: Text(
                            '${tx['amount']} ${widget.customer['currency']} - (${isGive ? "له" : "عليه"})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isGive ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                          subtitle: Text(
                            '${tx['details'] ?? ''}\nالتاريخ: ${tx['date']}\nالرصيد المتبقي: ${runBal.abs().toStringAsFixed(1)} (${runBal >= 0 ? "له" : "عليه"})',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => provider.deleteTransaction(int.parse(tx['id'].toString()), int.parse(widget.customer['id'].toString())),
                          ),
                        ),
                      );
                    },
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
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final greenColor = PdfColor.fromHex("#2F855A");
    final redColor = PdfColor.fromHex("#C53030");

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
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
