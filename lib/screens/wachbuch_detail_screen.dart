import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../models/wachbuch.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../core/constants.dart';
import '../services/secure_storage_service.dart';
import '../services/acl_service.dart';
import 'package:intl/intl.dart';

String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

String _formatTimestamp(String? utcString) {
  if (utcString == null || utcString.isEmpty) return '-';
  try {
    // Espo format: "YYYY-MM-DD HH:mm:ss". We add 'Z' to treat it as UTC for parsing.
    final dt = DateTime.parse(utcString.replaceAll(' ', 'T') + 'Z').toLocal();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  } catch (e) {
    return utcString;
  }
}

class WachbuchDetailScreen extends StatefulWidget {
  final Wachbuch wachbuch;
  const WachbuchDetailScreen({Key? key, required this.wachbuch}) : super(key: key);

  @override
  _WachbuchDetailScreenState createState() => _WachbuchDetailScreenState();
}

class _WachbuchDetailScreenState extends State<WachbuchDetailScreen> {
  final ApiService _apiService = ApiService();
  final AclService _aclService = AclService();
  final TextEditingController _noteController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late Future<List<Note>> _notesFuture;

  // Starts with the list-view object; replaced by the full record once loaded
  late Wachbuch _fullWachbuch;
  bool _loadingDetails = true;
  final List<XFile> _pendingFiles = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _fullWachbuch = widget.wachbuch; // show what we have immediately
    _aclService.init().then((_) { if (mounted) setState(() {}); });
    _loadNotes();
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    final full = await _apiService.getWachbuchById(widget.wachbuch.id);
    if (mounted && full != null) {
      setState(() {
        _fullWachbuch = full;
        _loadingDetails = false;
      });
    } else {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  void _loadNotes() {
    setState(() {
      _notesFuture = _apiService.getWachbuchNotes(widget.wachbuch.id);
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file != null) setState(() => _pendingFiles.add(file));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Öffnen: $e')),
      );
    }
  }

