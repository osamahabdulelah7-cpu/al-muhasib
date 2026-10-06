import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:image_picker/image_picker.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

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
Future<void> cleanTempPdfFiles() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync();
    for (var file in files) {
      if (file is File && file.path.endsWith('.pdf')) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

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

  static Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
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

    // ✅ طلب إذن الإشعارات (أندرويد 13+)
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> showPersistentLocalNotification(
      String timeText) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/launcher_icon',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _localNotificationId,
      '📁 النسخ الاحتياطي المحلي',
      'سيتم النسخ يومياً في الساعة $timeText',
      details,
    );
  }

  static Future<void> showPersistentDriveNotification(
      String timeText) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/launcher_icon',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _driveNotificationId,
      '☁️ النسخ الاحتياطي على Drive',
      'سيتم الرفع يومياً في الساعة $timeText',
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
      icon: '@mipmap/launcher_icon',
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
    await NotificationService.initialize();
    try {
      await AppDBHelper.instance.database;
      final localError = await AutoBackupService.performScheduledBackup();
      debugPrint('✅ نسخ محلي مجدول: $localError');
      if (GoogleDriveService.isSignedIn) {
        final driveError = await AutoBackupService.performScheduledDriveBackup();
        debugPrint('✅ نسخ Drive مجدول: $driveError');
      }
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في المهمة الخلفية: $e');
      return false;
    }
  });
}

