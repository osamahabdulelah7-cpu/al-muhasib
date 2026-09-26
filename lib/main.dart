import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as excel_lib;

// ====================================================
// ✅ دالة تنسيق الأرقام
// ====================================================
String formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  String str = value.toStringAsFixed(2);
  str = str.replaceAll(RegExp(r'0+$'), '');
  str = str.replaceAll(RegExp(r'\.$'), '');
  return str;
}

// ====================================================
// الألوان
// ====================================================
class AppColors {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF3B7CB8);
  static const Color primaryDark = Color(0xFF1E3A5F);
  static const Color gold = Color(0xFFD4A017);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color green = Color(0xFF2E7D32);
  static const Color greenLight = Color(0xFFE8F5E9);
  static const Color greenDarker = Color(0xFFC8E6C9);
  static const Color greenBright = Color(0xFF66BB6A);
  static const Color greenDark = Color(0xFF1B5E20);
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);
  static const Color redDarker = Color(0xFFFFCDD2);
  static const Color redBright = Color(0xFFEF5350);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color greyLight = Color(0xFFE0E0E0);
  static const Color greyArrow = Color(0xFF9E9E9E);
  static const Color textDarkest = Color(0xFF0D1F3F);
  static const Color whatsapp = Color(0xFF25D366);
  static const Color drive = Color(0xFF4285F4);
  static const Color background = Color(0xFFF8F9FA);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color summaryBar = Color(0xFF1E3A5F);

  static const LinearGradient appBarGradient = LinearGradient(
    colors: [Color(0xFF3B7CB8), Color(0xFF1E3A5F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient summaryGradient = LinearGradient(
    colors: [Color(0xFF3B7CB8), Color(0xFF1E3A5F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ====================================================
// ✅ خدمة النسخ الاحتياطي
// ====================================================
class AutoBackupService {
  static const String _prefEnabled = 'auto_backup_enabled';
  static const String _prefHour = 'auto_backup_hour';
  static const String _prefMinute = 'auto_backup_minute';
  static const String _prefFolderPath = 'auto_backup_folder_path';
  static const String _prefLastBackup = 'auto_backup_last_time';
  static const String _prefLastDbModified = 'auto_backup_last_db_modified';

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_prefEnabled) ?? false,
      'hour': prefs.getInt(_prefHour) ?? 3,
      'minute': prefs.getInt(_prefMinute) ?? 0,
      'folderPath': prefs.getString(_prefFolderPath) ?? '',
      'lastBackup': prefs.getString(_prefLastBackup) ?? '',
      'lastDbModified': prefs.getString(_prefLastDbModified) ?? '',
    };
  }

  static Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? folderPath,
    String? lastBackup,
    String? lastDbModified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) await prefs.setBool(_prefEnabled, enabled);
    if (hour != null) await prefs.setInt(_prefHour, hour);
    if (minute != null) await prefs.setInt(_prefMinute, minute);
    if (folderPath != null) await prefs.setString(_prefFolderPath, folderPath);
    if (lastBackup != null) await prefs.setString(_prefLastBackup, lastBackup);
    if (lastDbModified != null) {
      await prefs.setString(_prefLastDbModified, lastDbModified);
    }
  }

  static Future<bool> requestStoragePermission() async {
    try {
      if (!Platform.isAndroid) return true;
      if (await Permission.manageExternalStorage.isGranted) return true;
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;
      final oldStatus = await Permission.storage.request();
      if (oldStatus.isGranted) return true;
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  static Future<File> _getDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    return File(p.join(dbPath, 'al_muhasib_final_v6.db'));
  }

  static Future<bool> _hasDataChanged() async {
    try {
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) return false;
      final lastModified = (await dbFile.stat()).modified.toIso8601String();
      final settings = await getSettings();
      final lastDbModified = settings['lastDbModified'] as String;
      return lastModified != lastDbModified;
    } catch (e) {
      return true;
    }
  }

  static Future<String?> checkAndRunBackup() async {
    try {
      final settings = await getSettings();
      if (settings['enabled'] != true) return null;
      final folderPath = settings['folderPath'] as String;
      if (folderPath.isEmpty) return null;

      final now = DateTime.now();
      final hour = settings['hour'] as int;
      final minute = settings['minute'] as int;
      final todayTarget =
          DateTime(now.year, now.month, now.day, hour, minute);

      final lastBackupStr = settings['lastBackup'] as String;
      DateTime? lastBackup;
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      bool shouldBackup = false;
      if (lastBackup == null) {
        shouldBackup = true;
      } else if (now.isAfter(todayTarget) &&
          lastBackup.isBefore(todayTarget)) {
        shouldBackup = true;
      }

      if (!shouldBackup) return null;

      final dataChanged = await _hasDataChanged();
      if (!dataChanged) return null;

      return await performBackup(folderPath);
    } catch (e) {
      return null;
    }
  }

  static Future<String?> performBackup(String folderPath) async {
    try {
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) {
        return 'قاعدة البيانات غير موجودة';
      }

      final backupDir = Directory(folderPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final now = DateTime.now();
      final fileName = 'al_muhasib_'
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          '_'
          '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}'
          '.db';

      final targetFile = File(p.join(folderPath, fileName));
      await dbFile.copy(targetFile.path);

      final lastModified = (await dbFile.stat()).modified.toIso8601String();
      await saveSettings(
        lastBackup: now.toIso8601String(),
        lastDbModified: lastModified,
      );

      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<String?> runBackupNow() async {
    final settings = await getSettings();
    final folderPath = settings['folderPath'] as String;
    if (folderPath.isEmpty) {
      return 'الرجاء اختيار مجلد أولاً';
    }
    return await performBackup(folderPath);
  }

  static Future<int> countBackups() async {
    try {
      final settings = await getSettings();
      final folderPath = settings['folderPath'] as String;
      if (folderPath.isEmpty) return 0;

      final dir = Directory(folderPath);
      if (!await dir.exists()) return 0;

      return dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('al_muhasib_'))
          .length;
    } catch (e) {
      return 0;
    }
  }

  static Future<String?> shareLatestBackup() async {
    try {
      final settings = await getSettings();
      final folderPath = settings['folderPath'] as String;
      if (folderPath.isEmpty) return 'لا يوجد مجلد محدد';

      final dir = Directory(folderPath);
      if (!await dir.exists()) return 'المجلد غير موجود';

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('al_muhasib_'))
          .toList();

      if (files.isEmpty) return 'لا توجد نسخ احتياطية';

      files.sort((a, b) => b.path.compareTo(a.path));
      final latest = files.first;

      await Share.shareXFiles(
        [XFile(latest.path)],
        text: 'نسخة احتياطية - تطبيق المحاسب',
      );
      return null;
    } catch (e) {
      return '$e';
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
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

    Future.delayed(const Duration(seconds: 2), () async {
      await AutoBackupService.checkAndRunBackup();
    });
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
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
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
        category_id INTEGER,
        last_activity TEXT
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

    await db.insert('categories', {'name': 'عام', 'sort_order': 1});
    await db.insert('categories', {'name': 'عملاء', 'sort_order': 2});
    await db.insert('categories', {'name': 'موردون', 'sort_order': 3});

    await db.insert('currencies', {'name': 'ريال يمني', 'symbol': 'ر.ي'});
    await db.insert('currencies', {'name': 'ريال سعودي', 'symbol': 'ر.س'});
    await db.insert('currencies', {'name': 'دولار أمريكي', 'symbol': '\$'});
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE customers ADD COLUMN last_activity TEXT');
      final customers = await db.query('customers');
      for (var cust in customers) {
        final cId = cust['id'];
        final lastTx = await db.query(
          'transactions',
          where: 'customer_id = ?',
          whereArgs: [cId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (lastTx.isNotEmpty) {
          await db.update(
            'customers',
            {'last_activity': lastTx.first['date']},
            where: 'id = ?',
            whereArgs: [cId],
          );
        }
      }
    }

    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0');
      final cats = await db.query('categories', orderBy: 'id ASC');
      for (int i = 0; i < cats.length; i++) {
        await db.update(
          'categories',
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [cats[i]['id']],
        );
      }
    }
  }

  Future<void> restoreDatabase(File newDbFile) async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'al_muhasib_final_v6.db');

    await newDbFile.copy(path);
    _db = await openDatabase(path, version: 3, onCreate: _createDB,
        onUpgrade: _upgradeDB);
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
    categories = await db.rawQuery('''
      SELECT * FROM categories
      ORDER BY 
        CASE 
          WHEN sort_order IS NULL OR sort_order = 0 THEN 1 
          ELSE 0 
        END,
        sort_order ASC,
        id ASC
    ''');
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final db = await AppDBHelper.instance.database;
    final maxResult = await db.rawQuery(
        'SELECT MAX(sort_order) as max_order FROM categories');
    int maxOrder = 0;
    if (maxResult.isNotEmpty && maxResult.first['max_order'] != null) {
      maxOrder = int.parse(maxResult.first['max_order'].toString());
    }
    await db.insert('categories', {
      'name': name,
      'sort_order': maxOrder + 1,
    });
    await loadCategories();
  }

  Future<void> updateCategory(int id, String newName) async {
    final db = await AppDBHelper.instance.database;
    await db.update(
      'categories',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadCategories();
  }

  Future<void> reorderCategories(List<int> orderedIds) async {
    final db = await AppDBHelper.instance.database;
    for (int i = 0; i < orderedIds.length; i++) {
      await db.update(
        'categories',
        {'sort_order': i + 1},
        where: 'id = ?',
        whereArgs: [orderedIds[i]],
      );
    }
    await loadCategories();
  }

  Future<int> countCustomersInCategory(int categoryId) async {
    final db = await AppDBHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM customers WHERE category_id = ?',
      [categoryId],
    );
    if (result.isNotEmpty) {
      return int.parse(result.first['count'].toString());
    }
    return 0;
  }

  Future<void> deleteCategory(int id) async {
    final db = await AppDBHelper.instance.database;
    final customersInCat = await db.query(
      'customers',
      where: 'category_id = ?',
      whereArgs: [id],
    );
    for (var cust in customersInCat) {
      final custId = cust['id'];
      await db.delete('transactions',
          where: 'customer_id = ?', whereArgs: [custId]);
    }
    await db.delete('customers', where: 'category_id = ?', whereArgs: [id]);
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    await loadCategories();
    await loadCustomers();
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
    customers = await db.rawQuery('''
      SELECT * FROM customers
      ORDER BY 
        CASE 
          WHEN last_activity IS NULL OR last_activity = '' THEN 1 
          ELSE 0 
        END,
        last_activity DESC,
        id DESC
    ''');
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
      'last_activity': null,
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

  Future<List<String>> getDistinctDetails({String query = ''}) async {
    try {
      final db = await AppDBHelper.instance.database;
      List<Map<String, dynamic>> result;
      if (query.trim().isEmpty) {
        result = await db.rawQuery('''
          SELECT details, COUNT(*) as usage_count
          FROM transactions
          WHERE details IS NOT NULL 
            AND TRIM(details) != ''
          GROUP BY details
          ORDER BY usage_count DESC, details ASC
          LIMIT 50
        ''');
      } else {
        result = await db.rawQuery('''
          SELECT details, COUNT(*) as usage_count
          FROM transactions
          WHERE details IS NOT NULL 
            AND TRIM(details) != ''
            AND details LIKE ?
          GROUP BY details
          ORDER BY usage_count DESC, details ASC
          LIMIT 30
        ''', ['$query%']);
      }
      return result
          .map((row) => (row['details'] ?? '').toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
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
    await db.update(
      'customers',
      {'last_activity': date},
      where: 'id = ?',
      whereArgs: [customerId],
    );
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
    final now = DateTime.now().toString().split('.')[0];
    await db.update(
      'customers',
      {'last_activity': now},
      where: 'id = ?',
      whereArgs: [customerId],
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

      if (headerRowIndex == -1) continue;

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

          if (takeAmount == 0 && giveAmount == 0) continue;

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
                'last_activity': dateStr,
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

          await db.update(
            'customers',
            {'last_activity': dateStr},
            where: 'id = ?',
            whereArgs: [customerId],
          );
        } catch (e) {
          rowsSkipped++;
        }
      }
    }

    await loadInitialData();

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
          backgroundColor: Colors.transparent,
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
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.primary),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}

// ----------------------------------------------------
// ✅ AppBar بتدرج أزرق
// ----------------------------------------------------
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;

  const GradientAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.appBarGradient,
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        toolbarHeight: toolbarHeight,
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBackup();
    });
  }

  Future<void> _checkAutoBackup() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final wasEnabled = settings['enabled'] as bool;
      final lastBackupBefore = settings['lastBackup'] as String;

      final error = await AutoBackupService.checkAndRunBackup();

      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ فشل النسخ التلقائي: $error'),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (error == null && wasEnabled && mounted) {
        final newSettings = await AutoBackupService.getSettings();
        final newLastBackup = newSettings['lastBackup'] as String;

        if (newLastBackup.isNotEmpty && newLastBackup != lastBackupBefore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('✅ تم النسخ الاحتياطي بنجاح'),
                  ],
                ),
                backgroundColor: AppColors.green,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص النسخ: $e');
    }
  }

  void _showBackupDialog(BuildContext context, {bool fromDrive = false}) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            Icon(
              fromDrive ? Icons.cloud : Icons.backup,
              color: fromDrive ? AppColors.drive : AppColors.gold,
            ),
            const SizedBox(width: 8),
            Text(fromDrive ? 'النسخ الاحتياطي (Drive)' : 'النسخ الاحتياطي'),
          ],
        ),
        content: Text(
          fromDrive
              ? 'اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من Google Drive.'
              : 'اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من الهاتف.',
        ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  fromDrive ? AppColors.drive : AppColors.gold,
            ),
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

  void _showBackupOptionsSheet(BuildContext context) {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'النسخ الاحتياطي والاستعادة',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const Divider(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.schedule,
                      color: AppColors.goldDark),
                ),
                title: const Text('خيارات حفظ البيانات',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('حفظ تلقائي يومي',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AutoBackupScreen(),
                    ),
                  ).then((_) {
                    _checkAutoBackup();
                  });
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.smartphone,
                      color: AppColors.green),
                ),
                title: const Text('النسخ الاحتياطي من الهاتف',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('حفظ / استعادة من الجهاز',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBackupDialog(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.drive.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cloud, color: AppColors.drive),
                ),
                title: const Text('النسخ الاحتياطي من Drive',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('حفظ / استعادة من Google Drive',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showBackupDialog(context, fromDrive: true);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showSearchDialog() {
    final searchCtrl = TextEditingController(text: searchQuery);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(
          children: [
            Icon(Icons.search, color: AppColors.primary),
            SizedBox(width: 8),
            Text('البحث عن حساب'),
          ],
        ),
        content: TextField(
          controller: searchCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'اسم الحساب',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (val) {
            setState(() => searchQuery = val);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => searchQuery = '');
              Navigator.pop(ctx);
            },
            child: const Text('إلغاء',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تم'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                borderRadius: BorderRadius.circular(8)),
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
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.appBarGradient,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.menu,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                        ),
                        const Spacer(),
                        Row(
                          children: const [
                            Icon(
                              Icons.menu_book,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'المحاسب',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: _showSearchDialog,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: TabBar(
                      controller: _tabController,
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
                ],
              ),
            ),
          ),
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
                gradient: AppColors.appBarGradient,
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
                _showBackupOptionsSheet(context);
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: categories.map((cat) {
                final int currentCatId = int.parse(cat['id'].toString());

                final categoryCustomers = provider.customers.where((c) {
                  final int customerCatId =
                      int.parse(c['category_id'].toString());
                  final matchesCategory = customerCatId == currentCatId;
                  final String name = (c['name'] ?? '').toString();
                  final String phone = (c['phone'] ?? '').toString();
                  final matchesSearch = name.contains(searchQuery) ||
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
                                  const EdgeInsets.symmetric(vertical: 6),
                              itemCount: categoryCustomers.length,
                              itemBuilder: (ctx, i) {
                                return _buildCustomerCard(
                                    context, provider, categoryCustomers[i]);
                              },
                            ),
                    ),
                    // ✅ شريط المجاميع السفلي مع تدرج أزرق
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      color: AppColors.background,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: Material(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                              elevation: 2,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  final activeIndex = _tabController!.index;
                                  final activeCategoryId = int.parse(
                                      categories[activeIndex]['id'].toString());
                                  _showAddCustomerDialog(
                                      context, activeCategoryId);
                                },
                                child: const Center(
                                  child: Icon(
                                    Icons.add,
                                    color: AppColors.gold,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: AppColors.summaryGradient,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'عليه: ${formatNumber(totalTake)}',
                                        style: const TextStyle(
                                          color: AppColors.redBright,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                      Text(
                                        'له: ${formatNumber(totalGive)}',
                                        style: const TextStyle(
                                          color: AppColors.greenBright,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    height: 1,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 3),
                                  Center(
                                    child: Text(
                                      '${netBalance == 0 ? "الرصيد" : (netBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(netBalance.abs())}',
                                      style: TextStyle(
                                        color: netBalance > 0
                                            ? AppColors.greenBright
                                            : (netBalance < 0
                                                ? AppColors.redBright
                                                : Colors.white),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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

  // ✅ بطاقة الحساب
  Widget _buildCustomerCard(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
    final int cId = int.parse(customer['id'].toString());
    final String custName = (customer['name'] ?? 'حساب').toString();
    final double bal = provider.customerBalances[cId] ?? 0.0;

    Color mainColor;
    Color circleColor;
    if (bal > 0) {
      mainColor = AppColors.greenDark;
      circleColor = AppColors.greenLight;
    } else if (bal < 0) {
      mainColor = AppColors.redDark;
      circleColor = AppColors.redLight;
    } else {
      mainColor = AppColors.greenDark;
      circleColor = AppColors.greenLight;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CustomerDetailsScreen(customer: customer),
              ),
            ).then((_) {
              provider.loadCustomers();
            });
          },
          onLongPress: () {
            _showCustomerOptionsModal(context, provider, customer);
          },
          child: Stack(
            children: [
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: mainColor,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(
                      height: 70,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: circleColor,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person,
                            color: mainColor,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 70,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            custName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textDarkest,
                            ),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 70,
                      child: Center(
                        child: Text(
                          formatNumber(bal.abs()),
                          style: TextStyle(
                            color: mainColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 70,
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_ios,
                          size: 14,
                          color: AppColors.greyArrow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
// 5. صفحة خيارات حفظ البيانات
// ----------------------------------------------------
class AutoBackupScreen extends StatefulWidget {
  const AutoBackupScreen({super.key});

  @override
  State<AutoBackupScreen> createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends State<AutoBackupScreen> {
  bool _enabled = false;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 3, minute: 0);
  String _folderPath = '';
  String _lastBackup = '';
  int _backupCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AutoBackupService.getSettings();
    final count = await AutoBackupService.countBackups();

    if (!mounted) return;
    setState(() {
      _enabled = settings['enabled'] as bool;
      _selectedTime = TimeOfDay(
        hour: settings['hour'] as int,
        minute: settings['minute'] as int,
      );
      _folderPath = settings['folderPath'] as String;
      _lastBackup = settings['lastBackup'] as String;
      _backupCount = count;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final hasPermission = await AutoBackupService.hasStoragePermission();

      if (!hasPermission) {
        if (!mounted) return;

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            title: const Row(
              children: [
                Icon(Icons.security, color: AppColors.gold),
                SizedBox(width: 8),
                Text('صلاحية الوصول'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لكي يعمل الحفظ التلقائي، نحتاج صلاحية الوصول للملفات.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                SizedBox(height: 10),
                Text(
                  '⚠️ سيظهر لك النظام نافذة "السماح بالوصول لجميع الملفات"',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
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
                    backgroundColor: AppColors.gold),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('منح الصلاحية'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;

        final granted = await AutoBackupService.requestStoragePermission();

        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ لم يتم منح الصلاحية'),
                backgroundColor: AppColors.red,
              ),
            );
          }
          return;
        }
      }

      if (_folderPath.isEmpty) {
        final folderPicked = await _pickFolder();
        if (!folderPicked) return;
      }
    }

    await AutoBackupService.saveSettings(enabled: value);
    setState(() => _enabled = value);
  }

  Future<bool> _pickFolder() async {
    try {
      String? selectedDirectory =
          await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) return false;

      await AutoBackupService.saveSettings(folderPath: selectedDirectory);
      setState(() => _folderPath = selectedDirectory);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديد المجلد'),
            backgroundColor: AppColors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'اختر وقت حفظ البيانات',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );

    if (picked != null) {
      await AutoBackupService.saveSettings(
        hour: picked.hour,
        minute: picked.minute,
      );
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _runBackupNow() async {
    if (_folderPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار مجلد أولاً'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    final error = await AutoBackupService.runBackupNow();

    if (!mounted) return;
    Navigator.pop(context);

    if (error == null) {
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ تم الحفظ بنجاح'),
              ],
            ),
            backgroundColor: AppColors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل: $error'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  String _formatLastBackup() {
    if (_lastBackup.isEmpty) return 'لا يوجد';
    try {
      final dt = DateTime.parse(_lastBackup);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return _lastBackup;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('خيارات حفظ البيانات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            child: SwitchListTile(
              value: _enabled,
              onChanged: _toggleEnabled,
              activeColor: Colors.pink,
              secondary: Container(
                width: 45,
                height: 45,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alarm, color: Colors.red, size: 26),
              ),
              title: const Text(
                'حفظ البيانات يومياً',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              subtitle: const Text(
                'حفظ البيانات تلقائياً مرة واحدة باليوم (بشرط تغيرت البيانات)',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF8E1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder,
                  color: Color(0xFFFFA000), size: 26),
            ),
            title: const Text(
              'مجلد حفظ البيانات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            subtitle: Text(
              _folderPath.isEmpty
                  ? 'لم يتم تحديد مجلد'
                  : '$_folderPath/',
              style: TextStyle(
                fontSize: 13,
                color: _folderPath.isEmpty
                    ? AppColors.red
                    : AppColors.textMuted,
              ),
            ),
            onTap: () async {
              if (_folderPath.isEmpty) {
                await _pickFolder();
              } else {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    title: const Text('مجلد حفظ البيانات'),
                    content: SelectableText(
                      _folderPath,
                      style: const TextStyle(fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _pickFolder();
                        },
                        child: const Text('تغيير المجلد'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('حسناً'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                color: Color(0xFFE3F2FD),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time,
                  color: Color(0xFF1976D2), size: 26),
            ),
            title: const Text(
              'وقت حفظ البيانات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            subtitle: Text(
              '${_selectedTime.hour.toString().padLeft(2, '0')}:'
              '${_selectedTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
            ),
            onTap: _pickTime,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                color: Color(0xFFF3E5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history,
                  color: Color(0xFF7B1FA2), size: 26),
            ),
            title: const Text(
              'آخر نسخة',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            subtitle: Text(
              _formatLastBackup(),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_copy,
                  color: Color(0xFF2E7D32), size: 26),
            ),
            title: const Text(
              'عدد النسخ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            subtitle: Text(
              '$_backupCount ملف',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 20),
          if (_enabled && _folderPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _runBackupNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    icon: const Icon(Icons.backup),
                    label: const Text('نسخ الآن (تجريبي)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final error =
                          await AutoBackupService.shareLatestBackup();
                      if (error != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: AppColors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('مشاركة آخر نسخة',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.goldDark, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتم الحفظ عند فتح التطبيق إذا فات الموعد المحدد وكانت البيانات قد تغيرت',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textDark,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ----------------------------------------------------
// 6. شاشة تفاصيل الحساب
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: AppColors.primary),
              SizedBox(width: 8),
              Text('تعديل العملية'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
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
                  decoration:
                      const InputDecoration(labelText: 'نوع العملية'),
                  items: const [
                    DropdownMenuItem(
                        value: 'give', child: Text('له (قبض)')),
                    DropdownMenuItem(
                        value: 'take', child: Text('عليه (دفع)')),
                  ],
                  onChanged: (val) {
                    if (val != null)
                      setDialogState(() => selectedType = val);
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

  // ✅ نافذة إضافة عملية جديدة (بدون اقتراحات - مبسطة)
  void _showAddTransactionDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final dateCtrl = TextEditingController(
        text:
            '${selectedDate.year}-${selectedDate.month}-${selectedDate.day}');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: [
              const Icon(Icons.add_circle_outline,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('إضافة عملية جديدة'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                          dateCtrl.text =
                              '${picked.year}-${picked.month}-${picked.day}';
                        });
                      }
                    },
                    child: AbsorbPointer(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'التاريخ',
                          prefixIcon: Icon(Icons.calendar_today),
                          suffixIcon: Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'التفاصيل / البيان',
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount =
                                double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text('الرجاء إدخال المبلغ'),
                                  backgroundColor: AppColors.red,
                                ),
                              );
                              return;
                            }
                            final now = DateTime.now();
                            final dateStr = '${selectedDate.year}-'
                                '${selectedDate.month}-'
                                '${selectedDate.day} '
                                '${now.hour.toString().padLeft(2, '0')}:'
                                '${now.minute.toString().padLeft(2, '0')}:'
                                '${now.second.toString().padLeft(2, '0')}';
                            Provider.of<AppAccountProvider>(context,
                                    listen: false)
                                .addTransaction(
                              int.parse(widget.customer['id'].toString()),
                              amount,
                              'take',
                              detailsCtrl.text,
                              dateStr,
                            );
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('عليه',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount =
                                double.tryParse(amountCtrl.text);
                            if (amount == null || amount <= 0) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text('الرجاء إدخال المبلغ'),
                                  backgroundColor: AppColors.red,
                                ),
                              );
                              return;
                            }
                            final now = DateTime.now();
                            final dateStr = '${selectedDate.year}-'
                                '${selectedDate.month}-'
                                '${selectedDate.day} '
                                '${now.hour.toString().padLeft(2, '0')}:'
                                '${now.minute.toString().padLeft(2, '0')}:'
                                '${now.second.toString().padLeft(2, '0')}';
                            Provider.of<AppAccountProvider>(context,
                                    listen: false)
                                .addTransaction(
                              int.parse(widget.customer['id'].toString()),
                              amount,
                              'give',
                              detailsCtrl.text,
                              dateStr,
                            );
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('له',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.grey)),
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
      appBar: GradientAppBar(
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: AppColors.gold),
            onPressed: () => _exportToPdf(
                processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(
              Icons.chat,
              color: AppColors.whatsapp,
              size: 26,
            ),
            tooltip: 'إرسال عبر واتساب',
            onPressed: () => _sendWhatsApp(
                widget.customer['phone']?.toString(), finalBalance),
          ),
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

                            Color amtBg = isGive
                                ? AppColors.green
                                : AppColors.red;
                            Color balBg = runBal >= 0
                                ? AppColors.green
                                : AppColors.red;

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
                                          color: amtBg,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          formatNumber(amt),
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
                                          color: balBg,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          formatNumber(runBal.abs()),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
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
          // ✅ شريط سفلي بتدرج أزرق
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: AppColors.background,
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Material(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showAddTransactionDialog(context),
                      child: const Center(
                        child: Icon(
                          Icons.add,
                          color: AppColors.gold,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppColors.summaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'عليه: ${formatNumber(totalTake)}',
                              style: const TextStyle(
                                color: AppColors.redBright,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              'له: ${formatNumber(totalGive)}',
                              style: const TextStyle(
                                color: AppColors.greenBright,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.3),
                        ),
                        const SizedBox(height: 3),
                        Center(
                          child: Text(
                            '${finalBalance == 0 ? "الرصيد" : (finalBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(finalBalance.abs())}',
                            style: TextStyle(
                              color: finalBalance > 0
                                  ? AppColors.greenBright
                                  : (finalBalance < 0
                                      ? AppColors.redBright
                                      : Colors.white),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfHeaderCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
            font: font, fontSize: 10, color: PdfColors.white),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  Future<void> _exportToPdf(List<Map<String, dynamic>> txs, double totalGive,
      double totalTake, double finalBal) async {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.gold),
                  SizedBox(height: 15),
                  Text('جاري إنتاج PDF...'),
                  SizedBox(height: 5),
                  Text('قد يستغرق 10-30 ثانية',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      );
    }

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

      final List<pw.TableRow> dataRows = [];

      for (var tx in txs) {
        final bool isGive = tx['type'] == 'give';
        final double amt = (tx['amount'] as num).toDouble();
        final double runBal = (tx['running_balance'] as num).toDouble();

        String formattedDate = tx['date'].toString();
        String formattedTime = '';
        try {
          final dt = DateTime.parse(tx['date'].toString());
          formattedDate = "${dt.year}-${dt.month}-${dt.day}";
          int hour = dt.hour;
          final period = hour >= 12 ? 'م' : 'ص';
          hour = hour % 12;
          if (hour == 0) hour = 12;
          formattedTime =
              "$hour:${dt.minute.toString().padLeft(2, '0')} $period";
        } catch (_) {}

        dataRows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  '${formatNumber(runBal.abs())} ${runBal >= 0 ? "له" : "عليه"}',
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 8,
                      color: runBal >= 0 ? greenText : redText),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  isGive ? formatNumber(amt) : '-',
                  style: pw.TextStyle(
                      font: isGive ? fontBold : font,
                      fontSize: 8,
                      color: isGive ? greenText : textDark),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  isGive ? '-' : formatNumber(amt),
                  style: pw.TextStyle(
                      font: isGive ? font : fontBold,
                      fontSize: 8,
                      color: isGive ? textDark : redText),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  tx['details'].toString(),
                  style: pw.TextStyle(
                      font: font, fontSize: 8, color: textDark),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(formattedDate,
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 7,
                            color: primaryColor)),
                    if (formattedTime.isNotEmpty)
                      pw.Text(formattedTime,
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 6,
                              color: PdfColors.grey700)),
                  ],
                ),
              ),
            ],
          ),
        );
      }

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
              pw.Table(
                border: pw.TableBorder.all(
                    width: 0.5, color: PdfColors.grey500),
                defaultVerticalAlignment:
                    pw.TableCellVerticalAlignment.middle,
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.5),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(3.5),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: primaryColor),
                    children: [
                      _pdfHeaderCell('الرصيد', fontBold),
                      _pdfHeaderCell('له', fontBold),
                      _pdfHeaderCell('عليه', fontBold),
                      _pdfHeaderCell('التفاصيل', fontBold),
                      _pdfHeaderCell('التاريخ', fontBold),
                    ],
                  ),
                  ...dataRows,
                ],
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
                    pw.Text('إجمالي له: ${formatNumber(totalGive)}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 11,
                            color: greenText)),
                    pw.Text('إجمالي عليه: ${formatNumber(totalTake)}',
                        style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 11,
                            color: redText)),
                    pw.Text(
                      'الرصيد: ${formatNumber(finalBal.abs())} (${finalBal >= 0 ? "له" : "عليه"})',
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

      final bytes = await pdf.save();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      final tempDir = await getTemporaryDirectory();
      final sanitizedName =
          widget.customer['name'].toString().replaceAll('/', '_');
      final fileName = 'كشف_${sanitizedName}_'
          '${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      final result = await OpenFile.open(file.path);

      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('لا يوجد تطبيق لعرض PDF: ${result.message}'),
              backgroundColor: AppColors.red,
            ),
          );
        }
      }

      Future.delayed(const Duration(minutes: 5), () {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      });
    } catch (e, st) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
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
        "المبلغ الحالي: ${formatNumber(balance.abs())} ${widget.customer['currency']} ($status)";

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
// 7. شاشة إدارة التصنيفات
// ----------------------------------------------------
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة التصنيفات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onLongPress: () =>
                        _showOptionsSheet(context, provider, cat),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
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

  void _showOptionsSheet(BuildContext context, AppAccountProvider provider,
      Map<String, dynamic> cat) {
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  cat['name'].toString(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const Divider(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: AppColors.primary),
                ),
                title: const Text('تعديل الاسم',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(context, provider, cat);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.swap_vert,
                      color: AppColors.goldDark),
                ),
                title: const Text('إعادة الترتيب',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReorderDialog(context, provider);
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
                title: const Text('حذف',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, provider, cat);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, AppAccountProvider provider,
      Map<String, dynamic> cat) {
    final controller = TextEditingController(text: cat['name'].toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: AppColors.primary),
            SizedBox(width: 8),
            Text('تعديل التصنيف'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم التصنيف',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.updateCategory(
                  int.parse(cat['id'].toString()),
                  controller.text.trim(),
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

  void _showReorderDialog(BuildContext context, AppAccountProvider provider) {
    List<Map<String, dynamic>> tempCats = List.from(provider.categories);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(
            children: [
              Icon(Icons.swap_vert, color: AppColors.goldDark),
              SizedBox(width: 8),
              Text('إعادة الترتيب'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'اسحب التصنيف من مكانه لتغيير ترتيبه',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: tempCats.length,
                    onReorder: (oldIndex, newIndex) {
                      setStateDialog(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = tempCats.removeAt(oldIndex);
                        tempCats.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final cat = tempCats[index];
                      return Card(
                        key: ValueKey(cat['id']),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.drag_handle,
                                color: AppColors.primary),
                          ),
                          title: Text(
                            cat['name'].toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.goldDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () {
                final orderedIds = tempCats
                    .map((c) => int.parse(c['id'].toString()))
                    .toList();
                provider.reorderCategories(orderedIds);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ تم حفظ الترتيب'),
                    backgroundColor: AppColors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('حفظ الترتيب'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> cat) async {
    final int catId = int.parse(cat['id'].toString());
    final int customersCount =
        await provider.countCustomersInCategory(catId);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سيتم حذف التصنيف: "${cat['name']}"',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (customersCount > 0) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.redLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning,
                        color: AppColors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ يوجد $customersCount حساب داخل هذا التصنيف\nسيتم حذفهم جميعًا مع كل عملياتهم!',
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              const Text(
                'لا توجد حسابات داخل هذا التصنيف.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              provider.deleteCategory(catId);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🗑️ تم الحذف'),
                  backgroundColor: AppColors.red,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
// 8. شاشة إدارة العملات
// ----------------------------------------------------
class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة العملات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
