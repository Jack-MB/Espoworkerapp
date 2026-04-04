import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/document.dart';
import 'document_viewer_screen.dart';
import '../core/constants.dart';

class DocumentListScreen extends StatefulWidget {
  const DocumentListScreen({Key? key}) : super(key: key);

  @override
  _DocumentListScreenState createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<EspoDocument>> _documentsFuture;

  @override
  void initState() {
    super.initState();
    _documentsFuture = _apiService.getDocuments();
  }

  void _loadData() {
    setState(() {
      _documentsFuture = _apiService.getDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dokumente'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<EspoDocument>>(
        future: _documentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Dokumente gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final doc = list[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Icon(Icons.file_present, color: Theme.of(context).primaryColor),
                  ),
                  title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(doc.fileName ?? "-"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (doc.fileId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DocumentViewerScreen(document: doc),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Keine Datei hinterlegt.')),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