// ====================================================
// ✅ دالة معالجة AlarmManager
// ====================================================
@pragma('vm:entry-point')
Future<void> alarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  try {
    await AppDBHelper.instance.database;
    await AutoBackupService.performScheduledBackup();
    await AutoBackupService.performScheduledDriveBackup();
    debugPrint('✅ تم تنفيذ مهمة AlarmManager');
  } catch (e) {
    debugPrint('❌ خطأ في AlarmManager: $e');
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
    return {
      'nameAr': prefs.getString(_prefNameAr) ?? '',
      'nameEn': prefs.getString(_prefNameEn) ?? '',
      'titleAr': prefs.getString(_prefTitleAr) ?? '',
      'titleEn': prefs.getString(_prefTitleEn) ?? '',
      'phone': prefs.getString(_prefPhone) ?? '',
      'email': prefs.getString(_prefEmail) ?? '',
      'logoShape': prefs.getString(_prefLogoShape) ?? 'circle',
    };
  }

  static Future<void> saveData({
    String? nameAr,
    String? nameEn,
    String? titleAr,
    String? titleEn,
    String? phone,
    String? email,
    String? logoShape,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (nameAr != null) await prefs.setString(_prefNameAr, nameAr);
    if (nameEn != null) await prefs.setString(_prefNameEn, nameEn);
    if (titleAr != null) await prefs.setString(_prefTitleAr, titleAr);
    if (titleEn != null) await prefs.setString(_prefTitleEn, titleEn);
    if (phone != null) await prefs.setString(_prefPhone, phone);
    if (email != null) await prefs.setString(_prefEmail, email);
    if (logoShape != null) await prefs.setString(_prefLogoShape, logoShape);
  }

  static Future<String?> getLogoBase64() async {
    final db = await AppDBHelper.instance.database;
    final result =
        await db.query('personal_logo', orderBy: 'id DESC', limit: 1);
    if (result.isNotEmpty) return result.first['logo_data'] as String?;
    return null;
  }

  static Future<void> saveLogoBase64(String? base64) async {
    final db = await AppDBHelper.instance.database;
    await db.delete('personal_logo');
    if (base64 != null) {
      await db.insert('personal_logo', {'logo_data': base64});
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

  static Future<String?> uploadBackup(File dbFile) async {
    if (_driveApi == null) return 'الرجاء تسجيل الدخول أولاً';
    try {
      final now = DateTime.now();
      final fileName =
          'al_muhasib_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}.db';
      final fileContent = await dbFile.readAsBytes();
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
  static const String _prefDriveEnabled = 'drive_backup_enabled';
  static const String _prefDriveHour = 'drive_backup_hour';
  static const String _prefDriveMinute = 'drive_backup_minute';
  static const String _prefDriveLastBackup = 'drive_backup_last_time';
  static const String _prefDriveLastDbModified = 'drive_backup_last_db_modified';
  static const int _maxLocalBackups = 5;
  static const int _maxDriveBackups = 5;
  static const String _workManagerTaskName = 'al_muhasib_daily_backup';
  static const String _workManagerUniqueName = 'al_muhasib_backup_unique';
  static const int _alarmIdLocal = 2001;
  static const int _alarmIdDrive = 2002;

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_prefEnabled) ?? false,
      'hour': prefs.getInt(_prefHour) ?? 3,
      'minute': prefs.getInt(_prefMinute) ?? 0,
      'folderPath': prefs.getString(_prefFolderPath) ?? '',
      'lastBackup': prefs.getString(_prefLastBackup) ?? '',
      'lastDbModified': prefs.getString(_prefLastDbModified) ?? '',
      'driveEnabled': prefs.getBool(_prefDriveEnabled) ?? false,
      'driveHour': prefs.getInt(_prefDriveHour) ?? 4,
      'driveMinute': prefs.getInt(_prefDriveMinute) ?? 0,
      'driveLastBackup': prefs.getString(_prefDriveLastBackup) ?? '',
      'driveLastDbModified': prefs.getString(_prefDriveLastDbModified) ?? '',
    };
  }

  static Future<void> saveSettings({
    bool? enabled,
    int? hour,
    int? minute,
    String? folderPath,
    String? lastBackup,
    String? lastDbModified,
    bool? driveEnabled,
    int? driveHour,
    int? driveMinute,
    String? driveLastBackup,
    String? driveLastDbModified,
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
      return lastModified != (settings['lastDbModified'] as String);
    } catch (e) {
      return true;
    }
  }

  static Future<bool> _hasDataChangedForDrive() async {
    try {
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) return false;
      final lastModified = (await dbFile.stat()).modified.toIso8601String();
      final settings = await getSettings();
      return lastModified != (settings['driveLastDbModified'] as String);
    } catch (e) {
      return true;
    }
  }

  static String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  // ============ جدولة المهام (Workmanager + AlarmManager + إشعارات) ============
  static Future<void> scheduleDailyBackup() async {
    final settings = await getSettings();
    final hour = settings['hour'] as int;
    final minute = settings['minute'] as int;

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    final delay = target.difference(now);

    // ✅ إلغاء أي مهمة سابقة
    await Workmanager().cancelByUniqueName(_workManagerUniqueName);

    // ✅ جدولة Workmanager (كاحتياطي)
    await Workmanager().registerPeriodicTask(
      _workManagerUniqueName,
      _workManagerTaskName,
      initialDelay: delay,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );

    // ✅ جدولة AlarmManager (الأكثر دقة)
    await AndroidAlarmManager.cancel(_alarmIdLocal);
    await AndroidAlarmManager.oneShotAt(
      target,
      _alarmIdLocal,
      alarmCallback,
      exact: true,
      wakeup: true,
    );

    // ✅ عرض الإشعار الدائم
    await NotificationService.showPersistentLocalNotification(
        _formatTime(hour, minute));

    debugPrint('✅ تم جدولة المهام اليومية بعد: ${delay.inHours} ساعة');
  }

  static Future<void> cancelDailyBackup() async {
    await Workmanager().cancelByUniqueName(_workManagerUniqueName);
    await AndroidAlarmManager.cancel(_alarmIdLocal);
    await NotificationService.cancelLocalNotification();
    debugPrint('✅ تم إلغاء المهام اليومية');
  }

  static Future<String?> performScheduledBackup() async {
    final settings = await getSettings();
    if (settings['enabled'] != true) return null;
    final folderPath = settings['folderPath'] as String;
    if (folderPath.isEmpty) return null;
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
      final dbFile = await _getDatabaseFile();
      final error = await GoogleDriveService.uploadBackup(dbFile);
      if (error == null) {
        final now = DateTime.now();
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified);
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

  // ✅ التحقق عند فتح التطبيق (نسخ محلي)
  static Future<String?> checkAndRunBackup() async {
    try {
      final settings = await getSettings();
      if (settings['enabled'] != true) return null;
      final folderPath = settings['folderPath'] as String;
      if (folderPath.isEmpty) return null;

      final now = DateTime.now();
      final todayTarget = DateTime(now.year, now.month, now.day,
          settings['hour'] as int, settings['minute'] as int);
      DateTime? lastBackup;
      final lastBackupStr = settings['lastBackup'] as String;
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      bool shouldBackup =
          lastBackup == null || lastBackup.isBefore(todayTarget);

      if (!shouldBackup) return null;
      if (!await _hasDataChanged()) return null;

      final result = await performBackup(folderPath);
      // ✅ إعادة جدولة المهام بعد النسخ
      await scheduleDailyBackup();
      return result;
    } catch (e) {
      return null;
    }
  }

  // ✅ التحقق عند فتح التطبيق (نسخ Drive)
  static Future<String?> checkAndRunDriveBackup() async {
    try {
      final settings = await getSettings();
      if (settings['driveEnabled'] != true) return null;
      if (!GoogleDriveService.isSignedIn) {
        if (!await GoogleDriveService.trySilentSignIn()) return null;
      }

      final now = DateTime.now();
      final todayTarget = DateTime(now.year, now.month, now.day,
          settings['driveHour'] as int, settings['driveMinute'] as int);
      DateTime? lastBackup;
      final lastBackupStr = settings['driveLastBackup'] as String;
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      bool shouldBackup =
          lastBackup == null || lastBackup.isBefore(todayTarget);

      if (!shouldBackup) return null;
      if (!await _hasDataChangedForDrive()) return null;

      final dbFile = await _getDatabaseFile();
      final error = await GoogleDriveService.uploadBackup(dbFile);
      if (error == null) {
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified);
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
      if (backups.length <= _maxDriveBackups) return;
      backups.sort((a, b) =>
          (b['createdTime'] as String).compareTo(a['createdTime'] as String));
      for (int i = _maxDriveBackups; i < backups.length; i++) {
        await GoogleDriveService.deleteBackup(backups[i]['id'] as String);
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
      if (files.length <= _maxLocalBackups) return;
      files.sort((a, b) => a.path.compareTo(b.path));
      for (int i = 0; i < files.length - _maxLocalBackups; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في حذف النسخ المحلية القديمة: $e');
    }
  }

  static Future<String?> performBackup(String folderPath) async {
    try {
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) return 'قاعدة البيانات غير موجودة';
      final backupDir = Directory(folderPath);
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      final now = DateTime.now();
      final fileName =
          'al_muhasib_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.db';
      await dbFile.copy(p.join(folderPath, fileName));
      final lastModified = (await dbFile.stat()).modified.toIso8601String();
      await saveSettings(
          lastBackup: now.toIso8601String(), lastDbModified: lastModified);
      await _cleanOldLocalBackups(folderPath);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  static Future<String?> runBackupNow() async {
    final settings = await getSettings();
    final folderPath = settings['folderPath'] as String;
    if (folderPath.isEmpty) return 'الرجاء اختيار مجلد أولاً';
    return await performBackup(folderPath);
  }

  static Future<String?> runDriveBackupNow() async {
    if (!GoogleDriveService.isSignedIn) {
      return 'الرجاء تسجيل الدخول إلى Google';
    }
    try {
      final dbFile = await _getDatabaseFile();
      final error = await GoogleDriveService.uploadBackup(dbFile);
      if (error == null) {
        final now = DateTime.now();
        final lastModified = (await dbFile.stat()).modified.toIso8601String();
        await saveSettings(
            driveLastBackup: now.toIso8601String(),
            driveLastDbModified: lastModified);
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

  // ✅ جدولة Drive مع AlarmManager وإشعار
  static Future<void> scheduleDriveBackup() async {
    final settings = await getSettings();
    final hour = settings['driveHour'] as int;
    final minute = settings['driveMinute'] as int;

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }

    await AndroidAlarmManager.cancel(_alarmIdDrive);
    await AndroidAlarmManager.oneShotAt(
      target,
      _alarmIdDrive,
      alarmCallback,
      exact: true,
      wakeup: true,
    );

    await NotificationService.showPersistentDriveNotification(
        _formatTime(hour, minute));

    debugPrint('✅ تم جدولة نسخ Drive');
  }

  static Future<void> cancelDriveBackup() async {
    await AndroidAlarmManager.cancel(_alarmIdDrive);
    await NotificationService.cancelDriveNotification();
    debugPrint('✅ تم إلغاء نسخ Drive');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  // ✅ تهيئة الإشعارات
  await NotificationService.initialize();

  // ✅ تهيئة AlarmManager
  await AndroidAlarmManager.initialize();

  // ✅ تهيئة Workmanager
  await Workmanager().initialize(callbackDispatcher);

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // ✅ تنظيف ملفات PDF المؤقتة عند فتح التطبيق
  await cleanTempPdfFiles();

  runZonedGuarded(() async {
    final provider = AppAccountProvider();
    try {
      await provider.loadInitialData();
    } catch (e, st) {
      debugPrint('خطأ: $e\n$st');
    }
    runApp(
      ChangeNotifierProvider<AppAccountProvider>.value(
        value: provider,
        child: const AlMuhasibApp(),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () async {
      await AutoBackupService.checkAndRunBackup();
      await AutoBackupService.checkAndRunDriveBackup();
      final settings = await AutoBackupService.getSettings();
      if (settings['enabled'] == true) {
        await AutoBackupService.scheduleDailyBackup();
      }
      if (settings['driveEnabled'] == true) {
        await AutoBackupService.scheduleDriveBackup();
      }
    });
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
    return await openDatabase(p.join(dbPath, filePath),
        version: 5, onCreate: _createDB, onUpgrade: _upgradeDB);
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
        image_data TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE personal_logo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        logo_data TEXT
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
  }

  Future<void> restoreDatabase(File newDbFile) async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'al_muhasib_final_v6.db');
    await newDbFile.copy(path);
    _db = await openDatabase(path,
        version: 5, onCreate: _createDB, onUpgrade: _upgradeDB);
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

  Future<void> deleteCategory(int id) async {
    final db = await AppDBHelper.instance.database;
    final customersInCat =
        await db.query('customers', where: 'category_id = ?', whereArgs: [id]);
    for (var cust in customersInCat) {
      await db.delete('transactions',
          where: 'customer_id = ?', whereArgs: [cust['id']]);
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
        CASE WHEN last_activity IS NULL OR last_activity = '' THEN 1 ELSE 0 END,
        last_activity DESC, id DESC
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
          'category_id': categoryId
        },
        where: 'id = ?',
        whereArgs: [id]);
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
      String details, String date,
      {String? imageData}) async {
    final db = await AppDBHelper.instance.database;
    await db.insert('transactions', {
      'customer_id': customerId,
      'amount': amount,
      'type': type,
      'details': details,
      'date': date,
      'image_data': imageData,
    });
    await db.update('customers', {'last_activity': date},
        where: 'id = ?', whereArgs: [customerId]);
    await loadTransactions(customerId);
    await loadCustomers();
  }

  Future<void> updateTransaction(int id, int customerId, double amount,
      String type, String details,
      {String? imageData}) async {
    final db = await AppDBHelper.instance.database;
    await db.update(
        'transactions',
        {
          'amount': amount,
          'type': type,
          'details': details,
          if (imageData != null) 'image_data': imageData,
        },
        where: 'id = ?',
        whereArgs: [id]);
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
      if (await File(path).exists()) {
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
        await AppDBHelper.instance
            .restoreDatabase(File(result.files.single.path!));
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
      await AppDBHelper.instance.restoreDatabase(selectedFile);
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
          LIMIT 100
        ''');
      } else {
        result = await db.rawQuery('''
          SELECT details, COUNT(*) as usage_count
          FROM transactions
          WHERE details IS NOT NULL AND TRIM(details) != '' 
            AND details LIKE ?
          GROUP BY details
          ORDER BY usage_count DESC, details ASC
          LIMIT 100
        ''', ['%$query%']);
      }
      return result
          .map((row) => (row['details'] ?? '').toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
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
    int finalCategoryId;
    if (categoryId != null) {
      final catCheck = await db
          .query('categories', where: 'id = ?', whereArgs: [categoryId]);
      if (catCheck.isEmpty) throw Exception('التصنيف المحدد غير موجود');
      finalCategoryId = categoryId;
    } else {
      final existingCat =
          await db.query('categories', where: 'name = ?', whereArgs: ['عام']);
      finalCategoryId = existingCat.isEmpty
          ? await db.insert('categories', {'name': 'عام'})
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
            if (dateCell is excel_lib.DateCellValue) {
              dateStr =
                  DateTime(dateCell.year, dateCell.month, dateCell.day)
                      .toString()
                      .split('.')[0];
            } else if (dateCell is excel_lib.DateTimeCellValue) {
              dateStr = dateCell.asDateTimeLocal().toString().split('.')[0];
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
              await db.update('customers', {'category_id': finalCategoryId},
                  where: 'id = ?', whereArgs: [customerId]);
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
          await db.update('customers', {'last_activity': dateStr},
              where: 'id = ?', whereArgs: [customerId]);
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
      return DateTime.parse(dateStr).toString().split('.')[0];
    } catch (_) {}
    final match1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dateStr);
    if (match1 != null) {
      return '${match1.group(1)}-${match1.group(2)!.padLeft(2, '0')}-${match1.group(3)!.padLeft(2, '0')}T00:00:00';
    }
    final match2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(dateStr);
    if (match2 != null) {
      return '${match2.group(3)}-${match2.group(2)!.padLeft(2, '0')}-${match2.group(1)!.padLeft(2, '0')}T00:00:00';
    }
    return DateTime.now().toString().split('.')[0];
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
        cardTheme: CardTheme(
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
      color: AppColors.solidBlue,
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        toolbarHeight: toolbarHeight,
        foregroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));
}

// ==================== PersonalDataScreen ====================
class PersonalDataScreen extends StatefulWidget {
  const PersonalDataScreen({super.key});

  @override
  State<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends State<PersonalDataScreen> {
  final nameArCtrl = TextEditingController();
  final nameEnCtrl = TextEditingController();
  final titleArCtrl = TextEditingController();
  final titleEnCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  String? _logoBase64;
  String _logoShape = 'circle';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await PersonalDataService.getData();
    final logo = await PersonalDataService.getLogoBase64();
    if (!mounted) return;
    setState(() {
      nameArCtrl.text = data['nameAr'];
      nameEnCtrl.text = data['nameEn'];
      titleArCtrl.text = data['titleAr'];
      titleEnCtrl.text = data['titleEn'];
      phoneCtrl.text = data['phone'];
      emailCtrl.text = data['email'];
      _logoShape = data['logoShape'];
      _logoBase64 = logo;
      _loading = false;
    });
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final base64Data = base64Encode(bytes);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('شكل الشعار'),
        content: const Text('هل تريد الشعار دائرياً أم مربعاً؟'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await PersonalDataService.saveLogoBase64(base64Data);
              await PersonalDataService.saveData(logoShape: 'circle');
              setState(() {
                _logoBase64 = base64Data;
                _logoShape = 'circle';
              });
            },
            child: const Text('دائري'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              Navigator.pop(ctx);
              await PersonalDataService.saveLogoBase64(base64Data);
              await PersonalDataService.saveData(logoShape: 'square');
              setState(() {
                _logoBase64 = base64Data;
                _logoShape = 'square';
              });
            },
            child: const Text('مربع'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLogo() async {
    await PersonalDataService.saveLogoBase64(null);
    setState(() => _logoBase64 = null);
  }

  Future<void> _save() async {
    await PersonalDataService.saveData(
      nameAr: nameArCtrl.text.trim(),
      nameEn: nameEnCtrl.text.trim(),
      titleAr: titleArCtrl.text.trim(),
      titleEn: titleEnCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
      email: emailCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ تم حفظ البيانات'),
        backgroundColor: AppColors.green,
      ));
      Navigator.pop(context);
    }
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                icon: const Icon(Icons.image),
                label: const Text('تغيير الشعار'),
              ),
              const SizedBox(width: 10),
              if (_logoBase64 != null)
                ElevatedButton.icon(
                  onPressed: _deleteLogo,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red),
                  icon: const Icon(Icons.delete),
                  label: const Text('حذف الشعار'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'البيانات التي تظهر في ترويسة التقارير',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameArCtrl,
            decoration: const InputDecoration(
              labelText: 'الاسم (عربي)',
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameEnCtrl,
            decoration: const InputDecoration(
              labelText: 'الاسم (إنجليزي)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleArCtrl,
            decoration: const InputDecoration(
              labelText: 'العنوان (عربي)',
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleEnCtrl,
            decoration: const InputDecoration(
              labelText: 'العنوان (إنجليزي)',
              prefixIcon: Icon(Icons.title_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
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
    });
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
        body: const Center(child: Text('لا توجد تصنيفات مضافة')),
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
                  child: TabBar(
                    controller: _tabController,
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

              double totalGive = 0.0, totalTake = 0.0;
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
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.solidBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                  height: 1,
                                  color: Colors.black.withOpacity(0.2)),
                              const SizedBox(height: 3),
                              Center(
                                child: Text(
                                    '${netBalance == 0 ? "الرصيد" : (netBalance > 0 ? "الرصيد له" : "الرصيد عليه")}: ${formatNumber(netBalance.abs())}',
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

  // ✅ التحقق من النسخ عند إغلاق التطبيق
  @override
  void dispose() {
    AutoBackupService.checkAndRunBackup();
    if (GoogleDriveService.isSignedIn) {
      AutoBackupService.checkAndRunDriveBackup();
    }
    _tabController?.dispose();
    searchController?.dispose();
    super.dispose();
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
              onPressed: () {
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: fromDrive ? AppColors.drive : AppColors.gold),
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
    if (value) {
      if (!await AutoBackupService.hasStoragePermission()) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            title: const Row(children: [
              Icon(Icons.security, color: AppColors.gold),
              SizedBox(width: 8),
              Text('صلاحية الوصول'),
            ]),
            content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('لكي يعمل الحفظ التلقائي، نحتاج صلاحية الوصول للملفات.',
                      style: TextStyle(fontSize: 14, height: 1.5)),
                  SizedBox(height: 10),
                  Text(
                      '⚠️ سيظهر لك النظام نافذة "السماح بالوصول لجميع الملفات"',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء',
                      style: TextStyle(color: Colors.grey))),
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
        if (!await AutoBackupService.requestStoragePermission()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('❌ لم يتم منح الصلاحية'),
                backgroundColor: AppColors.red));
          }
          return;
        }
      }
      if (_folderPath.isEmpty) {
        if (!await _pickFolder()) return;
      }
    }
    await AutoBackupService.saveSettings(enabled: value);
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
    } else {
      if (mounted) {
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

    // ✅ جدولة/إلغاء نسخ Drive
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
            onTap: () {
              Navigator.pop(ctx);
              provider.deleteTransaction(
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

  // ========== نافذة الاقتراحات المستقلة ==========
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

  // ========== نافذة تعديل العملية ==========
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
                      onChanged: (val) async {
                        if (val.length >= 2) {
                          final allDetails =
                              await provider.getDistinctDetails();
                          final prefixMatches = allDetails
                              .where((d) => d.startsWith(val) && d != val)
                              .toList();
                          final containsMatches = allDetails
                              .where((d) =>
                                  d.contains(val) &&
                                  !d.startsWith(val) &&
                                  d != val)
                              .toList();
                          final combined = [
                            ...prefixMatches,
                            ...containsMatches
                          ];
                          if (combined.isNotEmpty && context.mounted) {
                            _showSuggestionsDialog(
                              parentContext: context,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onSelected: () {
                                setDialogState(() {});
                              },
                            );
                          }
                        }
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
                                          imageQuality: 60);
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
                                          imageQuality: 60);
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
                      onPressed: () {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month}-${selectedDate.day} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'take',
                          detailsCtrl.text,
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
                      onPressed: () {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month}-${selectedDate.day} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        provider.updateTransaction(
                          int.parse(tx['id'].toString()),
                          int.parse(widget.customer['id'].toString()),
                          amount,
                          'give',
                          detailsCtrl.text,
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

  // ========== نافذة إضافة عملية جديدة ==========
  void _showAddTransactionDialog(BuildContext context) {
    final amountCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedImageBase64;
    final dateCtrl = TextEditingController(
        text: '${selectedDate.year}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}');

    final provider = Provider.of<AppAccountProvider>(context, listen: false);

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
                      onChanged: (val) async {
                        if (val.length >= 2) {
                          final allDetails =
                              await provider.getDistinctDetails();
                          final prefixMatches = allDetails
                              .where((d) => d.startsWith(val) && d != val)
                              .toList();
                          final containsMatches = allDetails
                              .where((d) =>
                                  d.contains(val) &&
                                  !d.startsWith(val) &&
                                  d != val)
                              .toList();
                          final combined = [
                            ...prefixMatches,
                            ...containsMatches
                          ];
                          if (combined.isNotEmpty && context.mounted) {
                            _showSuggestionsDialog(
                              parentContext: context,
                              suggestions: combined,
                              controller: detailsCtrl,
                              onSelected: () {
                                setDialogState(() {});
                              },
                            );
                          }
                        }
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
                                          imageQuality: 60);
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
                                          imageQuality: 60);
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
                      onPressed: () {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month}-${selectedDate.day} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        provider.addTransaction(
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
                      onPressed: () {
                        final amount = double.tryParse(amountCtrl.text);
                        if (amount == null || amount <= 0) return;
                        final now = DateTime.now();
                        final dateStr =
                            '${selectedDate.year}-${selectedDate.month}-${selectedDate.day} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
                        provider.addTransaction(
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

  void _showTransactionDetailsDialog(BuildContext context,
      AppAccountProvider provider, Map<String, dynamic> tx) {
    final bool isGive = tx['type'] == 'give';
    final double amt = (tx['amount'] as num).toDouble();
    final String details = tx['details']?.toString() ?? '';
    final String dateStr = tx['date'].toString();
    final String? imageData = tx['image_data']?.toString();

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
                    onTap: () => _showImageOptionsSheet(ctx, provider, tx),
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
                  source: ImageSource.camera, imageQuality: 60);
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
                  source: ImageSource.gallery, imageQuality: 60);
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
    await db.update('transactions', {'image_data': imageData},
        where: 'id = ?', whereArgs: [txId]);
    await provider
        .loadTransactions(int.parse(widget.customer['id'].toString()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppAccountProvider>(context);
    final rawTransactions = provider.currentTransactions;

    double cumulative = 0.0, totalGive = 0.0, totalTake = 0.0;
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
            onPressed: () => _exportToPdf(
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
      final greenTotal = PdfColor.fromHex("#1B5E20");
      final redTotal = PdfColor.fromHex("#B71C1C");
      final headerBg = PdfColor.fromHex("#CCCCCC");
      final totalBg = PdfColor.fromHex("#E0E0E0");
      final lightGreen = PdfColor.fromHex("#C8E6C9");
      final lightRed = PdfColor.fromHex("#FFCDD2");
      final black = PdfColors.black;

      final List<pw.TableRow> dataRows = [];
      double newFinalBal = 0;
      double newTotalGive = 0;
      double newTotalTake = 0;
      for (var tx in txs) {
        final bool isGive = tx['type'] == 'give';
        final double amt = (tx['amount'] as num).toDouble();
        if (isGive) {
          newFinalBal -= amt;
          newTotalGive += amt;
        } else {
          newFinalBal += amt;
          newTotalTake += amt;
        }
        String dateOnly = tx['date'].toString().split(' ').first;
        try {
          final dt = DateTime.parse(tx['date'].toString());
          dateOnly =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {}

        final String balStr = newFinalBal < 0
            ? '-${formatNumber(newFinalBal.abs())}'
            : formatNumber(newFinalBal);

        dataRows.add(pw.TableRow(children: [
          _pdfCell(balStr, fontRegular, 12, black),
          _pdfCell(isGive ? formatNumber(amt) : '-', fontRegular, 12, black),
          _pdfCell(isGive ? '-' : formatNumber(amt), fontRegular, 12, black),
          _pdfCell((tx['details'] ?? '').toString(), fontRegular, 12, black),
          _pdfCell(dateOnly, fontRegular, 12, black),
        ]));
      }

      final bool isOnHim = newTotalTake >= newTotalGive;
      final String balanceText = isOnHim
          ? 'الرصيد الإجمالي - عليه'
          : 'الرصيد الإجمالي - له';
      final double balanceValue = (newTotalTake - newTotalGive).abs();
      final PdfColor balanceRowColor = isOnHim ? lightRed : lightGreen;

      pw.Widget buildHeader() {
        final leftItems = <pw.Widget>[];
        final rightItems = <pw.Widget>[];

        if ((personalData['nameAr'] ?? '').isNotEmpty) {
          rightItems.add(pw.Text(
            personalData['nameAr'],
            style: pw.TextStyle(font: fontBold, fontSize: 10, color: black),
          ));
        }
        if ((personalData['titleAr'] ?? '').isNotEmpty) {
          rightItems.add(pw.Text(
            personalData['titleAr'],
            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: black),
          ));
        }
        if ((personalData['phone'] ?? '').isNotEmpty) {
          rightItems.add(pw.Text(
            personalData['phone'],
            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: black),
          ));
        }

        if ((personalData['nameEn'] ?? '').isNotEmpty) {
          leftItems.add(pw.Text(
            personalData['nameEn'],
            style: pw.TextStyle(font: fontBold, fontSize: 10, color: black),
          ));
        }
        if ((personalData['titleEn'] ?? '').isNotEmpty) {
          leftItems.add(pw.Text(
            personalData['titleEn'],
            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: black),
          ));
        }
        if ((personalData['email'] ?? '').isNotEmpty) {
          leftItems.add(pw.Text(
            personalData['email'],
            style: pw.TextStyle(font: fontRegular, fontSize: 9, color: black),
          ));
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
                ),
              ],
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
                      black),
                  _pdfCell(
                      isOnHim ? formatNumber(balanceValue) : '',
                      fontBold,
                      14,
                      black),
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
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'كشف_${widget.customer['name']}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
      Future.delayed(const Duration(seconds: 5), () async {
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
          ? const Center(child: Text('لا توجد تصنيفات'))
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
            ? 'يوجد $count حساب داخل التصنيف. سيتم حذفهم جميعاً!'
            : 'هل أنت متأكد من حذف التصنيف؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              provider.deleteCategory(catId);
              Navigator.pop(ctx);
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
