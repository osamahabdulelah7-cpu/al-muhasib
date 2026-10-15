part of '../main.dart';

/// نسخ احتياطي فوري بعد تعديل البيانات (إضافة فوق النظام الحالي، لا يستبدله).
///
/// لا تعمل إلا إذا كان "النسخ التلقائي للهاتف" مفعّلاً، وتستخدم نفس دالة النسخ
/// الحالية (performBackup) بنفس الوجهة والتحقق من سلامة الملف.
///
/// الاحتفاظ: خمس نسخ فورية (اسمها يبدأ بـ instant_al_muhasib_) منفصلة تماماً عن
/// خمس النسخ العادية/اليومية (al_muhasib_)، فيكون المجموع عشر نسخ.
class InstantBackupService {
  InstantBackupService._();

  static const String _prefEnabled = 'instant_backup_enabled';
  static const String _prefPending = 'instant_backup_pending';
  static const String _prefLastRunMs = 'instant_backup_last_run_ms';
  static const String _prefDrivePending = 'instant_drive_backup_pending';
  static const String _prefLastFingerprint = 'instant_backup_last_fingerprint';
  static const String _prefDriveEnabled = 'instant_drive_backup_enabled';
  static const String _prefDriveFingerprint = 'instant_drive_backup_last_fingerprint';

  static const Duration _debounce = Duration(seconds: 8);
  static const Duration _minGap = Duration(minutes: 1);
  static const String _namePrefix = 'GO_al_muhasib_';
  static const int _maxInstantBackups = 5;

