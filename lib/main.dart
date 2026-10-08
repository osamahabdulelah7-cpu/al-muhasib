import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:archive/archive.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:image_picker/image_picker.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
// ✅ دالة تنظيف ملفات PDF المؤقتة
// ====================================================
Future<void> cleanTemporaryArtifacts() async {
  try {
    final tempRoot = await getTemporaryDirectory();
    if (!await tempRoot.exists()) return;

    // احذف فقط الملفات التي ينشئها التطبيق في التخزين المؤقت.
    // لا نحذف ملفات plugins أو ملفات النظام الأخرى.
    await for (final entity in tempRoot.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final lower = name.toLowerCase();
      final isOurBackup = name.startsWith('al_muhasib_') &&
          (lower.endsWith('.alb') || lower.endsWith('.db'));
      final isOurPdf = lower.endsWith('.pdf') &&
          (name.startsWith('كشف_') || name.startsWith('statement_'));
      if (isOurBackup || isOurPdf) {
        try { await entity.delete(); } catch (_) {}
      }
    }

    // احذف مجلد PDF بعد تفريغه إن أصبح فارغاً.
    final pdfDir = Directory(p.join(tempRoot.path, 'pdf'));
    if (await pdfDir.exists()) {
      try { await pdfDir.delete(recursive: false); } catch (_) {}
    }
  } catch (_) {}
}

// توافق مع أي استدعاء قديم.
Future<void> cleanTempPdfFiles() => cleanTemporaryArtifacts();

// ====================================================
// ✅ الألوان
// ====================================================
class AppColors {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF3B7CB8);
  static const Color gold = Color(0xFFD4A017);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color green = Color(0xFF2E7D32);
  static const Color greenLight = Color(0xFFE8F5E9);
  static const Color greenDark = Color(0xFF1B5E20);
  static const Color red = Color(0xFFC62828);
  static const Color redLight = Color(0xFFFFEBEE);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color greyArrow = Color(0xFF9E9E9E);
  static const Color textDarkest = Color(0xFF0D1F3F);
  static const Color whatsapp = Color(0xFF25D366);
  static const Color drive = Color(0xFF4285F4);
  static const Color background = Color(0xFFE0E0E0);
  static const Color solidBlue = Color(0xFF7EB8E8);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF6B7280);
}

// ====================================================
// ✅ خدمة الإشعارات
// ====================================================
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'al_muhasib_backup_channel';
  static const String _channelName = 'النسخ الاحتياطي';
  static const String _channelDesc = 'إشعارات النسخ الاحتياطي التلقائي';
  static const int _localNotificationId = 1001;
  static const int _driveNotificationId = 1002;

  static Future<void> initialize({bool requestPermission = true}) async {
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(initSettings);

    if (Platform.isAndroid && requestPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> showPersistentLocalNotification(String timeText) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@drawable/ic_notification',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _localNotificationId,
      '📁 النسخ الاحتياطي المحلي',
      'الموعد المستهدف للنسخ يومياً: $timeText',
      details,
    );
  }

  static Future<void> showPersistentDriveNotification(String timeText) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@drawable/ic_notification',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _driveNotificationId,
      '☁️ النسخ الاحتياطي على Drive',
      'الموعد المستهدف للرفع يومياً: $timeText',
      details,
    );
  }

  static Future<void> cancelLocalNotification() async {
    await _plugin.cancel(_localNotificationId);
  }

  static Future<void> cancelDriveNotification() async {
    await _plugin.cancel(_driveNotificationId);
  }

  static Future<void> showTemporarySuccess(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}

// ====================================================
// ✅ دالة معالجة المهام في الخلفية (Workmanager)
// ====================================================
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    await NotificationService.initialize(requestPermission: false);
    try {
      await AppDBHelper.instance.database;
      bool shouldRetry = false;

      final localError = await AutoBackupService.checkAndRunBackup();
      if (localError != null) {
        shouldRetry = true;
        debugPrint('❌ فشل النسخ المحلي بالخلفية: $localError');
      } else {
        debugPrint('✅ فحص النسخ المحلي بالخلفية اكتمل');
      }

      final settings = await AutoBackupService.getSettings();
      if (settings['driveEnabled'] == true) {
        final signedIn = await GoogleDriveService.trySilentSignIn();
        if (signedIn) {
          final driveError = await AutoBackupService.checkAndRunDriveBackup();
          if (driveError != null) {
            shouldRetry = true;
            debugPrint('❌ فشل نسخ Drive بالخلفية: $driveError');
          } else {
            debugPrint('☁️ فحص نسخ Drive بالخلفية اكتمل');
          }
        } else {
          shouldRetry = true;
          debugPrint('⚠️ تعذر تسجيل الدخول إلى Google في المهمة الخلفية');
        }
      }

      // This worker is periodic and remains registered by Android.
      // Do not cancel/re-register it from inside its own execution.
      return !shouldRetry;
    } catch (e, st) {
      debugPrint('❌ خطأ في المهمة الخلفية: $e\n$st');
      return false;
    }
  });
}

// ====================================================
// ✅ تخزين الصور كملفات خاصة بالتطبيق (بدلاً من Base64 داخل SQLite)
// ====================================================
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

  static Future<File> createBundle({Directory? outputDirectory}) async {
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
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final now = DateTime.now();
    final name = 'al_muhasib_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.alb';
    final file = File(p.join(outDir.path, name));
    await file.writeAsBytes(encoded, flush: true);
    return file;
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

    final root = await _appDataRoot();
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

    // جهّز ملفات الصور/البيانات المساندة قبل استبدال القاعدة.
    if (source != null && await source.exists()) {
      await _copyDirectory(source, stagedTarget);
    }

    try {
      if (await target.exists()) await target.rename(safetyTarget.path);
      await AppDBHelper.instance.restoreDatabase(dbFile);
      if (await stagedTarget.exists()) {
        await stagedTarget.rename(target.path);
      } else {
        await Directory(target.path).create(recursive: true);
      }
      if (await safetyTarget.exists()) await safetyTarget.delete(recursive: true);
    } catch (e) {
      if (await stagedTarget.exists()) {
        try { await stagedTarget.delete(recursive: true); } catch (_) {}
      }
      if (!await target.exists() && await safetyTarget.exists()) {
        await safetyTarget.rename(target.path);
      }
      rethrow;
    }
  }

  static Future<bool> isBundle(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext == '.alb') return true;
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

