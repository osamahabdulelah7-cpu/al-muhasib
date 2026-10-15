import 'dart:convert';
import 'dart:io';

import 'package:al_muhasib/main.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<File> _makeBundle({
  bool corruptPayload = false,
  bool unsafePath = false,
  bool undeclaredPayload = false,
  bool duplicateManifestPath = false,
  bool incorrectDatabaseSize = false,
  bool wrongFormat = false,
  bool missingManifest = false,
  bool missingDatabase = false,
}) async {
  final database = <int>[1, 2, 3, 4, 5, 6];
  final payload = <int>[10, 20, 30, 40];
  final payloadPath = unsafePath ? '../outside.bin' : 'app_data/example.bin';
  final archive = Archive();

  if (!missingDatabase) {
    archive.addFile(ArchiveFile(
      'database/al_muhasib_final_v6.db',
      database.length,
      database,
    ));
  }
  archive.addFile(ArchiveFile(payloadPath, payload.length, payload));

  if (undeclaredPayload) {
    archive.addFile(ArchiveFile('app_data/unlisted.bin', 3, <int>[7, 8, 9]));
  }

  final manifest = <String, dynamic>{
    'format': wrongFormat ? 'unknown_format' : 'al_muhasib_backup',
    'formatVersion': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'databaseSha256': sha256.convert(database).toString(),
    'databaseSize':
        incorrectDatabaseSize ? database.length + 1 : database.length,
    'schemaVersion': 10,
    'files': [
      if (!missingDatabase)
        {
          'path': 'database/al_muhasib_final_v6.db',
          'size': database.length,
          'sha256': sha256.convert(database).toString(),
        },
      if (duplicateManifestPath)
        {
          'path': 'database/al_muhasib_final_v6.db',
          'size': database.length,
          'sha256': sha256.convert(database).toString(),
        },
      {
        'path': payloadPath,
        'size': payload.length,
        'sha256': sha256
            .convert(corruptPayload ? <int>[99, 20, 30, 40] : payload)
            .toString(),
      },
    ],
  };

  if (!missingManifest) {
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  }

  final encoded = ZipEncoder().encode(archive)!;
  final dir = await Directory.systemTemp.createTemp('al_muhasib_test_');
  final file = File('${dir.path}/test.alb');
  await file.writeAsBytes(encoded, flush: true);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cleanup stages run sequentially in the declared order', () async {
    final order = <String>[];
    await runCleanupStagesInOrderForTesting([
      () async { order.add('cancel-schedules'); },
      () async { order.add('delete-database'); },
      () async { order.add('delete-files'); },
      () async { order.add('clear-preferences'); },
    ]);
    expect(order, <String>[
      'cancel-schedules',
      'delete-database',
      'delete-files',
      'clear-preferences',
    ]);
  });

  group('AutoBackupService.isAttemptThrottled', () {
    final now = DateTime(2026, 10, 12, 12);

    test('allows the first attempt when no previous attempt exists', () {
      expect(AutoBackupService.isAttemptThrottled(null, now), isFalse);
    });

    test('throttles an attempt made less than 15 minutes ago', () {
      expect(
        AutoBackupService.isAttemptThrottled(
          now.subtract(const Duration(minutes: 14, seconds: 59)),
          now,
        ),
        isTrue,
      );
    });

    test('allows an attempt after the 15-minute interval', () {
      expect(
        AutoBackupService.isAttemptThrottled(
          now.subtract(const Duration(minutes: 15)),
          now,
        ),
        isFalse,
      );
    });

    test('throttles when the saved attempt is in the future', () {
      expect(
        AutoBackupService.isAttemptThrottled(
          now.add(const Duration(minutes: 1)),
          now,
        ),
        isTrue,
      );
    });
  });

  test('countBackups counts external ALB backup files only', () async {
    SharedPreferences.setMockInitialValues({});
    final documents = await Directory.systemTemp.createTemp('backup_count_test_');
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      throw MissingPluginException('Unexpected method: ${call.method}');
    });

    try {
      await AutoBackupService.saveSettings(folderPath: documents.path);
      final backups = Directory('${documents.path}/AlMuhasib/Backups');
      await backups.create(recursive: true);
      await File('${backups.path}/al_muhasib_one.alb').writeAsString('bundle');
      await File('${backups.path}/al_muhasib_two.db').writeAsString('database');
      await File('${backups.path}/al_muhasib_notes.txt').writeAsString('not a backup');

      // Counts are now based on the selected shared destination, and legacy
      // .db files are not counted as verified .alb bundles.
      expect(await AutoBackupService.countBackups(), 1);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await documents.delete(recursive: true);
    }
  });

  group('BackupBundleService.writeEncodedBundleForTesting', () {
    test('returns only a written bundle that passes integrity verification', () async {
      final source = await _makeBundle();
      final output = await Directory.systemTemp.createTemp('verified_bundle_');
      try {
        final result = await BackupBundleService.writeEncodedBundleForTesting(
          await source.readAsBytes(), output);
        expect(await result.exists(), isTrue);
        expect(await BackupBundleService.verifyBundle(result), isTrue);
      } finally {
        await source.parent.delete(recursive: true);
        await output.delete(recursive: true);
      }
    });

    test('removes output when written bytes fail integrity verification', () async {
      final output = await Directory.systemTemp.createTemp('invalid_bundle_');
      try {
        await expectLater(
          BackupBundleService.writeEncodedBundleForTesting(<int>[1, 2, 3, 4], output),
          throwsA(isA<Exception>()),
        );
        expect(await output.list().toList(), isEmpty);
      } finally {
        await output.delete(recursive: true);
      }
    });

    test('fails when the output directory path is an ordinary file', () async {
      final root = await Directory.systemTemp.createTemp('bundle_output_failure_');
      final file = File('${root.path}/not_a_directory');
      await file.writeAsString('keep');
      try {
        await expectLater(
          BackupBundleService.writeEncodedBundleForTesting(<int>[1, 2, 3], Directory(file.path)),
          throwsA(anything),
        );
        expect(await file.readAsString(), 'keep');
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  group('BackupBundleService.verifyBundle', () {
    test('accepts a valid bundle', () async {
      final file = await _makeBundle();
      try {
        expect(await BackupBundleService.verifyBundle(file), isTrue);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects corrupt payload', () async {
      final file = await _makeBundle(corruptPayload: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('refuses to restore corrupt bundle', () async {
      final file = await _makeBundle(corruptPayload: true);
      try {
        await expectLater(
          BackupBundleService.restoreBundle(file),
          throwsA(isA<Exception>()),
        );
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects undeclared payload', () async {
      final file = await _makeBundle(undeclaredPayload: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects duplicate manifest paths', () async {
      final file = await _makeBundle(duplicateManifestPath: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects incorrect database size', () async {
      final file = await _makeBundle(incorrectDatabaseSize: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects a truncated bundle after a previously valid header', () async {
      final source = await _makeBundle();
      final dir = await Directory.systemTemp.createTemp('truncated_bundle_');
      final file = File('${dir.path}/truncated.alb');
      try {
        final bytes = await source.readAsBytes();
        await file.writeAsBytes(bytes.take(24).toList(), flush: true);
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await source.parent.delete(recursive: true);
        await dir.delete(recursive: true);
      }
    });

    test('rejects non-ZIP file', () async {
      final dir = await Directory.systemTemp.createTemp('bad_');
      final file = File('${dir.path}/broken.alb');
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects unsafe relative path', () async {
      final file = await _makeBundle(unsafePath: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects wrong format marker', () async {
      final file = await _makeBundle(wrongFormat: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects missing manifest', () async {
      final file = await _makeBundle(missingManifest: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects missing database', () async {
      final file = await _makeBundle(missingDatabase: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });
  });
}