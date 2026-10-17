part of '../main.dart';

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
    final db = await openDatabase(
      p.join(dbPath, filePath),
      version: 11,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    // نقل الصور القديمة إلى ملفات التطبيق بعد اكتمال ترقية SQLite.
    // هذا يمنع بقاء ملفات خارج المعاملة إذا فشلت ترقية قاعدة البيانات.
    try {
      await ImageStorageService.migrateLegacyTransactionImages(db);
      await ImageStorageService.migrateLegacyLogo(db);
    } catch (e) {
      debugPrint('⚠️ تعذر ترحيل بعض الصور القديمة، ستتم المحاولة لاحقاً: $e');
    }
    return db;
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
        date TEXT NOT NULL,
        image_data TEXT,
        image_path TEXT,
        currency TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE personal_logo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        logo_data TEXT,
        logo_path TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    // فهارس لتحسين سرعة الحسابات والبحث والنسخ.
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_category ON customers(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_last_activity ON customers(last_activity)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_currency ON transactions(currency)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions(customer_id, date, id)');

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
        final lastTx = await db.query('transactions',
            where: 'customer_id = ?',
            whereArgs: [cId],
            orderBy: 'id DESC',
            limit: 1);
        if (lastTx.isNotEmpty) {
          await db.update('customers', {'last_activity': lastTx.first['date']},
              where: 'id = ?', whereArgs: [cId]);
        }
      }
    }
    if (oldVersion < 3) {
      await db.execute(
          'ALTER TABLE categories ADD COLUMN sort_order INTEGER DEFAULT 0');
      final cats = await db.query('categories', orderBy: 'id ASC');
      for (int i = 0; i < cats.length; i++) {
        await db.update('categories', {'sort_order': i + 1},
            where: 'id = ?', whereArgs: [cats[i]['id']]);
      }
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE transactions ADD COLUMN image_data TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE personal_logo (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          logo_data TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_category ON customers(category_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_last_activity ON customers(last_activity)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions(customer_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date)');
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE app_metadata (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }
    if (oldVersion < 8) {
      final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
      final txNames = txColumns.map((e) => e['name'].toString()).toSet();
      if (!txNames.contains('image_path')) {
        await db.execute('ALTER TABLE transactions ADD COLUMN image_path TEXT');
      }

      final logoTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='personal_logo'");
      if (logoTables.isNotEmpty) {
        final logoColumns = await db.rawQuery('PRAGMA table_info(personal_logo)');
        final logoNames = logoColumns.map((e) => e['name'].toString()).toSet();
        if (!logoNames.contains('logo_path')) {
          await db.execute('ALTER TABLE personal_logo ADD COLUMN logo_path TEXT');
        }
      }
    }
    if (oldVersion < 9) {
      await db.execute("ALTER TABLE transactions ADD COLUMN currency TEXT NOT NULL DEFAULT ''");
      final rows = await db.rawQuery('''
        SELECT t.id, c.currency
        FROM transactions t
        INNER JOIN customers c ON c.id = t.customer_id
        WHERE t.currency = ''
      ''');
      for (final row in rows) {
        await db.update('transactions', {'currency': row['currency']?.toString() ?? ''},
            where: 'id = ?', whereArgs: [row['id']]);
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_currency ON transactions(currency)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions(customer_id, date, id)');
    }
    if (oldVersion < 10) {
      // توحيد جميع تواريخ العمليات القديمة إلى ISO محلي: YYYY-MM-DD HH:mm:ss
      final rows = await db.query('transactions', columns: ['id', 'date']);
      for (final row in rows) {
        final raw = row['date']?.toString().trim() ?? '';
        if (raw.isEmpty) continue;
        String? normalized;
        final direct = DateTime.tryParse(raw);
        if (direct != null) {
          normalized = direct.toString().split('.').first;
        } else {
          final match = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$').firstMatch(raw);
          if (match != null) {
            final y = int.parse(match.group(1)!);
            final m = int.parse(match.group(2)!);
            final d = int.parse(match.group(3)!);
            final h = int.tryParse(match.group(4) ?? '0') ?? 0;
            final min = int.tryParse(match.group(5) ?? '0') ?? 0;
            final sec = int.tryParse(match.group(6) ?? '0') ?? 0;
            final value = DateTime(y, m, d, h, min, sec);
            if (value.year == y && value.month == m && value.day == d) {
              normalized = value.toString().split('.').first;
            }
          }
        }
        if (normalized != null && normalized != raw) {
          await db.update('transactions', {'date': normalized},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      }

      // إعادة حساب آخر نشاط لكل حساب بعد توحيد التواريخ.
      final customers = await db.query('customers', columns: ['id']);
      for (final customer in customers) {
        final latest = await db.query(
          'transactions',
          columns: ['date'],
          where: 'customer_id = ?',
          whereArgs: [customer['id']],
          orderBy: 'datetime(date) DESC, id DESC',
          limit: 1,
        );
        await db.update(
          'customers',
          {'last_activity': latest.isNotEmpty ? latest.first['date'] : null},
          where: 'id = ?',
          whereArgs: [customer['id']],
        );
      }
    }
  }

  Future<String?> getLogoRelativePath() async {
    final db = await database;
    final rows = await db.query('personal_logo', columns: ['logo_path'], orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['logo_path']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> syncPersonalDataToDatabase() async {
    final db = await database;
    final prefs = await SharedPreferences.getInstance();
    final values = <String, String>{
      'nameAr': prefs.getString('personal_name_ar') ?? '',
      'nameEn': prefs.getString('personal_name_en') ?? '',
      'titleAr': prefs.getString('personal_title_ar') ?? '',
      'titleEn': prefs.getString('personal_title_en') ?? '',
      'phone': prefs.getString('personal_phone') ?? '',
      'email': prefs.getString('personal_email') ?? '',
      'logoShape': prefs.getString('personal_logo_shape') ?? 'circle',
      'logoPath': (await AppDBHelper.instance.getLogoRelativePath()) ?? '',
      'backupFormatVersion': '3',
    };
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        final existing = await txn.query('app_metadata',
            where: 'key = ?', whereArgs: [entry.key], limit: 1);
        final oldValue = existing.isNotEmpty ? existing.first['value']?.toString() : null;
        if (oldValue != entry.value) {
          await txn.insert('app_metadata',
              {'key': entry.key, 'value': entry.value},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> restorePersonalDataFromDatabase() async {
    final db = await database;
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='app_metadata'");
    if (tables.isEmpty) return;
    final rows = await db.query('app_metadata');
    if (rows.isEmpty) return;
    final values = <String, String>{};
    for (final row in rows) {
      final key = row['key'];
      final value = row['value'];
      if (key != null && value != null) values[key.toString()] = value.toString();
    }
    final prefs = await SharedPreferences.getInstance();
    final mapping = {
      'nameAr': 'personal_name_ar',
      'nameEn': 'personal_name_en',
      'titleAr': 'personal_title_ar',
      'titleEn': 'personal_title_en',
      'phone': 'personal_phone',
      'email': 'personal_email',
      'logoShape': 'personal_logo_shape',
    };
    if (values.containsKey('logoBase64') && values['logoBase64']!.isNotEmpty) {
      // توافق مع النسخ القديمة فقط؛ النسخ الجديدة تعتمد على app_data/logo file.
      await PersonalDataService.saveLogoBase64(values['logoBase64']);
    }
    for (final entry in mapping.entries) {
      if (values.containsKey(entry.key)) {
        await prefs.setString(entry.value, values[entry.key]!);
      }
    }
  }

  Future<void> deleteAllLocalData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('customers');
      await txn.delete('personal_logo');
      await txn.delete('app_metadata');
      await txn.delete('categories');
      await txn.delete('currencies');
      await txn.insert('categories', {'name': 'عام', 'sort_order': 1});
      await txn.insert('categories', {'name': 'عملاء', 'sort_order': 2});
      await txn.insert('categories', {'name': 'موردون', 'sort_order': 3});
      await txn.insert('currencies', {'name': 'ريال يمني', 'symbol': 'ر.ي'});
      await txn.insert('currencies', {'name': 'ريال سعودي', 'symbol': 'ر.س'});
      await txn.insert('currencies', {'name': 'دولار أمريكي', 'symbol': '\$'});
    });
    try {
      final root = await ImageStorageService._root;
      final images = Directory(p.join(root.path, 'images'));
      if (await images.exists()) await images.delete(recursive: true);
    } catch (e) {
      debugPrint('تعذر حذف بعض ملفات الصور المحلية: $e');
      rethrow;
    }
  }

  Future<void> restoreDatabase(File newDbFile) async {
    if (!await newDbFile.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }
    final bytes = await newDbFile.openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
    const sqliteHeader = 'SQLite format 3\u0000';
    if (String.fromCharCodes(bytes) != sqliteHeader) {
      throw Exception('الملف المحدد ليس قاعدة بيانات SQLite صالحة');
    }

    // تحقق كامل من النسخة قبل لمس قاعدة البيانات الحالية.
    final sourceDb = await openDatabase(newDbFile.path, readOnly: true);
    try {
      final integrity = await sourceDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first?.toString().toLowerCase() != 'ok') {
        throw Exception('ملف النسخة الاحتياطية تالف أو غير سليم');
      }
      final tables = await sourceDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((e) => e['name'].toString()).toSet();
      const required = {'categories', 'currencies', 'customers', 'transactions'};
      if (!required.every(names.contains)) {
        throw Exception('النسخة الاحتياطية لا تحتوي على جداول المحاسب المطلوبة');
      }
      final txColumns = await sourceDb.rawQuery('PRAGMA table_info(transactions)');
      final txColumnNames = txColumns.map((e) => e['name'].toString()).toSet();
      const requiredTxColumns = {'customer_id', 'amount', 'type', 'date'};
      if (!requiredTxColumns.every(txColumnNames.contains)) {
        throw Exception('بنية جدول العمليات في النسخة الاحتياطية غير صالحة');
      }
    } finally {
      await sourceDb.close();
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'al_muhasib_final_v6.db');
    final current = File(path);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final staged = File(p.join(dbPath, 'al_muhasib_restore_$stamp.db'));
    final safety = File(p.join(dbPath, 'al_muhasib_pre_restore_$stamp.db'));

    // جهّز النسخة في ملف منفصل أولاً؛ لا نستبدل الحالية مباشرة.
    await newDbFile.copy(staged.path);
    Database? stagedDb;
    try {
      stagedDb = await openDatabase(
        staged.path,
        version: 11,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      );
      final integrity = await stagedDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first?.toString().toLowerCase() != 'ok') {
        throw Exception('فشل التحقق من النسخة بعد تجهيزها للاستعادة');
      }
      await stagedDb.close();
      stagedDb = null;

      if (_db != null) {
        await _db!.close();
        _db = null;
      }
      if (await current.exists()) {
        await current.rename(safety.path);
      }
      try {
        await staged.rename(path);
      } catch (_) {
        if (await safety.exists()) await safety.rename(path);
        rethrow;
      }
      _db = await openDatabase(
        path,
        version: 11,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      );
      try {
        await ImageStorageService.migrateLegacyTransactionImages(_db!);
        await ImageStorageService.migrateLegacyLogo(_db!);
      } catch (e) {
        debugPrint('⚠️ تعذر ترحيل صور النسخة المستعادة: $e');
      }
      await restorePersonalDataFromDatabase();
      // تُحذف نسخة الأمان لاحقاً بعد نجاح فتح القاعدة فقط.
      if (await safety.exists()) await safety.delete();
    } catch (e) {
      try { await stagedDb?.close(); } catch (_) {}
      if (await safety.exists()) {
        // A failure can happen after the replacement DB was opened (for
        // example while restoring personal metadata). Close it before
        // rolling back; checking only _db == null can leave the new DB live.
        final activeDb = _db;
        _db = null;
        try { await activeDb?.close(); } catch (_) {}
        if (await current.exists()) await current.delete();
        await safety.rename(path);
        _db = await openDatabase(
          path,
          version: 11,
          onCreate: _createDB,
          onUpgrade: _upgradeDB,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        );
        try {
          await ImageStorageService.migrateLegacyTransactionImages(_db!);
          await ImageStorageService.migrateLegacyLogo(_db!);
          await restorePersonalDataFromDatabase();
        } catch (rollbackRefreshError) {
          debugPrint('تعذر تحديث بيانات النسخة بعد التراجع عن الاستعادة: $rollbackRefreshError');
        }
      }
      if (await staged.exists()) {
        try { await staged.delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}

// ==================== AppAccountProvider ====================
