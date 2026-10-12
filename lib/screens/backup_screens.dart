part of '../main.dart';

class BackupOptionsScreen extends StatelessWidget {
  const BackupOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          ListTile(
            tileColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smartphone, color: AppColors.green, size: 30),
            ),
            title: const Text('من الهاتف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            subtitle: const Text('مجلد الحفظ والنسخ المحلي والاستعادة والنسخ التلقائي'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AutoBackupScreen())),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.drive.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.cloud, color: AppColors.drive, size: 30),
            ),
            title: const Text('من Google Drive', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            subtitle: const Text('النسخ إلى Google Drive والاستعادة منه'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AutoBackupScreen())),
          ),
        ],
      ),
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
      final listError = GoogleDriveService.lastListBackupsError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(listError ?? 'لا توجد نسخ احتياطية على Google Drive'),
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
  final bool driveOnly;
  const AutoBackupScreen({super.key, this.driveOnly = false});

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
  bool _hasExactAlarm = false;
  bool _scheduledTimeEnabled = true;
  bool _repeatEnabled = false;
  int _repeatValue = 60;
  String _repeatUnit = 'minutes';
  final TextEditingController _repeatController = TextEditingController(text: '60');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _repeatController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await AutoBackupService.getSettings();
    final count = await AutoBackupService.countBackups();
    final driveCount = await AutoBackupService.countDriveBackups();
    final signedIn = GoogleDriveService.isSignedIn ||
        await GoogleDriveService.trySilentSignIn();
    final hasExact = await AutoBackupService.hasExactAlarmPermission();
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
      _hasExactAlarm = hasExact;
      _scheduledTimeEnabled = settings['scheduledTimeEnabled'] == true;
      _repeatEnabled = settings['repeatEnabled'] == true;
      _repeatValue = settings['repeatValue'] as int? ?? 60;
      _repeatController.text = _repeatValue.toString();
      _repeatUnit = settings['repeatUnit'] as String? ?? 'minutes';
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
    // The scheduler is shared by local and Drive backups. Disabling one
    // destination must not cancel jobs still needed by the other.
    final latest = await AutoBackupService.getSettings();
    if (latest['enabled'] == true || latest['driveEnabled'] == true) {
      await AutoBackupService.scheduleDailyBackup();
    } else {
      await AutoBackupService.cancelDailyBackup();
    }
  }

  Future<bool> _pickFolder() async {
    try {
      final selected = await Saf().pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (selected == null) return false;
      final setting = 'saf:${selected.uri}';
      await AutoBackupService.saveSettings(folderPath: setting);
      if (!mounted) return true;
      setState(() => _folderPath = setting);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ تم منح صلاحية مستمرة لمجلد النسخ المحدد'),
          backgroundColor: AppColors.green));
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر تحديد مجلد بطاقة SD: $e'),
          backgroundColor: AppColors.red,
        ));
      }
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

  Future<void> _showRestoreOptionsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة النسخة الاحتياطية'),
        content: const Text('اختر مصدر النسخة التي تريد استعادتها.'),
        actions: [
          TextButton.icon(
            onPressed: () { Navigator.pop(ctx); _showAppRestoreList(); },
            icon: const Icon(Icons.storage),
            label: const Text('من التطبيق'),
          ),
          ElevatedButton.icon(
            onPressed: () { Navigator.pop(ctx); _restoreFromPhone(); },
            icon: const Icon(Icons.folder_open),
            label: const Text('من الهاتف'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ],
      ),
    );
  }

  Future<void> _showAppRestoreList() async {
    final dir = await AutoBackupService.internalBackupDirectory();
    final files = (await dir.list().where((entity) => entity is File).cast<File>().toList())
        .where((file) => p.extension(file.path).toLowerCase() == '.alb')
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا توجد نسخ محفوظة داخل التطبيق'),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('النسخ المحفوظة داخل التطبيق'),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (ctx, index) {
              final file = files[index];
              return ListTile(
                leading: const Icon(Icons.backup),
                title: Text(p.basename(file.path)),
                subtitle: FutureBuilder<int>(
                  future: file.length(),
                  builder: (ctx, snapshot) => Text(snapshot.hasData
                      ? (snapshot.data! / 1024).toStringAsFixed(1) + ' KB'
                      : 'جارٍ قراءة الحجم...'),
                ),
                onTap: () { Navigator.pop(ctx); _restoreLocalBackupFile(file); },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))],
      ),
    );
  }

  Future<void> _restoreFromPhone() async {
    try {
      // Avoid Android document-provider failures from FileType.custom filters.
      // Pick first, then validate the extension and bundle before restoring.
      final selected = await Saf().pickFile(
        mimeTypes: ['*/*'],
        persistablePermission: false,
      );
      if (selected == null) return;
      if (p.extension(selected.name).toLowerCase() != '.alb') {
        throw Exception('اختر ملف نسخة احتياطية بامتداد .alb');
      }
      final tempDir = await getTemporaryDirectory();
      final localCopy = File(p.join(tempDir.path,
          'restore_${DateTime.now().microsecondsSinceEpoch}_${p.basename(selected.name)}'));
      await Saf().copyToLocalFile(selected.uri, localCopy.path);
      try {
        await _restoreLocalBackupFile(localCopy);
      } finally {
        try { if (await localCopy.exists()) await localCopy.delete(); } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذرت قراءة النسخة: ' + e.toString()),
        backgroundColor: AppColors.red,
      ));
    }
  }

  Future<void> _restoreLocalBackupFile(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text('سيتم استبدال البيانات الحالية. هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!await BackupBundleService.verifyBundle(file)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ملف النسخة غير صالح أو تالف؛ لم يتم تغيير البيانات.'),
        backgroundColor: AppColors.red,
      ));
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final safetyError = await AutoBackupService.runInternalBackupNow();
      if (safetyError != null) throw Exception('تعذر إنشاء نسخة أمان: ' + safetyError);
      await BackupBundleService.restoreBundle(file);
      if (mounted) {
        try {
          await Provider.of<AppAccountProvider>(context, listen: false)
              .loadInitialData();
        } catch (refreshError) {
          debugPrint('تمت الاستعادة لكن تعذر تحديث واجهة البيانات: $refreshError');
        }
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تمت الاستعادة بنجاح'),
          backgroundColor: AppColors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشلت الاستعادة: ' + e.toString()),
          backgroundColor: AppColors.red,
        ));
      }
    }
  }

  Future<void> _runBackupNow() async {
    // A folder on shared storage is optional: the app always keeps a verified
    // internal snapshot even if the user has not granted an external folder.
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

    // Local and Drive backups share the same background scheduler.
    final latest = await AutoBackupService.getSettings();
    if (latest['enabled'] == true || latest['driveEnabled'] == true) {
      await AutoBackupService.scheduleDailyBackup();
    } else {
      await AutoBackupService.cancelDailyBackup();
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
      final listError = GoogleDriveService.lastListBackupsError;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(listError ?? 'لا توجد نسخ على Drive'),
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
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: AppColors.drive),
      ),
    );
    File? file;
    var message = '❌ فشل الاستعادة';
    var success = false;
    try {
      file = await GoogleDriveService.downloadBackup(
        backup['id'] as String,
        backup['name'] as String,
      );
      if (file == null) {
        throw Exception(GoogleDriveService.lastDownloadError ?? 'فشل تنزيل النسخة من Google Drive');
      }

      if (p.extension(file.path).toLowerCase() == '.alb' &&
          !await BackupBundleService.verifyBundle(file)) {
        throw Exception('النسخة الموجودة على Google Drive تالفة؛ لم يتم تغيير البيانات.');
      }

      final safetyError = await AutoBackupService.runInternalBackupNow();
      if (safetyError != null) {
        throw Exception('تعذر إنشاء نسخة أمان قبل الاستعادة: $safetyError');
      }

      final provider = Provider.of<AppAccountProvider>(context, listen: false);
      success = await provider.importBackupFromFile(file);
      if (!success) throw Exception('رفض التطبيق النسخة أو فشل التحقق منها');
      message = '✅ تمت الاستعادة من Drive';
    } catch (e, st) {
      debugPrint('فشل الاستعادة من Drive: $e\n$st');
      message = '❌ فشل الاستعادة: $e';
    } finally {
      if (file != null) {
        try { if (await file.exists()) await file.delete(); } catch (_) {}
      }
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: success ? AppColors.green : AppColors.red,
        ));
        if (success) await _loadSettings();
      }
    }
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

  Future<void> _requestExactAlarm() async {
    final granted = await AutoBackupService.requestExactAlarmPermissionFromUI();
    if (!mounted) return;
    setState(() => _hasExactAlarm = granted);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(granted
          ? '✅ تم تفعيل النسخ الاحتياطي الدقيق'
          : '⚠️ لم يتم تفعيل الصلاحية. النسخ قد يعمل متأخرًا.\n'
              'افتح: الإعدادات ← التطبيقات ← المحاسب ← المنبّهات والتذكيرات.'),
      backgroundColor: granted ? AppColors.green : Colors.orange,
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AppColors.red),
          SizedBox(width: 8),
          Text('حذف الحساب والبيانات'),
        ]),
        content: const Text(
          'سيتم حذف جميع بياناتك نهائيًا:\n'
          '• جميع المعاملات والحسابات\n'
          '• جميع الصور المرفقة\n'
          '• الشعار والبيانات الشخصية\n'
          '• جميع النسخ الاحتياطية على Google Drive\n\n'
          'لا يمكن التراجع. هل أنت متأكد؟',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    final result = await GoogleDriveService.deleteAccountAndData();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.success
          ? 'تم حذف الحساب والبيانات بنجاح'
          : 'حدثت أخطاء:\n${result.errors.join('\n')}'),
      backgroundColor: result.success ? AppColors.green : AppColors.red,
      duration: const Duration(seconds: 8),
    ));
    if (result.success && mounted) Navigator.pop(context);
  }

Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: GradientAppBar(
        title: Text(widget.driveOnly ? 'خيارات حفظ البيانات على Google Drive' : 'خيارات حفظ البيانات'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(children: [
        if (!widget.driveOnly) Container(
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
            title: const Text('النسخ التلقائي للهاتف',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark)),
            subtitle: const Text(
                'نسخ تلقائي إلى مجلد حفظ البيانات عند تفعيل الجدولة',
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
              _folderPath.isEmpty
                  ? 'لم يتم تحديد مجلد'
                  : (_folderPath.startsWith('saf:')
                      ? 'بطاقة SD / مجلد خارجي (صلاحية مستمرة)'
                      : '$_folderPath/'),
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
                    content: SelectableText(
                        _folderPath.startsWith('saf:')
                            ? 'مجلد خارجي محدد عبر Android Storage Access Framework.\nتم حفظ صلاحية الوصول للاستخدام في مهام الخلفية.'
                            : _folderPath,
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
        SwitchListTile(
          value: _scheduledTimeEnabled,
          activeColor: AppColors.primary,
          secondary: const Icon(Icons.schedule, color: Color(0xFF1976D2), size: 28),
          title: const Text('تفعيل تحديد وقت النسخ',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
          subtitle: const Text('تشغيل أو إيقاف النسخ المرتبط بالوقت المحدد'),
          onChanged: (value) async {
            await AutoBackupService.saveSettings(scheduledTimeEnabled: value);
            if (!mounted) return;
            setState(() => _scheduledTimeEnabled = value);
            await AutoBackupService.scheduleDailyBackup();
          },
        ),
        Container(
          color: Colors.white,
          child: ListTile(
            enabled: _scheduledTimeEnabled,
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
        SwitchListTile(
          value: _repeatEnabled,
          activeColor: AppColors.primary,
          secondary: const Icon(Icons.repeat, color: Color(0xFF1976D2), size: 28),
          title: const Text('تفعيل تكرار النسخ التلقائي',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
          subtitle: Text('التكرار الحالي: كل ' + _repeatValue.toString() + ' ' + (_repeatUnit == 'hours' ? 'ساعة' : _repeatUnit == 'days' ? 'يوم' : 'دقيقة')),
          onChanged: (value) async {
            await AutoBackupService.saveSettings(repeatEnabled: value);
            if (!mounted) return;
            setState(() => _repeatEnabled = value);
            await AutoBackupService.scheduleDailyBackup();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _repeatController,
                enabled: _repeatEnabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'قيمة فترة التكرار',
                  helperText: 'الحد الأدنى الفعلي على Android هو 15 دقيقة',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (text) async {
                  final parsed = int.tryParse(text);
                  if (parsed == null || parsed < 1 || parsed > 10080) {
                    _repeatController.text = _repeatValue.toString();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل رقمًا من 1 إلى 10080')));
                    return;
                  }
                  setState(() => _repeatValue = parsed);
                  await AutoBackupService.saveSettings(repeatValue: parsed);
                  await AutoBackupService.scheduleDailyBackup();
                },
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _repeatUnit,
              items: const [
                DropdownMenuItem(value: 'minutes', child: Text('دقيقة')),
                DropdownMenuItem(value: 'hours', child: Text('ساعة')),
                DropdownMenuItem(value: 'days', child: Text('يوم')),
              ],
              onChanged: _repeatEnabled ? (unit) async {
                if (unit == null) return;
                setState(() => _repeatUnit = unit);
                await AutoBackupService.saveSettings(repeatUnit: unit);
                await AutoBackupService.scheduleDailyBackup();
              } : null,
            ),
          ]),
        ),
        const Divider(height: 1),
        if (_enabled && !_hasExactAlarm)
          Container(
            color: Colors.orange.shade50,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لضمان عمل النسخ في الوقت المحدد، يلزم تفعيل صلاحية "المنبّهات والتذكيرات".',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _requestExactAlarm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.alarm_on),
                    label: const Text('تفعيل النسخ الدقيق', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        if (_enabled && _hasExactAlarm)
          Container(
            color: AppColors.greenLight,
            padding: const EdgeInsets.all(10),
            child: Row(children: const [
              Icon(Icons.check_circle, color: AppColors.green, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('النسخ الدقيق مفعّل ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.greenDark)),
              ),
            ]),
          ),
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
        if (_enabled && _folderPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _showRestoreOptionsDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.restore),
              label: const Text('استعادة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        if (_signedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: OutlinedButton.icon(
              onPressed: _confirmDeleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.delete_forever),
              label: const Text('حذف الحساب وجميع البيانات',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ==================== CustomerDetailsScreen ====================
