part of '../main.dart';

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
    try {
      const androidSettings =
          AndroidInitializationSettings('ic_notification');
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
    } catch (e, st) {
      // Notifications are best-effort: failures must not stop backup work.
      debugPrint('تعذر تهيئة الإشعارات (ستستمر مهمة النسخ): $e\n$st');
    }
  }

  static Future<void> showPersistentLocalNotification(String timeText) async {
    try {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: 'ic_notification',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _localNotificationId,
      '📁 النسخ الاحتياطي المحلي',
      'الموعد المستهدف للنسخ يومياً: $timeText',
      details,
    );
    } catch (e) {
      debugPrint('تعذر عرض إشعار النسخ المحلي: $e');
    }
  }

  static Future<void> showPersistentDriveNotification(String timeText) async {
    try {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      icon: 'ic_notification',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _driveNotificationId,
      '☁️ النسخ الاحتياطي على Drive',
      'الموعد المستهدف للرفع يومياً: $timeText',
      details,
    );
    } catch (e) {
      debugPrint('تعذر عرض إشعار النسخ على Drive: $e');
    }
  }

  static Future<void> cancelLocalNotification() async {
    try { await _plugin.cancel(_localNotificationId); } catch (e) {
      debugPrint('تعذر إلغاء إشعار النسخ المحلي: $e');
    }
  }

  static Future<void> cancelDriveNotification() async {
    try { await _plugin.cancel(_driveNotificationId); } catch (e) {
      debugPrint('تعذر إلغاء إشعار Drive: $e');
    }
  }

  static Future<void> showTemporarySuccess(String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('تعذر عرض الإشعار (لن تتعطل مهمة النسخ): $e');
    }
  }

  static Future<void> showTemporaryFailure(String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
      );
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('تعذر عرض إشعار فشل النسخ؛ ستستمر مهام الخلفية: $e');
    }
  }
}

// ====================================================
// ✅ دالة معالجة المهام في الخلفية (Workmanager)
// ====================================================
@pragma('vm:entry-point')
Future<void> exactBackupAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();
  try {
    await NotificationService.initialize(requestPermission: false);
  } catch (e) {
    debugPrint('تعذر تهيئة الإشعارات: $e');
  }
  try {
    await AppDBHelper.instance.database;
  } catch (e) {
    debugPrint('تعذر فتح قاعدة البيانات: $e');
  }
  try {
    final settings = await AutoBackupService.getSettings();
    if (settings['enabled'] == true) {
      final err = await AutoBackupService.performScheduledBackup();
      if (err != null) {
        try { await NotificationService.showTemporaryFailure('تعذر النسخ المحلي', err); } catch (_) {}
      } else {
        try { await NotificationService.showTemporarySuccess('📁 النسخ المحلي', 'تم بنجاح'); } catch (_) {}
      }
    }
    if (settings['driveEnabled'] == true && await GoogleDriveService.trySilentSignIn()) {
      final err = await AutoBackupService.performScheduledDriveBackup();
      if (err != null) {
        try { await NotificationService.showTemporaryFailure('تعذر نسخ Drive', err); } catch (_) {}
      }
    }
  } catch (e, st) {
    debugPrint('فشل المنبّه: $e\n$st');
  } finally {
    try {
      final exact = await AutoBackupService._scheduleNextExactBackup();
      if (!exact) await AutoBackupService._scheduleNextTimedBackup(replacePending: true);
    } catch (e) {
      debugPrint('تعذر إعادة الجدولة: $e');
    }
  }
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    try {
      await NotificationService.initialize(requestPermission: false);
    } catch (e) {
      debugPrint('تعذر تهيئة الإشعارات: $e');
    }
    try {
      await AppDBHelper.instance.database;
    } catch (e) {
      debugPrint('تعذر فتح قاعدة البيانات: $e');
      return false;
    }
    var shouldRetry = false;
    try {
      if (task == AutoBackupService.workManagerExitTaskName) {
        final settings = await AutoBackupService.getSettings();
        final now = DateTime.now();
        final lastLocal = DateTime.tryParse(settings['lastBackup'] as String? ?? '');
        final localDone = lastLocal != null && now.difference(lastLocal).inHours < 6 && !now.isBefore(lastLocal);
        if (settings['enabled'] == true && !localDone) {
          final err = await AutoBackupService.runBackupNow();
          if (err != null) shouldRetry = true;
        }
        final lastDrive = DateTime.tryParse(settings['driveLastBackup'] as String? ?? '');
        final driveDone = lastDrive != null && now.difference(lastDrive).inHours < 6 && !now.isBefore(lastDrive);
        if (settings['driveEnabled'] == true && !driveDone) {
          if (await GoogleDriveService.trySilentSignIn()) {
            final err = await AutoBackupService.runDriveBackupNow();
            if (err != null) shouldRetry = true;
          } else {
            shouldRetry = true;
          }
        }
        return !shouldRetry;
      }
      final localError = await AutoBackupService.checkAndRunBackup();
      if (localError != null) {
        shouldRetry = true;
        try { await NotificationService.showTemporaryFailure('تعذر النسخ المحلي', localError); } catch (_) {}
      }
      final settings = await AutoBackupService.getSettings();
      if (settings['driveEnabled'] == true) {
        if (await GoogleDriveService.trySilentSignIn()) {
          final driveError = await AutoBackupService.checkAndRunDriveBackup();
          if (driveError != null) {
            shouldRetry = true;
            try { await NotificationService.showTemporaryFailure('تعذر نسخ Drive', driveError); } catch (_) {}
          }
        } else {
          shouldRetry = true;
        }
      }
      try {
        final exact = await AutoBackupService._scheduleNextExactBackup();
        if (!exact) await AutoBackupService._scheduleNextTimedBackup();
      } catch (e) {
        debugPrint('تعذر إعادة الجدولة: $e');
      }
      return !shouldRetry;
    } catch (e, st) {
      debugPrint('خطأ في WorkManager: $e\n$st');
      return false;
    }
  });
}

// ====================================================
// ✅ تخزين الصور كملفات خاصة بالتطبيق (بدلاً من Base64 داخل SQLite)
// ====================================================