// ==================== Google Drive Service ====================
class GoogleDriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.appdata'],
  );
  static GoogleSignInAccount? _currentUser;
  static drive.DriveApi? _driveApi;
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
      if (account == null) return false;
      _currentUser = account;
      final authHeaders = await account.authHeaders;
      _driveApi = drive.DriveApi(GoogleAuthClient(authHeaders));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> uploadBackup(File backupFile) async {
    if (_driveApi == null) return 'الرجاء تسجيل الدخول أولاً';
    try {
      final now = DateTime.now();
      final ext = p.extension(backupFile.path).toLowerCase();
      final safeExt = (ext == '.alb' || ext == '.db') ? ext : '.alb';
      final fileName =
          'al_muhasib_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}$safeExt';
      final fileContent = await backupFile.readAsBytes();
      final driveFile = drive.File()
        ..name = fileName
        ..parents = ['appDataFolder'];
      final media = drive.Media(Stream.value(fileContent), fileContent.length,
          contentType: 'application/octet-stream');
      await _driveApi!.files.create(driveFile,
          uploadMedia: media, $fields: 'id,name,size,createdTime');
      return null;
    } catch (e) {
      return 'فشل الرفع: $e';
    }
  }

  static Future<String?> uploadBackupPair(File bundle, File dbFile) async {
    final albError = await uploadBackup(bundle);
    if (albError != null) return albError;
    return await uploadBackup(dbFile);
  }

  static Future<List<Map<String, dynamic>>> listBackups() async {
    if (_driveApi == null) return [];
    try {
      final result = await _driveApi!.files.list(
        spaces: 'appDataFolder',
        q: "name contains 'al_muhasib_'",
        orderBy: 'createdTime desc',
        $fields: 'files(id,name,size,createdTime)',
      );
      return (result.files ?? [])
          .map((f) => {
                'id': f.id ?? '',
                'name': f.name ?? '',
                'size': f.size ?? '0',
                'createdTime': f.createdTime?.toIso8601String() ?? '',
              })
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<File?> downloadBackup(String fileId, String fileName) async {
    if (_driveApi == null) return null;
    try {
      final result = await _driveApi!.files.get(fileId,
          downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final dataStore = <int>[];
      await for (final chunk in result.stream) {
        dataStore.addAll(chunk);
      }
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(dataStore);
      return file;
    } catch (e) {
      return null;
    }
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
class AutoBackupService {
  static const String _prefEnabled = 'auto_backup_enabled';
  static const String _prefHour = 'auto_backup_hour';
  static const String _prefMinute = 'auto_backup_minute';
  static const String _prefFolderPath = 'auto_backup_folder_path';
  static const String _prefLastBackup = 'auto_backup_last_time';
  static const String _prefLastDbModified = 'auto_backup_last_db_modified';
  static const String _prefDbFingerprint = 'auto_backup_db_fingerprint';
  static const String _prefDriveEnabled = 'drive_backup_enabled';
  static const String _prefDriveHour = 'drive_backup_hour';
  static const String _prefDriveMinute = 'drive_backup_minute';
  static const String _prefDriveLastBackup = 'drive_backup_last_time';
  static const String _prefDriveLastDbModified = 'drive_backup_last_db_modified';
  static const String _prefDriveDbFingerprint = 'drive_backup_db_fingerprint';
  static const int _maxLocalBackups = 5;
  static const int _maxDriveBackups = 5;
  static const String _workManagerTaskName = 'al_muhasib_daily_backup';
  static const String _workManagerUniqueName = 'al_muhasib_backup_unique';

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_prefEnabled) ?? false,
      'hour': prefs.getInt(_prefHour) ?? 3,
      'minute': prefs.getInt(_prefMinute) ?? 0,
      'folderPath': prefs.getString(_prefFolderPath) ?? '',
      'lastBackup': prefs.getString(_prefLastBackup) ?? '',
      'lastDbModified': prefs.getString(_prefLastDbModified) ?? '',
      'dbFingerprint': prefs.getString(_prefDbFingerprint) ?? '',
      'driveEnabled': prefs.getBool(_prefDriveEnabled) ?? false,
      'driveHour': prefs.getInt(_prefDriveHour) ?? 4,
      'driveMinute': prefs.getInt(_prefDriveMinute) ?? 0,
      'driveLastBackup': prefs.getString(_prefDriveLastBackup) ?? '',
      'driveLastDbModified': prefs.getString(_prefDriveLastDbModified) ?? '',
      'driveDbFingerprint': prefs.getString(_prefDriveDbFingerprint) ?? '',
    };
  }

  static Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? folderPath,
    String? lastBackup,
    String? lastDbModified,
    String? dbFingerprint,
    bool? driveEnabled,
    int? driveHour,
    int? driveMinute,
    String? driveLastBackup,
    String? driveLastDbModified,
    String? driveDbFingerprint,
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
    if (dbFingerprint != null) {
      await prefs.setString(_prefDbFingerprint, dbFingerprint);
    }
    if (driveEnabled != null) {
      await prefs.setBool(_prefDriveEnabled, driveEnabled);
    }
    if (driveHour != null) await prefs.setInt(_prefDriveHour, driveHour);
    if (driveMinute != null) await prefs.setInt(_prefDriveMinute, driveMinute);
    if (driveLastBackup != null) {
      await prefs.setString(_prefDriveLastBackup, driveLastBackup);
    }
    if (driveLastDbModified != null) {
      await prefs.setString(_prefDriveLastDbModified, driveLastDbModified);
    }
    if (driveDbFingerprint != null) {
      await prefs.setString(_prefDriveDbFingerprint, driveDbFingerprint);
    }
  }

  // اختيار المجلد يتم عبر Storage Access Framework/FilePicker؛ لا نطلب MANAGE_EXTERNAL_STORAGE.
  static Future<bool> requestStoragePermission() async => true;

  static Future<bool> hasStoragePermission() async => true;

  static Future<File> _getDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    return File(p.join(dbPath, 'al_muhasib_final_v6.db'));
  }

  static Future<String?> _getDatabaseFingerprint() async {
    try {
      final entries = <String>[];
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) return null;
      final dbBytes = await dbFile.readAsBytes();
      entries.add('database/al_muhasib_final_v6.db:${dbBytes.length}:${crypto.sha256.convert(dbBytes)}');

      final root = await BackupBundleService.appDataRootForFingerprint();
      if (await root.exists()) {
        final files = <String>[];
        await for (final entity in root.list(recursive: true, followLinks: false)) {
          if (entity is File) files.add(entity.path);
        }
        files.sort();
        for (final filePath in files) {
          final bytes = await File(filePath).readAsBytes();
          final rel = p.relative(filePath, from: root.path).replaceAll('\\', '/');
          entries.add('app_data/$rel:${bytes.length}:${crypto.sha256.convert(bytes)}');
        }
      }
      final stable = entries.join('\n');
      return crypto.sha256.convert(utf8.encode(stable)).toString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _hasDataChanged() async {
    final fingerprint = await _getDatabaseFingerprint();
    if (fingerprint == null) return true;
    final settings = await getSettings();
    return fingerprint != (settings['dbFingerprint'] as String);
  }

  static Future<bool> _hasDataChangedForDrive() async {
    final fingerprint = await _getDatabaseFingerprint();
    if (fingerprint == null) return true;
    final settings = await getSettings();
    return fingerprint != (settings['driveDbFingerprint'] as String);
  }

  static String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // ============ جدولة المهام الخلفية ============
  static Future<void> _scheduleBackgroundBackup() async {
    final settings = await getSettings();
    final localEnabled = settings['enabled'] == true;
    final driveEnabled = settings['driveEnabled'] == true;

    if (!localEnabled && !driveEnabled) {
      await Workmanager().cancelByUniqueName(_workManagerUniqueName);
      debugPrint('النسخ المحلي وDrive متوقفان؛ ألغيت مهمة الخلفية');
      return;
    }

    // Periodic WorkManager survives normal app closure and device reboot.
    // Android's minimum periodic interval is 15 minutes, and execution time
    // is best-effort; the task checks the configured daily times each run.
    await Workmanager().registerPeriodicTask(
      _workManagerUniqueName,
      _workManagerTaskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
    debugPrint('تم تسجيل فحص النسخ الاحتياطي الدوري كل 15 دقيقة');
  }

  static Future<void> scheduleDailyBackup() async {
    await _scheduleBackgroundBackup();
  }

  static Future<void> cancelDailyBackup() async {
    await Workmanager().cancelByUniqueName(_workManagerUniqueName);
    await NotificationService.cancelLocalNotification();
    debugPrint('تم إلغاء المهام اليومية');
  }

  static Future<bool> _isWritableDirectory(String path) async {
    try {
      final dir = Directory(path);
      await dir.create(recursive: true);
      final probe = File(p.join(
          dir.path, '.al_muhasib_write_test_' + DateTime.now().microsecondsSinceEpoch.toString()));
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _defaultAutomaticBackupFolder() async {
    // مجلد خارجي خاص بالتطبيق: يعمل في الخلفية دون الاعتماد على مجلد
    // مشترك أو صلاحية MANAGE_EXTERNAL_STORAGE.
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final dir = Directory(p.join(external.path, 'AlMuhasib', 'Backups'));
        if (await _isWritableDirectory(dir.path)) return dir.path;
      }
    } catch (_) {}

    // احتياط أخير: تخزين داخلي دائم للتطبيق.
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'auto_backups'));
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> _resolveBackupFolder(String? selectedFolder) async {
    final selected = selectedFolder?.trim() ?? '';

    // المسار المحفوظ يجب أن يكون مساراً مطلقاً؛ المسارات النسبية القديمة
    // قد تتحول إلى مسارات خاطئة مثل /المحاسب/... داخل عملية الخلفية.
    if (selected.isNotEmpty &&
        p.isAbsolute(selected) &&
        await _isWritableDirectory(selected)) {
      return selected;
    }

    final fallback = await _defaultAutomaticBackupFolder();
    if (selected != fallback) {
      await saveSettings(folderPath: fallback);
    }
    return fallback;
  }

  static Future<String?> performScheduledBackup() async {
    final settings = await getSettings();
    if (settings['enabled'] != true) return null;
    final selectedFolder = (settings['folderPath'] as String? ?? '').trim();
    final folderPath = await _resolveBackupFolder(selectedFolder);
    if (!await _hasDataChanged()) return null;

    final result = await performBackup(folderPath);
    if (result == null) {
      await NotificationService.showTemporarySuccess(
          '✅ تم النسخ المحلي', 'تم إنشاء نسخة احتياطية بنجاح');
    }
    return result;
  }

  static Future<String?> performScheduledDriveBackup() async {
    final settings = await getSettings();
    if (settings['driveEnabled'] != true) return null;
    if (!GoogleDriveService.isSignedIn) return null;
    if (!await _hasDataChangedForDrive()) return null;

    try {
      final bundle = await BackupBundleService.createBundle();
      final error = await GoogleDriveService.uploadBackup(bundle);
      try { await bundle.delete(); } catch (_) {}
      if (error == null) {
        final now = DateTime.now();
        final dbFile = await _getDatabaseFile();
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified,
            driveDbFingerprint: await _getDatabaseFingerprint());
        await _cleanOldDriveBackups();
        await NotificationService.showTemporarySuccess(
            '☁️ تم الرفع على Drive', 'تم رفع النسخة الاحتياطية بنجاح');
        return null;
      } else {
        await NotificationService.showTemporarySuccess(
            '⚠️ فشل النسخ على Drive', error);
        return error;
      }
    } catch (e) {
      return '$e';
    }
  }

  static Future<String?> checkAndRunBackup() async {
    try {
      final settings = await getSettings();
      if (settings['enabled'] != true) return null;
      final selectedFolder = (settings['folderPath'] as String? ?? '').trim();
      final folderPath = await _resolveBackupFolder(selectedFolder);

      final now = DateTime.now();
      final todayTarget = DateTime(now.year, now.month, now.day,
          settings['hour'] as int, settings['minute'] as int);
      DateTime? lastBackup;
      final lastBackupStr = settings['lastBackup'] as String? ?? '';
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      if (now.isBefore(todayTarget)) return null;
      bool shouldBackup =
          lastBackup == null || lastBackup.isBefore(todayTarget);

      if (!shouldBackup) return null;
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      if (!await _hasDataChanged()) return null;

      final error = await performBackup(folderPath);
      if (error == null) {
        await NotificationService.showTemporarySuccess(
            '📁 تم النسخ الاحتياطي',
            'تم إنشاء النسخة الاحتياطية الكاملة بصيغة .alb بنجاح');
      }
      return error;
    } catch (e, st) {
      debugPrint('❌ فشل النسخ التلقائي المحلي: $e\\n$st');
      return 'فشل النسخ التلقائي المحلي: $e';
    }
  }
  static Future<String?> checkAndRunDriveBackup() async {
    try {
      final settings = await getSettings();
      if (settings['driveEnabled'] != true) return null;
      if (!GoogleDriveService.isSignedIn) {
        if (!await GoogleDriveService.trySilentSignIn()) {
          return 'تعذر تسجيل الدخول إلى Google في الخلفية. افتح التطبيق وسجّل الدخول مجدداً.';
        }
      }

      final now = DateTime.now();
      final todayTarget = DateTime(now.year, now.month, now.day,
          settings['driveHour'] as int, settings['driveMinute'] as int);
      DateTime? lastBackup;
      final lastBackupStr = settings['driveLastBackup'] as String? ?? '';
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      if (now.isBefore(todayTarget)) return null;
      bool shouldBackup =
          lastBackup == null || lastBackup.isBefore(todayTarget);

      if (!shouldBackup) return null;
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      if (!await _hasDataChangedForDrive()) return null;

      final bundle = await BackupBundleService.createBundle();
      final error = await GoogleDriveService.uploadBackup(bundle);
      try { await bundle.delete(); } catch (_) {}
      if (error == null) {
        final dbFile = await _getDatabaseFile();
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified,
            driveDbFingerprint: await _getDatabaseFingerprint());
        await _cleanOldDriveBackups();
        return null;
      } else {
        return error;
      }
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> _cleanOldDriveBackups() async {
    try {
      final backups = await GoogleDriveService.listBackups();
      final alb = backups
          .where((b) => p.extension((b['name'] as String?) ?? '').toLowerCase() == '.alb')
          .toList();
      final db = backups
          .where((b) => p.extension((b['name'] as String?) ?? '').toLowerCase() == '.db')
          .toList();

      for (final group in [alb, db]) {
        if (group.length <= _maxDriveBackups) continue;
        group.sort((a, b) =>
            (b['createdTime'] as String).compareTo(a['createdTime'] as String));
        for (int i = _maxDriveBackups; i < group.length; i++) {
          await GoogleDriveService.deleteBackup(group[i]['id'] as String);
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في حذف النسخ القديمة على Drive: $e');
    }
  }

  static Future<void> _cleanOldLocalBackups(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('al_muhasib_'))
          .toList();
      final albFiles = files
          .where((f) => p.extension(f.path).toLowerCase() == '.alb')
          .toList();
      final dbFiles = files
          .where((f) => p.extension(f.path).toLowerCase() == '.db')
          .toList();

      for (final group in [albFiles, dbFiles]) {
        if (group.length <= _maxLocalBackups) continue;
        group.sort((a, b) => a.path.compareTo(b.path));
        for (int i = 0; i < group.length - _maxLocalBackups; i++) {
          try {
            await group[i].delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في حذف النسخ المحلية القديمة: $e');
    }
  }

  static Future<String?> performBackup(String folderPath) async {
    try {
      final db = await AppDBHelper.instance.database;
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      try { await db.rawQuery('PRAGMA wal_checkpoint(FULL)'); } catch (_) {}
      final backupDir = Directory(folderPath);
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      await BackupBundleService.createBundle(outputDirectory: backupDir);
      // النسخ التلقائي يحفظ ملف ALB الكامل فقط؛ تصدير DB متاح يدوياً عند الحاجة.
      final now = DateTime.now();
      final lastModified = (await _getDatabaseFile()).statSync().modified.toIso8601String();
      await saveSettings(
          lastBackup: now.toIso8601String(),
          lastDbModified: lastModified,
          dbFingerprint: await _getDatabaseFingerprint());
      await _cleanOldLocalBackups(folderPath);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<String?> runBackupNow() async {
    final settings = await getSettings();
    final folderPath =
        await _resolveBackupFolder(settings['folderPath'] as String?);
    return await performBackup(folderPath);
  }

  static Future<String?> runDriveBackupNow() async {
    if (!GoogleDriveService.isSignedIn) {
      return 'الرجاء تسجيل الدخول إلى Google';
    }
    try {
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      try { await (await AppDBHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)'); } catch (_) {}
      final bundle = await BackupBundleService.createBundle();
      final error = await GoogleDriveService.uploadBackup(bundle);
      if (error == null) {
        final now = DateTime.now();
        final dbFile = await _getDatabaseFile();
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified,
            driveDbFingerprint: await _getDatabaseFingerprint());
        await _cleanOldDriveBackups();
        return null;
      } else {
        return error;
      }
    } catch (e) {
      return '$e';
    }
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
      .where((f) => p.extension(f.path).toLowerCase() == '.alb')
          .length;
    } catch (e) {
      return 0;
    }
  }

  static Future<int> countDriveBackups() async {
    if (!GoogleDriveService.isSignedIn) return 0;
    try {
      return (await GoogleDriveService.listBackups()).length;
    } catch (e) {
      return 0;
    }
  }

  // ✅ جدولة Drive مع مهمة خلفية فعلية
  static Future<void> scheduleDriveBackup() async {
    await _scheduleBackgroundBackup();
    debugPrint('تم جدولة نسخ Drive بالخلفية');
  }

  static Future<void> cancelDriveBackup() async {
    final settings = await getSettings();
    await NotificationService.cancelDriveNotification();
    if (settings['enabled'] != true) {
      await Workmanager().cancelByUniqueName(_workManagerUniqueName);
    }
    debugPrint('✅ تم إلغاء نسخ Drive');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // عرض الواجهة فوراً. لا نجعل تهيئة قاعدة البيانات أو الخدمات
  // والإشعارات سبباً في بقاء شاشة البداية بيضاء في Release.
  final provider = AppAccountProvider();
  runApp(
    ChangeNotifierProvider<AppAccountProvider>.value(
      value: provider,
      child: const AlMuhasibApp(),
    ),
  );

  runZonedGuarded(() async {
    try {
      await NotificationService.initialize();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تهيئة الإشعارات: $e\n$st');
    }

    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (e, st) {
      debugPrint('⚠️ تعذر تهيئة WorkManager: $e\n$st');
    }

    try {
      await cleanTemporaryArtifacts();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تنظيف الملفات المؤقتة: $e\n$st');
    }

    try {
      await provider.loadInitialData();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تحميل بيانات التطبيق: $e\n$st');
    }

    try {
      await Future.delayed(const Duration(seconds: 2));
      await AutoBackupService.checkAndRunBackup();
      await AutoBackupService.checkAndRunDriveBackup();
      final settings = await AutoBackupService.getSettings();
      if (settings['enabled'] == true) {
        await AutoBackupService.scheduleDailyBackup();
      }
      if (settings['driveEnabled'] == true) {
        await AutoBackupService.scheduleDriveBackup();
      }
    } catch (e, st) {
      debugPrint('⚠️ تعذر تشغيل مهام النسخ الاحتياطي عند بدء التطبيق: $e\n$st');
    }
  }, (error, stack) {
    debugPrint('ZoneError: $error\n$stack');
  });
}

// ==================== AppDBHelper ====================
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
      version: 10,
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_currency ON transactions(currency)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_customer_date ON transactions(customer_id, date, id)');
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
        version: 10,
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
        version: 10,
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
      if (_db == null && await safety.exists()) {
        if (await current.exists()) await current.delete();
        await safety.rename(path);
        _db = await openDatabase(
          path,
          version: 10,
          onCreate: _createDB,
          onUpgrade: _upgradeDB,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        );
        try {
          await ImageStorageService.migrateLegacyTransactionImages(_db!);
          await ImageStorageService.migrateLegacyLogo(_db!);
        } catch (_) {}
      }
      if (await staged.exists()) {
        try { await staged.delete(); } catch (_) {}
      }
      rethrow;
    }
  }
}

// ==================== AppAccountProvider ====================
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
    await loadCategories();
  }

  Future<void> updateCategory(int id, String newName) async {
    final db = await AppDBHelper.instance.database;
    await db.update('categories', {'name': newName},
        where: 'id = ?', whereArgs: [id]);
    await loadCategories();
  }

  Future<void> reorderCategories(List<int> orderedIds) async {
    final db = await AppDBHelper.instance.database;
    for (int i = 0; i < orderedIds.length; i++) {
      await db.update('categories', {'sort_order': i + 1},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
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
    await loadCustomers();
    return true;
  }

  Future<bool> deleteCustomer(int id) async {
    final db = await AppDBHelper.instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE customer_id = ?', [id])) ?? 0;
    if (count > 0) return false;
    final deleted = await db.delete('customers', where: 'id = ?', whereArgs: [id]);
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
        await txn.insert('transactions', {
          'customer_id': customerId,
          'amount': amount,
          'type': type,
          'details': details,
          'date': _normalizeDate(date),
          'image_data': null,
          'image_path': imagePath,
          'currency': currency,
        });
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
        if (await BackupBundleService.isBundle(selected)) {
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
      if (await BackupBundleService.isBundle(selectedFile)) {
        await BackupBundleService.restoreBundle(selectedFile);
      } else {
        await AppDBHelper.instance.restoreDatabase(selectedFile);
      }
      await loadInitialData();
      return true;
    } catch (e) {
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
    await loadInitialData();
    return importResult;
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
        fontFamily: 'Cairo',
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.gold,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.gold,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.gold, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.primary),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        useMaterial3: false,
      ),
      home: const HomeScreen(),
    );
  }
}

