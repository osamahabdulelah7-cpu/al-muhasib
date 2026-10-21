part of '../main.dart';

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
        CASE WHEN sort_order IS NULL OR sort_order = 0 THEN 1 ELSE 0 END,
        sort_order ASC, id ASC
    ''');
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final db = await AppDBHelper.instance.database;
    final maxResult =
        await db.rawQuery('SELECT MAX(sort_order) as max_order FROM categories');
    int maxOrder = 0;
    if (maxResult.isNotEmpty && maxResult.first['max_order'] != null) {
      maxOrder = int.parse(maxResult.first['max_order'].toString());
    }
    await db.insert('categories', {'name': name, 'sort_order': maxOrder + 1});
    InstantBackupService.markChanged();
    await loadCategories();
  }

  Future<void> updateCategory(int id, String newName) async {
    final db = await AppDBHelper.instance.database;
    await db.update('categories', {'name': newName},
        where: 'id = ?', whereArgs: [id]);
    InstantBackupService.markChanged();
    await loadCategories();
  }

  Future<void> reorderCategories(List<int> orderedIds) async {
    final db = await AppDBHelper.instance.database;
    for (int i = 0; i < orderedIds.length; i++) {
      await db.update('categories', {'sort_order': i + 1},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    InstantBackupService.markChanged();
    await loadCategories();
  }

  Future<int> countCustomersInCategory(int categoryId) async {
    final db = await AppDBHelper.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE category_id = ?',
        [categoryId]);
    if (result.isNotEmpty) return int.parse(result.first['count'].toString());
    return 0;
  }

  Future<bool> deleteCategory(int id) async {
    final db = await AppDBHelper.instance.database;
    final categoryCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM categories')) ?? 0;
    if (categoryCount <= 1) return false;
    final customerCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM customers WHERE category_id = ?', [id])) ?? 0;
    // الحذف الآمن: لا نحذف الحسابات والمعاملات تلقائياً مع التصنيف.
    if (customerCount > 0) return false;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    InstantBackupService.markChanged();
    await loadCategories();
    await loadCustomers();
    return true;
  }

  Future<void> loadCurrencies() async {
    final db = await AppDBHelper.instance.database;
    currencies = await db.query('currencies');
    notifyListeners();
  }

  Future<void> addCurrency(String name, String symbol) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('currencies', {'name': name, 'symbol': symbol});
    InstantBackupService.markChanged();
    await loadCurrencies();
  }

  Future<void> loadCustomers() async {
    final db = await AppDBHelper.instance.database;
    customers = await db.rawQuery('''
      SELECT * FROM customers
      ORDER BY 
        CASE WHEN last_activity IS NULL OR last_activity = '' THEN 1 ELSE 0 END,
        datetime(last_activity) DESC, id DESC
    ''');
    await calculateAllCustomerBalances();
    notifyListeners();
  }

  Future<void> calculateAllCustomerBalances() async {
    final db = await AppDBHelper.instance.database;
    customerBalances.clear();
    final rows = await db.rawQuery('''
      SELECT t.customer_id,
             COALESCE(SUM(CASE WHEN t.type = 'give' THEN t.amount ELSE -t.amount END), 0) AS balance
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      WHERE t.currency = c.currency
      GROUP BY t.customer_id, t.currency
    ''');
    for (final row in rows) {
      final id = int.tryParse(row['customer_id'].toString());
      if (id != null) {
        customerBalances[id] = (row['balance'] as num?)?.toDouble() ?? 0.0;
      }
    }
    for (final cust in customers) {
      final id = int.tryParse(cust['id'].toString());
      if (id != null) customerBalances.putIfAbsent(id, () => 0.0);
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
    InstantBackupService.markChanged();
    await loadCustomers();
  }

  Future<bool> updateCustomer(int id, String name, String phone,
      String currency, int categoryId) async {
    final db = await AppDBHelper.instance.database;
    final current = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (current.isEmpty) return false;
    final oldCurrency = current.first['currency']?.toString() ?? '';
    if (oldCurrency != currency) {
      final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM transactions WHERE customer_id = ?', [id])) ?? 0;
      if (count > 0) {
        throw StateError('لا يمكن تغيير عملة حساب يحتوي على عمليات سابقة. أنشئ حساباً جديداً للعملة الأخرى.');
      }
    }
    await db.update(
        'customers',
        {
          'name': name,
          'phone': phone,
          'currency': currency,
          'category_id': categoryId
        },
        where: 'id = ?',
        whereArgs: [id]);
    InstantBackupService.markChanged();
    await loadCustomers();
    return true;
  }

  Future<bool> deleteCustomer(int id) async {
    final db = await AppDBHelper.instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE customer_id = ?', [id])) ?? 0;
    if (count > 0) return false;
    final deleted = await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    if (deleted > 0) InstantBackupService.markChanged();
    await loadCustomers();
    return deleted > 0;
  }

  Future<void> loadTransactions(int customerId) async {
    final db = await AppDBHelper.instance.database;
    final rows = await db.query('transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'datetime(date) ASC, id ASC');
    // لا نحمل صور آلاف العمليات إلى الذاكرة عند فتح الحساب.
    // الصورة تُقرأ فقط عند الحاجة لعرض تفاصيل العملية.
    currentTransactions = rows;
    notifyListeners();
  }

  Future<void> addTransaction(int customerId, double amount, String type,
      String details, String date,
      {String? imageData}) async {
    if (amount <= 0 || !amount.isFinite) throw ArgumentError('المبلغ غير صالح');
    if (type != 'give' && type != 'take') throw ArgumentError('نوع العملية غير صالح');
    final db = await AppDBHelper.instance.database;

    // احفظ الصورة أولاً؛ وإذا فشلت المعاملة نحذف الملف الجديد حتى لا يصبح orphan.
    String? imagePath;
    if (imageData != null && imageData.trim().isNotEmpty) {
      imagePath = await ImageStorageService.saveBase64(imageData, 'tx_new');
      if (imagePath == null) throw Exception('تعذر حفظ صورة العملية');
    }

    try {
      await db.transaction((txn) async {
        final customer = await txn.query('customers', columns: ['currency'],
            where: 'id = ?', whereArgs: [customerId], limit: 1);
        if (customer.isEmpty) throw StateError('الحساب غير موجود');
        final currency = customer.first['currency']?.toString() ?? '';
        if (currency.trim().isEmpty) throw StateError('عملة الحساب غير محددة');
        final transactionId = await txn.insert('transactions', {
          'customer_id': customerId,
          'amount': amount,
          'type': type,
          'details': details,
          'date': _normalizeDate(date),
          'image_data': null,
          'image_path': imagePath,
          'currency': currency,
        });
        await SmartMerchantAuditService.record(
          db: txn,
          action: 'add',
          customerId: customerId,
          transactionId: transactionId,
          after: {
            'amount': amount, 'type': type, 'details': details,
            'date': _normalizeDate(date), 'currency': currency,
          },
        );
        final latest = await txn.query('transactions',
            columns: ['date'],
            where: 'customer_id = ?',
            whereArgs: [customerId],
            orderBy: 'datetime(date) DESC, id DESC',
            limit: 1);
        await txn.update('customers',
            {'last_activity': latest.isNotEmpty ? latest.first['date'] : null},
            where: 'id = ?', whereArgs: [customerId]);
      });
    } catch (_) {
      if (imagePath != null) await ImageStorageService.deleteRelative(imagePath);
      rethrow;
    }
    InstantBackupService.markChanged();
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> updateTransaction(
      int id,
      int customerId,
      double amount,
      String type,
      String details,
      String date,
      {String? imageData}) async {
    if (amount <= 0 || !amount.isFinite) throw ArgumentError('المبلغ غير صالح');
    if (type != 'give' && type != 'take') throw ArgumentError('نوع العملية غير صالح');
    final db = await AppDBHelper.instance.database;

    String? newImagePath;
    if (imageData != null && imageData.trim().isNotEmpty) {
      newImagePath = await ImageStorageService.saveBase64(imageData, 'tx_$id');
      if (newImagePath == null) throw Exception('تعذر حفظ صورة العملية');
    }
    String? oldImagePath;
    try {
      await db.transaction((txn) async {
        final existing = await txn.query('transactions',
            where: 'id = ? AND customer_id = ?', whereArgs: [id, customerId], limit: 1);
        if (existing.isEmpty) throw StateError('العملية غير موجودة');
        oldImagePath = existing.first['image_path']?.toString();
        final beforeAudit = <String, Object?>{
          'amount': existing.first['amount'],
          'type': existing.first['type'],
          'details': existing.first['details'],
          'date': existing.first['date'],
          'currency': existing.first['currency'],
        };
        await txn.update(
            'transactions',
            {
              'amount': amount,
              'type': type,
              'details': details,
              'date': _normalizeDate(date),
              if (imageData != null) 'image_data': null,
              if (imageData != null) 'image_path': newImagePath,
            },
            where: 'id = ? AND customer_id = ?',
            whereArgs: [id, customerId]);
        await SmartMerchantAuditService.record(
          db: txn,
          action: 'update',
          customerId: customerId,
          transactionId: id,
          before: beforeAudit,
          after: {
            'amount': amount, 'type': type, 'details': details,
            'date': _normalizeDate(date),
            'currency': existing.first['currency'],
          },
        );
        final latest = await txn.query(
          'transactions',
          columns: ['date'],
          where: 'customer_id = ?',
          whereArgs: [customerId],
          orderBy: 'datetime(date) DESC, id DESC',
          limit: 1,
        );
        await txn.update(
          'customers',
          {'last_activity': latest.isNotEmpty ? latest.first['date'] : null},
          where: 'id = ?',
          whereArgs: [customerId],
        );
      });
    } catch (_) {
      if (newImagePath != null) await ImageStorageService.deleteRelative(newImagePath);
      rethrow;
    }
    InstantBackupService.markChanged();
    if (imageData != null && oldImagePath != null && oldImagePath != newImagePath) {
      await ImageStorageService.deleteRelative(oldImagePath);
    }
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> deleteTransaction(int id, int customerId) async {
    final db = await AppDBHelper.instance.database;
    String? oldImagePath;
    await db.transaction((txn) async {
      final existing = await txn.query('transactions',
          where: 'id = ? AND customer_id = ?',
          whereArgs: [id, customerId],
          limit: 1);
      if (existing.isEmpty) throw StateError('العملية غير موجودة');
      oldImagePath = existing.first['image_path']?.toString();
      await SmartMerchantAuditService.record(
        db: txn,
        action: 'delete',
        customerId: customerId,
        transactionId: id,
        before: {
          'amount': existing.first['amount'],
          'type': existing.first['type'],
          'details': existing.first['details'],
          'date': existing.first['date'],
          'currency': existing.first['currency'],
        },
      );
      await txn.delete('transactions',
          where: 'id = ? AND customer_id = ?', whereArgs: [id, customerId]);
      final latest = await txn.query(
        'transactions',
        columns: ['date'],
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'datetime(date) DESC, id DESC',
        limit: 1,
      );
      await txn.update(
        'customers',
        {'last_activity': latest.isNotEmpty ? latest.first['date'] : null},
        where: 'id = ?',
        whereArgs: [customerId],
      );
    });
    InstantBackupService.markChanged();
    if (oldImagePath != null) await ImageStorageService.deleteRelative(oldImagePath);
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> exportBackup() async {
    File? bundle;
    try {
      bundle = await BackupBundleService.createBundle();
      await Share.shareXFiles([XFile(bundle.path)], text: 'نسخة احتياطية كاملة - تطبيق المحاسب (.alb)');
    } catch (e) {
      debugPrint('خطأ أثناء تصدير ALB: $e');
    } finally {
      if (bundle != null) {
        try { await bundle.delete(); } catch (_) {}
      }
    }
  }

  Future<void> exportDatabaseBackup() async {
    File? out;
    try {
      final db = await AppDBHelper.instance.database;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      final dbPath = p.join(await getDatabasesPath(), 'al_muhasib_final_v6.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('قاعدة البيانات غير موجودة');
      }
      final tempDir = await getTemporaryDirectory();
      final fileName = 'al_muhasib_${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}_${DateTime.now().hour.toString().padLeft(2, '0')}-${DateTime.now().minute.toString().padLeft(2, '0')}-${DateTime.now().second.toString().padLeft(2, '0')}.db';
      out = File(p.join(tempDir.path, fileName));
      await dbFile.copy(out.path);
      await Share.shareXFiles([XFile(out.path)], text: 'نسخة قاعدة البيانات - تطبيق المحاسب (.db)');
    } catch (e) {
      debugPrint('خطأ أثناء تصدير DB: $e');
    } finally {
      if (out != null) {
        try { await out.delete(); } catch (_) {}
      }
    }
  }

  Future<bool> importBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final selected = File(result.files.single.path!);
        if (p.extension(selected.path).toLowerCase() == '.alb') {
          if (!await BackupBundleService.verifyBundle(selected)) {
            throw Exception('ملف النسخة .alb تالف؛ لم يتم تغيير البيانات.');
          }
          await BackupBundleService.restoreBundle(selected);
        } else {
          await AppDBHelper.instance.restoreDatabase(selected);
        }
        await loadInitialData();
        return true;
      }
    } catch (e) {
      debugPrint('خطأ أثناء الاستعادة: $e');
    }
    return false;
  }

  Future<bool> importBackupFromFile(File selectedFile) async {
    try {
      final isBundle = p.extension(selectedFile.path).toLowerCase() == '.alb';
      if (isBundle && !await BackupBundleService.verifyBundle(selectedFile)) {
        // Reject damaged bundles before touching the current database.
        return false;
      }

      // Preserve a verified rollback snapshot before any restore path,
      // including Google Drive restores and legacy raw database imports.
      final safetyError = await AutoBackupService.runInternalBackupNow();
      if (safetyError != null) {
        debugPrint('تعذر إنشاء نسخة أمان قبل الاستعادة: $safetyError');
        return false;
      }

      if (isBundle) {
        await BackupBundleService.restoreBundle(selectedFile);
      } else {
        await AppDBHelper.instance.restoreDatabase(selectedFile);
      }
      await loadInitialData();
      return true;
    } catch (e, st) {
      debugPrint('فشل استيراد/استعادة النسخة: $e\n$st');
      return false;
    }
  }

  Future<List<String>> getDistinctDetails({String query = ''}) async {
    try {
      final db = await AppDBHelper.instance.database;
      List<Map<String, dynamic>> result;
      if (query.trim().isEmpty) {
        result = await db.rawQuery('''
          SELECT details, COUNT(*) as usage_count
          FROM transactions
          WHERE details IS NOT NULL AND TRIM(details) != ''
          GROUP BY details
          ORDER BY usage_count DESC, details ASC
          LIMIT 200
        ''');
      } else {
        result = await db.rawQuery('''
          SELECT details, COUNT(*) as usage_count
          FROM transactions
          WHERE details IS NOT NULL AND TRIM(details) != '' 
            AND details LIKE ?
          GROUP BY details
          ORDER BY usage_count DESC, details ASC
          LIMIT 200
        ''', ['%$query%']);
      }
      return result
          .map((row) => (row['details'] ?? '').toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (e) {
      return [];    }
  }

  Future<Map<String, dynamic>> importFromExcel(File excelFile,
      {int? categoryId}) async {
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
    final importResult = await db.transaction((txn) async {
    int finalCategoryId;
    if (categoryId != null) {
      final catCheck = await txn
          .query('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (catCheck.isEmpty) throw Exception('التصنيف المحدد غير موجود');
      finalCategoryId = categoryId;
    } else {
      final existingCat =
          await txn.query('categories', where: 'name = ?', whereArgs: ['عام']);
      finalCategoryId = existingCat.isEmpty
          ? await txn.insert('categories', {'name': 'عام'})
          : int.parse(existingCat.first['id'].toString());
    }
    Map<String, int> customerNameToId = {};
    for (var tableName in excel.tables.keys) {
      final sheet = excel.tables[tableName]!;
      String? headerAccountName;
      for (int i = 0; i < sheet.maxRows && i < 5; i++) {
        for (var cell in sheet.rows[i]) {
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
      int headerRowIndex = -1, colDate = -1, colDetails = -1;
      int colTake = -1, colGive = -1, colCustomerName = -1;
      for (int i = 0; i < sheet.maxRows && i < 15; i++) {
        final row = sheet.rows[i];
        int foundHeaders = 0;
        for (int j = 0; j < row.length; j++) {
          final cellText = row[j]?.value?.toString().trim() ?? '';
          // Normalize Arabic headings so decorative tatweel/kashida and
          // diacritics do not prevent matching Excel column names.
          final normalizedHeader = _normalizeExcelHeader(cellText);
          if (normalizedHeader == _normalizeExcelHeader('التاريخ')) {
            colDate = j;
            foundHeaders++;
          } else if (normalizedHeader == _normalizeExcelHeader('التفاصيل')) {
            colDetails = j;
            foundHeaders++;
          } else if (normalizedHeader == _normalizeExcelHeader('عليه')) {
            colTake = j;
            foundHeaders++;
          } else if (normalizedHeader == _normalizeExcelHeader('له')) {
            colGive = j;
            foundHeaders++;
          } else if (normalizedHeader == _normalizeExcelHeader('اسم الحساب')) {
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
            if (dateCell is excel_lib.DateCellValue) {
              dateStr =
                  DateTime(dateCell.year, dateCell.month, dateCell.day)
                      .toString()
                      .split('.')[0];
            } else if (dateCell is excel_lib.DateTimeCellValue) {
              dateStr = dateCell.asDateTimeLocal().toString().split('.')[0];
            } else if (dateCell is excel_lib.IntCellValue || dateCell is excel_lib.DoubleCellValue) {
              final serial = dateCell is excel_lib.IntCellValue
                  ? dateCell.value.toDouble()
                  : (dateCell as excel_lib.DoubleCellValue).value;
              if (serial > 0) {
                final wholeDays = serial.floor();
                final millis = ((serial - wholeDays) * Duration.millisecondsPerDay).round();
                final excelDate = DateTime(1899, 12, 30).add(
                    Duration(days: wholeDays, milliseconds: millis));
                dateStr = excelDate.toString().split('.').first;
              }
            } else if (dateCell != null) {
              dateStr = dateCell.toString().trim();
            }
          }
          double takeAmount = 0, giveAmount = 0;
          if (colTake != -1 && colTake < row.length) {
            final v = row[colTake]?.value;
            if (v is excel_lib.IntCellValue) {
              takeAmount = v.value.toDouble();
            } else if (v is excel_lib.DoubleCellValue) {
              takeAmount = v.value;
            } else if (v != null) {
              takeAmount =
                  double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
            }
          }
          if (colGive != -1 && colGive < row.length) {
            final v = row[colGive]?.value;
            if (v is excel_lib.IntCellValue) {
              giveAmount = v.value.toDouble();
            } else if (v is excel_lib.DoubleCellValue) {
              giveAmount = v.value;
            } else if (v != null) {
              giveAmount =
                  double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
            }
          }
          if (takeAmount < 0 || giveAmount < 0) {
            rowsSkipped++;
            continue;
          }
          if (takeAmount == 0 && giveAmount == 0) continue;
          // لا نقبل صفًا يحتوي مبلغًا في (له) و(عليه) معًا؛ فهذا غامض محاسبيًا.
          if (takeAmount > 0 && giveAmount > 0) {
            rowsSkipped++;
            continue;
          }
          final double amount;
          final String type;
          if (giveAmount > 0) {
            amount = giveAmount;
            type = 'give';
          } else {
            amount = takeAmount;
            type = 'take';
          }
          if (dateStr.isEmpty) {
            rowsSkipped++;
            continue;
          }
          try {
            dateStr = _normalizeDate(dateStr);
          } catch (_) {
            rowsSkipped++;
            continue;
          }
          int customerId;
          if (customerNameToId.containsKey(customerName)) {
            customerId = customerNameToId[customerName]!;
          } else {
            final existingCust = await txn.query('customers',
                where: 'name = ?', whereArgs: [customerName]);
            if (existingCust.isEmpty) {
              customerId = await txn.insert('customers', {
                'name': customerName,
                'phone': '',
                'currency': 'ريال يمني',
                'category_id': finalCategoryId,
                'last_activity': dateStr,
              });
              customersCreated++;
            } else {
              customerId = int.parse(existingCust.first['id'].toString());
              await txn.update('customers', {'category_id': finalCategoryId},
                  where: 'id = ?', whereArgs: [customerId]);
            }
            customerNameToId[customerName] = customerId;
          }
          await txn.insert('transactions', {
            'customer_id': customerId,
            'amount': amount,
            'type': type,
            'details': details,
            'date': dateStr,
            'currency': (await txn.query('customers', columns: ['currency'], where: 'id = ?', whereArgs: [customerId], limit: 1)).first['currency']?.toString() ?? 'ريال يمني',
          });
          transactionsCreated++;
          await txn.update('customers', {'last_activity': dateStr},
              where: 'id = ?', whereArgs: [customerId]);
      }
    }
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
    });
    InstantBackupService.markChanged();
    await loadInitialData();
    return importResult;
  }

  String _normalizeExcelHeader(String value) {
    return value
        .replaceAll(RegExp(r'[ـ\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  String _normalizeDate(String dateStr) {
  final raw = dateStr.trim();
  if (raw.isEmpty) throw FormatException('التاريخ فارغ');

  final direct = DateTime.tryParse(raw);
  if (direct != null) return direct.toString().split('.').first;

  final match = RegExp(
    r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(raw);
  if (match != null) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '0') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '0') ?? 0;
    final second = int.tryParse(match.group(6) ?? '0') ?? 0;
    if (year < 1000) throw FormatException('تاريخ غير صالح: $raw');
    final d = DateTime(year, month, day, hour, minute, second);
    if (d.year != year || d.month != month || d.day != day ||
        d.hour != hour || d.minute != minute || d.second != second) {
      throw FormatException('تاريخ غير صالح: $raw');
    }
    return d.toString().split('.').first;
  }
  throw FormatException('تنسيق تاريخ غير مدعوم: $raw');
}
}

// ==================== AlMuhasibApp ====================
