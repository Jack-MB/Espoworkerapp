import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../core/constants.dart';
import '../core/server_config.dart';
import '../services/secure_storage_service.dart';
import '../utils/file_download.dart';

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
      final response = await http.get(Uri.parse(url), headers: headers);
      
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
      if (widget.document.type == 'Lohnabrechnung' || widget.document.type == 'SV-Meldung' || widget.document.type == 'Lohnsteuerbescheinigung') {
        fileName += '.pdf';
      } else {
        fileName += '.pdf'; // Default fallback just in case
      }
    }

    if (kIsWeb) {
      // On Web, use our custom dart:html implementation to trigger a real download
      try {
        final ext = fileName.split('.').last.toLowerCase();
        String mimeType = 'application/octet-stream';
        if (ext == 'pdf') mimeType = 'application/pdf';
        if (ext == 'png') mimeType = 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
        
        await downloadFileWeb(_documentBytes!, fileName, mimeType);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download im Browser fehlgeschlagen.')),
        );
      }
      return;
    }

    // Mobile platforms
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(_documentBytes!);
      
      await OpenFilex.open(file.path);
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Öffnen/Speichern der Datei.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var ext = widget.document.fileName?.toLowerCase() ?? '';
    if (ext.isEmpty || !ext.contains('.')) {
       ext = '.pdf'; // Default fallback for rendering logic
    }
    final isPdf = ext.endsWith('.pdf');
    final isImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.name),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading && _documentBytes != null)
            IconButton(
              icon: const Icon(Icons.download),
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
                    ? SfPdfViewer.memory(_documentBytes!)
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
