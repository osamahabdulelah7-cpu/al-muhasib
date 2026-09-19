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
// الألوان المريحة للعين
// ====================================================
class AppColors {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF2C5282);
  static const Color gold = Color(0xFFD4A017);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color green = Color(0xFF2E7D32);
  static const Color greenLight = Color(0xFFE8F5E9);
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);
  static const Color background = Color(0xFFF8F9FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
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
  // استيراد من Excel - يدعم نوعين من الملفات
  // ====================================================
  Future<Map<String, dynamic>> importFromExcel(
    File excelFile, {
    int? categoryId,
  }) async {
    final fileName = excelFile.path.toLowerCase();
    if (fileName.endsWith('.xls')) {
      throw Exception('صيغة .xls غير مدعومة. يرجى حفظ الملف بصيغة .xlsx');
    }

    final bytes = excelFile.readAsBytesSync();
    final excel = excel_lib.Excel.decodeBytes(bytes);

    int customersCreated = 0;
    int transactionsCreated = 0;
    int rowsSkipped = 0;
    String detectedAccountName = '';

    final db = await AppDBHelper.instance.database;

    int finalCategoryId;
    if (categoryId != null) {
      final catCheck = await db.query('categories',
          where: 'id = ?', whereArgs: [categoryId]);
      if (catCheck.isEmpty) {
        throw Exception('التصنيف المحدد غير موجود');
      }
      finalCategoryId = categoryId;
    } else {
      final existingCat = await db.query('categories',
          where: 'name = ?', whereArgs: ['عام']);
      if (existingCat.isEmpty) {
        finalCategoryId = await db.insert('categories', {'name': 'عام'});
      } else {
        finalCategoryId = int.parse(existingCat.first['id'].toString());
      }
    }

    Map<String, int> customerNameToId = {};

    for (var tableName in excel.tables.keys) {
      final sheet = excel.tables[tableName]!;

      debugPrint('📄 قراءة ورقة: $tableName');
      debugPrint('📊 إجمالي الصفوف: ${sheet.maxRows}');

      String? headerAccountName;
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
              headerAccountName = extracted;
            }
          }
        }
      }

      if (headerAccountName != null && detectedAccountName.isEmpty) {
        detectedAccountName = headerAccountName;
      }

      int headerRowIndex = -1;
      int colDate = -1;
      int colDetails = -1;
      int colTake = -1;
      int colGive = -1;
      int colCustomerName = -1;

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
          } else if (cellText == 'اسم الحساب') {
            colCustomerName = j;
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
      debugPrint('👤 عمود اسم الحساب: $colCustomerName');
      debugPrint('📝 عمود التفاصيل: $colDetails');
      debugPrint('⬆️ عمود عليه: $colTake');
      debugPrint('⬇️ عمود له: $colGive');

      if (headerRowIndex == -1) {
        debugPrint('❌ لم يتم العثور على صف العناوين!');
        continue;
      }

      for (int i = headerRowIndex + 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          String customerName = '';

          if (colCustomerName != -1 && colCustomerName < row.length) {
            customerName =
                row[colCustomerName]?.value?.toString().trim() ?? '';
          }

          if (customerName.isEmpty &&
              headerAccountName != null &&
              headerAccountName.isNotEmpty) {
            customerName = headerAccountName;
          }

          String details = '';
          if (colDetails != -1 && colDetails < row.length) {
            details = row[colDetails]?.value?.toString().trim() ?? '';
          }

          if (details.contains('إجمالي') ||
              details.contains('الرصيد الإجمالي') ||
              details.contains('إجمالي العمليات') ||
              customerName.contains('إجمالي') ||
              customerName.contains('الرصيد الإجمالي')) {
            debugPrint('⚠️ تخطي صف الإجمالي');
            continue;
          }

          if (customerName.isEmpty) {
            rowsSkipped++;
            continue;
          }

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
                dateStr =
                    dateCell.asDateTimeLocal().toString().split('.')[0];
              } else {
                dateStr = dateCell.toString().trim();
              }
            }
          }

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

          if (takeAmount == 0 && giveAmount == 0) {
            continue;
          }

          double amount;
          String type;
          if (giveAmount > 0) {
            amount = giveAmount;
            type = 'give';
          } else {
            amount = takeAmount;
            type = 'take';
          }

          if (dateStr.isEmpty) {
            dateStr = DateTime.now().toString().split('.')[0];
          } else {
            try {
              dateStr = _normalizeDate(dateStr);
            } catch (_) {
              dateStr = DateTime.now().toString().split('.')[0];
            }
          }

          int customerId;
          if (customerNameToId.containsKey(customerName)) {
            customerId = customerNameToId[customerName]!;
          } else {
            final existingCust = await db.query('customers',
                where: 'name = ?', whereArgs: [customerName]);
            if (existingCust.isEmpty) {
              customerId = await db.insert('customers', {
                'name': customerName,
                'phone': '',
                'currency': 'ريال يمني',
                'category_id': finalCategoryId,
              });
              customersCreated++;
            } else {
              customerId = int.parse(existingCust.first['id'].toString());
              await db.update(
                'customers',
                {'category_id': finalCategoryId},
                where: 'id = ?',
                whereArgs: [customerId],
              );
            }
            customerNameToId[customerName] = customerId;
          }

          await db.insert('transactions', {
            'customer_id': customerId,
            'amount': amount,
            'type': type,
            'details': details,
            'date': dateStr,
          });
          transactionsCreated++;

          if (transactionsCreated % 100 == 0) {
            debugPrint('📝 تم استيراد $transactionsCreated معاملة...');
          }
        } catch (e) {
          debugPrint('❌ خطأ في الصف $i: $e');
          rowsSkipped++;
        }
      }
    }

    await loadInitialData();

    debugPrint(
        '✅ تم الاستيراد: $customersCreated حساب و $transactionsCreated معاملة');

    String displayName;
    if (customersCreated > 1) {
      displayName = 'كل الحسابات ($customersCreated حساب)';
    } else if (detectedAccountName.isNotEmpty) {
      displayName = detectedAccountName;
    } else if (customersCreated == 1) {
      displayName = 'حساب واحد';
    } else {
      displayName = 'لا توجد بيانات جديدة';
    }

    return {
      'customers': customersCreated,
      'transactions': transactionsCreated,
      'skipped': rowsSkipped,
      'accountName': displayName,
    };
  }

  String _normalizeDate(String dateStr) {
    dateStr = dateStr.trim();

    try {
      DateTime dt = DateTime.parse(dateStr);
      return dt.toString().split('.')[0];
    } catch (_) {}

    final match1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dateStr);
    if (match1 != null) {
      final y = match1.group(1)!;
      final m = match1.group(2)!.padLeft(2, '0');
      final d = match1.group(3)!.padLeft(2, '0');
      return '$y-$m-${d}T00:00:00';
    }

    final match2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(dateStr);
    if (match2 != null) {
      final d = match2.group(1)!.padLeft(2, '0');
      final m = match2.group(2)!.padLeft(2, '0');
      final y = match2.group(3)!;
      return '$y-$m-${d}T00:00:00';
    }

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
            fontSize: 18,
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
          elevation: 2,
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String searchQuery = '';
  TabController? _tabController;

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

  Future<void> _importFromExcel(BuildContext context) async {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);

    if (provider.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد تصنيفات. أضف تصنيفاً أولاً'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    int selectedCategoryId =
        int.parse(provider.categories.first['id'].toString());

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.folder_open, color: AppColors.primary),
              SizedBox(width: 8),
              Text('اختر التصنيف'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'في أي تصنيف تريد إضافة الحسابات المستوردة؟',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<int>(
                value: selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  prefixIcon: Icon(Icons.folder),
                ),
                items: provider.categories.map((c) {
                  final int cId = int.parse(c['id'].toString());
                  return DropdownMenuItem<int>(
                    value: cId,
                    child: Text(c['name'].toString()),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null)
                    setDialogState(() => selectedCategoryId = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.single.path == null) return;

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
      final stats = await provider.importFromExcel(
        excelFile,
        categoryId: selectedCategoryId,
      );

      if (context.mounted) {
        Navigator.pop(context);

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
                  Text('📁 ${stats['accountName']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const Divider(),
                ],
                Text('✅ حسابات جديدة: ${stats['customers']}',
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
      if (context.mounted) {
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

    if (_tabController == null ||
        _tabController!.length != categories.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: categories.length,
        vsync: this,
      );
    }

    return Scaffold(
      // ✅ بدون عنوان — التابات في الأعلى مباشرة
      appBar: AppBar(
        title: const SizedBox.shrink(),
        toolbarHeight: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        leadingWidth: 56,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppColors.gold,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: categories
              .map((cat) => Tab(text: cat['name'].toString()))
              .toList(),
        ),
      ),
      drawerEnableOpenDragGesture: false,
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
                      border: Border.all(color: AppColors.gold, width: 3),
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
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(Icons.phone, color: AppColors.gold, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '770638276',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14),
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
                child: const Icon(Icons.category, color: AppColors.primary),
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
                child: const Icon(Icons.cloud_sync, color: AppColors.green),
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
                'دفتر المحاسب © 2026',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      body: Column(
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: categories.map((cat) {
                final int currentCatId =
                    int.parse(cat['id'].toString());

                final categoryCustomers = provider.customers.where((c) {
                  final int customerCatId =
                      int.parse(c['category_id'].toString());
                  final matchesCategory = customerCatId == currentCatId;
                  final String name = (c['name'] ?? '').toString();
                  final String phone = (c['phone'] ?? '').toString();
                  final matchesSearch =
                      name.contains(searchQuery) ||
                          phone.contains(searchQuery);
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
                    Expanded(
                      child: categoryCustomers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              itemCount: categoryCustomers.length,
                              itemBuilder: (ctx, i) {
                                final customer = categoryCustomers[i];
                                final int cId = int.parse(
                                    customer['id'].toString());
                                final String custName =
                                    (customer['name'] ?? 'حساب')
                                        .toString();
                                final String firstLetter =
                                    custName.isNotEmpty ? custName[0] : '?';
                                final double bal =
                                    provider.customerBalances[cId] ?? 0.0;
                                final bool isGive = bal >= 0;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  elevation: 1,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              CustomerDetailsScreen(
                                                  customer: customer),
                                        ),
                                      );
                                    },
                                    onLongPress: () {
                                      _showCustomerOptionsModal(
                                          context, provider, customer);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 45,
                                            height: 45,
                                            decoration: BoxDecoration(
                                              color: isGive
                                                  ? AppColors.greenLight
                                                  : AppColors.redLight,
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              firstLetter,
                                              style: TextStyle(
                                                color: isGive
                                                    ? AppColors.green
                                                    : AppColors.red,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 20,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              custName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: AppColors.textDark,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            bal.abs().toStringAsFixed(1),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isGive
                                                  ? AppColors.green
                                                  : AppColors.red,
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
                    // ✅ شريط الإجماليات - زر + في اليمين أولاً
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E8E8),
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey.shade400,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // ✅ زر + في اليمين - أول عنصر
                          Material(
                            color: AppColors.gold,
                            shape: const CircleBorder(),
                            elevation: 4,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                final activeIndex = _tabController!.index;
                                final activeCategoryId = int.parse(
                                    categories[activeIndex]['id'].toString());
                                _showAddCustomerDialog(
                                    context, activeCategoryId);
                              },
                              child: Container(
                                width: 60,
                                height: 60,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // ✅ الإجماليات بعد الزر
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'عليه: ${totalTake.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        color: AppColors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      'له: ${totalGive.toStringAsFixed(1)}',
                                      style: const TextStyle(
                                        color: AppColors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'الرصيد ${netBalance >= 0 ? "له" : "عليه"}: ${netBalance.abs().toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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
                        color: AppColors.primary,
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
                                    vertical: 10, horizontal: 4),
                                color: i.isEven
                                    ? Colors.white
                                    : const Color(0xFFF9FAFB),
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
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textDark),
                                          ),
                                          if (dateTimeFormatted['time']!
                                              .isNotEmpty)
                                            Text(
                                              dateTimeFormatted['time']!,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textMuted),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: isGive
                                              ? AppColors.greenLight
                                              : AppColors.redLight,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          amt.toStringAsFixed(0),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: isGive
                                                  ? AppColors.green
                                                  : AppColors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(
                                          (tx['details'] ?? '').toString(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textDark),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: runBal >= 0
                                              ? const Color(0xFFF1F8E9)
                                              : const Color(0xFFFFF3E0),
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
            color: AppColors.primary,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_upward,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'عليه: ${totalTake.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    '${finalBalance.abs().toStringAsFixed(1)} ${finalBalance >= 0 ? "له" : "عليه"}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'له: ${totalGive.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_downward,
                        color: Colors.greenAccent, size: 18),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.remove, color: Colors.white),
                    label: const Text('عليه',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    onPressed: () =>
                        _showAddTransactionDialog(context, 'take'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('له',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    onPressed: () =>
                        _showAddTransactionDialog(context, 'give'),
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

      final primaryColor = PdfColor.fromHex("#1E3A5F");
      final greenText = PdfColor.fromHex("#1B5E20");
      final redText = PdfColor.fromHex("#B71C1C");
      final textDark = PdfColor.fromHex("#000000");

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(20),
          header: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('كشف حساب',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 14,
                              color: primaryColor)),
                      pw.Text(
                          'التاريخ: ${DateTime.now().toString().split(' ')[0]}',
                          style: pw.TextStyle(
                              font: font, fontSize: 10, color: textDark)),
                    ],
                  ),
                  pw.Divider(color: primaryColor, thickness: 1.5),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('الحساب: ${widget.customer['name']}',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: primaryColor)),
                  if (widget.customer['phone'] != null &&
                      widget.customer['phone'].toString().trim().isNotEmpty)
                    pw.Text('الهاتف: ${widget.customer['phone']}',
                        style: pw.TextStyle(
                            font: font, fontSize: 11, color: textDark)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                border:
                    pw.TableBorder.all(width: 0.5, color: PdfColors.grey500),
                headerStyle: pw.TextStyle(
                    font: fontBold,
                    fontSize: 10,
                    color: PdfColors.white),
                cellStyle: pw.TextStyle(
                    font: font, fontSize: 9, color: textDark),
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
                  'الرصيد',
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
                        "$hour:${dt.minute.toString().padLeft(2, '0')} $period";
                  } catch (_) {}

                  return [
                    pw.Text(
                      '${runBal.abs().toStringAsFixed(1)} ${runBal >= 0 ? "له" : "عليه"}',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: runBal >= 0 ? greenText : redText),
                    ),
                    isGive
                        ? pw.Text(amt.toStringAsFixed(1),
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: greenText))
                        : pw.Text('-',
                            style: pw.TextStyle(
                                font: font, fontSize: 9, color: textDark)),
                    isGive
                        ? pw.Text('-',
                            style: pw.TextStyle(
                                font: font, fontSize: 9, color: textDark))
                        : pw.Text(amt.toStringAsFixed(1),
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9,
                                color: redText)),
                    pw.Text(
                      tx['details'].toString(),
                      style: pw.TextStyle(
                          font: font, fontSize: 9, color: textDark),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(formattedDate,
                            style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 8,
                                color: primaryColor)),
                        if (formattedTime.isNotEmpty)
                          pw.Text(formattedTime,
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 7,
                                  color: PdfColors.grey700)),
                      ],
                    ),
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: primaryColor, width: 1),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي له: ${totalGive.toStringAsFixed(1)}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 11,
                            color: greenText)),
                    pw.Text('إجمالي عليه: ${totalTake.toStringAsFixed(1)}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 11,
                            color: redText)),
                    pw.Text(
                      'الرصيد: ${finalBal.abs().toStringAsFixed(1)} (${finalBal >= 0 ? "له" : "عليه"})',
                      style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 11,
                          color: primaryColor),
                    ),
                  ],
                ),
              ),
            ];
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
    String message = "كشف حساب:\n"
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
