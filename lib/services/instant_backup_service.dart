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

  static const String _prefPending = 'instant_backup_pending';
  static const String _prefLastRunMs = 'instant_backup_last_run_ms';

  static const Duration _debounce = Duration(seconds: 8);
  static const Duration _minGap = Duration(minutes: 1);
  static const String _internalOkPrefix = 'تم إنشاء نسخة داخلية سليمة';
  static const String _namePrefix = 'instant_al_muhasib_';
  static const int _maxInstantBackups = 5;

  static Timer? _timer;
  static bool _running = false;
  static bool _rerun = false;

  /// تُستدعى بعد أي تعديل على البيانات.
  static void markChanged() {
    unawaited(_markChanged());
  }

  /// تُستدعى عند فتح التطبيق وعند خروجه للخلفية.
  static Future<void> flushIfPending() async {
    _timer?.cancel();
    await _run(ignoreGap: true);
  }

  static Future<void> _markChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefPending, true);
      _schedule(_debounce);
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

      final settings = await AutoBackupService.getSettings();
      if (settings['enabled'] != true) return;

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final since = nowMs - (prefs.getInt(_prefLastRunMs) ?? 0);
      if (!ignoreGap && since >= 0 && since < _minGap.inMilliseconds) {
        _schedule(Duration(milliseconds: _minGap.inMilliseconds - since + 500));
        return;
      }

      // نصفّر العلامة قبل النسخ حتى يعيد أي تعديل أثناء النسخ تفعيلها.
      await prefs.setBool(_prefPending, false);
      await prefs.setInt(_prefLastRunMs, nowMs);

      final folder = (settings['folderPath'] as String? ?? '').trim();
      final error = await AutoBackupService.performBackup(
        folder,
        namePrefix: _namePrefix,
        recordSchedule: false,
      );
      final internalOk = error == null || error.startsWith(_internalOkPrefix);
      if (!internalOk) {
        debugPrint('فشل النسخ الفوري: $error');
        await prefs.setBool(_prefPending, true);
        return;
      }
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

  static bool _isInstantName(String name) =>
      name.startsWith(_namePrefix) && p.extension(name).toLowerCase() == '.alb';

  /// يُبقي أحدث خمس نسخ فورية فقط (داخلياً وفي مجلد الحفظ الخارجي).
  static Future<void> _pruneOldInstantBackups(String folder) async {
    try {
      final internalDir = await AutoBackupService.internalBackupDirectory();
      try {
        await _pruneDirectory(internalDir);
      } catch (e) {
        debugPrint('تعذر تنظيف النسخ الفورية الداخلية: $e');
      }

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
        } else if (p.normalize(folder) != p.normalize(internalDir.path)) {
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
