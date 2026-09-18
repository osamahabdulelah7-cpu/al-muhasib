import 'dart:async';
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
import 'package:excel/excel.dart' as excel_lib;

// ====================================================
// الألوان الموحدة
// ====================================================
class AppColors {
  static const Color primary = Color(0xFF1A237E);
  static const Color primaryLight = Color(0xFF3949AB);
  static const Color gold = Color(0xFFFFB300);
  static const Color goldDark = Color(0xFFF57C00);
  static const Color green = Color(0xFF2E7D32);
  static const Color red = Color(0xFFC62828);
  static const Color background = Color(0xFFF5F5F7);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };

  runZonedGuarded(() async {
    final provider = AppAccountProvider();
    try {
      await provider.loadInitialData();
    } catch (e, st) {
      debugPrint('خطأ في تحميل البيانات الأولية: $e\n$st');
    }

    runApp(
      ChangeNotifierProvider<AppAccountProvider>.value(
        value: provider,
        child: const AlMuhasibApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('ZoneError: $error\n$stack');
  });
}

// ----------------------------------------------------
// 1. قاعدة البيانات
// ----------------------------------------------------
class AppDBHelper {
  static final AppDBHelper instance = AppDBHelper._init();
  static Database? _db;

  AppDBHelper._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
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
    if (_db != null) {
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
// 2. إدارة البيانات
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
      final txs = await db.query('transactions',
          where: 'customer_id = ?', whereArgs: [cId]);
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

  Future<void> addCustomer(
      String name, String phone, String currency, int categoryId) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('customers', {
      'name': name,
      'phone': phone,
      'currency': currency,
      'category_id': categoryId,
    });
    await loadCustomers();
  }

  Future<void> updateCustomer(int id, String name, String phone,
      String currency, int categoryId) async {
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
    currentTransactions = await db.query('transactions',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id ASC');
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, double amount, String type,
      String details, String date) async {
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

  Future<void> updateTransaction(int id, int customerId, double amount,
      String type, String details) async {
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
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'al_muhasib_final_v6.db');
      final file = File(path);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(path)],
            text: 'نسخة احتياطية - تطبيق المحاسب');
      }
    } catch (e) {
      debugPrint('خطأ أثناء التصدير: $e');
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

  // ====================================================
  // استيراد من Excel (مُحسَّن)
  // ====================================================
  Future<Map<String, dynamic>> importFromExcel(File excelFile) async {
    // التحقق من الصيغة
    final fileName = excelFile.path.toLowerCase();
    if (fileName.endsWith('.xls')) {
      throw Exception('صيغة .xls غير مدعومة. يرجى حفظ الملف بصيغة .xlsx');
    }

    final bytes = excelFile.readAsBytesSync();
    final excel = excel_lib.Excel.decodeBytes(bytes);

    int customersCreated = 0;
    int transactionsCreated = 0;
    int rowsSkipped = 0;
    String? accountName;
    String categoryName = 'عام';

    final db = await AppDBHelper.instance.database;

    for (var tableName in excel.tables.keys) {
      final sheet = excel.tables[tableName]!;

      debugPrint('📄 قراءة ورقة: $tableName');
      debugPrint('📊 إجمالي الصفوف: ${sheet.maxRows}');

      // === 1. البحث عن اسم الحساب ===
      for (int i = 0; i < sheet.maxRows && i < 5; i++) {
        final row = sheet.rows[i];
        for (var cell in row) {
          final cellText = cell?.value?.toString() ?? '';
          if (cellText.contains('كشف حساب')) {
            final parts = cellText.split('حساب');
            if (parts.length > 1) {
              String extracted = parts[1].trim();
              if (extracted.startsWith('-')) {
                extracted = extracted.substring(1).trim();
              }
              accountName = extracted;
            }
          }
        }
      }

      // === 2. البحث عن صف العناوين ===
      int headerRowIndex = -1;
      int colDate = -1;
      int colDetails = -1;
      int colTake = -1;
      int colGive = -1;

      for (int i = 0; i < sheet.maxRows && i < 15; i++) {
        final row = sheet.rows[i];
        int foundHeaders = 0;
        for (int j = 0; j < row.length; j++) {
          final cellText = row[j]?.value?.toString().trim() ?? '';
          if (cellText == 'التاريخ') {
            colDate = j;
            foundHeaders++;
          } else if (cellText == 'التفاصيل') {
            colDetails = j;
            foundHeaders++;
          } else if (cellText == 'عليه') {
            colTake = j;
            foundHeaders++;
          } else if (cellText == 'له') {
            colGive = j;
            foundHeaders++;
          }
        }
        if (foundHeaders >= 3) {
          headerRowIndex = i;
          break;
        }
      }

      debugPrint('📍 صف العناوين: $headerRowIndex');
      debugPrint('📅 عمود التاريخ: $colDate');
      debugPrint('📝 عمود التفاصيل: $colDetails');
      debugPrint('⬆️ عمود عليه: $colTake');
      debugPrint('⬇️ عمود له: $colGive');

      if (headerRowIndex == -1) {
        debugPrint('❌ لم يتم العثور على صف العناوين!');
        continue;
      }

      // === 3. التصنيف ===
      int categoryId;
      final existingCat = await db.query('categories',
          where: 'name = ?', whereArgs: [categoryName]);
      if (existingCat.isEmpty) {
        categoryId = await db.insert('categories', {'name': categoryName});
      } else {
        categoryId = int.parse(existingCat.first['id'].toString());
      }

      // === 4. الحساب ===
      if (accountName == null || accountName.isEmpty) {
        accountName = 'حساب ${DateTime.now().millisecondsSinceEpoch}';
      }

      int customerId;
      final existingCust = await db.query('customers',
          where: 'name = ?', whereArgs: [accountName]);
      if (existingCust.isEmpty) {
        customerId = await db.insert('customers', {
          'name': accountName,
          'phone': '',
          'currency': 'ريال يمني',
          'category_id': categoryId,
        });
        customersCreated++;
      } else {
        customerId = int.parse(existingCust.first['id'].toString());
      }

      // === 5. قراءة جميع الصفوف ===
      for (int i = headerRowIndex + 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          // قراءة التفاصيل
          String checkDetails = '';
          if (colDetails != -1 && colDetails < row.length) {
            checkDetails = row[colDetails]?.value?.toString().trim() ?? '';
          }

          // تجاهل صفوف الإجماليات
          if (checkDetails.contains('إجمالي') ||
              checkDetails.contains('الرصيد الإجمالي') ||
              checkDetails.contains('إجمالي العمليات')) {
            debugPrint('⚠️ تخطي صف الإجمالي: $checkDetails');
            continue;
          }

          // قراءة التاريخ
          String dateStr = '';
          if (colDate != -1 && colDate < row.length) {
            final dateCell = row[colDate]?.value;
            if (dateCell != null) {
              if (dateCell is excel_lib.DateCellValue) {
                DateTime dt = DateTime(
                  dateCell.year,
                  dateCell.month,
                  dateCell.day,
                );
                dateStr = dt.toString().split('.')[0];
              } else if (dateCell is excel_lib.DateTimeCellValue) {
                dateStr = dateCell.asDateTimeLocal().toString().split('.')[0];
              } else {
                dateStr = dateCell.toString().trim();
              }
            }
          }

          // قراءة المبالغ
          double takeAmount = 0;
          double giveAmount = 0;

          if (colTake != -1 && colTake < row.length) {
            final v = row[colTake]?.value;
            if (v is excel_lib.IntCellValue) {
              takeAmount = v.value.toDouble();
            } else if (v is excel_lib.DoubleCellValue) {
              takeAmount = v.value;
            } else if (v != null) {
              String s = v.toString().replaceAll(',', '').trim();
              takeAmount = double.tryParse(s) ?? 0;
            }
          }

          if (colGive != -1 && colGive < row.length) {
            final v = row[colGive]?.value;
            if (v is excel_lib.IntCellValue) {
              giveAmount = v.value.toDouble();
            } else if (v is excel_lib.DoubleCellValue) {
              giveAmount = v.value;
            } else if (v != null) {
              String s = v.toString().replaceAll(',', '').trim();
              giveAmount = double.tryParse(s) ?? 0;
            }
          }

          // تخطي الصفوف التي بلا مبلغ
          if (takeAmount == 0 && giveAmount == 0) {
            continue;
          }

          // تحديد النوع
          double amount;
          String type;
          if (giveAmount > 0) {
            amount = giveAmount;
            type = 'give';
          } else {
            amount = takeAmount;
            type = 'take';
          }

          // التاريخ
          if (dateStr.isEmpty) {
            dateStr = DateTime.now().toString().split('.')[0];
          } else {
            try {
              dateStr = _normalizeDate(dateStr);
            } catch (_) {
              dateStr = DateTime.now().toString().split('.')[0];
            }
          }

          // إضافة المعاملة
          await db.insert('transactions', {
            'customer_id': customerId,
            'amount': amount,
            'type': type,
            'details': checkDetails,
            'date': dateStr,
          });
          transactionsCreated++;

          // طباعة كل 50 معاملة
          if (transactionsCreated % 50 == 0) {
            debugPrint('📝 تم استيراد $transactionsCreated معاملة...');
          }
        } catch (e) {
          debugPrint('❌ خطأ في الصف $i: $e');
          rowsSkipped++;
        }
      }
    }

    await loadInitialData();

    debugPrint('✅ تم الاستيراد: $transactionsCreated معاملة');

    return {
      'customers': customersCreated,
      'transactions': transactionsCreated,
      'skipped': rowsSkipped,
      'accountName': accountName ?? '',
    };
  }

  // تحويل التاريخ إلى صيغة موحدة
  String _normalizeDate(String dateStr) {
    dateStr = dateStr.trim();

    // إذا كان بالفعل ISO
    try {
      DateTime dt = DateTime.parse(dateStr);
      return dt.toString().split('.')[0];
    } catch (_) {}

    // محاولة تنسيق YYYY-MM-DD
    final match1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dateStr);
    if (match1 != null) {
      final y = match1.group(1)!;
      final m = match1.group(2)!.padLeft(2, '0');
      final d = match1.group(3)!.padLeft(2, '0');
      return '$y-$m-${d}T00:00:00';
    }

    // محاولة تنسيق DD/MM/YYYY
    final match2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(dateStr);
    if (match2 != null) {
      final d = match2.group(1)!.padLeft(2, '0');
      final m = match2.group(2)!.padLeft(2, '0');
      final y = match2.group(3)!;
      return '$y-$m-${d}T00:00:00';
    }

    // إرجاع تاريخ اليوم كافتراضي
    return DateTime.now().toString().split('.')[0];
  }
}

