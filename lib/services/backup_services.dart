part of '../main.dart';

@visibleForTesting
Future<void> runCleanupStagesInOrderForTesting(
    List<Future<void> Function()> stages) async {
  for (final stage in stages) {
    await stage();
  }
}


class ImageStorageService {
  static Future<Directory> get _root async {
    final dir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(dir.path, 'app_data'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static Future<Directory> get imagesDirectory async {
    final root = await _root;
    final dir = Directory(p.join(root.path, 'images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> saveBase64(String? base64Data, String prefix) async {
    if (base64Data == null || base64Data.trim().isEmpty) return null;
    try {
      final clean = base64Data.contains(',')
          ? base64Data.substring(base64Data.indexOf(',') + 1)
          : base64Data;
      final bytes = base64Decode(clean);
      if (bytes.isEmpty) return null;
      final dir = await imagesDirectory;
      final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${crypto.sha256.convert(bytes).toString().substring(0, 12)}.bin';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      return p.join('images', name);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> readRelative(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    try {
      final root = await _root;
      final normalized = p.normalize(relativePath);
      if (p.isAbsolute(normalized) || normalized.startsWith('..')) return null;
      final file = File(p.join(root.path, normalized));
      if (!await file.exists()) return null;
      return Uint8List.fromList(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteRelative(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    try {
      final root = await _root;
      final normalized = p.normalize(relativePath);
      if (p.isAbsolute(normalized) || normalized.startsWith('..')) return;
      final file = File(p.join(root.path, normalized));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> migrateLegacyTransactionImages(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final names = columns.map((e) => e['name'].toString()).toSet();
    if (!names.contains('image_path') || !names.contains('image_data')) return;
    final rows = await db.query('transactions', columns: ['id', 'image_data', 'image_path']);
    for (final row in rows) {
      final legacy = row['image_data']?.toString() ?? '';
      final pathValue = row['image_path']?.toString() ?? '';
      if (legacy.isEmpty || pathValue.isNotEmpty) continue;
      final saved = await saveBase64(legacy, 'tx_${row['id']}');
      if (saved != null) {
        await db.update('transactions', {'image_path': saved, 'image_data': null},
            where: 'id = ?', whereArgs: [row['id']]);
      }
    }
  }

  static Future<void> migrateLegacyLogo(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(personal_logo)');
    final names = columns.map((e) => e['name'].toString()).toSet();
    if (!names.contains('logo_path') || !names.contains('logo_data')) return;
    final rows = await db.query('personal_logo', orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return;
    final legacy = rows.first['logo_data']?.toString() ?? '';
    final pathValue = rows.first['logo_path']?.toString() ?? '';
    if (legacy.isEmpty || pathValue.isNotEmpty) return;
    final saved = await saveBase64(legacy, 'logo');
    if (saved != null) {
      await db.update('personal_logo', {'logo_path': saved, 'logo_data': null},
          where: 'id = ?', whereArgs: [rows.first['id']]);
    }
  }
}

// ====================================================
// ✅ حزمة النسخ الاحتياطي الموحدة: قاعدة البيانات + الصور + البيانات المساندة
// ====================================================
class BackupBundleService {
  static const int formatVersion = 1;

  static Future<Directory> _appDataRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, 'app_data'));
  }

  static Future<Directory> appDataRootForFingerprint() => _appDataRoot();

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await source.exists()) return;
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      }
    }
  }

  static Future<void> _addDirectoryToArchive(
      Archive archive, Directory dir, String prefix) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile('$prefix/$rel', bytes.length, bytes));
      }
    }
  }

  static Future<File> createBundle({
    Directory? outputDirectory,
    String namePrefix = 'al_muhasib_',
  }) async {
    await AppDBHelper.instance.syncPersonalDataToDatabase();
    try {
      await (await AppDBHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
    final dbPath = p.join(await getDatabasesPath(), 'al_muhasib_final_v6.db');
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) throw Exception('قاعدة البيانات غير موجودة');

    final archive = Archive();
    final dbBytes = await dbFile.readAsBytes();
    final dbHash = crypto.sha256.convert(dbBytes).toString();
    archive.addFile(ArchiveFile('database/al_muhasib_final_v6.db', dbBytes.length, dbBytes));

    final root = await _appDataRoot();
    await _addDirectoryToArchive(archive, root, 'app_data');

    final fileChecksums = <Map<String, dynamic>>[];
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final content = List<int>.from(entry.content as List<int>);
      fileChecksums.add({
        'path': entry.name,
        'size': content.length,
        'sha256': crypto.sha256.convert(content).toString(),
      });
    }
    final manifest = jsonEncode({
      'format': 'al_muhasib_backup',
      'formatVersion': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'databaseSha256': dbHash,
      'databaseSize': dbBytes.length,
      'schemaVersion': 10,
      'files': fileChecksums,
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null || encoded.isEmpty) throw Exception('تعذر إنشاء ملف النسخة الاحتياطية');
    final outDir = outputDirectory ?? await getTemporaryDirectory();
    return writeEncodedBundleForTesting(encoded, outDir, namePrefix: namePrefix);
  }

  @visibleForTesting
  static Future<File> writeEncodedBundleForTesting(
      List<int> encoded, Directory outDir,
      {String namePrefix = 'al_muhasib_'}) async {
    if (encoded.isEmpty) throw Exception('تعذر إنشاء ملف النسخة الاحتياطية');
    if (!await outDir.exists()) await outDir.create(recursive: true);
    var now = DateTime.now();
    final cleanPrefix = namePrefix.replaceFirst(RegExp(r'_+$'), '');
    String buildName(DateTime value) =>
        '$cleanPrefix(${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')})(${value.hour.toString().padLeft(2, '0')}-${value.minute.toString().padLeft(2, '0')}-${value.second.toString().padLeft(2, '0')}).alb';
    var name = buildName(now);
    var file = File(p.join(outDir.path, name));
    while (await file.exists()) {
      now = now.add(const Duration(seconds: 1));
      name = buildName(now);
      file = File(p.join(outDir.path, name));
    }
    try {
      await file.writeAsBytes(encoded, flush: true);
      final written = await file.length();
      if (written != encoded.length) {
        throw Exception('فشل حفظ النسخة كاملة: $written/${encoded.length} بايت');
      }
      if (!await verifyBundle(file)) {
        throw Exception('فشل فحص سلامة النسخة الاحتياطية بعد حفظها');
      }
      return file;
    } catch (_) {
      try { if (await file.exists()) await file.delete(); } catch (_) {}
      rethrow;
    }
  }

  static Future<File> _extractDatabase(File bundle) async {
    final bytes = await bundle.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? manifestFile;
    ArchiveFile? databaseFile;
    for (final entry in archive) {
      if (entry.name == 'manifest.json') manifestFile = entry;
      if (entry.name == 'database/al_muhasib_final_v6.db') databaseFile = entry;
    }
    if (manifestFile == null || databaseFile == null) {
      throw Exception('النسخة الاحتياطية غير مكتملة');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>));
    if (manifest is! Map || manifest['format'] != 'al_muhasib_backup') {
      throw Exception('صيغة النسخة الاحتياطية غير معروفة');
    }
    final dbBytes = List<int>.from(databaseFile.content as List<int>);
    final expected = manifest['databaseSha256']?.toString() ?? '';
    final actual = crypto.sha256.convert(dbBytes).toString();
    if (expected.isEmpty || expected != actual) throw Exception('فشل التحقق من سلامة قاعدة البيانات');

    final declaredFiles = manifest['files'];
    if (declaredFiles is List) {
      final archiveByName = <String, ArchiveFile>{};
      for (final entry in archive) {
        if (entry.isFile) archiveByName[entry.name] = entry;
      }
      for (final item in declaredFiles) {
        if (item is! Map) throw Exception('سجل ملفات النسخة الاحتياطية غير صالح');
        final name = item['path']?.toString() ?? '';
        if (name.isEmpty || p.isAbsolute(name) || p.normalize(name).startsWith('..')) {
          throw Exception('مسار ملف غير آمن داخل النسخة الاحتياطية');
        }
        final entry = archiveByName[name];
        if (entry == null) throw Exception('ملف مفقود من النسخة الاحتياطية: $name');
        final content = List<int>.from(entry.content as List<int>);
        final hash = crypto.sha256.convert(content).toString();
        if (hash != item['sha256']?.toString() || content.length.toString() != item['size']?.toString()) {
          throw Exception('فشل التحقق من سلامة الملف: $name');
        }
      }
    }

    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'al_muhasib_restore_${DateTime.now().microsecondsSinceEpoch}'));
    await dir.create(recursive: true);
    final dbOut = File(p.join(dir.path, 'al_muhasib_final_v6.db'));
    await dbOut.writeAsBytes(dbBytes, flush: true);

    final stagingRoot = Directory(p.join(dir.path, 'app_data'));
    for (final entry in archive) {
      if (!entry.isFile || !entry.name.startsWith('app_data/')) continue;
      final relative = entry.name.substring('app_data/'.length);
      final normalized = p.normalize(relative);
      if (p.isAbsolute(normalized) || normalized.startsWith('..')) {
        throw Exception('ملف داخل النسخة الاحتياطية غير آمن');
      }
      final out = File(p.join(stagingRoot.path, normalized));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(List<int>.from(entry.content as List<int>), flush: true);
    }
    // يتم وضع مسار app_data المستخرج مؤقتاً في ملف نصي خاص بالاستعادة.
    await File(p.join(dir.path, '.app_data_source')).writeAsString(stagingRoot.path);
    return dbOut;
  }

  static Future<void> restoreBundle(File bundle) async {
    if (!await verifyBundle(bundle)) {
      throw Exception('ملف النسخة الاحتياطية تالف أو غير مكتمل؛ أُلغيت الاستعادة دون تغيير البيانات.');
    }
    final dbFile = await _extractDatabase(bundle);
    final sourceMarker = File(p.join(p.dirname(dbFile.path), '.app_data_source'));
    Directory? source;
    if (await sourceMarker.exists()) {
      source = Directory((await sourceMarker.readAsString()).trim());
    }

    final target = await _appDataRoot();
    final parent = target.parent;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stagedTarget = Directory(p.join(parent.path, 'app_data_restore_$stamp'));
    final safetyTarget = Directory(p.join(parent.path, 'app_data_pre_restore_$stamp'));
    var newTargetInstalled = false;

    try {
      // Stage every auxiliary file before touching the live database or files.
      if (source != null && await source.exists()) {
        await _copyDirectory(source, stagedTarget);
      }

      if (await target.exists()) {
        await target.rename(safetyTarget.path);
      }
      if (await stagedTarget.exists()) {
        await stagedTarget.rename(target.path);
      } else {
        await Directory(target.path).create(recursive: true);
      }
      newTargetInstalled = true;

      // The database restore performs its own staged validation and rollback.
      // Install app_data first so any database failure can roll the whole restore back.
      await AppDBHelper.instance.restoreDatabase(dbFile);

      if (await safetyTarget.exists()) {
        try {
          await safetyTarget.delete(recursive: true);
        } catch (cleanupError) {
          // Cleanup must not turn a successful restore into a reported failure.
          debugPrint('تعذر حذف ملفات app_data القديمة بعد الاستعادة: $cleanupError');
        }
      }
    } catch (e) {
      if (await stagedTarget.exists()) {
        try { await stagedTarget.delete(recursive: true); } catch (_) {}
      }
      if (await safetyTarget.exists()) {
        try {
          if (await target.exists()) await target.delete(recursive: true);
          await safetyTarget.rename(target.path);
        } catch (rollbackError) {
          debugPrint('تعذر التراجع عن استعادة ملفات app_data: $rollbackError');
        }
      } else if (newTargetInstalled && await target.exists()) {
        // There was no previous app_data tree to restore.
        try { await target.delete(recursive: true); } catch (rollbackError) {
          debugPrint('تعذر إزالة ملفات app_data الجزئية: $rollbackError');
        }
      }
      rethrow;
    }
  }

  static Future<bool> verifyBundle(File file) async {
    try {
      if (!await file.exists() || await file.length() < 100) return false;
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final byName = <String, ArchiveFile>{};
      for (final entry in archive) {
        if (!entry.isFile) continue;
        // Duplicate ZIP paths make the effective payload ambiguous.
        if (byName.containsKey(entry.name)) return false;
        byName[entry.name] = entry;
      }
      final manifestEntry = byName['manifest.json'];
      final databaseEntry = byName['database/al_muhasib_final_v6.db'];
      if (manifestEntry == null || databaseEntry == null) return false;
      final manifest = jsonDecode(utf8.decode(List<int>.from(manifestEntry.content as List<int>)));
      if (manifest is! Map || manifest['format'] != 'al_muhasib_backup') return false;
      final dbBytes = List<int>.from(databaseEntry.content as List<int>);
      if (crypto.sha256.convert(dbBytes).toString() != manifest['databaseSha256']) return false;
      final declared = manifest['files'];
      if (declared is! List) return false;
      var declaresDatabase = false;
      final declaredPaths = <String>{};
      for (final item in declared) {
        if (item is! Map) return false;
        final name = item['path']?.toString() ?? '';
        final segments = name.split('/');
        if (name.isEmpty ||
            p.isAbsolute(name) ||
            name.contains('\\') ||
            segments.any((segment) => segment == '..' || segment.isEmpty) ||
            !declaredPaths.add(name)) {
          return false;
        }
        if (name == 'database/al_muhasib_final_v6.db') declaresDatabase = true;
        final entry = byName[name];
        if (entry == null) return false;
        final bytes = List<int>.from(entry.content as List<int>);
        if (bytes.length.toString() != item['size']?.toString() ||
            crypto.sha256.convert(bytes).toString() != item['sha256']?.toString()) {
          return false;
        }
      }
      // Every payload file must be covered by the manifest; otherwise restore
      // could import unverified app_data files that were never checksummed.
      if (!declaresDatabase ||
          declaredPaths.length != byName.keys.where((name) => name != 'manifest.json').length ||
          byName.keys.any((name) => name != 'manifest.json' && !declaredPaths.contains(name))) {
        return false;
      }
      if (manifest['databaseSize']?.toString() !=
          List<int>.from(databaseEntry.content as List<int>).length.toString()) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('فشل التحقق من النسخة الاحتياطية: $e');
      return false;
    }
  }

  static Future<bool> isBundle(File file) async {
    if (p.extension(file.path).toLowerCase() == '.alb') return verifyBundle(file);
    try {
      final bytes = await file.openRead(0, 4).fold<List<int>>([], (a, b) => a..addAll(b));
      return bytes.length == 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
    } catch (_) {
      return false;
    }
  }
}

