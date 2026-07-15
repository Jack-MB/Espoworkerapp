import 'package:flutter/material.dart';
import 'dart:typed_data';

class NativeWebPdfViewer extends StatelessWidget {
  final Uint8List bytes;
  const NativeWebPdfViewer({Key? key, required this.bytes}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Only supported on web'));
  }
}