  void _showAttachmentSource() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt, color: Theme.of(context).primaryColor),
              title: const Text('Kamera'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: Theme.of(context).primaryColor),
              title: const Text('Galerie / Dateien'),
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _submitNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty && _pendingFiles.isEmpty) return;

    setState(() => _isSending = true);

    try {
      // Upload attachments first
      final List<String> attachmentIds = [];
      for (final file in _pendingFiles) {
        final bytes = await file.readAsBytes();
        final mimeType = _mimeFromExtension(file.name);
        final id = await _apiService.uploadAttachment(
          fileName: file.name,
          mimeType: mimeType,
          bytes: bytes,
        );
        if (id != null) attachmentIds.add(id);
      }

      final success = await _apiService.createNoteWithAttachments(
        widget.wachbuch.id,
        text,
        attachmentIds,
      );

      if (success) {
        _noteController.clear();
        setState(() => _pendingFiles.clear());
        _loadNotes();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Speichern des Eintrags.')),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  String _mimeFromExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }

  void _showAttachment(BuildContext ctx, String name, String type, String fileUrl) {
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              title: Text(name, style: const TextStyle(fontSize: 14)),
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))
              ],
            ),
            type.startsWith('image/')
                ? Flexible(
                    child: InteractiveViewer(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _AuthImage(url: fileUrl, maxHeight: 500),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      const Icon(Icons.insert_drive_file, size: 60, color: Colors.white60),
                      const SizedBox(height: 12),
                      Text(name, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text('Diese Datei kann nur auf dem Gerät geöffnet werden.',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                  ),
          ],
        ),
      ),
    );
  }

  // ─── Field helpers ───────────────────────────────────────────────────────────

  Widget _fieldRow(String label, String? value, {IconData icon = Icons.info_outline, VoidCallback? onTap}) {
    final clean = value?.trim() ?? '';
    if (clean.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  clean, 
                  style: TextStyle(
                    fontSize: 15, 
                    color: onTap != null ? Theme.of(context).colorScheme.secondary : null,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  )
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _linkifyText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    final urlRegExp = RegExp(
      r'((https?:\/\/)?([a-z0-9-]+\.)+[a-z]{2,6}(\/[^\s]*)?)',
      caseSensitive: false,
    );
    final matches = urlRegExp.allMatches(text);
    if (matches.isEmpty) return Text(text, style: const TextStyle(fontSize: 15));

    final List<InlineSpan> spans = [];
    int lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final url = match.group(0)!;
      final fullUrl = url.startsWith('http') ? url : 'https://$url';
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold),
        recognizer: TapGestureRecognizer()..onTap = () async {
          final uri = Uri.tryParse(fullUrl);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        },
      ));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87),
        children: spans,
      ),
    );
  }

  Widget _htmlFieldRow(String label, String? html, {IconData icon = Icons.description}) {
    if (html == null || html.trim().isEmpty) return const SizedBox.shrink();
    if (_stripHtml(html).isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Html(
              data: html,
              style: {
                'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero, fontSize: FontSize(15)),
                'p': Style(margin: Margins.only(bottom: 4)),
                'a': Style(color: Theme.of(context).primaryColor),
              },
              onLinkTap: (url, _, __) async {
                if (url != null) {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  }
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _chipRow(String label, List<String>? values) {
    if (values == null || values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: values.map((v) => Chip(
                label: Text(v, style: const TextStyle(fontSize: 12)),
                backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor.withOpacity(0.12),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              )).toList(),
        ),
      ]),
    );
  }

  Widget _attachmentRow(String label, List<WachbuchAttachment> attachments) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: attachments.map((att) {
            final isImage = att.type.startsWith('image/');
            final fileUrl = '${AppConstants.baseUrl}/?entryPoint=download&id=${att.id}';
            if (isImage) {
              return GestureDetector(
                onTap: () => _showAttachment(context, att.name, att.type, fileUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _AuthImage(url: fileUrl),
                ),
              );
            } else {
              return ActionChip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                onPressed: () => _showAttachment(context, att.name, att.type, fileUrl),
              );
            }
          }).toList(),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wb = _fullWachbuch;
    return Scaffold(
      
      appBar: AppBar(
        title: Text(wb.name),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_loadingDetails)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ─── DETAILS CARD ─────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.assignment, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Text('Objekt-Details', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                    ]),
                    const SizedBox(height: 16),
                    _fieldRow('Name', wb.name, icon: Icons.label),
                    if (_aclService.isAdmin) _fieldRow('Status', wb.status, icon: Icons.flag),
                    _fieldRow('Objekt', wb.objekteName, icon: Icons.location_on, onTap: () {
                      if (wb.objekteName != null) {
                        final query = Uri.encodeComponent(wb.objekteName!);
                        launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'), mode: LaunchMode.externalApplication);
                      }
                    }),
                    _fieldRow('Bezieht sich auf', wb.parentName, icon: Icons.business),
                    if (_aclService.isAdmin) _fieldRow('Zugewiesen an', wb.assignedUserName, icon: Icons.person),
                    if (_aclService.isAdmin) _fieldRow('Startdatum', _formatTimestamp(wb.dateStart), icon: Icons.calendar_today),
                    if (_aclService.isAdmin) _fieldRow('Enddatum', _formatTimestamp(wb.dateEnd), icon: Icons.event),
                    _fieldRow('Datum/Uhrzeit', _formatTimestamp(wb.datumUhrzeit), icon: Icons.access_time),
                    _chipRow('Art', wb.art),
                    _htmlFieldRow('Beschreibung', wb.beschreibung, icon: Icons.description),
                    _htmlFieldRow('Notiz', wb.description, icon: Icons.notes),
                    _htmlFieldRow('Zusätzliche Informationen', wb.zustzlicheInformationen, icon: Icons.info),
                    _attachmentRow('Dateien / Fotos', wb.dateinFotos),
                    if (_aclService.isAdmin) _fieldRow('Erstellt von', wb.createdByName, icon: Icons.person_add),
                    if (_aclService.isAdmin) _fieldRow('Erstellt am', _formatTimestamp(wb.createdAt), icon: Icons.access_time),
                    if (_aclService.isAdmin) _fieldRow('Zuletzt geändert von', wb.modifiedByName, icon: Icons.edit),
                    if (_aclService.isAdmin) _fieldRow('Zuletzt geändert am', _formatTimestamp(wb.modifiedAt), icon: Icons.history),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // ─── STREAM ───────────────────────────────────────
              Row(children: const [
                Icon(Icons.forum, color: Colors.grey),
                SizedBox(width: 8),
                Text('Stream / Verlauf', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
              ]),
              const SizedBox(height: 8),
              FutureBuilder<List<Note>>(
                future: _notesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError) return Center(child: Text('Fehler: ${snapshot.error}'));
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Noch keine Einträge im Stream.'))),
                    );
                  }
                  return Column(
                    children: snapshot.data!.map((note) {
                      final postText = (note.post?.trim().isEmpty ?? true) ? '' : note.post!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                               Icon(Icons.person, size: 16, color: Theme.of(context).primaryColor),
                              const SizedBox(width: 4),
                              Text(note.createdByName ?? 'System',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                              const Spacer(),
                              Text(_formatTimestamp(note.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ]),
                            if (postText.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _linkifyText(postText),
                            ] else ...[
                              const SizedBox(height: 4),
                              Text('[${note.type ?? "Systemeintrag"}]',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                            ],
                            if (note.attachments.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: note.attachments.map((att) {
                                  final isImage = att.type.startsWith('image/');
                                  final fileUrl = '${AppConstants.baseUrl}/?entryPoint=download&id=${att.id}';
                                  if (isImage) {
                                    return GestureDetector(
                                      onTap: () => _showAttachment(context, att.name, att.type, fileUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: _AuthImage(url: fileUrl),
                                      ),
                                    );
                                  } else {
                                    return ActionChip(
                                      avatar: const Icon(Icons.attach_file, size: 16),
                                      label: Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                      onPressed: () => _showAttachment(context, att.name, att.type, fileUrl),
                                    );
                                  }
                                }).toList(),
                              ),
                            ],
                          ]),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),

        // ─── INPUT BAR ────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pending attachment previews
                if (_pendingFiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final file = _pendingFiles[i];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  file.path,
                                  height: 80,
                                  width: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 80,
                                    width: 80,
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.attach_file),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => setState(() => _pendingFiles.removeAt(i)),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                // Text input row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    // Attachment button
                    IconButton(
                      icon: Icon(Icons.attach_file, color: Theme.of(context).primaryColor),
                      onPressed: _isSending ? null : _showAttachmentSource,
                    ),
                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _noteController,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'Neuer Eintrag...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF0F0F0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button
                    _isSending
                        ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))
                        : CircleAvatar(
                            backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _submitNote,
                            ),
                          ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Auth-gesicherter Bild-Loader ─────────────────────────────────────────────

class _AuthImage extends StatefulWidget {
  final String url;
  final double? maxHeight;
  const _AuthImage({required this.url, this.maxHeight});

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Map<String, String>? _headers;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _storage.getToken().then((t) {
      if (mounted) setState(() => _headers = t != null ? {'Authorization': t} : {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_headers == null) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    return Image.network(
      widget.url,
      headers: _headers!,
      height: widget.maxHeight ?? 120,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
    );
  }
}