// ====================================================
// ✅ خدمة البيانات الشخصية
// ====================================================
class PersonalDataService {
  static const String _prefNameAr = 'personal_name_ar';
  static const String _prefNameEn = 'personal_name_en';
  static const String _prefTitleAr = 'personal_title_ar';
  static const String _prefTitleEn = 'personal_title_en';
  static const String _prefPhone = 'personal_phone';
  static const String _prefEmail = 'personal_email';
  static const String _prefLogoShape = 'personal_logo_shape';

  static Future<Map<String, dynamic>> getData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'nameAr': prefs.getString(_prefNameAr) ?? '',
      'nameEn': prefs.getString(_prefNameEn) ?? '',
      'titleAr': prefs.getString(_prefTitleAr) ?? '',
      'titleEn': prefs.getString(_prefTitleEn) ?? '',
      'phone': prefs.getString(_prefPhone) ?? '',
      'email': prefs.getString(_prefEmail) ?? '',
      'logoShape': prefs.getString(_prefLogoShape) ?? 'circle',
    };
    for (final side in ['right', 'left']) {
      for (var i = 1; i <= 3; i++) {
        data['${side}Line$i'] = prefs.getString('personal_${side}Line$i') ?? '';
        data['${side}Color$i'] = prefs.getString('personal_${side}Color$i') ?? '#000000';
        data['${side}Size$i'] = prefs.getDouble('personal_${side}Size$i') ?? 10.0;
      }
    }
    return data;
  }

  static Future<void> saveData({
    String? nameAr,
    String? nameEn,
    String? titleAr,
    String? titleEn,
    String? phone,
    String? email,
    String? logoShape,
    Map<String, String>? lineTexts,
    Map<String, String>? lineColors,
    Map<String, double>? lineSizes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (nameAr != null) await prefs.setString(_prefNameAr, nameAr);
    if (nameEn != null) await prefs.setString(_prefNameEn, nameEn);
    if (titleAr != null) await prefs.setString(_prefTitleAr, titleAr);
    if (titleEn != null) await prefs.setString(_prefTitleEn, titleEn);
    if (phone != null) await prefs.setString(_prefPhone, phone);
    if (email != null) await prefs.setString(_prefEmail, email);
    if (logoShape != null) await prefs.setString(_prefLogoShape, logoShape);
    if (lineTexts != null) {
      for (final entry in lineTexts.entries) {
        await prefs.setString('personal_${entry.key}', entry.value);
      }
    }
    if (lineColors != null) {
      for (final entry in lineColors.entries) {
        await prefs.setString('personal_${entry.key}', entry.value);
      }
    }
    if (lineSizes != null) {
      for (final entry in lineSizes.entries) {
        await prefs.setDouble('personal_${entry.key}', entry.value);
      }
    }
  }

  static Future<String?> getLogoBase64() async {
    final db = await AppDBHelper.instance.database;
    final result = await db.query('personal_logo', orderBy: 'id DESC', limit: 1);
    if (result.isEmpty) return null;
    final pathValue = result.first['logo_path']?.toString();
    if (pathValue != null && pathValue.isNotEmpty) {
      final bytes = await ImageStorageService.readRelative(pathValue);
      if (bytes != null) return base64Encode(bytes);
    }
    return result.first['logo_data']?.toString();
  }

  static Future<void> saveLogoBase64(String? base64) async {
    final db = await AppDBHelper.instance.database;
    final old = await db.query('personal_logo', orderBy: 'id DESC', limit: 1);
    final oldPath = old.isNotEmpty ? old.first['logo_path']?.toString() : null;
    String? newPath;
    if (base64 != null && base64.trim().isNotEmpty) {
      newPath = await ImageStorageService.saveBase64(base64, 'logo');
      if (newPath == null) throw Exception('تعذر حفظ الشعار');
    }
    await db.transaction((txn) async {
      await txn.delete('personal_logo');
      if (newPath != null) {
        await txn.insert('personal_logo', {'logo_data': null, 'logo_path': newPath});
      }
    });
    if (oldPath != null && oldPath != newPath) {
      await ImageStorageService.deleteRelative(oldPath);
    }
  }
}

