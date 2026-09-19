import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/document.dart';
import '../core/constants.dart';
import '../core/server_config.dart';
import '../services/secure_storage_service.dart';
import '../utils/file_download.dart';
import '../utils/native_web_pdf_viewer.dart';

class DocumentViewerScreen extends StatefulWidget {
  final EspoDocument document;

  const DocumentViewerScreen({Key? key, required this.document}) : super(key: key);

  @override
  _DocumentViewerScreenState createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final SecureStorageService _storageService = SecureStorageService();
  bool _isLoading = true;
  Uint8List? _documentBytes;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchDocumentBytes();
  }

  Future<void> _fetchDocumentBytes() async {
    try {
      final token = await _storageService.getToken();
      final Map<String, String> headers = {};
      if (token != null) {
        if (token.startsWith('Basic ')) {
          headers['Authorization'] = token;
        } else if (token.startsWith('ApiKey ')) {
          headers['X-Api-Key'] = token.replaceAll('ApiKey ', '');
        } else {
          headers['X-Auth-Token'] = token;
        }
      }
      
      final url = '${ServerConfig().baseUrl}/?entryPoint=download&id=${widget.document.fileId}';
      final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
      
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _documentBytes = response.bodyBytes;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Fehler beim Laden (Status: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Verbindungsfehler: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndOpenFile() async {
    if (_documentBytes == null) return;
    
    var fileName = widget.document.fileName ?? "document";
    if (!fileName.contains('.')) {
      fileName += '.pdf';
    }

    if (kIsWeb) {
      try {
        final ext = fileName.split('.').last.toLowerCase();
        String mimeType = 'application/octet-stream';
        if (ext == 'pdf') mimeType = 'application/pdf';
        if (ext == 'png') mimeType = 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
        
        await downloadFileWeb(_documentBytes!, fileName, mimeType);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download im Browser fehlgeschlagen.')),
        );
      }
      return;
    }

    // Native Mobile
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(_documentBytes!);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Öffnen/Speichern der Datei.')),
      );
    }
  }

  /// Platform-aware PDF viewer:
  /// - Desktop Web (Windows/Mac/Linux): native iframe via NativeWebPdfViewer
  /// - Mobile Web (Android/iOS): button to open in browser tab
  /// - Native App: SfPdfViewer
  Widget _buildPdfView() {
    if (kIsWeb) {
      final isMobile = defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

      if (isMobile) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.picture_as_pdf, size: 80, color: Color(0xFF1565C0)),
                const SizedBox(height: 24),
                const Text(
                  'PDF-Vorschau',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tippe auf das Browser-Symbol oben rechts\num das Dokument anzuzeigen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Im Browser öffnen'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () async {
                    var fileName = widget.document.fileName ?? 'document.pdf';
                    if (!fileName.contains('.')) fileName += '.pdf';
                    final ext = fileName.split('.').last.toLowerCase();
                    final mimeType = ext == 'pdf' ? 'application/pdf' : 'application/octet-stream';
                    try {
                      await viewFileWeb(_documentBytes!, mimeType);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
        );
      } else {
        // Desktop Web: embedded iframe with blob URL — works perfectly in Chrome/Edge/Firefox
        return NativeWebPdfViewer(bytes: _documentBytes!);
      }
    }
    // Native App (Android APK / iOS)
    return SfPdfViewer.memory(_documentBytes!);
  }

  @override
  Widget build(BuildContext context) {
    var ext = widget.document.fileName?.toLowerCase() ?? '';
    if (ext.isEmpty || !ext.contains('.')) {
       ext = '.pdf';
    }
    final isPdf = ext.endsWith('.pdf');
    final isImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.name),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (kIsWeb && !_isLoading && _documentBytes != null)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Im Browser öffnen',
              onPressed: () async {
                var fileName = widget.document.fileName ?? "document";
                if (!fileName.contains('.')) {
                  fileName += '.pdf';
                }
                final ext = fileName.split('.').last.toLowerCase();
                String mimeType = 'application/octet-stream';
                if (ext == 'pdf') mimeType = 'application/pdf';
                if (ext == 'png') mimeType = 'image/png';
                if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
                
                try {
                  await viewFileWeb(_documentBytes!, mimeType);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Fehler beim Öffnen im Browser.')),
                  );
                }
              },
            ),
          if (!_isLoading && _documentBytes != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Herunterladen / Öffnen',
              onPressed: _downloadAndOpenFile,
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage.isNotEmpty
            ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
            : _documentBytes == null 
                ? const Center(child: Text('Leeres Dokument.'))
                : (isPdf
                    ? _buildPdfView()
                    : (isImage
                        ? Center(
                            child: InteractiveViewer(
                              child: Image.memory(_documentBytes!),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.insert_drive_file, size: 80, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text('Dateityp/Endung: $ext'),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _downloadAndOpenFile,
                                  child: const Text('Speichern / Öffnen'),
                                ),
                              ],
                            ),
                          ))),
    );
  }
}
