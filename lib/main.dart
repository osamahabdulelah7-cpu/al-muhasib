import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
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
import 'package:arabic_pdf_fixer/arabic_pdf_fixer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:saf/saf.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel_community/excel_community.dart' as excel_lib;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:archive/archive.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:telephony/telephony.dart';


part 'services/common_services.dart';
part 'services/backup_services.dart';
part 'services/auto_backup_service.dart';
part 'services/instant_backup_service.dart';
part 'data/app_database.dart';
part 'data/app_account_provider.dart';
part 'screens/app_shell.dart';
part 'screens/app_lock_screen.dart';
part 'screens/home_screen.dart';
part 'screens/backup_screens.dart';
part 'screens/customer_details_screen.dart';
part 'screens/management_screens.dart';

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
      await CustomerSmsAutoService.schedule();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تهيئة WorkManager أو جدولة رسائل العملاء: $e\n$st');
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
      // Reconcile the persisted WorkManager schedule on startup.
      await AutoBackupService.scheduleDailyBackup();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تشغيل مهام النسخ الاحتياطي عند بدء التطبيق: $e\n$st');
    }

    // نسخ أي تعديل سابق لم يُنسخ لأن التطبيق أُغلق قبل تنفيذ النسخ الفوري.
    try {
      await InstantBackupService.flushIfPending();
    } catch (e, st) {
      debugPrint('⚠️ تعذر تشغيل النسخ الفوري عند بدء التطبيق: $e\n$st');
    }
  }, (error, stack) {
    debugPrint('ZoneError: $error\n$stack');
  });
}

// ==================== AppDBHelper ====================