class DeleteAccountResult {
  final bool success;
  final List<String> errors;
  DeleteAccountResult({required this.success, required this.errors});
}

// ==================== Google Drive Service ====================
class GoogleDriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.appdata'],
  );
  static GoogleSignInAccount? _currentUser;
  static drive.DriveApi? _driveApi;
  static String? _lastListBackupsError;
  static String? get lastListBackupsError => _lastListBackupsError;
  static String? _lastDownloadError;
  static String? get lastDownloadError => _lastDownloadError;
  static bool get isSignedIn => _currentUser != null;
  static String? get userEmail => _currentUser?.email;

  static Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      _currentUser = account;
      final authHeaders = await account.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
  }

  static Future<bool> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) {
        // Never keep an API client backed by a stale/expired account.
        _currentUser = null;
        _driveApi = null;
        return false;
      }
      _currentUser = account;
      final authHeaders = await account.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      return true;
    } catch (e) {
      _currentUser = null;
      _driveApi = null;
      debugPrint('تعذر تجديد جلسة Google في الخلفية: $e');
      return false;
    }
  }

  static Future<String?> uploadBackup(File backupFile, {String namePrefix = 'al_muhasib_'}) async {
    if (_driveApi == null) {
      final signedIn = await trySilentSignIn();
      if (!signedIn || _driveApi == null) return 'الرجاء تسجيل الدخول إلى Google مجدداً';
    }
    if (!await backupFile.exists()) return 'ملف النسخة الاحتياطية غير موجود';
    final now = DateTime.now();
    final ext = p.extension(backupFile.path).toLowerCase();
    final safeExt = (ext == '.alb' || ext == '.db') ? ext : '.alb';
    final cleanPrefix = namePrefix.replaceFirst(RegExp(r'_+$'), '');
    final fileName =
        '$cleanPrefix(${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')})(${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')})$safeExt';
    if (safeExt == '.alb' && !await BackupBundleService.verifyBundle(backupFile)) {
      return 'رفض رفع النسخة إلى Google Drive لأن فحص سلامة ملف .alb فشل';
    }
    final fileContent = await backupFile.readAsBytes();
    final expectedMd5 = crypto.md5.convert(fileContent).toString();

    // Retry transient DNS/network/server failures. A new Drive file name is used
    // per operation, so retrying an interrupted upload may create a duplicate;
    // old-backup retention removes excess copies after a confirmed upload.
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (_driveApi == null) {
          final signedIn = await trySilentSignIn();
          if (!signedIn || _driveApi == null) {
            throw Exception('تعذر تجديد جلسة Google؛ افتح التطبيق وسجّل الدخول مجدداً');
          }
        }
        // Reconcile before every create attempt. If listing fails because
        // of a transient network issue, the create request is attempted and
        // the surrounding retry loop handles any resulting failure.
        try {
          final existing = await _driveApi!.files.list(
            spaces: 'appDataFolder',
            q: "name = '$fileName'",
            $fields: 'files(id,name,size,md5Checksum)',
          ).timeout(const Duration(seconds: 20));
          final confirmed = (existing.files ?? []).any((f) =>
              (f.id ?? '').isNotEmpty &&
              f.name == fileName &&
              f.size == fileContent.length.toString() &&
              f.md5Checksum == expectedMd5);
          if (confirmed) return null;
        } catch (reconcileError) {
          debugPrint('تعذر التحقق من نتيجة محاولة Drive السابقة: $reconcileError');
          rethrow;
        }
        final driveFile = drive.File()
          ..name = fileName
          ..parents = ['appDataFolder'];
        final media = drive.Media(Stream.value(fileContent), fileContent.length,
            contentType: 'application/octet-stream');
        final uploaded = await _driveApi!.files.create(driveFile,
            uploadMedia: media, $fields: 'id,name,size,createdTime,md5Checksum')
            .timeout(const Duration(seconds: 45));
        if (uploaded.id == null ||
            uploaded.id!.isEmpty ||
            uploaded.size == null ||
            uploaded.size != fileContent.length.toString() ||
            uploaded.md5Checksum == null ||
            uploaded.md5Checksum != expectedMd5) {
          throw Exception('لم يؤكد Google Drive اكتمال الرفع وسلامة الحجم وبصمة MD5');
        }
        return null;
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 2 << attempt));
          // Refresh authentication before retrying a failed request.
          await trySilentSignIn();
        }
      }
    }
    return 'فشل الرفع إلى Google Drive بعد 3 محاولات. تحقق من الإنترنت وDNS، ثم افتح التطبيق وأعد تسجيل الدخول. التفاصيل: $lastError';
  }

  static Future<String?> uploadBackupPair(File bundle, File dbFile) async {
    final albError = await uploadBackup(bundle);
    if (albError != null) return albError;
    return await uploadBackup(dbFile);
  }

  static Future<List<Map<String, dynamic>>> listBackups() async {
    _lastListBackupsError = null;
    if (_driveApi == null && !await trySilentSignIn()) {
      _lastListBackupsError = 'جلسة Google غير متاحة. سجّل الدخول مجدداً.';
      return [];
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (_driveApi == null) {
          _lastListBackupsError = 'جلسة Google غير متاحة. سجّل الدخول مجدداً.';
          return [];
        }
        final result = await _driveApi!.files.list(
          spaces: 'appDataFolder',
          q: "(name contains 'al_muhasib_' or name contains 'al_muhasib(' or name contains 'GO_al_muhasib' or name contains 'instant_al_muhasib_')",
          orderBy: 'createdTime desc',
          $fields: 'files(id,name,size,createdTime)',
        ).timeout(const Duration(seconds: 30));
        _lastListBackupsError = null;
        return (result.files ?? [])
            .map((f) => {
                  'id': f.id ?? '',
                  'name': f.name ?? '',
                  'size': f.size ?? '0',
                  'createdTime': f.createdTime?.toIso8601String() ?? '',
                })
            .toList();
      } catch (e) {
        final textError = e.toString();
        final looksLikeExpiredSession = textError.contains('401') ||
            textError.toLowerCase().contains('unauthorized') ||
            textError.toLowerCase().contains('invalid credentials');
        if (attempt == 0 && looksLikeExpiredSession &&
            await trySilentSignIn()) {
          continue;
        }
        _lastListBackupsError =
            'تعذر الاتصال بـ Google Drive. تحقق من الإنترنت ثم أعد المحاولة. التفاصيل: $e';
        debugPrint(_lastListBackupsError);
        return [];
      }
    }
    _lastListBackupsError = 'تعذر الاتصال بـ Google Drive.';
    return [];
  }

  static Future<File?> downloadBackup(String fileId, String fileName) async {
    _lastDownloadError = null;
    Object? lastError;
    final safeName = p.basename(fileName).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tempDir = await getTemporaryDirectory();

    for (var attempt = 0; attempt < 3; attempt++) {
      File? file;
      try {
        if (_driveApi == null) {
          final signedIn = await trySilentSignIn();
          if (!signedIn || _driveApi == null) {
            throw Exception('انتهت جلسة Google؛ افتح التطبيق وسجّل الدخول مجدداً.');
          }
        }
        final result = await _driveApi!.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ).timeout(const Duration(seconds: 45)) as drive.Media;
        final dataStore = <int>[];
        await for (final chunk in result.stream.timeout(const Duration(seconds: 45))) {
          dataStore.addAll(chunk);
        }
        if (dataStore.isEmpty) throw Exception('ملف النسخة الذي نُزّل فارغ');
        file = File(p.join(tempDir.path,
            'drive_restore_${DateTime.now().microsecondsSinceEpoch}_$safeName'));
        await file.writeAsBytes(dataStore, flush: true);
        if (p.extension(safeName).toLowerCase() == '.alb' &&
            !await BackupBundleService.verifyBundle(file)) {
          throw Exception('النسخة التي نُزّلت من Drive تالفة أو غير مكتملة');
        }
        return file;
      } catch (e) {
        lastError = e;
        if (file != null) {
          try { if (await file.exists()) await file.delete(); } catch (_) {}
        }
        if (attempt < 2) {
          final message = e.toString().toLowerCase();
          final authError = message.contains('401') ||
              message.contains('unauthorized') ||
              message.contains('invalid credentials');
          if (authError) {
            await trySilentSignIn();
          } else {
            await Future.delayed(Duration(seconds: 2 << attempt));
            // A connection may have dropped and invalidated the cached client.
            if (_driveApi == null) await trySilentSignIn();
          }
        }
      }
    }

    _lastDownloadError =
        'تعذر تنزيل النسخة من Google Drive بعد 3 محاولات: $lastError';
    debugPrint(_lastDownloadError);
    return null;
  }

  static Future<bool> deleteBackup(String fileId) async {
    if (_driveApi == null) return false;
    try {
      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<DeleteAccountResult> deleteAccountAndData({
    bool deleteLocalData = true,
  }) async {
    final errors = <String>[];
    if (_driveApi != null || await trySilentSignIn()) {
      try {
        final backups = await listBackups();
        for (final backup in backups) {
          final id = backup['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final ok = await deleteBackup(id);
          if (!ok) errors.add('تعذر حذف الملف: ${backup['name']}');
        }
      } catch (e) {
        errors.add('تعذر حذف النسخ من Drive: $e');
      }
    }
    if (deleteLocalData) {
      // Keep cleanup stages sequential: scheduled work is cancelled before
      // storage is removed, and preferences are cleared only after cleanup.
      await runCleanupStagesInOrderForTesting([
        () async {
          try {
            await AutoBackupService.cancelDailyBackup();
            await AutoBackupService.cancelDriveBackup();
          } catch (e) {
            errors.add('تعذر إلغاء الجدولة: $e');
          }
        },
        () async {
          try {
            await AppDBHelper.instance.deleteAllLocalData();
          } catch (e) {
            errors.add('تعذر حذف البيانات المحلية: $e');
          }
        },
        () async {
          try {
            final docs = await getApplicationDocumentsDirectory();
            for (final folder in ['app_data', 'AlMuhasib']) {
              final dir = Directory(p.join(docs.path, folder));
              if (await dir.exists()) await dir.delete(recursive: true);
            }
          } catch (e) {
            errors.add('تعذر حذف ملفات التطبيق: $e');
          }
        },
        () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
          } catch (e) {
            errors.add('تعذر حذف التفضيلات: $e');
          }
        },
      ]);
    }
    try {
      await signOut();
    } catch (e) {
      errors.add('تعذر تسجيل الخروج: $e');
    }
    return DeleteAccountResult(success: errors.isEmpty, errors: errors);
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

// ==================== AutoBackupService ====================
