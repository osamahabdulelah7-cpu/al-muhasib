part of '../main.dart';

class AutoBackupService {
  static const String _prefEnabled = 'auto_backup_enabled';
  static const String _prefScheduledTimeEnabled = 'auto_backup_scheduled_time_enabled';
  static const String _prefRepeatEnabled = 'auto_backup_repeat_enabled';
  static const String _prefRepeatValue = 'auto_backup_repeat_value';
  static const String _prefRepeatUnit = 'auto_backup_repeat_unit';
  static const String _prefHour = 'auto_backup_hour';
  static const String _prefMinute = 'auto_backup_minute';
  static const String _prefFolderPath = 'auto_backup_folder_path';
  static const String _prefLastBackup = 'auto_backup_last_time';
  static const String _prefLastAttempt = 'auto_backup_last_attempt';
  static const Duration _minRetryInterval = Duration(minutes: 15);
  static const String _prefLastDbModified = 'auto_backup_last_db_modified';
  static const String _prefDbFingerprint = 'auto_backup_db_fingerprint';
  static const String _prefLastDestinationError = 'auto_backup_last_destination_error';
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
  static const String _workManagerTimedTaskName = 'al_muhasib_backup_at_time';
  static const String _workManagerTimedUniqueName = 'al_muhasib_backup_at_time_unique';
  static const int _exactAlarmId = 7042026;
  static const String workManagerExitTaskName = 'al_muhasib_backup_on_exit';
  static const String _workManagerExitUniqueName = 'al_muhasib_backup_on_exit_unique';
  static const String _prefLastExitEnqueuedAt = 'auto_backup_exit_enqueued_at';

