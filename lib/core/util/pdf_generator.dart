import 'package:flutter/material.dart' hide TableRow;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  static Future<void> generateAndDownloadPdf({
    required BuildContext context,
    required List<dynamic> pdfData,
    required String roomCode,
    required String level,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Lexirush Arena Mission',
                      style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Room: $roomCode',
                      style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10)),
            pw.Text('Level/Type: $level',
                style: const pw.TextStyle(fontSize: 16)),
            pw.Padding(padding: const pw.EdgeInsets.only(bottom: 20)),
            pw.TableHelper.fromTextArray(
              headers: ['No.', 'Word', 'Meaning', 'Synonyms', 'Antonyms'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellPadding: const pw.EdgeInsets.all(5),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
              },
              data: List<List<String>>.generate(
                pdfData.length,
                (index) {
                  final item = Map<String, dynamic>.from(pdfData[index] as Map);
                  return [
                    '${index + 1}',
                    item['word']?.toString() ?? 'N/A',
                    item['meaning']?.toString() ?? 'N/A',
                    item['synonyms']?.toString() ?? 'N/A',
                    item['antonyms']?.toString() ?? 'N/A',
                  ];
                },
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Lexirush_Mission_$roomCode.pdf',
    );
  }
}