  static Timer? _timer;
  static Timer? _driveTimer;
  static bool _running = false;
  static bool _rerun = false;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  static Future<bool> isDriveEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDriveEnabled) ?? false;
  }

  static Future<void> setDriveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDriveEnabled, value);
    if (!value) {
      _driveTimer?.cancel();
      await prefs.setBool(_prefDrivePending, false);
    }
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
    if (!value) {
      _timer?.cancel();
      await prefs.setBool(_prefPending, false);
    }
  }

  /// تُستدعى بعد أي تعديل على البيانات.
  static void markChanged() {
    unawaited(_markChanged());
  }

  /// تُستدعى عند فتح التطبيق وعند خروجه للخلفية.
  static Future<void> flushIfPending() async {
    _timer?.cancel();
    _driveTimer?.cancel();
    await Future.wait([_run(ignoreGap: true), _runDrive(ignoreGap: true)]);
  }

  static Future<void> _markChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefEnabled) == true) {
        await prefs.setBool(_prefPending, true);
        _schedule(_debounce);
      }
      if (prefs.getBool(_prefDriveEnabled) == true) {
        await prefs.setBool(_prefDrivePending, true);
        _scheduleDrive(_debounce);
      }
    } catch (e) {
      debugPrint('تعذر تسجيل تعديل للنسخ الفوري: $e');
    }
  }

  static void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_run(ignoreGap: false)));
  }

  static Future<void> _run({required bool ignoreGap}) async {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getBool(_prefPending) != true) return;

      if (prefs.getBool(_prefEnabled) != true) return;
      final settings = await AutoBackupService.getSettings();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final since = nowMs - (prefs.getInt(_prefLastRunMs) ?? 0);
      if (!ignoreGap && since >= 0 && since < _minGap.inMilliseconds) {
        _schedule(Duration(milliseconds: _minGap.inMilliseconds - since + 500));
        return;
      }

      // نصفّر العلامة قبل النسخ حتى يعيد أي تعديل أثناء النسخ تفعيلها.
      await prefs.setBool(_prefPending, false);
      await prefs.setInt(_prefLastRunMs, nowMs);

      await AppDBHelper.instance.syncPersonalDataToDatabase();
      final fingerprint = await AutoBackupService._getDatabaseFingerprint();
      final previousFingerprint = prefs.getString(_prefLastFingerprint);
      if (fingerprint != null && fingerprint == previousFingerprint) {
        // A queued change can be a no-op (for example, repeated notifications).
        // Do not create another identical snapshot.
        await prefs.setBool(_prefPending, false);
        return;
      }

      final folder = (settings['folderPath'] as String? ?? '').trim();
      final error = await AutoBackupService.performBackup(
        folder,
        namePrefix: _namePrefix,
        recordSchedule: false,
      );
      if (error != null) {
        debugPrint('فشل النسخ الفوري: $error');
        await prefs.setBool(_prefPending, true);
        return;
      }
      if (fingerprint != null) await prefs.setString(_prefLastFingerprint, fingerprint);
      await _pruneOldInstantBackups(folder);
    } catch (e, st) {
      debugPrint('خطأ في النسخ الفوري: $e\n$st');
      try {
        (await SharedPreferences.getInstance()).setBool(_prefPending, true);
      } catch (_) {}
    } finally {
      _running = false;
      if (_rerun) {
        _rerun = false;
        _schedule(_debounce);
      }
    }
  }

  static void _scheduleDrive(Duration delay) {
    _driveTimer?.cancel();
    _driveTimer = Timer(delay, () => unawaited(_runDrive(ignoreGap: false)));
  }

  /// Upload an independent instant snapshot to Drive. A failed upload remains
  /// pending and never affects local backup state.
  static Future<void> _runDrive({required bool ignoreGap}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(_prefDriveEnabled) != true ||
        prefs.getBool(_prefDrivePending) != true) return;
    if (!GoogleDriveService.isSignedIn &&
        !await GoogleDriveService.trySilentSignIn()) {
      debugPrint('النسخ الفوري إلى Drive مؤجل حتى تسجيل الدخول');
      return;
    }
    try {
      await AppDBHelper.instance.syncPersonalDataToDatabase();
      final fingerprint = await AutoBackupService._getDatabaseFingerprint();
      final previous = prefs.getString(_prefDriveFingerprint);
      if (fingerprint != null && fingerprint == previous) {
        await prefs.setBool(_prefDrivePending, false);
        return;
      }
      final bundle = await BackupBundleService.createBundle();
      try {
        if (!await BackupBundleService.verifyBundle(bundle)) {
          throw Exception('فشل التحقق من ملف النسخة الفورية');
        }
        final error = await GoogleDriveService.uploadBackup(
          bundle, namePrefix: 'GO_al_muhasib_',
        );
        if (error != null) throw Exception(error);
        if (fingerprint != null) {
          await prefs.setString(_prefDriveFingerprint, fingerprint);
        }
        await prefs.setBool(_prefDrivePending, false);
        await AutoBackupService.cleanOldInstantDriveBackups();
      } finally {
        try { await bundle.delete(); } catch (_) {}
      }
    } catch (e, st) {
      debugPrint('فشل النسخ الفوري على Drive، ستبقى المحاولة معلقة: $e\\n$st');
      await prefs.setBool(_prefDrivePending, true);
    }
  }

  static Future<int> countBackups() async {
    try {
      final settings = await AutoBackupService.getSettings();
      final folder = (settings['folderPath'] as String? ?? '').trim();
      if (folder.isEmpty) return 0;
      if (AutoBackupService._isSafFolder(folder)) {
        final entries = await Saf().list(AutoBackupService._safUri(folder));
        return entries.where((e) => !e.isDir && _isInstantName(e.name)).length;
      }
      final dir = Directory(folder);
      if (!await dir.exists()) return 0;
      return dir.listSync().whereType<File>()
          .where((f) => _isInstantName(p.basename(f.path))).length;
    } catch (e) {
      debugPrint('تعذر حساب النسخ الفورية: $e');
      return 0;
    }
  }

  static bool _isInstantName(String name) =>
      (name.startsWith(_namePrefix) ||
       name.startsWith('GO_al_muhasib(') ||
       name.startsWith('instant_al_muhasib_') ||
       name.startsWith('instant_al_muhasib(')) &&
      p.extension(name).toLowerCase() == '.alb';

  /// يُبقي أحدث خمس نسخ فورية في مجلد الحفظ الخارجي المشترك فقط.
  static Future<void> _pruneOldInstantBackups(String folder) async {
    try {
      if (folder.isEmpty) return;
      try {
        if (AutoBackupService._isSafFolder(folder)) {
          final entries = await Saf().list(AutoBackupService._safUri(folder));
          final instant = entries
              .where((e) => !e.isDir && _isInstantName(e.name))
              .toList()
            ..sort((a, b) => b.name.compareTo(a.name));
          for (final old in instant.skip(_maxInstantBackups)) {
            try {
              await Saf().delete(old.uri);
            } catch (e) {
              debugPrint('تعذر حذف نسخة فورية قديمة ${old.name}: $e');
            }
          }
        } else {
          await _pruneDirectory(Directory(folder));
        }
      } catch (e) {
        debugPrint('تعذر تنظيف النسخ الفورية في المجلد الخارجي: $e');
      }
    } catch (e) {
      debugPrint('تعذر تنظيف النسخ الفورية القديمة: $e');
    }
  }

  static Future<void> _pruneDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => _isInstantName(p.basename(f.path)))
        .toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final old in files.skip(_maxInstantBackups)) {
      try {
        await old.delete();
      } catch (e) {
        debugPrint('تعذر حذف نسخة فورية قديمة ${old.path}: $e');
      }
    }
  }
}
