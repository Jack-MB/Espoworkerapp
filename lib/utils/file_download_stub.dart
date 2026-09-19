import 'dart:typed_data';

Future<void> downloadFileWeb(Uint8List bytes, String fileName, String mimeType) async {
  throw UnsupportedError('Only supported on Web');
}

Future<void> viewFileWeb(Uint8List bytes, String mimeType) async {
  throw UnsupportedError('Only supported on Web');
}