class GradientAppBar extends StatelessW
class LogoCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String shape;

  const LogoCropScreen({
    super.key,
    required this.imageBytes,
    required this.shape,
  });

  @override
  State<LogoCropScreen> createState() => _LogoCropScreenState();
}

class _LogoCropScreenState extends State<LogoCropScreen> {
  ui.Image? _image;
  double _zoom = 1.0;
  Offset _offset = Offset.zero;
  double _startZoom = 1.0;
  Offset _startOffset = Offset.zero;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double _baseScale(Size size) {
    final image = _image!;
    return (size.width / image.width > size.height / image.height)
        ? size.width / image.width
        : size.height / image.height;
  }

  Offset _clampOffset(Offset value, Size size, double zoom) {
    final image = _image!;
    final scale = _baseScale(size) * zoom;
    final width = image.width * scale;
    final height = image.height * scale;
    final maxX = (width - size.width) / 2;
    final maxY = (height - size.height) / 2;
    return Offset(
      maxX <= 0 ? 0 : value.dx.clamp(-maxX, maxX).toDouble(),
      maxY <= 0 ? 0 : value.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  Future<void> _confirmCrop() async {
    if (_image == null || _saving) return;
    setState(() => _saving = true);
    try {
      const outputSize = 1024;
      final renderSize = Size(outputSize.toDouble(), outputSize.toDouble());
      final scale = _baseScale(renderSize) * _zoom;
      final image = _image!;
      final drawnWidth = image.width * scale;
      final drawnHeight = image.height * scale;
      final left = (outputSize - drawnWidth) / 2 + _offset.dx * (outputSize / _viewportSize);
      final top = (outputSize - drawnHeight) / 2 + _offset.dy * (outputSize / _viewportSize);
      final sourceRect = Rect.fromLTWH(
        (0 - left) / scale,
        (0 - top) / scale,
        outputSize / scale,
        outputSize / scale,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        image,
        sourceRect,
        const Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(outputSize, outputSize);
      picture.dispose();
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      if (data == null) throw Exception('تعذر تجهيز الصورة');
      if (mounted) Navigator.of(context).pop(Uint8List.view(data.buffer));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قص الصورة: $e')),
      );
    }
  }

  double get _viewportSize => 320;

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحديد الشعار'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'حرّك الصورة بإصبعك، واستخدم إصبعين للتكبير والتصغير. ضع الجزء المطلوب داخل الإطار.',
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.maxWidth < constraints.maxHeight
                        ? constraints.maxWidth - 28
                        : constraints.maxHeight - 28;
                    final size = side.clamp(220.0, 360.0).toDouble();
                    if (image == null) {
                      return const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(),
                      );
                    }
                    return SizedBox(
                      width: size,
                      height: size,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) {
                          _startZoom = _zoom;
                          _startOffset = _offset;
                        },
                        onScaleUpdate: (details) {
                          final nextZoom = (_startZoom * details.scale).clamp(1.0, 8.0).toDouble();
                          setState(() {
                            _zoom = nextZoom;
                            _offset = _clampOffset(
                              _startOffset + details.focalPointDelta,
                              Size(size, size),
                              nextZoom,
                            );
                          });
                        },
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _LogoCropPainter(
                              image: image,
                              zoom: _zoom,
                              offset: _offset,
                              circular: widget.shape == 'circle',
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _saving ? null : _confirmCrop,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('تأكيد وحفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoCropPainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final Offset offset;
  final bool circular;

  _LogoCropPainter({
    required this.image,
    required this.zoom,
    required this.offset,
    required this.circular,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseScale = (size.width / image.width > size.height / image.height)
        ? size.width / image.width
        : size.height / image.height;
    final scale = baseScale * zoom;
    final width = image.width * scale;
    final height = image.height * scale;
    final imageRect = Rect.fromLTWH(
      (size.width - width) / 2 + offset.dx,
      (size.height - height) / 2 + offset.dy,
      width,
      height,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    final frame = circular
        ? Path()..addOval(Offset.zero & size)
        : Path()..addRect(Offset.zero & size);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(frame, Offset.zero);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.56));
    canvas.drawPath(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.zoom != zoom ||
      oldDelegate.offset != offset ||
      oldDelegate.circular != circular;
}

class PersonalDataScreen extends StatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  State<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends State<PersonalDataScreen> {
  final List<TextEditingController> _lineControllers =
      List.generate(6, (_) => TextEditingController());
  final List<String> _lineColors = List<String>.filled(6, '#000000');
  final List<double> _lineSizes = List<double>.filled(6, 10.0);

  static const Map<String, String> _colorNames = {
    '#000000': 'أسود',
    '#1E3A5F': 'أزرق داكن',
    '#1565C0': 'أزرق',
    '#008577': 'أخضر مزرق',
    '#008000': 'أخضر',
    '#E65100': 'برتقالي',
    '#C62828': 'أحمر',
    '#7B1FA2': 'بنفسجي',
    '#6D4C41': 'بني',
    '#757575': 'رمادي',
  };

  String? _logoBase64;
  String _logoShape = 'circle';
  bool _loading = true;

  String _sideKey(int index) => index < 3 ? 'right' : 'left';
  int _lineNumber(int index) => index < 3 ? index + 1 : index - 2;
  String _textKey(int index) => '${_sideKey(index)}Line${_lineNumber(index)}';
  String _colorKey(int index) => '${_sideKey(index)}Color${_lineNumber(index)}';
  String _sizeKey(int index) => '${_sideKey(index)}Size${_lineNumber(index)}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _lineControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await PersonalDataService.getData();
    final logo = await PersonalDataService.getLogoBase64();
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _lineControllers.length; i++) {
        _lineControllers[i].text = (data[_textKey(i)] ?? '').toString();
        _lineColors[i] = (data[_colorKey(i)] ?? '#000000').toString();
        _lineSizes[i] = (data[_sizeKey(i)] as num?)?.toDouble() ?? 10.0;
      }
      _logoShape = data['logoShape'] as String;
      _logoBase64 = logo;
      _loading = false;
    });
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (img == null || !mounted) return;

    final shape = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('شكل الشعار'),
        content: const Text('اختر شكل إطار القص الذي تريد استخدامه للشعار.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'circle'),
            child: const Text('دائري'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () => Navigator.pop(ctx, 'square'),
            child: const Text('مربع'),
          ),
        ],
      ),
    );
    if (shape == null || !mounted) return;

