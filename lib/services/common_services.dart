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

  // إشعار مؤقت أثناء تنفيذ النسخ فقط؛ يُلغى عند انتهاء العملية.
  static Future<void> showBackupInProgress({required bool drive}) async {
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
      final id = drive ? _driveNotificationId : _localNotificationId;
      await _plugin.show(
        id,
        drive ? '☁️ جاري النسخ إلى Google Drive' : '📁 جارٍ النسخ الاحتياطي للهاتف',
        'عملية النسخ الاحتياطي قيد التنفيذ',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('تعذر عرض إشعار تقدم النسخ (ستستمر العملية): $e');
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
// الرسائل التلقائية للعملاء عبر SMS
// ====================================================
class CustomerSmsAutoService {
  static const String taskName = 'al_muhasib_customer_sms_auto';
  static const String uniqueName = 'al_muhasib_customer_sms_auto_periodic';

  static Future<void> schedule() async {
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
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
  }

  static Future<bool> runDueMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final db = await AppDBHelper.instance.database;
    final now = DateTime.now();
    final customers = await db.query('customers');
    bool failed = false;

    for (final customer in customers) {
      final id = customer['id']?.toString();
      if (id == null || prefs.getBool('customer_sms_auto_enabled_$id') != true) continue;

      final phoneRaw = customer['phone']?.toString() ?? '';
      final phone = phoneRaw.replaceAll(RegExp(r'[^\d+]'), '');
      if (phone.isEmpty) continue;

      final frequency = prefs.getString('customer_sms_frequency_$id') ?? 'daily';
      final hour = prefs.getInt('customer_sms_hour_$id') ?? 9;
      final minute = prefs.getInt('customer_sms_minute_$id') ?? 0;
      final targetMinutes = hour * 60 + minute;
      final currentMinutes = now.hour * 60 + now.minute;
      final weekday = prefs.getInt('customer_sms_weekday_$id') ?? 1;
      final monthDay = prefs.getInt('customer_sms_monthday_$id') ?? 1;
      // إذا كان الهاتف مغلقاً عند الموعد، أرسل بعد تشغيله في أول فحص لاحق،
      // مع منع تكرار الرسالة في الفترة نفسها.
      bool due;
      String periodKey;
      if (frequency == 'weekly') {
        due = now.weekday > weekday ||
            (now.weekday == weekday && currentMinutes >= targetMinutes);
        final monday = now.subtract(Duration(days: now.weekday - 1));
        periodKey = 'week_${monday.year}_${monday.month}_${monday.day}';
      } else if (frequency == 'monthly') {
        final lastDay = DateTime(now.year, now.month + 1, 0).day;
        final effectiveMonthDay = monthDay > lastDay ? lastDay : monthDay;
        due = now.day > effectiveMonthDay ||
            (now.day == effectiveMonthDay && currentMinutes >= targetMinutes);
        periodKey = 'month_${now.year}_${now.month}';
      } else {
        due = currentMinutes >= targetMinutes;
        periodKey = 'day_${now.year}_${now.month}_${now.day}';
      }
      if (!due) continue;
      final sentKey = 'customer_sms_last_period_$id';
      if (prefs.getString(sentKey) == periodKey) continue;

      final tx = await db.rawQuery(
        '''SELECT COALESCE(SUM(CASE WHEN t.type = 'give' THEN t.amount ELSE -t.amount END), 0) AS balance
           FROM transactions t
           INNER JOIN customers c ON c.id = t.customer_id
           WHERE t.customer_id = ? AND t.currency = c.currency''',
        [customer['id']],
      );
      final balance = tx.isEmpty ? 0.0 : ((tx.first['balance'] as num?)?.toDouble() ?? 0.0);

      // في منطق التطبيق الحالي، الرصيد السالب يعني أن العميل مدين لنا.
      // لا ترسل مطالبة عندما يصبح الرصيد صفراً أو موجباً.
      if (balance >= 0) continue;

      final name = (customer['name'] ?? '').toString().trim();
      final currency = (customer['currency'] ?? '').toString().trim();
      final amount = formatNumber(balance.abs());
      final message = 'عزيزي العميل: $name\\nعليكم مبلغ: $amount $currency لحسابنا';
      try {
        await Telephony.instance.sendSms(to: phone, message: message);
        await prefs.setString(sentKey, periodKey);
      } catch (e) {
        failed = true;
        debugPrint('تعذر إرسال SMS تلقائي للعميل $id: $e');
      }
    }
    return !failed;
  }
}

// ====================================================
// ✅ دالة معالجة المهام في الخلفية (Workmanager)
// ====================================================

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    ui.DartPluginRegistrant.ensureInitialized();
    try {
      await NotificationService.initialize(requestPermission: false);
    } catch (e) {
      debugPrint('تعذر تهيئة الإشعارات: $e');
    }
    if (task == CustomerSmsAutoService.taskName) {
      try {
        return await CustomerSmsAutoService.runDueMessages();
      } catch (e, st) {
        debugPrint('تعذر فحص رسائل العملاء التلقائية: $e\\n$st');
        return false;
      }
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
        await AutoBackupService._scheduleNextTimedBackup(replacePending: true);
      } catch (e) {
        debugPrint('تعذر إعادة جدولة WorkManager: $e');
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
