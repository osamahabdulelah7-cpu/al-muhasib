import 'dart:convert';

import 'package:arabic_pdf_fixer/arabic_pdf_fixer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arabic PDF shaping handles standalone and final yeh forms', () async {
    final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    final regular = ShapedFont.fromBytes(
      regularData.buffer.asUint8List(),
      name: 'Cairo Regular test',
    );
    final bold = ShapedFont.fromBytes(
      boldData.buffer.asUint8List(),
      name: 'Cairo Bold test',
    );

    try {
      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              ArabicText('ي', font: regular, fontSize: 18),
              ArabicText('ى', font: regular, fontSize: 18),
              // Regression cases: yeh after Arabic letters that do not join
              // to the following letter, plus common words ending in yeh/ى.
              ArabicText('دري ذكي رأي زمي قوي', font: regular, fontSize: 18),
              ArabicText('هدى فتى مصطفى على', font: regular, fontSize: 18),
              ArabicText('كشف حساب: ي ى دري ذكي رأي', font: bold, fontSize: 18),
            ],
          ),
        ),
      );

      final bytes = await document.save();
      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    } finally {
      regular.dispose();
      bold.dispose();
    }
  });
}
