import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/document.dart';
import '../core/constants.dart';
import '../services/secure_storage_service.dart';

class DocumentViewerScreen extends StatefulWidget {
  final EspoDocument document;

  const DocumentViewerScreen({Key? key, required this.document}) : super(key: key);

  @override
  _DocumentViewerScreenState createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final SecureStorageService _storageService = SecureStorageService();
  bool _isLoading = false;
  Map<String, String>? _headers;
  String? _downloadUrl;

  @override
  void initState() {
    super.initState();
    _prepareHeaders();
  }

  Future<void> _prepareHeaders() async {
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
    
    setState(() {
      _headers = headers;
      _downloadUrl = '${AppConstants.baseUrl}/?entryPoint=download&id=${widget.document.fileId}';
    });
  }

  Future<void> _downloadAndOpenFile() async {
    if (_downloadUrl == null || _headers == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(Uri.parse(_downloadUrl!), headers: _headers!);
      
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.document.fileName ?? "document"}');
        await file.writeAsBytes(response.bodyBytes);
        
        await OpenFilex.open(file.path);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download fehlgeschlagen.')),
        );
      }
    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Öffnen der Datei.')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_headers == null || _downloadUrl == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.document.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ext = widget.document.fileName?.toLowerCase() ?? '';
    final isPdf = ext.endsWith('.pdf');
    final isImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.name),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloadAndOpenFile,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : (isPdf
            ? SfPdfViewer.network(
                _downloadUrl!,
                headers: _headers,
              )
            : (isImage
                ? Center(
                    child: InteractiveViewer(
                      child: Image.network(
                        _downloadUrl!,
                        headers: _headers,
                      ),
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
                          child: const Text('Mit nativer App öffnen / Speichern'),
                        ),
                      ],
                    ),
                  ))),
    );
  }
}