    final sourceBytes = await img.readAsBytes();
    if (!mounted) return;
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => LogoCropScreen(imageBytes: sourceBytes, shape: shape),
      ),
    );
    if (croppedBytes == null || !mounted) return;

    final base64Data = base64Encode(croppedBytes);
    try {
      await PersonalDataService.saveLogoBase64(base64Data);
      await PersonalDataService.saveData(logoShape: shape);
      if (!mounted) return;
      setState(() {
        _logoBase64 = base64Data;
        _logoShape = shape;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الشعار المحدد')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الشعار: $e')),
      );
    }
  }

  Future<void> _deleteLogo() async {
    await PersonalDataService.saveLogoBase64(null);
    if (!mounted) return;
    setState(() => _logoBase64 = null);
  }

  Future<void> _save() async {
    final lineTexts = <String, String>{};
    final lineColors = <String, String>{};
    final lineSizes = <String, double>{};
    for (var i = 0; i < _lineControllers.length; i++) {
      lineTexts[_textKey(i)] = _lineControllers[i].text.trim();
      lineColors[_colorKey(i)] = _lineColors[i];
      lineSizes[_sizeKey(i)] = _lineSizes[i];
    }
    await PersonalDataService.saveData(
      lineTexts: lineTexts,
      lineColors: lineColors,
      lineSizes: lineSizes,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ تم حفظ البيانات'),
        backgroundColor: AppColors.green,
      ));
      Navigator.pop(context);
    }
  }

  Widget _buildLineEditor(int index, String lineLabel) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _lineControllers[index],
              decoration: InputDecoration(
                labelText: lineLabel,
                hintText: lineLabel,
                prefixIcon: const Icon(Icons.edit),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: _lineColors[index],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'لون الخط',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _colorNames.entries.map((entry) {
                      final colorValue = int.parse(entry.key.substring(1), radix: 16);
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(0xFF000000 | colorValue),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(child: Text(entry.value, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _lineColors[index] = value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<double>(
                    value: _lineSizes[index],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'حجم الخط',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: const [8, 9, 10, 11, 12, 14, 16, 18, 20]
                        .map((size) => DropdownMenuItem<double>(
                              value: size.toDouble(),
                              child: Text('$size'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _lineSizes[index] = value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('البيانات الشخصية'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: _logoBase64 != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(
                        _logoShape == 'circle' ? 100 : 12),
                    child: Image.memory(
                      base64Decode(_logoBase64!),
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickLogo,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.image),
                label: const Text('تغيير الشعار'),
              ),
              const SizedBox(width: 10),
              if (_logoBase64 != null)
                ElevatedButton.icon(
                  onPressed: _deleteLogo,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  icon: const Icon(Icons.delete),
                  label: const Text('حذف الشعار'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'البيانات التي تظهر في ترويسة التقارير',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          const Text('يمين الصفحة', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 10),
          _buildLineEditor(0, 'السطر الأول'),
          _buildLineEditor(1, 'السطر الثاني'),
          _buildLineEditor(2, 'السطر الثالث'),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          const Text('يسار الصفحة', textAlign: TextAlign.right,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 10),
          _buildLineEditor(3, 'السطر الأول'),
          _buildLineEditor(4, 'السطر الثاني'),
          _buildLineEditor(5, 'السطر الثالث'),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.save),
            label: const Text('حفظ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              prefixIcon: Icon(Icons.email),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.save),
            label: const Text('حفظ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ==================== HomeScreen ====================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String searchQuery = '';
  bool isSearching = false;
  Timer? _autoBackupTimer;
  TextEditingController? searchController;
  TabController? _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _drawerLogoBase64;
  String _drawerLogoShape = 'circle';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoBackup();
      _loadDrawerLogo();
      _autoBackupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _checkAutoBackup();
      });
    });
  }

  @override
  void dispose() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    AutoBackupService.checkAndRunBackup();
    if (GoogleDriveService.isSignedIn) {
      AutoBackupService.checkAndRunDriveBackup();
    }
    _tabController?.dispose();
    searchController?.dispose();
    super.dispose();
  }

  Future<void> _loadDrawerLogo() async {
    final logo = await PersonalDataService.getLogoBase64();
    final data = await PersonalDataService.getData();
    if (!mounted) return;
    setState(() {
      _drawerLogoBase64 = logo;
      _drawerLogoShape = data['logoShape'] as String;
    });
  }

  void _startSearch() {
    setState(() {
      isSearching = true;
      searchController = TextEditingController();
      searchQuery = '';
    });
  }

  void _stopSearch() {
    setState(() {
      isSearching = false;
      searchController?.dispose();
      searchController = null;
      searchQuery = '';
    });
  }

  Future<void> _checkAutoBackup() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final wasEnabled = settings['enabled'] as bool;
      final lastBackupBefore = settings['lastBackup'] as String;
      final error = await AutoBackupService.checkAndRunBackup();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠️ فشل النسخ التلقائي: $error'),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 5),
        ));
      } else if (error == null && wasEnabled && mounted) {
        final newSettings = await AutoBackupService.getSettings();
        final newLastBackup = newSettings['lastBackup'] as String;
        if (newLastBackup.isNotEmpty && newLastBackup != lastBackupBefore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Row(children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ تم النسخ الاحتياطي بنجاح'),
              ]),
              backgroundColor: AppColors.green,
              duration: Duration(seconds: 4),
            ));
          }
        }
      }
      await _checkDriveBackup();
    } catch (e) {
      debugPrint('❌ خطأ في فحص النسخ: $e');
    }
  }

  Future<void> _checkDriveBackup() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final wasEnabled = settings['driveEnabled'] as bool;
      final lastBackupBefore = settings['driveLastBackup'] as String;
      final error = await AutoBackupService.checkAndRunDriveBackup();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('⚠️ فشل النسخ على Drive: $error'),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 5),
        ));
      } else if (error == null && wasEnabled && mounted) {
        final newSettings = await AutoBackupService.getSettings();
        final newLastBackup = newSettings['driveLastBackup'] as String;
        if (newLastBackup.isNotEmpty && newLastBackup != lastBackupBefore) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Row(children: [
                Icon(Icons.cloud_done, color: Colors.white),
                SizedBox(width: 8),
                Text('☁️ تم النسخ على Google Drive'),
              ]),
              backgroundColor: AppColors.drive,
              duration: Duration(seconds: 4),
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فحص Drive: $e');
    }
  }

  Future<void> _importFromExcel(BuildContext context) async {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    if (provider.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد تصنيفات. أضف تصنيفاً أولاً'),
          backgroundColor: AppColors.red));
      return;
    }
    int selectedCategoryId =
        int.parse(provider.categories.first['id'].toString());
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.folder_open, color: AppColors.primary),
            SizedBox(width: 8),
            Text('اختر التصنيف'),
          ]),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('في أي تصنيف تريد إضافة الحسابات المستوردة؟',
                    style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 15),
                DropdownButtonFormField<int>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                      labelText: 'التصنيف', prefixIcon: Icon(Icons.folder)),
                  items: provider.categories.map((c) {
                    final int cId = int.parse(c['id'].toString());
                    return DropdownMenuItem<int>(
                        value: cId, child: Text(c['name'].toString()));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCategoryId = val);
                    }
                  },
                ),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(color: Colors.grey))),
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
      FilePickerResult? result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: AppColors.gold),
                    SizedBox(height: 15),
                    Text('جاري الاستيراد...'),
                  ]),
                ),
              ),
            ),
          ),
        );
      }
      File excelFile = File(result.files.single.path!);
      final stats = await provider.importFromExcel(excelFile,
          categoryId: selectedCategoryId);
      if (context.mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Row(children: [
              Icon(Icons.check_circle, color: AppColors.green),
              SizedBox(width: 8),
              Text('تم الاستيراد بنجاح'),
            ]),
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
                ]),
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
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.settings.name != null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 8)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final categories = provider.categories;
    if (categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('دفتر المحاسب الشامل')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('لا توجد تصنيفات مضافة'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                icon: const Icon(Icons.category),
                label: const Text('إدارة التصنيفات'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tabController == null ||
        _tabController!.length != categories.length) {
      _tabController?.dispose();
      _tabController = TabController(length: categories.length, vsync: this);
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
              color: AppColors.solidBlue,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  height: 56,
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.menu,
                          color: Colors.black, size: 26),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const Spacer(),
                    if (!isSearching) ...[
                      Row(children: const [
                        Icon(Icons.menu_book, color: Colors.black, size: 24),
                        SizedBox(width: 8),
                        Text('المحاسب',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ] else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: Colors.black),
                            decoration: const InputDecoration(
                              hintText: 'ابحث في هذا التصنيف...',
                              hintStyle: TextStyle(color: Colors.black54),
                              border: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.black)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.black)),
                              isDense: true,
                            ),
                            onChanged: (val) =>
                                setState(() => searchQuery = val),
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (!isSearching)
                      IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.black, size: 26),
                        onPressed: _startSearch,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.black, size: 26),
                        onPressed: _stopSearch,
                      ),
                    const SizedBox(width: 4),
                  ]),
                ),
                SizedBox(
                  height: 48,
                  child: TabBar(                    controller: _tabController,
                    isScrollable: true,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.black54,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    tabs: categories
                        .map((cat) => Tab(text: cat['name'].toString()))
                        .toList(),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      drawerEnableOpenDragGesture: false,
      drawer: Drawer(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 25),
            color: AppColors.solidBlue,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 3),
                    ),
                    child: ClipOval(
                      child: _drawerLogoBase64 != null
                          ? Image.memory(
                              base64Decode(_drawerLogoBase64!),
                              fit: BoxFit.cover,
                              width: 90,
                              height: 90,
                            )
                          : Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.cover,
                              width: 90,
                              height: 90,
                            ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text('تطبيق المحاسب',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('المهندس : اسامه الاضرعي',
                      style: TextStyle(color: Colors.black54, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(children: const [
                    Icon(Icons.phone, color: AppColors.goldDark, size: 16),
                    SizedBox(width: 6),
                    Text('770638276',
                        style:
                            TextStyle(color: Colors.black54, fontSize: 14)),
                  ]),
                ]),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.category, color: AppColors.primary),
            ),
            title: const Text('إدارة التصنيفات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child:
                  const Icon(Icons.attach_money, color: AppColors.goldDark),
            ),
            title: const Text('إدارة العملات',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CurrenciesScreen())),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.person, color: Colors.purple),
            ),
            title: const Text('البيانات الشخصية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PersonalDataScreen())).then((_) {
                _loadDrawerLogo();
              });
            },
          ),
          const Divider(height: 20, indent: 20, endIndent: 20),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
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
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.cloud_sync, color: AppColors.green),
            ),
            title: const Text('النسخ الاحتياطي والاستعادة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BackupOptionsScreen()));
            },
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            child: const Text('دفتر المحاسب © 2026',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: categories.map((cat) {
              final int currentCatId = int.parse(cat['id'].toString());
              final categoryCustomers = provider.customers.where((c) {
                final int customerCatId =
                    int.parse(c['category_id'].toString());
                final name = (c['name'] ?? '').toString();
                final phone = (c['phone'] ?? '').toString();
                return customerCatId == currentCatId &&
                    (name.contains(searchQuery) || phone.contains(searchQuery));
              }).toList();

              // لا يجوز جمع أرصدة بعملات مختلفة في إجمالي واحد.
              // لذلك نحسب الإجماليات بشكل مستقل لكل عملة.
              final Map<String, Map<String, double>> currencyTotals = {};
              for (var cust in categoryCustomers) {
                final int cId = int.parse(cust['id'].toString());
                final String currency =
                    (cust['currency'] ?? 'غير محددة').toString();
                final double bal = provider.customerBalances[cId] ?? 0.0;
                final totals = currencyTotals.putIfAbsent(
                    currency, () => {'give': 0.0, 'take': 0.0});
                if (bal > 0) {
                  totals['give'] = (totals['give'] ?? 0) + bal;
                } else if (bal < 0) {
                  totals['take'] = (totals['take'] ?? 0) + bal.abs();
                }
              }

              return Column(children: [
                Expanded(
                  child: categoryCustomers.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Icon(Icons.inbox,
                                  size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 15),
                              Text('لا توجد حسابات مضافة',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 15)),
                            ]))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: categoryCustomers.length,
                          itemBuilder: (ctx, i) => _buildCustomerCard(
                              context, provider, categoryCustomers[i]),
                        ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: AppColors.background,
                  child: Row(children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        elevation: 3,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () {
                            final activeIndex = _tabController!.index;
                            final activeCategoryId = int.parse(
                                categories[activeIndex]['id'].toString());
                            _showAddCustomerDialog(context, activeCategoryId);
                          },
                          child: const Center(
                            child: Icon(Icons.add,
                                color: AppColors.gold, size: 30),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.solidBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: currencyTotals.entries.map((entry) {
                            final currency = entry.key;
                            final totalGive = entry.value['give'] ?? 0.0;
                            final totalTake = entry.value['take'] ?? 0.0;
                            final netBalance = totalGive - totalTake;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    currency,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'عليه: ${formatNumber(totalTake)}',
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                      Text(
                                        'له: ${formatNumber(totalGive)}',
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    height: 1,
                                    color: Colors.black.withOpacity(0.2),
                                  ),
                                  const SizedBox(height: 2),
                                  Center(
                                    child: Text(
                                      '${netBalance == 0 ? "الرصيد" : (netBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(netBalance.abs())}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]);
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildCustomerCard(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
    final int cId = int.parse(customer['id'].toString());
    final String custName = (customer['name'] ?? 'حساب').toString();
    final double bal = provider.customerBalances[cId] ?? 0.0;

    Color sideColor;
    Color circleColor;
    if (bal > 0) {
      sideColor = const Color(0xFF81C784);
      circleColor = AppColors.greenLight;
    } else if (bal < 0) {
      sideColor = AppColors.redDark;
      circleColor = AppColors.redLight;
    } else {
      sideColor = const Color(0xFF81C784);
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
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          CustomerDetailsScreen(customer: customer)))
              .then((_) => provider.loadCustomers()),
          onLongPress: () =>
              _showCustomerOptionsModal(context, provider, customer),
          child: Stack(children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                    color: sideColor,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8),
                        bottomRight: Radius.circular(8))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                SizedBox(
                  height: 70,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: circleColor, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(Icons.person, color: sideColor, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(custName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textDarkest),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                SizedBox(
                  height: 70,
                  child: Center(
                    child: Text(
                      formatNumber(bal.abs()),
                      style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ]),
            ),
          ]),
        ),
      ),
    );
  }



  void _showCustomerOptionsModal(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 15),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
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
                  borderRadius: BorderRadius.circular(8)),
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
        ]),
      ),
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.edit, color: AppColors.primary),
            SizedBox(width: 8),
            Text('تعديل الحساب'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الحساب/العميل')),
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
                items: provider.currencies
                    .map((c) => DropdownMenuItem<String>(
                        value: c['name'].toString(),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCurrency = val);
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
                items: provider.categories
                    .map((c) => DropdownMenuItem<int>(
                        value: int.parse(c['id'].toString()),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCat = val);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await provider.updateCustomer(
                    int.parse(customer['id'].toString()),
                    nameCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    selectedCurrency,
                    selectedCat,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(e.toString().replaceFirst('Bad state: ', '')),
                      backgroundColor: AppColors.red,
                    ));
                  }
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
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AppColors.red),
          SizedBox(width: 8),
          Text('تأكيد الحذف'),
        ]),
        content: const Text('هل أنت متأكد من عملية الحذف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () async {
              final ok = await provider.deleteCustomer(id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يمكن حذف حساب يحتوي على عمليات. احذف الحساب فقط بعد إزالة عملياته أو احتفظ به للأرشفة.'),
                  backgroundColor: AppColors.red,
                ));
              }
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
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Row(children: [
            Icon(Icons.person_add, color: AppColors.primary),
            SizedBox(width: 8),
            Text('إضافة حساب جديد'),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الحساب/العميل')),
              const SizedBox(height: 10),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedCurrency,
                decoration: const InputDecoration(labelText: 'العملة'),
                items: provider.currencies
                    .map((c) => DropdownMenuItem<String>(
                        value: c['name'].toString(),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCurrency = val);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: selectedCat,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: provider.categories
                    .map((c) => DropdownMenuItem<int>(
                        value: int.parse(c['id'].toString()),
                        child: Text(c['name'].toString())))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCat = val);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  provider.addCustomer(nameCtrl.text.trim(),
                      phoneCtrl.text.trim(), selectedCurrency, selectedCat);
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

// ==================== BackupOptionsScreen ====================
class BackupOptionsScreen extends StatelessWidget {
  const BackupOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(children: [
        const SizedBox(height: 10),
        ListTile(
          tileColor: Colors.white,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.schedule, color: AppColors.goldDark),
          ),
          title: const Text('خيارات حفظ البيانات',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('حفظ تلقائي يومي (محلي + Drive)',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AutoBackupScreen())),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.smartphone, color: AppColors.green),
          ),
          title: const Text('النسخ الاحتياطي من الهاتف',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('حفظ / استعادة من الجهاز',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          onTap: () => _showBackupDialog(context),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.white,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.drive.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.cloud, color: AppColors.drive),
          ),
          title: const Text('النسخ الاحتياطي من Drive',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('حفظ / استعادة من Google Drive',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          onTap: () => _showBackupDialog(context, fromDrive: true),
        ),
      ]),
    );
  }


  Future<void> _showDriveRestoreDialog(BuildContext context) async {
    if (!GoogleDriveService.isSignedIn) {
      final signedIn = await GoogleDriveService.trySilentSignIn();
      if (!signedIn) {
        final ok = await GoogleDriveService.signIn();
        if (!ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('❌ يجب تسجيل الدخول إلى Google أولاً'),
              backgroundColor: AppColors.red,
            ));
          }
          return;
        }
      }
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final backups = await GoogleDriveService.listBackups();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!context.mounted) return;
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا توجد نسخ احتياطية على Google Drive'),
        backgroundColor: AppColors.red,
      ));
      return;
    }

    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر نسخة للاستعادة'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backups.length,
            itemBuilder: (_, index) {
              final item = backups[index];
              final date = item['createdTime']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.cloud_download, color: AppColors.drive),
                title: Text(item['name']?.toString() ?? 'نسخة احتياطية'),
                subtitle: Text(date),
                onTap: () => Navigator.pop(ctx, item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (selected == null || !context.mounted) return;

    final fileId = selected['id']?.toString() ?? '';
    final fileName = selected['name']?.toString() ?? 'al_muhasib_backup.alb';
    if (fileId.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final file = await GoogleDriveService.downloadBackup(fileId, fileName);
    bool success = false;
    if (file != null) {
      try {
        success = await provider.importBackupFromFile(file);
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? 'تمت استعادة البيانات بنجاح'
            : 'تعذر استعادة النسخة الاحتياطية'),
        backgroundColor: success ? AppColors.green : AppColors.red,
      ));
    }
  }

  void _showBackupDialog(BuildContext context, {bool fromDrive = false}) {
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(children: [
          Icon(fromDrive ? Icons.cloud : Icons.backup,
              color: fromDrive ? AppColors.drive : AppColors.gold),
          const SizedBox(width: 8),
          Text(fromDrive ? 'النسخ الاحتياطي (Drive)' : 'النسخ الاحتياطي'),
        ]),
        content: Text(fromDrive
            ? 'اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من Google Drive.'
            : 'اختر حفظ نسخة احتياطية من بياناتك أو استعادة نسخة سابقة من الهاتف.'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, color: AppColors.green),
            label: const Text('استعادة نسخة',
                style: TextStyle(color: AppColors.green)),
            onPressed: () async {
              Navigator.pop(ctx);
              if (fromDrive) {
                await _showDriveRestoreDialog(context);
                return;
              }
              bool success = await provider.importBackup();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(success
                      ? 'تمت استعادة البيانات بنجاح'
                      : 'تعذر استعادة الملف'),
                  backgroundColor: success ? AppColors.green : AppColors.red,
                ));
              }
            },
          ),
          if (!fromDrive) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.storage),
              label: const Text('حفظ DB'),
              onPressed: () async {
                Navigator.pop(ctx);
                await provider.exportDatabaseBackup();
              },
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: fromDrive ? AppColors.drive : AppColors.gold),
            icon: const Icon(Icons.upload),
            label: Text(fromDrive ? 'حفظ نسخة' : 'حفظ ALB'),
            onPressed: () async {
              Navigator.pop(ctx);
              if (fromDrive) {
                if (!GoogleDriveService.isSignedIn) {
                  final signedIn = await GoogleDriveService.signIn();
                  if (!signedIn || !context.mounted) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('❌ يجب تسجيل الدخول إلى Google أولاً'),
                        backgroundColor: AppColors.red,
                      ));
                    }
                    return;
                  }
                }
                final error = await AutoBackupService.runDriveBackupNow();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error == null ? '☁️ تم الرفع على Drive بنجاح' : '❌ فشل الرفع: $error'),
                    backgroundColor: error == null ? AppColors.drive : AppColors.red,
                  ));
                }
              } else {
                await provider.exportBackup();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ==================== AutoBackupScreen ====================
class AutoBackupScreen extends StatefulWidget {
  const AutoBackupScreen({super.key});

  @override
  State<AutoBackupScreen> createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends State<AutoBackupScreen> {
  bool _enabled = false;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 3, minute: 0);
  String _folderPath = '', _lastBackup = '';
  int _backupCount = 0;
  bool _driveEnabled = false;
  TimeOfDay _driveTime = const TimeOfDay(hour: 4, minute: 0);
  String _driveLastBackup = '';
  int _driveBackupCount = 0;
  bool _signedIn = false;
  String? _userEmail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AutoBackupService.getSettings();
    final count = await AutoBackupService.countBackups();
    final driveCount = await AutoBackupService.countDriveBackups();
    final signedIn = GoogleDriveService.isSignedIn ||
        await GoogleDriveService.trySilentSignIn();
    if (!mounted) return;
    setState(() {
      _enabled = settings['enabled'] as bool;
      _selectedTime = TimeOfDay(
          hour: settings['hour'] as int, minute: settings['minute'] as int);
      _folderPath = settings['folderPath'] as String;
      _lastBackup = settings['lastBackup'] as String;
      _backupCount = count;
      _driveEnabled = settings['driveEnabled'] as bool;
      _driveTime = TimeOfDay(
          hour: settings['driveHour'] as int,
          minute: settings['driveMinute'] as int);
      _driveLastBackup = settings['driveLastBackup'] as String;
      _driveBackupCount = driveCount;
      _signedIn = signedIn;
      _userEmail = GoogleDriveService.userEmail;
      _loading = false;
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value && _folderPath.isEmpty) {
      if (!await _pickFolder()) return;
    }
    await AutoBackupService.saveSettings(enabled: value);
    if (!mounted) return;
    setState(() => _enabled = value);
    if (value) {
      await AutoBackupService.scheduleDailyBackup();
    } else {
      await AutoBackupService.cancelDailyBackup();
    }
  }

  Future<bool> _pickFolder() async {
    try {
      String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return false;
      await AutoBackupService.saveSettings(folderPath: dir);
      setState(() => _folderPath = dir);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ تم تحديد المجلد'),
            backgroundColor: AppColors.green));
      }
      return true;
    } catch (e) {
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
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!));
    if (picked != null) {
      await AutoBackupService.saveSettings(
          hour: picked.hour, minute: picked.minute);
      setState(() => _selectedTime = picked);
      if (_enabled) {
        await AutoBackupService.scheduleDailyBackup();
      }
    }
  }

  Future<void> _runBackupNow() async {
    if (_folderPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرجاء اختيار مجلد أولاً'),
          backgroundColor: AppColors.red));
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: AppColors.gold)));
    final error = await AutoBackupService.runBackupNow();
    if (!mounted) return;
    Navigator.pop(context);
    if (error == null) {
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('✅ تم الحفظ بنجاح'),
          ]),
          backgroundColor: AppColors.green,
        ));
      }
    } else {      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ فشل: $error'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _toggleDriveEnabled(bool value) async {
    if (value && !GoogleDriveService.isSignedIn) {
      if (!await GoogleDriveService.signIn()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('❌ لم يتم تسجيل الدخول'),
              backgroundColor: AppColors.red));
        }
        return;
      }
      setState(() {
        _signedIn = true;
        _userEmail = GoogleDriveService.userEmail;
      });
    }
    await AutoBackupService.saveSettings(driveEnabled: value);
    setState(() => _driveEnabled = value);

    if (value) {
      await AutoBackupService.scheduleDriveBackup();
    } else {
      await AutoBackupService.cancelDriveBackup();
    }
  }

  Future<void> _pickDriveTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _driveTime,
        helpText: 'اختر وقت النسخ على Drive',
        cancelText: 'إلغاء',
        confirmText: 'تأكيد',
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!));
    if (picked != null) {
      await AutoBackupService.saveSettings(
          driveHour: picked.hour, driveMinute: picked.minute);
      setState(() => _driveTime = picked);
      if (_driveEnabled) {
        await AutoBackupService.scheduleDriveBackup();
      }
    }
  }

  Future<void> _signInGoogle() async {
    if (await GoogleDriveService.signIn()) {
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _userEmail = GoogleDriveService.userEmail;
      });
      await _loadSettings();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ فشل تسجيل الدخول'),
          backgroundColor: AppColors.red));
    }
  }

  Future<void> _signOutGoogle() async {
    await GoogleDriveService.signOut();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _userEmail = null;
      _driveBackupCount = 0;
      _driveLastBackup = '';
    });
    await AutoBackupService.saveSettings(driveEnabled: false);
    setState(() => _driveEnabled = false);
    await AutoBackupService.cancelDriveBackup();
  }

  Future<void> _runDriveBackupNow() async {
    if (!GoogleDriveService.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرجاء تسجيل الدخول أولاً'),
          backgroundColor: AppColors.red));
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: AppColors.drive)));
    final error = await AutoBackupService.runDriveBackupNow();
    if (!mounted) return;
    Navigator.pop(context);
    if (error == null) {
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.cloud_done, color: Colors.white),
            SizedBox(width: 8),
            Text('☁️ تم الرفع على Drive بنجاح'),
          ]),
          backgroundColor: AppColors.drive,
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ فشل: $error'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _showDriveRestoreDialog() async {
    if (!GoogleDriveService.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرجاء تسجيل الدخول أولاً'),
          backgroundColor: AppColors.red));
      return;
    }
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: AppColors.drive)));
    final backups = await GoogleDriveService.listBackups();
    if (!mounted) return;
    Navigator.pop(context);
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا توجد نسخ على Drive'),
          backgroundColor: AppColors.red));
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.cloud_download, color: AppColors.drive),
          SizedBox(width: 8),
          Text('اختر نسخة للاستعادة'),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.separated(
            itemCount: backups.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final b = backups[i];
              final name = b['name'] as String;
              final size = b['size'] as String;
              final created = b['createdTime'] as String;
              String formattedDate = '';
              try {
                final dt = DateTime.parse(created);
                formattedDate =
                    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } catch (_) {
                formattedDate = created;
              }
              final sizeKB = (int.tryParse(size) ?? 0) / 1024;
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.drive.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child:
                      const Icon(Icons.description, color: AppColors.drive),
                ),
                title: Text(formattedDate,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${sizeKB.toStringAsFixed(1)} KB • $name',
                    style: const TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _restoreFromDrive(b);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Future<void> _restoreFromDrive(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AppColors.red),
          SizedBox(width: 8),
          Text('تحذير'),
        ]),
        content: const Text(
            'سيتم استبدال البيانات الحالية بالنسخة المحددة.\n\nهل أنت متأكد؟',
            style: TextStyle(height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('إلغاء', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: AppColors.drive)));
    final file = await GoogleDriveService.downloadBackup(
        backup['id'] as String, backup['name'] as String);
    if (!mounted) return;
    if (file == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ فشل التنزيل'), backgroundColor: AppColors.red));
      return;
    }
    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    final success = await provider.importBackupFromFile(file);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(success ? '✅ تمت الاستعادة من Drive' : '❌ فشل الاستعادة'),
      backgroundColor: success ? AppColors.green : AppColors.red,
    ));
    if (success) await _loadSettings();
  }

  String _formatDate(String s) {
    if (s.isEmpty) return 'لا يوجد';
    try {
      final dt = DateTime.parse(s);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('خيارات حفظ البيانات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(children: [
        Container(
          color: AppColors.primary.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(children: [
            Icon(Icons.smartphone, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('النسخ الاحتياطي المحلي',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
          ]),
        ),
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
                  color: Color(0xFFFFEBEE), shape: BoxShape.circle),
              child: const Icon(Icons.alarm, color: Colors.red, size: 26),
            ),
            title: const Text('حفظ البيانات يومياً',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: const Text(
                'حفظ البيانات تلقائياً مرة واحدة باليوم (بشرط تغيرت البيانات)',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E1), shape: BoxShape.circle),
              child:
                  const Icon(Icons.folder, color: Color(0xFFFFA000), size: 26),
            ),
            title: const Text('مجلد حفظ البيانات',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(
              _folderPath.isEmpty ? 'لم يتم تحديد مجلد' : '$_folderPath/',
              style: TextStyle(
                  fontSize: 13,
                  color: _folderPath.isEmpty
                      ? AppColors.red
                      : AppColors.textMuted),
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
                    content: SelectableText(_folderPath,
                        style: const TextStyle(fontSize: 13)),
                    actions: [
                      TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickFolder();
                          },
                          child: const Text('تغيير المجلد')),
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
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), shape: BoxShape.circle),
              child: const Icon(Icons.access_time,
                  color: Color(0xFF1976D2), size: 26),
            ),
            title: const Text('وقت حفظ البيانات',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(
              '${_selectedTime.hour.toString().padLeft(2, '0')}:'
              '${_selectedTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            onTap: _pickTime,
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFF3E5F5), shape: BoxShape.circle),
              child: const Icon(Icons.history,
                  color: Color(0xFF7B1FA2), size: 26),
            ),
            title: const Text('آخر نسخة محلية',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(_formatDate(_lastBackup),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted)),
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.folder_copy,
                  color: Color(0xFF2E7D32), size: 26),
            ),
            title: const Text('عدد النسخ المحلية',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text('$_backupCount / 5 ملف',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted)),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          color: AppColors.drive.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(children: [
            Icon(Icons.cloud, color: AppColors.drive, size: 20),
            SizedBox(width: 8),
            Text('النسخ الاحتياطي على Google Drive',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.drive)),
          ]),
        ),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: _signedIn
                    ? AppColors.green.withOpacity(0.15)
                    : AppColors.drive.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _signedIn ? Icons.check_circle : Icons.login,
                color: _signedIn ? AppColors.green : AppColors.drive,
                size: 26,
              ),
            ),
            title: Text(_signedIn ? 'الحساب المتصل' : 'تسجيل الدخول إلى Google',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(
              _signedIn ? (_userEmail ?? '') : 'اضغط لتسجيل الدخول',
              style: TextStyle(
                  fontSize: 13,
                  color:
                      _signedIn ? AppColors.green : AppColors.textMuted),
            ),
            trailing: _signedIn
                ? IconButton(
                    icon: const Icon(Icons.logout, color: AppColors.red),
                    onPressed: _signOutGoogle,
                  )
                : null,
            onTap: _signedIn ? null : _signInGoogle,
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: SwitchListTile(
            value: _driveEnabled,
            onChanged: _signedIn ? _toggleDriveEnabled : null,
            activeColor: AppColors.drive,
            secondary: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), shape: BoxShape.circle),
              child: const Icon(Icons.cloud_upload,
                  color: AppColors.drive, size: 26),
            ),
            title: const Text('النسخ التلقائي على Drive',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(
              _signedIn
                  ? 'رفع نسخة يومياً (بشرط تغير البيانات)'
                  : 'سجّل الدخول أولاً',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            enabled: _signedIn,
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), shape: BoxShape.circle),
              child: const Icon(Icons.schedule,
                  color: AppColors.drive, size: 26),
            ),
            title: const Text('وقت النسخ على Drive',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(
              '${_driveTime.hour.toString().padLeft(2, '0')}:'
              '${_driveTime.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            onTap: _signedIn ? _pickDriveTime : null,
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFF3E5F5), shape: BoxShape.circle),
              child: const Icon(Icons.history,
                  color: Color(0xFF7B1FA2), size: 26),
            ),
            title: const Text('آخر نسخة على Drive',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text(_formatDate(_driveLastBackup),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted)),
          ),
        ),
        const Divider(height: 1),
        Container(
          color: Colors.white,
          child: ListTile(
            leading: Container(
              width: 45,
              height: 45,
              decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.cloud_done,
                  color: Color(0xFF2E7D32), size: 26),
            ),
            title: const Text('عدد النسخ على Drive',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: Text('$_driveBackupCount / 5 ملف',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted)),
          ),
        ),
        const SizedBox(height: 20),
        if (_enabled && _folderPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: _runBackupNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.backup),
              label: const Text('نسخ محلي الآن',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        if (_signedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(children: [
              ElevatedButton.icon(
                onPressed: _runDriveBackupNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.drive,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(double.infinity, 50),
                ),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('رفع نسخة على Drive الآن',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _showDriveRestoreDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  minimumSize: const Size(double.infinity, 50),
                ),
                icon: const Icon(Icons.cloud_download),
                label: const Text('استعادة من Drive',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ==================== CustomerDetailsScreen ====================
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 15),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
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
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete, color: AppColors.red),
            ),
            title: const Text('حذف العملية',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              await provider.deleteTransaction(
                int.parse(tx['id'].toString()),
                int.parse(widget.customer['id'].toString()),
              );
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  void _showSuggestionsDialog({
    required BuildContext parentContext,
    required List<String> suggestions,
    required TextEditingController controller,
    required VoidCallback onSelected,
  }) {
    if (suggestions.isEmpty) return;
    showDialog(
      context: parentContext,
      barrierDismissible: true,
      builder: (suggestionCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(0),
        title: const Row(children: [
          Icon(Icons.history, color: AppColors.primary),
          SizedBox(width: 8),
          Text('الاقتراحات', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            itemBuilder: (ctx, i) {
              return InkWell(
                onTap: () {
                  controller.text = suggestions[i];
                  controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: controller.text.length));
                  Navigator.pop(suggestionCtx);
                  onSelected();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.history,
                        size: 18, color: AppColors.primary.withOpacity(0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestions[i],
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showEditTransactionDialog(BuildContext context, Map<String, dynamic> tx) {
    double amt = (tx['amount'] as num).toDouble();
    String amtStr = amt == amt.roundToDouble()
        ? amt.toInt().toString()
        : amt.toString();
    final amountCtrl = TextEditingController(text: amtStr);
    amountCtrl.selection = TextSelection(
        baseOffset: 0, extentOffset: amountCtrl.text.length);
    final detailsCtrl =
        TextEditingController(text: tx['details']?.toString() ?? '');
    DateTime selectedDate;
    try {
      selectedDate = DateTime.parse(tx['date'].toString().substring(0, 10));
    } catch (_) {
      selectedDate = DateTime.now();
    }
    String? selectedImageBase64 = tx['image_data']?.toString();
    final dateCtrl = TextEditingController(
        text: '${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}');

    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    Timer? suggestionDebounce;
    int suggestionRequest = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(children: [
            IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
            const Spacer(),
            const Text('تعديل العملية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.edit, color: AppColors.primary),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      onTap: () {
                        amountCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: amountCtrl.text.length);
                      },
                      decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: InkWell(
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
                                '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: dateCtrl,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                              labelText: 'التاريخ',
                              border: UnderlineInputBorder()),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 15),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: detailsCtrl,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'التفاصيل / البيان',
                          border: UnderlineInputBorder()),
                      onChanged: (val) {
                        suggestionDebounce?.cancel();
                        final request = ++suggestionRequest;
                        if (val.trim().length < 2) return;
                        suggestionDebounce = Timer(const Duration(milliseconds: 250), () async {
                          final allDetails = await provider.getDistinctDetails(query: val.trim());
                          if (request != suggestionRequest || detailsCtrl.text.trim() != val.trim()) return;
                          final prefixMatches = allDetails
                              .where((d) => d.startsWith(val.trim()) && d != val.trim())
                              .toList();
                          final containsMatches = allDetails
                              .where((d) => d.contains(val.trim()) && !d.startsWith(val.trim()) && d != val.trim())
                              .toList();
                          final combined = [...prefixMatches, ...containsMatches];
                          if (combined.isNotEmpty && context.mounted) {
                            _showSuggestionsDialog(
                              parentContext: context,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onSelected: () { setDialogState(() {}); },
                            );
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (imageCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: const Text('اختر مصدر الصورة'),
                          content: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.camera_alt,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الكاميرا'),
                                onPressed: () async {
                                  Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.photo_library,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الهاتف'),
                                onPressed: () async {
                                  Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },                    child: selectedImageBase64 == null
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.camera_alt,
                                color: Colors.grey, size: 28))
                        : GestureDetector(
                            onTap: () => _showImageOptionsSheet(
                                context, provider, tx),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                  base64Decode(selectedImageBase64!),
                                  width: 45,
                                  height: 45,
                                  fit: BoxFit.cover),
                            ),
                          ),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final original = DateTime.tryParse(tx['date']?.toString() ?? '');
                        final time = original ?? DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        await provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'take',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('عليه',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final original = DateTime.tryParse(tx['date']?.toString() ?? '');
                        final time = original ?? DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                        await provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'give',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('له',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedImageBase64;
    final dateCtrl = TextEditingController(
        text: '${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}');

    final provider = Provider.of<AppAccountProvider>(context, listen: false);
    Timer? suggestionDebounce;
    int suggestionRequest = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          title: Row(children: [
            IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => Navigator.pop(ctx),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
            const Spacer(),
            const Text('إضافة عملية جديدة',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            const Icon(Icons.add_circle_outline, color: AppColors.primary),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          border: UnderlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: InkWell(
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
                                '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextField(
                          controller: dateCtrl,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                              labelText: 'التاريخ',
                              border: UnderlineInputBorder()),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 15),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: detailsCtrl,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                          labelText: 'التفاصيل / البيان',
                          border: UnderlineInputBorder()),
                      onChanged: (val) {
                        suggestionDebounce?.cancel();
                        final request = ++suggestionRequest;
                        if (val.trim().length < 2) return;
                        suggestionDebounce = Timer(const Duration(milliseconds: 250), () async {
                          final allDetails = await provider.getDistinctDetails(query: val.trim());
                          if (request != suggestionRequest || detailsCtrl.text.trim() != val.trim()) return;
                          final prefixMatches = allDetails
                              .where((d) => d.startsWith(val.trim()) && d != val.trim())
                              .toList();
                          final containsMatches = allDetails
                              .where((d) => d.contains(val.trim()) && !d.startsWith(val.trim()) && d != val.trim())
                              .toList();
                          final combined = [...prefixMatches, ...containsMatches];
                          if (combined.isNotEmpty && context.mounted) {
                            _showSuggestionsDialog(
                              parentContext: context,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onSelected: () { setDialogState(() {}); },
                            );
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (imageCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          title: const Text('اختر مصدر الصورة'),
                          content: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.camera_alt,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الكاميرا'),
                                onPressed: () async {
                                  Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.photo_library,
                                    size: 32, color: AppColors.primary),
                                label: const Text('الهاتف'),
                                onPressed: () async {
                                  Navigator.pop(imageCtx);
                                  final img =
                                      await ImagePicker().pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 60,
                                          maxWidth: 1600,
                                          maxHeight: 1600);
                                  if (img != null) {
                                    final bytes =
                                        await img.readAsBytes();
                                    setDialogState(() =>
                                        selectedImageBase64 =
                                            base64Encode(bytes));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: selectedImageBase64 == null
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.camera_alt,
                                color: Colors.grey, size: 28))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                                base64Decode(selectedImageBase64!),
                                width: 45,
                                height: 45,
                                fit: BoxFit.cover),
                          ),
                  ),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        await provider.addTransaction(
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'take',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('عليه',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        await provider.addTransaction(
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'give',
                          detailsCtrl.text,
                          dateStr,
                          imageData: selectedImageBase64,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('له',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTransactionDetailsDialog(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) async {
    final bool isGive = tx['type'] == 'give';
    final double amt = (tx['amount'] as num).toDouble();
    final String details = tx['details']?.toString() ?? '';
    final String dateStr = tx['date'].toString();
    String? imageData = tx['image_data']?.toString();
    if ((imageData == null || imageData!.isEmpty) &&
        (tx['image_path']?.toString().isNotEmpty ?? false)) {
      final bytes = await ImageStorageService.readRelative(tx['image_path']?.toString());
      if (bytes != null) imageData = base64Encode(bytes);
    }
    final dialogTx = {...tx, if (imageData != null) 'image_data': imageData};

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(16),
        title: Row(children: [
          Icon(isGive ? Icons.arrow_downward : Icons.arrow_upward,
              color: isGive ? AppColors.green : AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.customer['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detailRow('المبلغ :', formatNumber(amt)),
                const Divider(),
                _detailRow('التاريخ :', dateStr.split(' ')[0]),
                const Divider(),
                _detailRow('التفاصيل :', details.isEmpty ? '-' : details),
                if (imageData != null && imageData.isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showImageOptionsSheet(ctx, provider, dialogTx),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(base64Decode(imageData),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                  ),
                ],
              ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditTransactionDialog(context, tx);
            },
            child: const Text('تعديل',
                style: TextStyle(color: AppColors.goldDark, fontSize: 15)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ]),
    );
  }

  void _showImageOptionsSheet(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) {
    final int txId = int.parse(tx['id'].toString());
    final String? imageData = tx['image_data']?.toString();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (imageData != null && imageData.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.visibility, color: AppColors.green),
              title: const Text('فتح الصورة'),
              onTap: () {
                Navigator.pop(ctx);
                _showFullImage(context, imageData);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.red),
              title: const Text('حذف الصورة'),
              onTap: () async {
                Navigator.pop(ctx);
                await _updateTransactionImage(provider, txId, null);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppColors.primary),
            title: const Text('الكاميرا'),
            onTap: () async {
              Navigator.pop(ctx);
              final img = await ImagePicker().pickImage(
                  source: ImageSource.camera, imageQuality: 60, maxWidth: 1600, maxHeight: 1600);
              if (img != null) {
                final bytes = await img.readAsBytes();
                await _updateTransactionImage(
                    provider, txId, base64Encode(bytes));
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('الهاتف'),
            onTap: () async {
              Navigator.pop(ctx);
              final img = await ImagePicker().pickImage(
                  source: ImageSource.gallery, imageQuality: 60, maxWidth: 1600, maxHeight: 1600);
              if (img != null) {
                final bytes = await img.readAsBytes();
                await _updateTransactionImage(
                    provider, txId, base64Encode(bytes));
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ]),
      ),
    );
  }

  void _showFullImage(BuildContext context, String base64Data) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(base64Decode(base64Data)),
        ),
      ),
    );
  }

  Future<void> _updateTransactionImage(
      AppAccountProvider provider, int txId, String? imageData) async {
    final db = await AppDBHelper.instance.database;
    final existing = await db.query('transactions',
        where: 'id = ?', whereArgs: [txId], limit: 1);
    if (existing.isEmpty) return;
    final oldPath = existing.first['image_path']?.toString();
    String? newPath;
    try {
      if (imageData != null && imageData.trim().isNotEmpty) {
        newPath = await ImageStorageService.saveBase64(imageData, 'tx_$txId');
        if (newPath == null) throw Exception('تعذر حفظ صورة العملية');
      }
      await db.update('transactions',
          {'image_data': null, 'image_path': newPath},
          where: 'id = ?', whereArgs: [txId]);
    } catch (_) {
      if (newPath != null) await ImageStorageService.deleteRelative(newPath);
      rethrow;
    }
    if (oldPath != null && oldPath != newPath) {
      await ImageStorageService.deleteRelative(oldPath);
    }
    await provider.loadTransactions(int.parse(widget.customer['id'].toString()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final rawTransactions = provider.currentTransactions;

    double cumulative = 0.0, totalGive = 0.0, totalTake = 0.0;
    List<Map<String, dynamic>> processedTransactions = [];
    final customerCurrency = (widget.customer['currency'] ?? '').toString();
    for (var tx in rawTransactions) {
      final txCurrency = (tx['currency'] ?? '').toString();
      if (txCurrency != customerCurrency) continue;
      double amt = (tx['amount'] as num).toDouble();
      if (tx['type'] == 'give') {
        cumulative += amt;
        totalGive += amt;
      } else {
        cumulative -= amt;
        totalTake += amt;
      }
      processedTransactions.add({...tx, 'running_balance': cumulative});
    }
    final double finalBalance = cumulative;
    final displayTransactions = processedTransactions.reversed.toList();

    return Scaffold(
      appBar: GradientAppBar(
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.customer['name'].toString(),
                  style: const TextStyle(fontSize: 18, color: Colors.black)),
              if (widget.customer['phone'] != null &&
                  widget.customer['phone'].toString().trim().isNotEmpty)
                Text(widget.customer['phone'].toString(),
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
            ]),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.black),
            tooltip: 'تصدير PDF',
            onPressed: () => _exportToPdf(
                processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.table_view, color: Colors.green),
            tooltip: 'تصدير Excel',
            onPressed: () => _exportToExcel(
                processedTransactions, totalGive, totalTake, finalBalance),
          ),
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.black, size: 26),
            tooltip: 'إرسال عبر واتساب',
            onPressed: () => _sendWhatsApp(
                widget.customer['phone']?.toString(), finalBalance),
          ),
        ],
      ),
      body: Column(children: [
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
                    ]))
              : Column(children: [
                  Container(
                    color: AppColors.solidBlue,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 4),
                    child: const Row(children: [
                      Expanded(
                          flex: 3,
                          child: Text('التاريخ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 2,
                          child: Text('المبلغ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 4,
                          child: Text('التفاصيل',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      Expanded(
                          flex: 2,
                          child: Text('الرصيد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                    ]),
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
                        Color amtBg =
                            isGive ? AppColors.green : AppColors.red;
                        Color balBg = runBal >= 0
                            ? AppColors.green
                            : AppColors.red;

                        return InkWell(
                          onTap: () => _showTransactionDetailsDialog(
                              context, provider, tx),
                          onLongPress: () =>
                              _showTransactionOptionsModal(context, provider, tx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 4),
                            color: i.isEven
                                ? Colors.white
                                : const Color(0xFFF9FAFB),
                            child: Row(children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(dateTimeFormatted['date']!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textDark)),
                                      if (dateTimeFormatted['time']!
                                          .isNotEmpty)
                                        Text(dateTimeFormatted['time']!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textMuted)),
                                    ]),
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
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(formatNumber(amt),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
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
                                          color: AppColors.textDark)),
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
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(formatNumber(runBal.abs()),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: AppColors.background,
          child: Row(children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => _showAddTransactionDialog(context),
                  child: const Center(
                      child: Icon(Icons.add, color: AppColors.gold, size: 30)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.solidBlue,
                    borderRadius: BorderRadius.circular(8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('عليه: ${formatNumber(totalTake)}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        Text('له: ${formatNumber(totalGive)}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ]),
                  const SizedBox(height: 3),
                  Container(
                      height: 1, color: Colors.black.withOpacity(0.2)),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                        '${finalBalance == 0 ? "الرصيد" : (finalBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(finalBalance.abs())}',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ============ تصدير كشف الحساب إلى Excel ============
  Future<void> _exportToExcel(
      List<Map<String, dynamic>> txs,
      double totalGive,
      double totalTake,
      double finalBal) async {
    try {
      final workbook = excel_lib.Excel.createExcel();
      final sheet = workbook['كشف الحساب'];
      sheet.appendRow([
        excel_lib.TextCellValue('التاريخ'),
        excel_lib.TextCellValue('التفاصيل'),
        excel_lib.TextCellValue('له'),
        excel_lib.TextCellValue('عليه'),
        excel_lib.TextCellValue('الرصيد'),
      ]);

      double runningBalance = 0;
      for (final tx in txs) {
        final isGive = tx['type'] == 'give';
        final amount = (tx['amount'] as num).toDouble();
        runningBalance += isGive ? amount : -amount;
        String dateOnly = (tx['date'] ?? '').toString().split(' ').first;
        try {
          final dt = DateTime.parse(tx['date'].toString());
          dateOnly =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {}
        sheet.appendRow([
          excel_lib.TextCellValue(dateOnly),
          excel_lib.TextCellValue((tx['details'] ?? '').toString()),
          isGive ? excel_lib.DoubleCellValue(amount) : excel_lib.TextCellValue('-'),
          isGive ? excel_lib.TextCellValue('-') : excel_lib.DoubleCellValue(amount),
          excel_lib.DoubleCellValue(runningBalance),
        ]);
      }

      sheet.appendRow([
        excel_lib.TextCellValue('إجمالي العمليات'),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(totalGive),
        excel_lib.DoubleCellValue(totalTake),
        excel_lib.DoubleCellValue(finalBal),
      ]);
      final bytes = workbook.encode();
      if (bytes == null) throw Exception('تعذر إنشاء ملف Excel');

      final tempDir =
          Directory(p.join((await getTemporaryDirectory()).path, 'excel'));
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final safeName = widget.customer['name']
          .toString()
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File(p.join(
        tempDir.path,
        'كشف_${safeName}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      ));
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'كشف حساب Excel - ${widget.customer['name']}',
      );
      Future.delayed(const Duration(minutes: 10), () async {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      });
    } catch (e, st) {
      debugPrint('Excel export error: $e\\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر تصدير Excel: $e'),
          backgroundColor: AppColors.red,
        ));
      }
    }
  }

  // ============ PDF محسّن مع حذف تلقائي ============
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: AppColors.gold),
                SizedBox(height: 15),
                Text('جاري إنتاج PDF...'),
              ]),
            ),
          ),
        ),
      );
    }

    try {
      final fontDataRegular =
          await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final fontRegular = pw.Font.ttf(fontDataRegular);
      final fontDataBold =
          await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      final fontBold = pw.Font.ttf(fontDataBold);

      final personalData = await PersonalDataService.getData();
      final logoBase64 = await PersonalDataService.getLogoBase64();
      final logoShape = personalData['logoShape'] as String;

      Uint8List? logoBytes;
      if (logoBase64 != null && logoBase64.isNotEmpty) {
        logoBytes = base64Decode(logoBase64);
      } else {
        try {
          final data = await rootBundle.load('assets/icon.png');
          logoBytes = data.buffer.asUint8List();
        } catch (_) {}
      }

      final pdf = pw.Document(
          theme: pw.ThemeData.withFont(
              base: fontRegular, bold: fontBold));

      final darkBlue = PdfColor.fromHex("#1E3A5F");
      final greenTotal = PdfColor.fromHex("#00A000");
      final redTotal = PdfColor.fromHex("#F00000");
      final headerBg = PdfColor.fromHex("#CCCCCC");
      final totalBg = PdfColor.fromHex("#E0E0E0");
      final lightGreen = PdfColor.fromHex("#D9F7D9");
      final lightRed = PdfColor.fromHex("#FFE0E0");
      final black = PdfColors.black;

      final List<pw.TableRow> dataRows = [];
      double newFinalBal = 0;
      double newTotalGive = 0;
      double newTotalTake = 0;
      for (var tx in txs) {
        final bool isGive = tx['type'] == 'give';
        final double amt = (tx['amount'] as num).toDouble();
        if (isGive) {
          newFinalBal += amt;
          newTotalGive += amt;
        } else {
          newFinalBal -= amt;
          newTotalTake += amt;
        }
        String dateOnly = tx['date'].toString().split(' ').first;
        try {
          final dt = DateTime.parse(tx['date'].toString());
          dateOnly =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {}

        final String balStr = formatNumber(newFinalBal.abs());

        final PdfColor balanceNumberColor = newFinalBal < 0
            ? redTotal
            : (newFinalBal > 0 ? greenTotal : black);

        dataRows.add(pw.TableRow(children: [
          _pdfCell(balStr, fontBold, 12, balanceNumberColor),
          _pdfCell(isGive ? formatNumber(amt) : '-', fontBold, 12, isGive ? greenTotal : black),
          _pdfCell(isGive ? '-' : formatNumber(amt), fontBold, 12, isGive ? black : redTotal),
          _pdfCell((tx['details'] ?? '').toString(), fontRegular, 12, black),
          _pdfCell(dateOnly, fontRegular, 12, black),
        ]));
      }

      final double balanceDiff = newTotalGive - newTotalTake;
      final String balanceText = balanceDiff == 0
          ? 'الرصيد الإجمالي'
          : (balanceDiff > 0 ? 'الرصيد الإجمالي - له' : 'الرصيد الإجمالي - عليه');
      final double balanceValue = balanceDiff.abs();
      final bool isOnHim = balanceDiff < 0;
      final PdfColor balanceRowColor = balanceDiff < 0 ? lightRed : lightGreen;

      pw.Widget buildHeader() {
        final rightItems = <pw.Widget>[];
        final leftItems = <pw.Widget>[];

        for (var i = 1; i <= 3; i++) {
          final rightText = (personalData['rightLine$i'] ?? '').toString();
          if (rightText.isNotEmpty) {
            final colorHex = (personalData['rightColor$i'] ?? '#000000').toString();
            final size = (personalData['rightSize$i'] as num?)?.toDouble() ?? 10.0;
            rightItems.add(pw.Text(
              rightText,
              style: pw.TextStyle(
                font: i == 1 ? fontBold : fontRegular,
                fontSize: size,
                color: PdfColor.fromHex(colorHex),
              ),
            ));
          }

          final leftText = (personalData['leftLine$i'] ?? '').toString();
          if (leftText.isNotEmpty) {
            final colorHex = (personalData['leftColor$i'] ?? '#000000').toString();
            final size = (personalData['leftSize$i'] as num?)?.toDouble() ?? 10.0;
            leftItems.add(pw.Text(
              leftText,
              style: pw.TextStyle(
                font: i == 1 ? fontBold : fontRegular,
                fontSize: size,
                color: PdfColor.fromHex(colorHex),
              ),
            ));
          }
        }

        return pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rightItems,
                  ),
                ),
                pw.SizedBox(
                  width: 60,
                  child: pw.Center(
                    child: logoBytes != null
                        ? pw.Container(
                            width: 50,
                            height: 50,
                            child: pw.ClipRRect(
                              horizontalRadius:
                                  logoShape == 'circle' ? 25 : 4,
                              verticalRadius:
                                  logoShape == 'circle' ? 25 : 4,
                              child: pw.Image(pw.MemoryImage(logoBytes),
                                  fit: pw.BoxFit.cover),
                            ),
                          )
                        : pw.SizedBox(),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: leftItems,
                  ),
                ),              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(color: darkBlue, thickness: 1.5),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'كشف حساب : ${widget.customer['name']}',
                style: pw.TextStyle(
                    font: fontBold, fontSize: 14, color: darkBlue),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.8),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(1.8),
                3: const pw.FlexColumnWidth(3.5),
                4: const pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: headerBg),
                  children: [
                    _pdfCell('الرصيد', fontBold, 12, black),
                    _pdfCell('له', fontBold, 12, black),
                    _pdfCell('عليه', fontBold, 12, black),
                    _pdfCell('التفاصيل', fontBold, 12, black),
                    _pdfCell('التاريخ', fontBold, 12, black),
                  ],
                ),
              ],
            ),
          ]),
        );
      }

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        header: (pw.Context ctx) => buildHeader(),
        footer: (pw.Context ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(children: [
            pw.Divider(color: black),
            pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تطبيق المحاسب',
                      style: pw.TextStyle(
                          font: fontRegular, fontSize: 10, color: black)),
                  pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                      style: pw.TextStyle(
                          font: fontRegular, fontSize: 10, color: black)),
                  pw.Text('المهندس : اسامه الاضرعي',
                      style: pw.TextStyle(
                          font: fontRegular, fontSize: 10, color: black)),
                ]),
          ]),
        ),
        build: (pw.Context context) => [
          pw.SizedBox(height: 5),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(3.5),
              4: const pw.FlexColumnWidth(2.2),
            },
            children: [
              ...dataRows,
              pw.TableRow(
                decoration: pw.BoxDecoration(color: totalBg),
                children: [
                  _pdfCell('', fontBold, 14, black),
                  _pdfCell(formatNumber(newTotalGive), fontBold, 14, greenTotal),
                  _pdfCell(formatNumber(newTotalTake), fontBold, 14, redTotal),
                  _pdfCell('إجمالي العمليات', fontBold, 14, black),
                  _pdfCell('', fontBold, 14, black),
                ],
              ),
              pw.TableRow(
                decoration: pw.BoxDecoration(color: balanceRowColor),
                children: [
                  _pdfCell('', fontBold, 14, black),
                  _pdfCell(
                      !isOnHim ? formatNumber(balanceValue) : '',
                      fontBold,
                      14,
                      !isOnHim ? greenTotal : black),
                  _pdfCell(
                      isOnHim ? formatNumber(balanceValue) : '',
                      fontBold,
                      14,
                      isOnHim ? redTotal : black),
                  _pdfCell(balanceText, fontBold, 14, black),
                  _pdfCell('', fontBold, 14, black),
                ],
              ),
            ],
          ),
        ],
      ));

      final bytes = await pdf.save();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final tempDir = Directory(p.join((await getTemporaryDirectory()).path, 'pdf'));
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      final fileName =
          'كشف_${widget.customer['name']}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(p.join(tempDir.path, fileName));
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
      Future.delayed(const Duration(minutes: 10), () async {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      });
    } catch (e, st) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('PDF Error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذر إنتاج PDF: $e'),
            backgroundColor: AppColors.red));
      }
    }
  }

  pw.Widget _pdfCell(
      String text, pw.Font font, double size, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font,
              fontSize: size,
              color: color,
              fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );
  }

  Future<void> _sendWhatsApp(String? rawPhone, double balance) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا يوجد رقم هاتف مضاف لهذا الحساب'),
          backgroundColor: AppColors.red));
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
      }
    } catch (_) {}
  }
}