  static Future<Map<String, dynamic>> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_prefEnabled) ?? false,
      'scheduledTimeEnabled': prefs.getBool(_prefScheduledTimeEnabled) ?? true,
      'repeatEnabled': prefs.getBool(_prefRepeatEnabled) ?? false,
      'repeatValue': prefs.getInt(_prefRepeatValue) ?? 1,
      'repeatUnit': prefs.getString(_prefRepeatUnit) ?? 'days',
      'hour': prefs.getInt(_prefHour) ?? 3,
      'minute': prefs.getInt(_prefMinute) ?? 0,
      'folderPath': prefs.getString(_prefFolderPath) ?? '',
      'lastBackup': prefs.getString(_prefLastBackup) ?? '',
      'lastDbModified': prefs.getString(_prefLastDbModified) ?? '',
      'dbFingerprint': prefs.getString(_prefDbFingerprint) ?? '',
      'lastDestinationError': prefs.getString(_prefLastDestinationError) ?? '',
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
    bool? scheduledTimeEnabled,
    bool? repeatEnabled,
    int? repeatValue,
    String? repeatUnit,
    int? hour,
    int? minute,
    String? folderPath,
    String? lastBackup,
    String? lastDbModified,
    String? dbFingerprint,
    String? lastDestinationError,
    bool? driveEnabled,
    int? driveHour,
    int? driveMinute,
    String? driveLastBackup,
    String? driveLastDbModified,
    String? driveDbFingerprint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) await prefs.setBool(_prefEnabled, enabled);
    if (scheduledTimeEnabled != null) {
      await prefs.setBool(_prefScheduledTimeEnabled, scheduledTimeEnabled);
    }
    if (repeatEnabled != null) await prefs.setBool(_prefRepeatEnabled, repeatEnabled);
    if (repeatValue != null) await prefs.setInt(_prefRepeatValue, repeatValue);
    if (repeatUnit != null) await prefs.setString(_prefRepeatUnit, repeatUnit);
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
    if (lastDestinationError != null) {
      await prefs.setString(_prefLastDestinationError, lastDestinationError);
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
      try {
        await (await AppDBHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (e) {
        debugPrint('تعذر إكمال WAL checkpoint قبل حساب البصمة: $e');
      }
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

  static Duration _configuredRepeatInterval(Map<String, dynamic> settings) {
    if (settings['repeatEnabled'] != true) return const Duration(minutes: 15);
    final value = (settings['repeatValue'] as int? ?? 60).clamp(1, 10080);
    final unit = settings['repeatUnit'] as String? ?? 'minutes';
    final requested = unit == 'hours'
        ? Duration(hours: value)
        : unit == 'days'
            ? Duration(days: value)
            : Duration(minutes: value);
    // Android WorkManager enforces a 15-minute minimum periodic interval.
    return requested < const Duration(minutes: 15)
        ? const Duration(minutes: 15)
        : requested;
  }

  // ============ جدولة المهام الخلفية ============
  static Future<void> _scheduleBackgroundBackup() async {
    final settings = await getSettings();
    final localEnabled = settings['enabled'] == true;
    final driveEnabled = settings['driveEnabled'] == true;
    if (!localEnabled && !driveEnabled) {
      await Workmanager().cancelByUniqueName(_workManagerUniqueName);
      await Workmanager().cancelByUniqueName(_workManagerTimedUniqueName);
      try { await AndroidAlarmManager.cancel(_exactAlarmId); } catch (_) {}
      return;
    }
    if (settings['repeatEnabled'] == true) {
      try {
        await Workmanager().registerPeriodicTask(
          _workManagerUniqueName,
          _workManagerTaskName,
          frequency: _configuredRepeatInterval(settings),
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
      } catch (e) {
        debugPrint('تعذر تسجيل WorkManager الدوري: $e');
      }
    } else {
      await Workmanager().cancelByUniqueName(_workManagerUniqueName);
    }
    var exactScheduled = false;
    try {
      exactScheduled = await _scheduleNextExactBackup(requestPermission: true);
    } catch (e) {
      debugPrint('تعذر جدولة المنبّه: $e');
    }
    if (!exactScheduled) {
      try {
        await _scheduleNextTimedBackup(replacePending: true);
      } catch (e) {
        debugPrint('تعذر جدولة WorkManager one-off: $e');
      }
    } else {
      await Workmanager().cancelByUniqueName(_workManagerTimedUniqueName);
    }
  }

  static Future<bool> _scheduleNextExactBackup({bool requestPermission = false}) async {
    final settings = await getSettings();
    final now = DateTime.now();
    final targets = <DateTime>[];
    void addTarget(bool enabled, int hour, int minute, String lastText) {
      if (!enabled) return;
      final target = DateTime(now.year, now.month, now.day, hour, minute);
      final last = DateTime.tryParse(lastText);
      final doneToday = last != null && !last.isBefore(target) && !last.isAfter(now);
      if (now.isBefore(target)) {
        targets.add(target);
      } else if (!doneToday) {
        targets.add(now.add(const Duration(minutes: 1)));
      } else {
        targets.add(target.add(const Duration(days: 1)));
      }
    }
    addTarget(settings['enabled'] == true && settings['scheduledTimeEnabled'] == true, settings['hour'] as int,
        settings['minute'] as int, settings['lastBackup'] as String? ?? '');
    addTarget(settings['driveEnabled'] == true && settings['scheduledTimeEnabled'] == true, settings['driveHour'] as int,
        settings['driveMinute'] as int, settings['driveLastBackup'] as String? ?? '');
    if (targets.isEmpty) {
      try { await AndroidAlarmManager.cancel(_exactAlarmId); } catch (_) {}
      return false;
    }
    targets.sort();
    final canSchedule = await ensureExactAlarmPermission(requestPermission: requestPermission);
    if (!canSchedule) {
      try { await AndroidAlarmManager.cancel(_exactAlarmId); } catch (_) {}
      return false;
    }
    try {
      final scheduled = await AndroidAlarmManager.oneShotAt(
        targets.first, _exactAlarmId, exactBackupAlarmCallback,
        exact: true, wakeup: true, allowWhileIdle: true, rescheduleOnReboot: true,
      );
      if (!scheduled) return false;
      debugPrint('✅ تم تسجيل منبّه النسخ عند ${targets.first}');
      return true;
    } catch (e, st) {
      debugPrint('خطأ في المنبّه الدقيق: $e\n$st');
      return false;
    }
  }

  static Future<bool> ensureExactAlarmPermission({bool requestPermission = false}) async {
    try {
      final status = await Permission.scheduleExactAlarm.status;
      if (status.isGranted) return true;
      if (!requestPermission) return false;
      final requested = await Permission.scheduleExactAlarm.request();
      if (requested.isGranted) return true;
      if (requested.isPermanentlyDenied) {
        try { await openAppSettings(); } catch (_) {}
      }
      return false;
    } catch (e) {
      debugPrint('خطأ في صلاحية Exact Alarm: $e');
      return false;
    }
  }

  static Future<bool> requestExactAlarmPermissionFromUI() async {
    final granted = await ensureExactAlarmPermission(requestPermission: true);
    if (granted) await scheduleDailyBackup();
    return granted;
  }

  static Future<bool> hasExactAlarmPermission() async {
    try {
      final status = await Permission.scheduleExactAlarm.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  // Periodic work is best-effort. Add a one-off request aimed at the next
  // configured time, keeping the periodic worker as a fallback.
  static Future<void> _scheduleNextTimedBackup({bool replacePending = false}) async {
    final settings = await getSettings();
    final now = DateTime.now();
    final candidates = <DateTime>[];

    void addTarget(bool enabled, int hour, int minute, String lastText) {
      if (!enabled) return;
      final target = DateTime(now.year, now.month, now.day, hour, minute);
      final last = DateTime.tryParse(lastText);
      final completedToday = last != null && !last.isBefore(target) && !last.isAfter(now);
      if (!now.isBefore(target) && !completedToday) {
        candidates.add(now.add(const Duration(minutes: 1)));
      } else if (now.isBefore(target)) {
        candidates.add(target);
      } else {
        candidates.add(target.add(const Duration(days: 1)));
      }
    }

    addTarget(settings['enabled'] == true, settings['hour'] as int,
        settings['minute'] as int, settings['lastBackup'] as String? ?? '');
    addTarget(settings['driveEnabled'] == true, settings['driveHour'] as int,
        settings['driveMinute'] as int, settings['driveLastBackup'] as String? ?? '');

    if (candidates.isEmpty) {
      await Workmanager().cancelByUniqueName(_workManagerTimedUniqueName);
      return;
    }
    candidates.sort();
    final delay = candidates.first.difference(now);
    await Workmanager().registerOneOffTask(
      _workManagerTimedUniqueName,
      _workManagerTimedTaskName,
      initialDelay: delay.isNegative ? Duration.zero : delay,
      existingWorkPolicy: replacePending ? ExistingWorkPolicy.replace : ExistingWorkPolicy.keep,
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
    debugPrint('تمت جدولة فحص النسخ القادم بعد ${delay.inMinutes} دقيقة');
  }

  static Future<void> scheduleDailyBackup() async {
    await _scheduleBackgroundBackup();
  }

  static Future<void> scheduleBackupOnExit() async {
    try {
      final settings = await getSettings();
      if (settings['enabled'] != true && settings['driveEnabled'] != true) return;

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final previous = prefs.getInt(_prefLastExitEnqueuedAt) ?? 0;
      // Avoid generating repeated snapshots when users switch between apps.
      if (now - previous < const Duration(hours: 6).inMilliseconds) return;

      await Workmanager().registerOneOffTask(
        _workManagerExitUniqueName,
        workManagerExitTaskName,
        existingWorkPolicy: ExistingWorkPolicy.keep,
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
      // Only throttle after WorkManager accepts the request.
      await prefs.setInt(_prefLastExitEnqueuedAt, now);
      debugPrint('تمت جدولة نسخة احتياطية عند خروج الواجهة');
    } catch (e, st) {
      debugPrint('تعذر جدولة النسخ عند خروج الواجهة: $e\n$st');
    }
  }

  static Future<void> cancelDailyBackup() async {
    await Workmanager().cancelByUniqueName(_workManagerUniqueName);
    await Workmanager().cancelByUniqueName(_workManagerTimedUniqueName);
    await Workmanager().cancelByUniqueName(_workManagerExitUniqueName);
    try { await AndroidAlarmManager.cancel(_exactAlarmId); } catch (_) {}
    await NotificationService.cancelLocalNotification();
    await NotificationService.cancelDriveNotification();
    debugPrint('تم إلغاء جميع مهام النسخ المحلية وDrive المجدولة');
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

  static bool _isSafFolder(String value) => value.startsWith('saf:');

  static String _safUri(String value) => value.substring(4);

  static Future<bool> _isValidSafFolder(String value) async {
    if (!_isSafFolder(value)) return false;
    try {
      final permissions = await Saf().persistedPermissions();
      return permissions.any((grant) =>
          grant.uri == _safUri(value) &&
          (grant.read && grant.write));
    } catch (e) {
      debugPrint('تعذر التحقق من صلاحية مجلد SD: $e');
      return false;
    }
  }

  static Future<String> _resolveBackupFolder(String? selectedFolder) async {
    final selected = selectedFolder?.trim() ?? '';
    // SAF returns content:// URIs, not filesystem paths. Keep the persisted
    // grant and never pass a document URI to Directory/File.
    if (_isSafFolder(selected)) {
      // Verify the persisted grant in the background. A revoked grant must not
      // prevent the independent internal backup from being created.
      if (!await _isValidSafFolder(selected)) {
        debugPrint('صلاحية SD غير موجودة أو غير مستمرة؛ ستُحفظ النسخة الداخلية وتُسجّل مشكلة الوجهة الخارجية.');
      }
      return selected;
    }
    if (selected.isNotEmpty &&
        p.isAbsolute(selected) &&
        await _isWritableDirectory(selected)) {
      return selected;
    }
    final fallback = await _defaultAutomaticBackupFolder();
    if (selected != fallback) await saveSettings(folderPath: fallback);
    return fallback;
  }

  static Future<void> _writeVerifiedSafBackup(
      File sourceFile, String folderSetting) async {
    final saf = Saf();
    final folderUri = _safUri(folderSetting);
    var fileName = p.basename(sourceFile.path);
    final tempDir = await getTemporaryDirectory();
    final verificationCopy = File(p.join(tempDir.path,
        'verify_${DateTime.now().microsecondsSinceEpoch}_$fileName'));

    // A prior interrupted write can leave a partial document with the same
    // name. Reuse it only if its contents verify; otherwise remove it first.
    final entries = await saf.list(folderUri);
    for (final entry in entries.where((e) => !e.isDir && e.name == fileName)) {
      var copiedForVerification = false;
      var validExistingCopy = false;
      Object? readError;
      try {
        await saf.copyToLocalFile(entry.uri, verificationCopy.path);
        copiedForVerification = true;
        validExistingCopy = await BackupBundleService.verifyBundle(verificationCopy);
        if (validExistingCopy) {
          await _cleanOldSafBackups(folderUri);
          return;
        }
      } catch (e) {
        readError = e;
        debugPrint('تعذر التحقق من النسخة الموجودة على SD: $e');
      } finally {
        try { if (await verificationCopy.exists()) await verificationCopy.delete(); } catch (_) {}
      }
      // Keep the existing document on any failed verification. A provider can
      // return incomplete bytes transiently; never destroy the only old copy.
      if (copiedForVerification && !validExistingCopy) {
        debugPrint('النسخة الموجودة على SD لم تجتز التحقق؛ سيتم الاحتفاظ بها وإضافة نسخة منفصلة');
        fileName = '${p.basenameWithoutExtension(fileName)}_retry_${DateTime.now().microsecondsSinceEpoch}${p.extension(fileName)}';
      } else if (!copiedForVerification) {
        throw Exception('تعذر قراءة النسخة الموجودة على بطاقة SD؛ لم يتم حذفها: $readError');
      }
    }

    SafDocumentFile? created;
    try {
      created = await saf.writeFileStream(
        folderUri,
        fileName,
        'application/octet-stream',
        sourceFile.openRead(),
        overwrite: false,
      );
      await saf.copyToLocalFile(created.uri, verificationCopy.path);
      if (!await BackupBundleService.verifyBundle(verificationCopy)) {
        throw Exception('فشل التحقق من النسخة بعد كتابتها على بطاقة SD');
      }
    } catch (_) {
      if (created != null) {
        try { await saf.delete(created.uri); } catch (_) {}
      }
      rethrow;
    } finally {
      try { if (await verificationCopy.exists()) await verificationCopy.delete(); } catch (_) {}
    }
    // Only verified new copies may trigger retention.
    await _cleanOldSafBackups(folderUri);
  }

  static Future<void> _cleanOldSafBackups(String folderUri) async {
    try {
      final entries = await Saf().list(folderUri);
      final backups = entries.where((entry) =>
          !entry.isDir &&
          entry.name.startsWith('al_muhasib_') &&
          p.extension(entry.name).toLowerCase() == '.alb').toList()
        ..sort((a, b) => b.name.compareTo(a.name));
      for (final old in backups.skip(_maxLocalBackups)) {
        try { await Saf().delete(old.uri); } catch (e) {
          debugPrint('تعذر حذف نسخة SD قديمة ${old.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('تعذر تنظيف النسخ القديمة على SD: $e');
    }
  }

  static Future<String?> _retryPendingDestination(String folderSetting) async {
    try {
      final internalDir = await internalBackupDirectory();
      final candidates = internalDir
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path).toLowerCase() == '.alb')
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));

      File? verifiedSource;
      for (final candidate in candidates) {
        if (await BackupBundleService.verifyBundle(candidate)) {
          verifiedSource = candidate;
          break;
        }
      }
      if (verifiedSource == null) {
        throw Exception('لا توجد نسخة داخلية سليمة لإعادة نسخها إلى الوجهة المحددة');
      }

      final selected = await _resolveBackupFolder(folderSetting);
      if (_isSafFolder(selected)) {
        await _writeVerifiedSafBackup(verifiedSource, selected);
      } else if (p.normalize(selected) != p.normalize(internalDir.path)) {
        final targetDir = Directory(selected);
        if (!await _isWritableDirectory(targetDir.path)) {
          throw Exception('الوجهة المحددة غير قابلة للكتابة');
        }
        final targetFile = File(p.join(targetDir.path, p.basename(verifiedSource.path)));
        await verifiedSource.copy(targetFile.path);
        if (!await BackupBundleService.verifyBundle(targetFile)) {
          try { await targetFile.delete(); } catch (_) {}
          throw Exception('فشل التحقق من النسخة بعد إعادة نسخها إلى الوجهة المحددة');
        }
        await _cleanOldLocalBackups(selected);
      }
      await saveSettings(lastDestinationError: '');
      return null;
    } catch (e, st) {
      debugPrint('فشل إعادة محاولة الوجهة الخارجية: $e\n$st');
      await saveSettings(lastDestinationError: e.toString());
      return 'تعذر إعادة النسخ إلى الوجهة المحددة: $e';
    }
  }

  static Future<String?> performScheduledBackup() async {
    final settings = await getSettings();
    if (settings['enabled'] != true) return null;
    final selectedFolder = (settings['folderPath'] as String? ?? '').trim();

    // Scheduled backups are snapshots, not change-only syncs.
    // Preserve internal backup creation even when the selected destination
    // is unavailable; performBackup records destination errors separately.
    final result = await performBackup(selectedFolder);
    if (result == null) {
      await NotificationService.showTemporarySuccess(
          '✅ تم النسخ المحلي', 'تم إنشاء نسخة احتياطية بنجاح');
    }
    return result;
  }

  static Future<String?> performScheduledDriveBackup() async {
    final settings = await getSettings();
    if (settings['driveEnabled'] != true) return null;
    if (!GoogleDriveService.isSignedIn &&
        !await GoogleDriveService.trySilentSignIn()) {
      return 'تعذر تسجيل الدخول إلى Google في الخلفية. افتح التطبيق وسجّل الدخول مجدداً.';
    }

    try {
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      final bundle = await BackupBundleService.createBundle();
      if (!await BackupBundleService.verifyBundle(bundle)) {
        try { await bundle.delete(); } catch (_) {}
        return 'تم إيقاف الرفع لأن فحص سلامة النسخة الجديدة فشل';
      }
      String? error;
      await NotificationService.showBackupInProgress(drive: true);
      try {
        error = await GoogleDriveService.uploadBackup(bundle);
      } finally {
        try { await bundle.delete(); } catch (_) {}
        await NotificationService.cancelDriveNotification();
      }
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

  @visibleForTesting
  static bool isAttemptThrottled(DateTime? last, DateTime now) {
    if (last == null) return false;
    final diff = now.difference(last);
    // Clock changes can put the saved attempt in the future. Treat that
    // as throttled too, rather than allowing an immediate repeated attempt.
    return diff.isNegative || diff < _minRetryInterval;
  }

  static Future<bool> _beginThrottledBackupAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final lastText = prefs.getString(_prefLastAttempt);
    final last = lastText == null ? null : DateTime.tryParse(lastText);
    final now = DateTime.now();
    if (isAttemptThrottled(last, now)) return false;
    await prefs.setString(_prefLastAttempt, now.toIso8601String());
    return true;
  }

  static Future<String?> checkAndRunBackup() async {
    try {
      final settings = await getSettings();
      if (settings['enabled'] != true) return null;
      final selectedFolder = (settings['folderPath'] as String? ?? '').trim();

      final now = DateTime.now();
      final todayTarget = DateTime(now.year, now.month, now.day,
          settings['hour'] as int, settings['minute'] as int);
      DateTime? lastBackup;
      final lastBackupStr = settings['lastBackup'] as String? ?? '';
      if (lastBackupStr.isNotEmpty) {
        lastBackup = DateTime.tryParse(lastBackupStr);
      }

      final hasPendingDestinationError =
          (settings['lastDestinationError'] as String? ?? '').isNotEmpty;
      if (now.isBefore(todayTarget)) {
        if (hasPendingDestinationError && selectedFolder.isNotEmpty) {
          if (!await _beginThrottledBackupAttempt()) return null;
          return await _retryPendingDestination(selectedFolder);
        }
        return null;
      }
      bool shouldBackup =
          lastBackup == null || lastBackup.isBefore(todayTarget);

      if (!shouldBackup) {
        if (hasPendingDestinationError && selectedFolder.isNotEmpty) {
          if (!await _beginThrottledBackupAttempt()) return null;
          return await _retryPendingDestination(selectedFolder);
        }
        return null;
      }
      if (!await _beginThrottledBackupAttempt()) return null;
      // This is a daily schedule, not a change-only sync. Create a verified
      // snapshot even when the database fingerprint matches yesterday.
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      // Let performBackup commit and verify the internal snapshot first.
      // A stale SD permission must not prevent the internal daily backup.
      final error = await performBackup(selectedFolder);
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
      // Daily Drive backups must not silently skip days with unchanged data.
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      final bundle = await BackupBundleService.createBundle();
      if (!await BackupBundleService.verifyBundle(bundle)) {
        try { await bundle.delete(); } catch (_) {}
        return 'تم إيقاف الرفع لأن فحص سلامة النسخة الجديدة فشل';
      }
      String? error;
      await NotificationService.showBackupInProgress(drive: true);
      try {
        error = await GoogleDriveService.uploadBackup(bundle);
      } finally {
        try { await bundle.delete(); } catch (_) {}
        await NotificationService.cancelDriveNotification();
      }
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
      // Retain five backup snapshots total per destination, regardless of
      // whether an older snapshot used the legacy .db or current .alb format.
      final snapshots = backups.where((b) {
        final ext = p.extension((b['name'] as String?) ?? '').toLowerCase();
        return ext == '.alb' || ext == '.db';
      }).toList()
        ..sort((a, b) {
          final aTime = (a['createdTime'] as String?)?.trim() ?? '';
          final bTime = (b['createdTime'] as String?)?.trim() ?? '';
          final aKey = aTime.isNotEmpty ? aTime : (a['name'] as String? ?? '');
          final bKey = bTime.isNotEmpty ? bTime : (b['name'] as String? ?? '');
          return bKey.compareTo(aKey);
        });
      for (final old in snapshots.skip(_maxDriveBackups)) {
        final id = old['id'] as String? ?? '';
        if (id.isNotEmpty) await GoogleDriveService.deleteBackup(id);
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
          .where((f) {
            final name = p.basename(f.path);
            final ext = p.extension(f.path).toLowerCase();
            return name.startsWith('al_muhasib_') &&
                (ext == '.alb' || ext == '.db');
          })
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      // The newly-created and verified snapshot is newest and must survive.
      for (final old in files.skip(_maxLocalBackups)) {
        try {
          await old.delete();
        } catch (e) {
          debugPrint('تعذر حذف النسخة القديمة ${old.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في حذف النسخ المحلية القديمة: $e');
    }
  }

  static Future<Directory> internalBackupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'AlMuhasib', 'Backups'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> performBackup(String folderPath) async {
    try {
      final db = await AppDBHelper.instance.database;
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      final internalDir = await internalBackupDirectory();
      final internalFile = await BackupBundleService.createBundle(outputDirectory: internalDir);
      if (!await BackupBundleService.verifyBundle(internalFile)) {
        try { await internalFile.delete(); } catch (_) {}
        throw Exception('فشل التحقق من سلامة النسخة الداخلية');
      }

      // The internal copy is a complete destination in its own right. Record
      // success only after its integrity check, before attempting optional targets.
      await _cleanOldLocalBackups(internalDir.path);
      final now = DateTime.now();
      final dbFile = await _getDatabaseFile();
      final lastModified = (await dbFile.stat()).modified.toIso8601String();
      await saveSettings(
        lastBackup: now.toIso8601String(),
        lastDbModified: lastModified,
        dbFingerprint: await _getDatabaseFingerprint(),
      );

      final selected = folderPath.trim();
      final internalOnly = selected.isEmpty ||
          p.normalize(selected) == p.normalize(internalDir.path);
      try {
        if (selected.isNotEmpty && _isSafFolder(selected)) {
          await _writeVerifiedSafBackup(internalFile, selected);
        } else if (!internalOnly) {
          final targetDir = Directory(selected);
          if (!await _isWritableDirectory(targetDir.path)) {
            throw Exception('المجلد المحدد غير قابل للكتابة');
          }
          final targetFile = File(p.join(targetDir.path, p.basename(internalFile.path)));
          await internalFile.copy(targetFile.path);
          if (!await BackupBundleService.verifyBundle(targetFile)) {
            try { await targetFile.delete(); } catch (_) {}
            throw Exception('فشل التحقق من النسخة في المجلد المحدد');
          }
          await _cleanOldLocalBackups(selected);
        }
        // Clear stale external-destination errors when the user has
        // switched back to internal-only backups as well.
        await saveSettings(lastDestinationError: '');
      } catch (destinationError, destinationStack) {
        await saveSettings(lastDestinationError: destinationError.toString());
        debugPrint('النسخة الداخلية سليمة، لكن فشل النسخ إلى الوجهة المحددة: $destinationError\n$destinationStack');
        return 'تم إنشاء نسخة داخلية سليمة والتحقق منها، لكن فشل الحفظ في الوجهة المحددة: $destinationError';
      }
      return null;
    } catch (e, st) {
      debugPrint('فشل النسخ المحلي: $e\n$st');
      return 'فشل إنشاء أو التحقق من النسخة الداخلية: $e';
    }
  }

  static Future<String?> runBackupNow() async {
    try {
      final settings = await getSettings();
      final folderPath = (settings['folderPath'] as String? ?? '').trim();
      // Destination failures are handled after the internal backup is safely
      // created and verified, rather than aborting the entire operation.
      return await performBackup(folderPath);
    } catch (e, st) {
      debugPrint('فشل تشغيل النسخ اليدوي: $e\n$st');
      return 'تعذر تشغيل النسخ الاحتياطي: $e';
    }
  }

  // Safety snapshots for restore must not depend on an optional SD-card or
  // shared-folder destination being mounted and writable.
  static Future<String?> runInternalBackupNow() async {
    try {
      // A restore safety snapshot must not advance the user's daily schedule
      // or clear a pending SD-card error. Build and verify it independently.
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      try {
        await (await AppDBHelper.instance.database)
            .rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      final internalDir = await internalBackupDirectory();
      final safetyBundle =
          await BackupBundleService.createBundle(outputDirectory: internalDir);
      if (!await BackupBundleService.verifyBundle(safetyBundle)) {
        try { await safetyBundle.delete(); } catch (_) {}
        throw Exception('فشل التحقق من نسخة الأمان الداخلية');
      }
      await _cleanOldLocalBackups(internalDir.path);
      return null;
    } catch (e, st) {
      debugPrint('فشل إنشاء نسخة الأمان الداخلية: $e\n$st');
      return 'تعذر إنشاء نسخة الأمان الداخلية: $e';
    }
  }

  static Future<String?> runDriveBackupNow() async {
    if (!GoogleDriveService.isSignedIn &&
        !await GoogleDriveService.trySilentSignIn()) {
      return 'انتهت جلسة Google أو لم تعد متاحة. افتح التطبيق وسجّل الدخول مجدداً.';
    }
    try {
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      try { await (await AppDBHelper.instance.database).rawQuery('PRAGMA wal_checkpoint(FULL)'); } catch (_) {}
      final bundle = await BackupBundleService.createBundle();
      if (!await BackupBundleService.verifyBundle(bundle)) {
        try { await bundle.delete(); } catch (_) {}
        return 'تم إيقاف الرفع لأن فحص سلامة النسخة الجديدة فشل';
      }
      String? error;
      await NotificationService.showBackupInProgress(drive: true);
      try {
        error = await GoogleDriveService.uploadBackup(bundle);
      } finally {
        try { await bundle.delete(); } catch (_) {}
        await NotificationService.cancelDriveNotification();
      }
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
      final dir = await internalBackupDirectory();
      return dir.listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('al_muhasib_'))
          .where((f) {
            final ext = p.extension(f.path).toLowerCase();
            return ext == '.alb' || ext == '.db';
          })
          .length;
    } catch (_) {
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
    if (settings['enabled'] != true && settings['driveEnabled'] != true) {
      // No destination remains enabled: clear every shared scheduled task.
      await cancelDailyBackup();
    } else {
      // Keep the shared scheduler aligned with the remaining destination.
      await _scheduleBackgroundBackup();
    }
    debugPrint('✅ تم إلغاء نسخ Drive');
  }
}
