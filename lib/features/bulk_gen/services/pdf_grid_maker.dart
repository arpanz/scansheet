import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../single_gen/models/generator_type.dart';

class PdfGridMaker {
  /// Generates a PDF document with barcodes/QRs arranged in a grid.
  /// Default format: 4 rows by 3 columns per page (12 labels per page).
  static Future<Uint8List> generateGridPdf({
    required List<List<dynamic>> data,
    required GeneratorType type,
    String paperSize = 'A4',
    bool includeLabels = true,
    int rows = 4,
    int cols = 3,
    int codeColorArgb = 0xFF000000,
    int codeBackgroundArgb = 0xFFFFFFFF,
    int labelColorArgb = 0xFF000000,
    int cardBorderColorArgb = 0xFFBDBDBD,
    bool qrFrameEnabled = false,
    double qrFrameThickness = 2,
    int qrFrameColorArgb = 0xFF000000,
  }) async {
    return await compute(_buildPdf, {
      'data': data,
      'type': type,
      'paperSize': paperSize,
      'includeLabels': includeLabels,
      'rows': rows,
      'cols': cols,
      'codeColorArgb': codeColorArgb,
      'codeBackgroundArgb': codeBackgroundArgb,
      'labelColorArgb': labelColorArgb,
      'cardBorderColorArgb': cardBorderColorArgb,
      'qrFrameEnabled': qrFrameEnabled,
      'qrFrameThickness': qrFrameThickness,
      'qrFrameColorArgb': qrFrameColorArgb,
    });
  }

  static Future<Uint8List> _buildPdf(Map<String, dynamic> args) async {
    final List<List<dynamic>> data = args['data'];
    final GeneratorType type = args['type'];
    final String paperSize = args['paperSize'] ?? 'A4';
    final bool includeLabels = args['includeLabels'] ?? true;
    final int rows = args['rows'] ?? 4;
    final int cols = args['cols'] ?? 3;
    final PdfColor codeColor = PdfColor.fromInt(
      args['codeColorArgb'] ?? 0xFF000000,
    );
    final PdfColor codeBgColor = PdfColor.fromInt(
      args['codeBackgroundArgb'] ?? 0xFFFFFFFF,
    );
    final PdfColor labelColor = PdfColor.fromInt(
      args['labelColorArgb'] ?? 0xFF000000,
    );
    final PdfColor cardBorderColor = PdfColor.fromInt(
      args['cardBorderColorArgb'] ?? 0xFFBDBDBD,
    );
    final bool qrFrameEnabled = args['qrFrameEnabled'] ?? false;
    final double qrFrameThickness = (args['qrFrameThickness'] ?? 2).toDouble();
    final PdfColor qrFrameColor = PdfColor.fromInt(
      args['qrFrameColorArgb'] ?? 0xFF000000,
    );

    final pdf = pw.Document();
    final int safeRows = rows <= 0 ? 4 : rows;
    final int safeCols = cols <= 0 ? 3 : cols;
    final int itemsPerPage = safeCols * safeRows;

    for (int i = 0; i < data.length; i += itemsPerPage) {
      final chunk = data.skip(i).take(itemsPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: paperSize == 'US Letter'
              ? PdfPageFormat.letter
              : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (context) {
            return pw.GridView(
              crossAxisCount: safeCols,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: 1.0,
              children: chunk.map((row) {
                final String labelText = row[0].toString();
                final String barcodeData = row[1].toString();

                return pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: cardBorderColor, width: 1),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Expanded(
                        child: pw.Center(
                          child: _buildPdfBarcode(
                            barcodeData,
                            type,
                            qrBytes: row.length > 2 && row[2] is Uint8List
                                ? row[2] as Uint8List
                                : null,
                            codeColor: codeColor,
                            codeBackgroundColor: codeBgColor,
                            qrFrameEnabled: qrFrameEnabled,
                            qrFrameThickness: qrFrameThickness,
                            qrFrameColor: qrFrameColor,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      if (includeLabels)
                        pw.Text(
                          labelText,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: labelColor,
                          ),
                          maxLines: 2,
                          textAlign: pw.TextAlign.center,
                        ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  static pw.Widget _buildPdfBarcode(
    String data,
    GeneratorType type, {
    Uint8List? qrBytes,
    required PdfColor codeColor,
    required PdfColor codeBackgroundColor,
    required bool qrFrameEnabled,
    required double qrFrameThickness,
    required PdfColor qrFrameColor,
  }) {
    try {
      if (type == GeneratorType.qrCode && qrBytes != null) {
        final image = pw.MemoryImage(qrBytes);
        return pw.Container(
          decoration: qrFrameEnabled
              ? pw.BoxDecoration(
                  border: pw.Border.all(
                    color: qrFrameColor,
                    width: qrFrameThickness.clamp(0, 10),
                  ),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(12),
                  ),
                )
              : null,
          padding: pw.EdgeInsets.all(qrFrameEnabled ? qrFrameThickness + 4 : 0),
          child: pw.Image(
            image,
            width: 100,
            height: 100,
            fit: pw.BoxFit.contain,
          ),
        );
      }

      pw.Barcode barcode;
      switch (type) {
        case GeneratorType.qrCode:
          barcode = pw.Barcode.qrCode();
          break;
        case GeneratorType.code128:
          barcode = pw.Barcode.code128();
          break;
        case GeneratorType.ean13:
          barcode = pw.Barcode.ean13();
          break;
        case GeneratorType.upcA:
          barcode = pw.Barcode.upcA();
          break;
      }

      return pw.BarcodeWidget(
        barcode: barcode,
        data: data,
        width: type == GeneratorType.qrCode ? 100 : 150,
        height: type == GeneratorType.qrCode ? 100 : 60,
        color: codeColor,
        backgroundColor: type == GeneratorType.qrCode
            ? codeBackgroundColor
            : null,
        drawText:
            type !=
            GeneratorType
                .qrCode, // QRs don't need text below them inside the widget
        textStyle: const pw.TextStyle(fontSize: 10),
      );
    } catch (e) {
      return pw.Text(
        'Invalid Data',
        style: const pw.TextStyle(color: PdfColors.red),
      );
    }
  }
}