// ==================== CategoriesScreen ====================
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة التصنيفات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: provider.categories.isEmpty
          ? Center(
              child: ElevatedButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة أول تصنيف'),
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
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.folder,
                            color: AppColors.primary),
                      ),
                      title: Text(cat['name'].toString(),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(context),
          child: const Icon(Icons.add, size: 30)),
    );
  }

  void _showOptionsSheet(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> cat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.primary),
            title: const Text('تعديل الاسم'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditDialog(context, provider, cat);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert, color: AppColors.goldDark),
            title: const Text('إعادة الترتيب'),
            onTap: () {
              Navigator.pop(ctx);
              _showReorderDialog(context, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: AppColors.red),
            title: const Text('حذف'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(context, provider, cat);
            },
          ),
        ]),
      ),
    );
  }

  void _showEditDialog(BuildContext context, AppAccountProvider provider,
      Map<String, dynamic> cat) {
    final controller = TextEditingController(text: cat['name'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('تعديل التصنيف'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.updateCategory(int.parse(cat['id'].toString()),
                    controller.text.trim());
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
          title: const Text('إعادة الترتيب'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
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
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(cat['name'].toString()),
                    trailing: Text('${index + 1}'),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              onPressed: () {
                provider.reorderCategories(
                    tempCats.map((c) => int.parse(c['id'].toString())).toList());
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> cat) async {
    final int catId = int.parse(cat['id'].toString());
    final int count = await provider.countCustomersInCategory(catId);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('تأكيد الحذف'),
        content: Text(count > 0
            ? 'يوجد $count حساب داخل التصنيف. لا يمكن حذف التصنيف حتى لا تضيع الحسابات والمعاملات.'
            : 'هل أنت متأكد من حذف التصنيف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () async {
              if (count > 0) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('لا يمكن حذف تصنيف يحتوي على حسابات. انقل الحسابات أولاً.'),
                  backgroundColor: AppColors.red,
                ));
                return;
              }
              final success = await provider.deleteCategory(catId);
              if (context.mounted) {
                Navigator.pop(ctx);
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('لا يمكن حذف آخر تصنيف في التطبيق'),
                    backgroundColor: AppColors.red,
                  ));
                }
              }
            },
            child: const Text('حذف'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('إضافة تصنيف جديد'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Provider.of<AppAccountProvider>(context, listen: false)
                    .addCategory(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

// ==================== CurrenciesScreen ====================
class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('إدارة العملات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: provider.currencies.isEmpty
          ? const Center(child: Text('لا توجد عملات'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: provider.currencies.length,
              itemBuilder: (ctx, i) {
                final curr = provider.currencies[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.attach_money,
                        color: AppColors.goldDark),
                    title: Text(curr['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('الرمز: ${curr['symbol']}'),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(context),
          child: const Icon(Icons.add, size: 30)),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('إضافة عملة جديدة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العملة')),
          const SizedBox(height: 10),
          TextField(
              controller: symbolCtrl,
              decoration: const InputDecoration(labelText: 'الرمز')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
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
          ),
        ],
      ),
    );
  }
}