// ----------------------------------------------------
// 3. التطبيق الرئيسي
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
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.gold,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.primary),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}

// ----------------------------------------------------
// 4. الشاشة الرئيسية
// ----------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String searchQuery = '';
  bool _isImporting = false;

  void _showBackupDialog(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.backup, color: AppColors.gold),
            SizedBox(width: 8),
            Text('النسخ الاحتياطي'),
          ],
        ),
        content: const Text(
            'اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من الهاتف.'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, color: AppColors.green),
            label: const Text('استعادة نسخة',
                style: TextStyle(color: AppColors.green)),
            onPressed: () async {
              Navigator.pop(ctx);
              bool success = await provider.importBackup();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'تمت استعادة البيانات بنجاح'
                        : 'تعذر استعادة الملف'),
                    backgroundColor:
                        success ? AppColors.green : AppColors.red,
                  ),
                );
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
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

  // ====================================================
  // استيراد من Excel
  // ====================================================
  Future<void> _importFromExcel(BuildContext context) async {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.single.path == null) return;

      // إظهار شاشة تحميل
      setState(() => _isImporting = true);
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => WillPopScope(
            onWillPop: () async => false,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.gold),
                      SizedBox(height: 15),
                      Text('جاري الاستيراد...'),
                      SizedBox(height: 5),
                      Text('قد يستغرق دقيقة للملفات الكبيرة',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      File excelFile = File(result.files.single.path!);
      final stats = await provider.importFromExcel(excelFile);

      setState(() => _isImporting = false);

      if (context.mounted) {
        Navigator.pop(context); // إغلاق شاشة التحميل

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.green),
                SizedBox(width: 8),
                Text('تم الاستيراد بنجاح'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((stats['accountName'] as String).isNotEmpty) ...[
                  Text('📁 الحساب: ${stats['accountName']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const Divider(),
                ],
                Text('✅ عملاء جدد: ${stats['customers']}',
                    style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 5),
                Text('✅ معاملات: ${stats['transactions']}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.green)),
                if ((stats['skipped'] as int) > 0) ...[
                  const SizedBox(height: 5),
                  Text('⚠️ تم تجاهل: ${stats['skipped']} صف',
                      style: const TextStyle(color: Colors.orange)),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تم'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isImporting = false);
      if (context.mounted) {
        // إغلاق شاشة التحميل إن كانت مفتوحة
        Navigator.of(context, rootNavigator: true).popUntil((route) {
          return route.settings.name != null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final categories = provider.categories;

    if (categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('دفتر المحاسب الشامل'),
        ),
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
              bottom: TabBar(
                isScrollable: true,
                indicatorColor: AppColors.gold,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
                tabs: categories
                    .map((cat) => Tab(text: cat['name'].toString()))
                    .toList(),
              ),
            ),
            drawer: Drawer(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 25),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.gold, width: 3),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'تطبيق المحاسب',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'المهندس : اسامه الاضرعي',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(Icons.phone,
                                color: AppColors.gold, size: 16),
                            SizedBox(width: 6),
                            Text(
                              '770638276',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.category,
                          color: AppColors.primary),
                    ),
                    title: const Text('إدارة التصنيفات',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CategoriesScreen())),
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.attach_money,
                          color: AppColors.goldDark),
                    ),
                    title: const Text('إدارة العملات',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CurrenciesScreen())),
                  ),
                  const Divider(height: 20, indent: 20, endIndent: 20),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.upload_file, color: Colors.teal),
                    ),
                    title: const Text('استيراد من Excel',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _importFromExcel(context);
                    },
                  ),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_sync,
                          color: AppColors.green),
                    ),
                    title: const Text('النسخ الاحتياطي والاستعادة',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _showBackupDialog(context);
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(15),
                    child: const Text(
                      'دفتر المحاسب الشامل © 2026',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            body: AnimatedBuilder(
              animation: tabController,
              builder: (context, _) {
                final activeIndex = tabController.index < categories.length
                    ? tabController.index
                    : 0;
                final currentCatId =
                    int.parse(categories[activeIndex]['id'].toString());

                final categoryCustomers = provider.customers.where((c) {
                  final int customerCatId =
                      int.parse(c['category_id'].toString());
                  final matchesCategory = customerCatId == currentCatId;
                  final String name = (c['name'] ?? '').toString();
                  final String phone = (c['phone'] ?? '').toString();
                  final matchesSearch =
                      name.contains(searchQuery) || phone.contains(searchQuery);
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: AppColors.primary,
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.gold,
                        decoration: InputDecoration(
                          hintText: 'بحث عن حساب...',
                          hintStyle: const TextStyle(color: Colors.white70),
                          prefixIcon:
                              const Icon(Icons.search, color: AppColors.gold),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onChanged: (val) => setState(() => searchQuery = val),
                      ),
                    ),
                    Expanded(
                      child: categoryCustomers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox,
                                      size: 80,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 15),
                                  Text(
                                    'لا توجد حسابات مضافة',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 15),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: categoryCustomers.length,
                              itemBuilder: (ctx, i) {
                                final customer = categoryCustomers[i];
                                final int cId =
                                    int.parse(customer['id'].toString());
                                final String custName =
                                    (customer['name'] ?? 'حساب').toString();
                                final String firstLetter =
                                    custName.isNotEmpty ? custName[0] : '?';
                                final double bal =
                                    provider.customerBalances[cId] ?? 0.0;
                                final bool isGive = bal >= 0;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailsScreen(
                                              customer: customer),
                                        ),
                                      );
                                    },
                                    onLongPress: () {
                                      _showCustomerOptionsModal(
                                          context, provider, customer);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: isGive
                                                    ? [
                                                        AppColors.green,
                                                        AppColors.green
                                                            .withOpacity(0.7)
                                                      ]
                                                    : [
                                                        AppColors.red,
                                                        AppColors.red
                                                            .withOpacity(0.7)
                                                      ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              firstLetter,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 22,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  custName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: AppColors.primary,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  customer['currency']
                                                      .toString(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isGive
                                                  ? AppColors.green
                                                      .withOpacity(0.12)
                                                  : AppColors.red
                                                      .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              bal.abs().toStringAsFixed(1),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isGive
                                                    ? AppColors.green
                                                    : AppColors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildTotalChip(
                                  'له', totalGive, Icons.arrow_downward, true),
                              _buildTotalChip('عليه', totalTake,
                                  Icons.arrow_upward, false),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'الرصيد: ${netBalance.abs().toStringAsFixed(1)} ${netBalance >= 0 ? "له" : "عليه"}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
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
                final activeIndex = tabController.index < categories.length
                    ? tabController.index
                    : 0;
                final activeCategoryId =
                    int.parse(categories[activeIndex]['id'].toString());
                _showAddCustomerDialog(context, activeCategoryId);
              },
              child: const Icon(Icons.add, size: 30),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTotalChip(
      String label, double amount, IconData icon, bool isGreen) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            color: isGreen ? Colors.greenAccent : Colors.redAccent, size: 20),
        const SizedBox(width: 6),
        Text(
          '$label: ${amount.toStringAsFixed(1)}',
          style: TextStyle(
            color: isGreen ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  void _showCustomerOptionsModal(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 15),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: AppColors.primary),
                ),
                title: const Text('تعديل الحساب',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditCustomerDialog(context, customer);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete, color: AppColors.red),
                ),
                title: const Text('حذف الحساب',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteCustomer(context, provider,
                      int.parse(customer['id'].toString()));
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showEditCustomerDialog(
      BuildContext context, Map<String, dynamic> customer) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final nameCtrl = TextEditingController(text: customer['name'].toString());
    final phoneCtrl =
        TextEditingController(text: customer['phone']?.toString() ?? '');
    String selectedCurrency = customer['currency'].toString();
    int selectedCat = int.parse(customer['category_id'].toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: AppColors.primary),
              SizedBox(width: 8),
              Text('تعديل الحساب'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'اسم الحساب/العميل')),
                const SizedBox(height: 10),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: provider.currencies
                          .any((c) => c['name'].toString() == selectedCurrency)
                      ? selectedCurrency
                      : (provider.currencies.isNotEmpty
                          ? provider.currencies.first['name'].toString()
                          : 'ريال يمني'),
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: provider.currencies.map((c) {
                    final String cName = c['name'].toString();
                    return DropdownMenuItem<String>(
                        value: cName, child: Text(cName));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null)
                      setDialogState(() => selectedCurrency = val);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: provider.categories.any(
                          (c) => int.parse(c['id'].toString()) == selectedCat)
                      ? selectedCat
                      : (provider.categories.isNotEmpty
                          ? int.parse(provider.categories.first['id'].toString())
                          : selectedCat),
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: provider.categories.map((c) {
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(
                        value: cId, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCat = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
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

  void _confirmDeleteCustomer(
      BuildContext context, AppAccountProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: const Text('هل أنت متأكد من عملية الحذف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
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
    String selectedCurrency = provider.currencies.isNotEmpty
        ? provider.currencies.first['name'].toString()
        : 'ريال يمني';
    int selectedCat = defaultCatId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: AppColors.primary),
              SizedBox(width: 8),
              Text('إضافة حساب جديد'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'اسم الحساب/العميل')),
                const SizedBox(height: 10),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'العملة'),
                  items: provider.currencies.map((c) {
                    final String cName = c['name'].toString();
                    return DropdownMenuItem<String>(
                        value: cName, child: Text(cName));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null)
                      setDialogState(() => selectedCurrency = val);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: selectedCat,
                  decoration: const InputDecoration(labelText: 'التصنيف'),
                  items: provider.categories.map((c) {
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(
                        value: cId, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCat = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  provider.addCustomer(
                      nameCtrl.text.trim(),
                      phoneCtrl.text.trim(),
                      selectedCurrency,
                      selectedCat);
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
    Future.microtask(() => Provider.of<AppAccountProvider>(context,
            listen: false)
        .loadTransactions(int.parse(widget.customer['id'].toString())));
  }

  Map<String, String> _formatDateTime(String rawDateTime) {
    try {
      DateTime dt = DateTime.parse(rawDateTime);
      String dateStr = "${dt.year}-${dt.month}-${dt.day}";
      int hour = dt.hour;
      String period = hour >= 12 ? 'م' : 'ص';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      String timeStr =
          "$hour:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} $period";
      return {'date': dateStr, 'time': timeStr};
    } catch (e) {
      List<String> parts = rawDateTime.split(' ');
      if (parts.length >= 2) {
        return {'date': parts[0], 'time': parts.sublist(1).join(' ')};
      }
      return {'date': rawDateTime, 'time': ''};
    }
  }

  void _showTransactionOptionsModal(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 15),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: AppColors.primary),
                ),
                title: const Text('تعديل العملية',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditTransactionDialog(context, tx);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete, color: AppColors.red),
                ),
                title: const Text('حذف العملية',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.deleteTransaction(
                    int.parse(tx['id'].toString()),
                    int.parse(widget.customer['id'].toString()),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showEditTransactionDialog(
      BuildContext context, Map<String, dynamic> tx) {
    final amountCtrl =
        TextEditingController(text: (tx['amount'] as num).toString());
    final detailsCtrl =
        TextEditingController(text: tx['details']?.toString() ?? '');
    String selectedType = tx['type'].toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: AppColors.primary),
              SizedBox(width: 8),
              Text('تعديل العملية'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المبلغ')),
              const SizedBox(height: 10),
              TextField(
                  controller: detailsCtrl,
                  decoration:
                      const InputDecoration(labelText: 'التفاصيل / البيان')),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () {
                final amount = double.tryParse(amountCtrl.text);
                if (amount != null) {
                  Provider.of<AppAccountProvider>(context, listen: false)
                      .updateTransaction(
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
            Text(widget.customer['name'].toString(),
                style: const TextStyle(fontSize: 18)),
            if (widget.customer['phone'] != null &&
                widget.customer['phone'].toString().trim().isNotEmpty)
              Text(
                widget.customer['phone'].toString(),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.gold),
            onPressed: () => _exportToPdf(
                processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: AppColors.gold),
            onPressed: () => _sendWhatsApp(
                widget.customer['phone']?.toString(), finalBalance),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: displayTransactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 15),
                        Text('لا توجد عمليات مسجلة',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 15)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 4),
                        child: const Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text('التاريخ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))),
                            Expanded(
                                flex: 2,
                                child: Text('المبلغ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))),
                            Expanded(
                                flex: 4,
                                child: Text('التفاصيل',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))),
                            Expanded(
                                flex: 2,
                                child: Text('الرصيد',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: displayTransactions.length,
                          separatorBuilder: (ctx, index) => const Divider(
                              height: 1, color: Color(0xFFEEEEEE)),
                          itemBuilder: (ctx, i) {
                            final tx = displayTransactions[i];
                            final bool isGive = tx['type'] == 'give';
                            final double runBal = tx['running_balance'];
                            final double amt = (tx['amount'] as num).toDouble();
                            final dateTimeFormatted =
                                _formatDateTime(tx['date'].toString());

                            return InkWell(
                              onLongPress: () {
                                _showTransactionOptionsModal(
                                    context, provider, tx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            dateTimeFormatted['date']!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary),
                                          ),
                                          if (dateTimeFormatted['time']!
                                              .isNotEmpty)
                                            Text(
                                              dateTimeFormatted['time']!,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      Colors.grey.shade600),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: isGive
                                              ? AppColors.green
                                              : AppColors.red,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          amt.toStringAsFixed(0),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        (tx['details'] ?? '').toString(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: runBal >= 0
                                              ? AppColors.green
                                                  .withOpacity(0.12)
                                              : AppColors.red
                                                  .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          runBal.abs().toStringAsFixed(0),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: runBal >= 0
                                                ? AppColors.green
                                                : AppColors.red,
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
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryChip('له', totalGive, Icons.arrow_downward,
                        Colors.greenAccent),
                    _buildSummaryChip('عليه', totalTake, Icons.arrow_upward,
                        Colors.redAccent),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'الرصيد النهائي: ${finalBalance.abs().toStringAsFixed(1)} ${finalBalance >= 0 ? "له" : "عليه"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('له (قبض)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    onPressed: () =>
                        _showAddTransactionDialog(context, 'give'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.remove, color: Colors.white),
                    label: const Text('عليه (دفع)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    onPressed: () =>
                        _showAddTransactionDialog(context, 'take'),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSummaryChip(
      String label, double amount, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          '$label: ${amount.toStringAsFixed(1)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  void _showAddTransactionDialog(BuildContext context, String type) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final bool isGive = type == 'give';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isGive ? Icons.arrow_downward : Icons.arrow_upward,
              color: isGive ? AppColors.green : AppColors.red,
            ),
            const SizedBox(width: 8),
            Text(isGive ? 'إضافة مبلغ (له)' : 'إضافة مبلغ (عليه)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'المبلغ', prefixIcon: Icon(Icons.attach_money))),
            const SizedBox(height: 10),
            TextField(
                controller: detailsCtrl,
                decoration: const InputDecoration(
                    labelText: 'التفاصيل / البيان',
                    prefixIcon: Icon(Icons.notes))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isGive ? AppColors.green : AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text);
              if (amount != null) {
                final dateStr = DateTime.now().toString().split('.')[0];
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addTransaction(
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

  Future<void> _exportToPdf(List<Map<String, dynamic>> txs, double totalGive,
      double totalTake, double finalBal) async {
    try {
      final fontData =
          await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontBoldData =
          await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final font = pw.Font.ttf(fontData);
      final fontBold = pw.Font.ttf(fontBoldData);

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      );

      final primaryColor = PdfColor.fromHex("#1A237E");
      final goldColor = PdfColor.fromHex("#FFB300");
      final greenColor = PdfColor.fromHex("#2E7D32");
      final redColor = PdfColor.fromHex("#C62828");

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: primaryColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('دفتر المحاسب الشامل',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 12,
                              color: PdfColors.white)),
                      pw.Text('كشف حساب',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 14,
                              color: goldColor)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text('كشف حساب: ${widget.customer['name']}',
                      style: pw.TextStyle(
                          font: fontBold, fontSize: 18, color: primaryColor)),
                ),
                pw.SizedBox(height: 5),
                pw.Divider(color: goldColor, thickness: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        'الهاتف: ${widget.customer['phone'] ?? "غير مسجل"}',
                        style: pw.TextStyle(font: font, fontSize: 12)),
                    pw.Text('العملة: ${widget.customer['currency']}',
                        style: pw.TextStyle(font: font, fontSize: 12)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  context: context,
                  border:
                      pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
                  headerStyle: pw.TextStyle(
                      font: fontBold,
                      fontSize: 10,
                      color: PdfColors.white),
                  cellStyle: pw.TextStyle(font: font, fontSize: 9),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  cellAlignments: {
                    0: pw.Alignment.center,
                    1: pw.Alignment.center,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.center,
                  },
                  headerAlignments: {
                    0: pw.Alignment.center,
                    1: pw.Alignment.center,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.center,
                  },
                  headers: [
                    'الرصيد التراكمي',
                    'له',
                    'عليه',
                    'التفاصيل',
                    'التاريخ',
                  ],
                  data: txs.map((tx) {
                    bool isGive = tx['type'] == 'give';
                    double amt = (tx['amount'] as num).toDouble();
                    double runBal = tx['running_balance'];

                    String rawDate = tx['date'].toString();
                    String formattedDate = rawDate;
                    String formattedTime = '';

                    try {
                      DateTime dt = DateTime.parse(rawDate);
                      formattedDate = "${dt.year}-${dt.month}-${dt.day}";
                      int hour = dt.hour;
                      String period = hour >= 12 ? 'م' : 'ص';
                      hour = hour % 12;
                      if (hour == 0) hour = 12;
                      formattedTime =
                          "$hour:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} $period";
                    } catch (_) {}

                    return [
                      pw.Text(
                        '${runBal.abs().toStringAsFixed(1)} (${runBal >= 0 ? "له" : "عليه"})',
                        style: pw.TextStyle(
                            font: fontBold,
                            color: runBal >= 0 ? greenColor : redColor),
                      ),
                      isGive
                          ? pw.Text(amt.toStringAsFixed(1),
                              style: pw.TextStyle(
                                  font: fontBold, color: greenColor))
                          : pw.Text('-', style: pw.TextStyle(font: font)),
                      isGive
                          ? pw.Text('-', style: pw.TextStyle(font: font))
                          : pw.Text(amt.toStringAsFixed(1),
                              style: pw.TextStyle(
                                  font: fontBold, color: redColor)),
                      pw.Text(tx['details'].toString(),
                          style: pw.TextStyle(font: font)),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(formattedDate,
                              style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 9,
                                  color: primaryColor)),
                          if (formattedTime.isNotEmpty)
                            pw.Text(formattedTime,
                                style: pw.TextStyle(
                                    font: font,
                                    fontSize: 8,
                                    color: PdfColors.grey700)),
                        ],
                      ),
                    ];
                  }).toList(),
                ),
                pw.SizedBox(height: 15),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: primaryColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Text('إجمالي له: ${totalGive.toStringAsFixed(1)}',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 11,
                              color: PdfColors.greenAccent)),
                      pw.Text('إجمالي عليه: ${totalTake.toStringAsFixed(1)}',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 11,
                              color: PdfColors.redAccent)),
                      pw.Text(
                        'الرصيد: ${finalBal.abs().toStringAsFixed(1)} (${finalBal >= 0 ? "له" : "عليه"})',
                        style: pw.TextStyle(
                            font: fontBold, fontSize: 11, color: goldColor),
                      ),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Divider(color: goldColor, thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('بواسطة دفتر المحاسب الشامل',
                        style: pw.TextStyle(
                            font: font, fontSize: 9, color: primaryColor)),
                    pw.Text(DateTime.now().toString().split(' ')[0],
                        style: pw.TextStyle(font: font, fontSize: 9)),
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
    } catch (e, st) {
      debugPrint('PDF Error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إنتاج ملف الـ PDF: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendWhatsApp(String? rawPhone, double balance) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يوجد رقم هاتف مضاف لهذا الحساب'),
            backgroundColor: AppColors.red),
      );
      return;
    }

    String phone = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    String status = balance >= 0 ? "لك في حسابنا" : "عليكم لحسابنا";
    String message = "كشف حساب من تطبيق المحاسب:\n"
        "العميل: ${widget.customer['name']}\n"
        "المبلغ الحالي: ${balance.abs().toStringAsFixed(1)} ${widget.customer['currency']} ($status)";

    final Uri url =
        Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('عذراً، تعذر فتح تطبيق واتساب'),
                backgroundColor: AppColors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('خطأ أثناء تشغيل رابط واتساب'),
              backgroundColor: AppColors.red),
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
      appBar: AppBar(title: const Text('إدارة التصنيفات')),
      body: provider.categories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 15),
                  Text('لا توجد تصنيفات',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 15)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.categories.length,
              itemBuilder: (ctx, i) {
                final cat = provider.categories[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.folder,
                          color: AppColors.primary),
                    ),
                    title: Text(cat['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.red),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: const Text('تأكيد الحذف'),
                            content:
                                const Text('هل أنت متأكد من حذف هذا التصنيف؟'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('إلغاء',
                                      style: TextStyle(color: Colors.grey))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.red),
                                onPressed: () {
                                  provider.deleteCategory(
                                      int.parse(cat['id'].toString()));
                                  Navigator.pop(ctx);
                                },
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder, color: AppColors.primary),
            SizedBox(width: 8),
            Text('إضافة تصنيف جديد'),
          ],
        ),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(
                labelText: 'اسم التصنيف',
                prefixIcon: Icon(Icons.folder_outlined))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addCategory(controller.text.trim());
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
      appBar: AppBar(title: const Text('إدارة العملات')),
      body: provider.currencies.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.attach_money,
                      size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 15),
                  Text('لا توجد عملات',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 15)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.currencies.length,
              itemBuilder: (ctx, i) {
                final curr = provider.currencies[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.attach_money,
                          color: AppColors.goldDark),
                    ),
                    title: Text(curr['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('الرمز: ${curr['symbol']}',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.monetization_on, color: AppColors.goldDark),
            SizedBox(width: 8),
            Text('إضافة عملة جديدة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم العملة',
                    prefixIcon: Icon(Icons.text_fields))),
            const SizedBox(height: 10),
            TextField(
                controller: symbolCtrl,
                decoration: const InputDecoration(
                    labelText: 'رمز العملة (مثل: ر.ي)',
                    prefixIcon: Icon(Icons.currency_exchange))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty &&
                  symbolCtrl.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addCurrency(
                        nameCtrl.text.trim(), symbolCtrl.text.trim());
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
