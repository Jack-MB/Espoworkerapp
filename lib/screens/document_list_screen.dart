import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/document.dart';
import '../models/document_folder.dart';
import 'document_viewer_screen.dart';

class DocumentListScreen extends StatefulWidget {
  final DocumentFolder? folder;
  const DocumentListScreen({Key? key, this.folder}) : super(key: key);

  @override
  _DocumentListScreenState createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends State<DocumentListScreen> {
  final ApiService _apiService = ApiService();
  Future<List<DocumentFolder>>? _foldersFuture;
  Future<List<EspoDocument>>? _documentsFuture;
  Future<List<Map<String, dynamic>>>? _dienstanweisungenFuture;
  final TextEditingController _daSearchController = TextEditingController();
  String _daSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _daSearchController.addListener(() {
      setState(() => _daSearchQuery = _daSearchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _daSearchController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      if (widget.folder == null) {
        _foldersFuture = _apiService.getDocumentFolders();
        _dienstanweisungenFuture = _apiService.getDienstanweisungen();
      }
      _documentsFuture = _apiService.getDocuments(folderId: widget.folder?.id);
    });
  }

  String _formatDate(dynamic dtStr) {
    if (dtStr == null || dtStr.toString().isEmpty) return '-';
    try {
      final dt = DateTime.parse(dtStr.toString());
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return dtStr.toString();
    }
  }

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showDienstanweisungDetail(Map<String, dynamic> da) {
    final name = da['name'] ?? 'Dienstanweisung';
    final inhalt = da['inhalt'] as String? ?? '';
    final version = da['version']?.toString() ?? '1.0';
    final gueltigAb = _formatDate(da['gueltigAb']);
    final status = da['status']?.toString() ?? 'Aktiv';
    final serviceObj = da['serviceObjectName'] ?? da['serviceObject'];
    final dokId = da['dokumentId'] as String?;
    final dokName = da['dokumentName'] as String? ?? '$name.pdf';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Top Bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Version $version · Gültig ab: $gueltigAb', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  if (serviceObj != null && serviceObj.toString().isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.business, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text('Objekt: $serviceObj', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (inhalt.isNotEmpty) ...[
                    Html(
                      data: inhalt,
                      style: {
                        'body': Style(fontSize: FontSize(14), lineHeight: const LineHeight(1.5)),
                      },
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Kein Fließtext hinterlegt.', style: TextStyle(color: Colors.grey))),
                    ),
                  ],
                  if (dokId != null && dokId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text('Original-Dokument öffnen ($dokName)'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DocumentViewerScreen(
                              document: EspoDocument(
                                id: dokId,
                                name: dokName,
                                status: 'Active',
                                fileId: dokId,
                                fileName: dokName,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeineDokumenteView() {
    return CustomScrollView(
      slivers: [
        if (widget.folder == null)
          FutureBuilder<List<DocumentFolder>>(
            future: _foldersFuture ?? Future.value([]),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
              final folders = snapshot.data!;
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final folder = folders[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: ListTile(
                        leading: Icon(Icons.folder, color: Colors.amber.shade700, size: 36),
                        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DocumentListScreen(folder: folder)),
                          );
                        },
                      ),
                    );
                  },
                  childCount: folders.length,
                ),
              );
            },
          ),
        
        if (widget.folder == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Alle / Kürzliche Dokumente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
            ),
          ),

        FutureBuilder<List<EspoDocument>>(
          future: _documentsFuture ?? Future.value([]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24), 
                    child: Text(widget.folder == null ? 'Keine kürzlichen Dokumente.' : 'Dieser Ordner ist leer.')
                  )
                )
              );
            }
            final docs = snapshot.data!;
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = docs[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Icon(Icons.insert_drive_file, color: Theme.of(context).primaryColor),
                      ),
                      title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(doc.fileName ?? "-"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (doc.fileId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DocumentViewerScreen(document: doc)),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine Datei hinterlegt.')));
                        }
                      },
                    ),
                  );
                },
                childCount: docs.length,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDienstanweisungenView() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dienstanweisungenFuture ?? Future.value([]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
        }
        final all = snapshot.data ?? [];
        final filtered = all.where((da) {
          if (_daSearchQuery.isEmpty) return true;
          final name = (da['name'] ?? '').toString().toLowerCase();
          final inhalt = (da['inhalt'] ?? '').toString().toLowerCase();
          final obj = (da['serviceObjectName'] ?? '').toString().toLowerCase();
          return name.contains(_daSearchQuery) || inhalt.contains(_daSearchQuery) || obj.contains(_daSearchQuery);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _daSearchController,
                decoration: InputDecoration(
                  hintText: 'Dienstanweisungen durchsuchen…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _daSearchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _daSearchController.clear())
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (filtered.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    all.isEmpty ? 'Keine Dienstanweisungen hinterlegt.' : 'Keine passenden Dienstanweisungen gefunden.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final da = filtered[index];
                    final name = da['name'] ?? 'Dienstanweisung';
                    final inhalt = _stripHtml(da['inhalt'] as String?);
                    final version = da['version']?.toString() ?? '1.0';
                    final gueltigAb = _formatDate(da['gueltigAb']);
                    final dokId = da['dokumentId'] as String?;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showDienstanweisungDetail(da),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFF1a3c5e).withOpacity(0.1),
                                    child: const Icon(Icons.policy, color: Color(0xFF1a3c5e), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blueGrey.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text('v$version', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text('Gültig ab: $gueltigAb', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                            if (dokId != null) ...[
                                              const SizedBox(width: 8),
                                              const Icon(Icons.attach_file, size: 14, color: Colors.grey),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ],
                              ),
                              if (inhalt.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  inhalt,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.folder != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.folder!.name),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
            ),
          ],
        ),
        body: _buildMeineDokumenteView(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dokumente & Richtlinien'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.folder_shared, size: 20), text: 'Meine Dokumente'),
              Tab(icon: Icon(Icons.policy, size: 20), text: 'Dienstanweisungen'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMeineDokumenteView(),
            _buildDienstanweisungenView(),
          ],
        ),
      ),
    );
  }
}
