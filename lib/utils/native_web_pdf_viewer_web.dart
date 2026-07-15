import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class NativeWebPdfViewer extends StatefulWidget {
  final Uint8List bytes;
  const NativeWebPdfViewer({Key? key, required this.bytes}) : super(key: key);

  @override
  _NativeWebPdfViewerState createState() => _NativeWebPdfViewerState();
}

class _NativeWebPdfViewerState extends State<NativeWebPdfViewer> {
  late String viewId;
  String? objectUrl;

  @override
  void initState() {
    super.initState();
    viewId = 'pdf-viewer-${DateTime.now().millisecondsSinceEpoch}';
    final blob = html.Blob([widget.bytes], 'application/pdf');
    objectUrl = html.Url.createObjectUrlFromBlob(blob);
    
    ui_web.platformViewRegistry.registerViewFactory(
      viewId,
      (int viewId) => html.IFrameElement()
        ..src = objectUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
    );
  }

  @override
  void dispose() {
    if (objectUrl != null) {
      html.Url.revokeObjectUrl(objectUrl!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewId);
  }
}
