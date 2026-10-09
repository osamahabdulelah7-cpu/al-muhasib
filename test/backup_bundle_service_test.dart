import 'dart:convert';
import 'dart:io';

import 'package:al_muhasib/main.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Future<File> _makeBundle({bool corruptPayload = false}) async {
  final database = <int>[1, 2, 3, 4, 5, 6];
  final payload = <int>[10, 20, 30, 40];
  final archive = Archive()
    ..addFile(ArchiveFile(
      'database/al_muhasib_final_v6.db',
      database.length,
      database,
    ))
    ..addFile(ArchiveFile('app_data/example.bin', payload.length, payload));

  final manifest = <String, dynamic>{
    'format': 'al_muhasib_backup',
    'formatVersion': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'databaseSha256': sha256.convert(database).toString(),
    'databaseSize': database.length,
    'schemaVersion': 10,
    'files': [
      {
        'path': 'database/al_muhasib_final_v6.db',
        'size': database.length,
        'sha256': sha256.convert(database).toString(),
      },
      {
        'path': 'app_data/example.bin',
        'size': payload.length,
        'sha256': sha256.convert(corruptPayload ? <int>[99, 20, 30, 40] : payload).toString(),
      },
    ],
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  final encoded = ZipEncoder().encode(archive)!;
  final dir = await Directory.systemTemp.createTemp('al_muhasib_test_');
  final file = File('${dir.path}/test.alb');
  await file.writeAsBytes(encoded, flush: true);
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupBundleService.verifyBundle', () {
    test('accepts a valid bundle with matching SHA-256 checksums', () async {
      final file = await _makeBundle();
      try {
        expect(await BackupBundleService.verifyBundle(file), isTrue);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects a bundle whose payload checksum does not match', () async {
      final file = await _makeBundle(corruptPayload: true);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await file.parent.delete(recursive: true);
      }
    });

    test('rejects a file that is not a ZIP backup', () async {
      final dir = await Directory.systemTemp.createTemp('al_muhasib_bad_');
      final file = File('${dir.path}/broken.alb');
      await file.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      try {
        expect(await BackupBundleService.verifyBundle(file), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
