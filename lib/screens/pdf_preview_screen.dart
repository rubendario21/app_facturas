import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Vista previa de un PDF (factura o recibo) con botones para imprimir y
/// compartir/guardar.
class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final String fileName;
  final Future<Uint8List> Function() builder;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (_) => builder(),
        pdfFileName: fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
