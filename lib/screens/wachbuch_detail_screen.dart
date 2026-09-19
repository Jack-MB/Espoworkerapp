import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../models/wachbuch.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../core/server_config.dart';
import '../services/secure_storage_service.dart';
import '../services/acl_service.dart';
import '../services/sync_queue_service.dart';
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

/// Entfernt Dark-Mode-CSS (background-color aus dem EspoCRM-Editor)
/// damit der HTML-Inhalt im Light-Theme der PWA korrekt aussieht.
String _sanitizeHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'background-color:\s*rgb\([^)]+\);?\s*'), '')
      .replaceAll(RegExp(r'background-color:\s*#[0-9a-fA-F]+;?\s*'), '')
      .replaceAll(RegExp(r'color:\s*rgb\([^)]+\);?\s*'), '')
      .replaceAll(RegExp(r'margin-top:[^;]+;\s*'), '')
      .replaceAll(RegExp(r'margin-bottom:[^;]+;\s*'), '')
      .replaceAll(RegExp(r' style=""'), '');
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
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  Future<List<Note>>? _notesFuture;
  List<Note> _allNotes = [];
  String _searchQuery = '';
  String? _filterPosition;

  Wachbuch? _fullWachbuch;
  bool _loadingDetails = true;
  final List<XFile> _pendingFiles = [];
  bool _isSending = false;

  // ── Helpers: Note-Text parsen ──────────────────────────────────────────────
  static String? _extractPosition(String? post) {
    if (post == null) return null;
    final m = RegExp(r'\u{1F477}\s*Position:\s*(.+)', unicode: true).firstMatch(post);
    return m?.group(1)?.trim();
  }

  static String _mainContent(String? post) {
    if (post == null || post.isEmpty) return '';
    final idx = post.indexOf('\n---\n');
    return idx >= 0 ? post.substring(idx + 5).trim() : post.trim();
  }

  static String? _extractMeta(String? post, String emoji) {
    if (post == null) return null;
    final m = RegExp('$emoji\\s*[^:]+:\\s*(.+)').firstMatch(post);
    return m?.group(1)?.trim();
  }

  List<String> get _uniquePositions {
    final positions = _allNotes
        .map((n) => _extractPosition(n.post))
        .whereType<String>()
        .toSet()
        .toList();
    positions.sort();
    return positions;
  }

  List<Note> get _filteredNotes {
    return _allNotes.where((n) {
      final pos = _extractPosition(n.post);
      if (_filterPosition != null && pos != _filterPosition) return false;
      if (_searchQuery.isNotEmpty) {
        return (n.post ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
               (n.createdByName ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fullWachbuch = widget.wachbuch;
    _aclService.init().then((_) { if (mounted) setState(() {}); });
    _loadNotes();
    _loadFullDetails();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text.trim()));
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
    final future = _apiService.getWachbuchNotes(widget.wachbuch.id);
    setState(() => _notesFuture = future);
    future.then((notes) {
      if (mounted) setState(() => _allNotes = notes);
    }).catchError((_) {});
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
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
        _apiService.triggerWachbuchUpdate(widget.wachbuch.id);
      } else {
        await SyncQueueService().enqueueWachbuchNote(
          wachbuchId: widget.wachbuch.id,
          text: text,
          attachmentIds: attachmentIds,
          description: 'Wachbuch (${widget.wachbuch.name}): ${text.length > 25 ? text.substring(0, 25) + '...' : text}',
        );
        _noteController.clear();
        setState(() => _pendingFiles.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Offline: Eintrag in Warteschlange gespeichert. Wird bei Verbindung übertragen.'),
            ),
          );
        }
      }
    } catch (e) {
      await SyncQueueService().enqueueWachbuchNote(
        wachbuchId: widget.wachbuch.id,
        text: text,
        description: 'Wachbuch (${widget.wachbuch.name}): ${text.length > 25 ? text.substring(0, 25) + '...' : text}',
      );
      _noteController.clear();
      setState(() => _pendingFiles.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Offline: Eintrag in Warteschlange gespeichert. Wird bei Verbindung übertragen.'),
          ),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  // ── DIN 77200 §7 Dienstablöse-Protokoll ────────────────────────────────────
  Future<void> _showAbloesungDialog() async {
    DateTime selectedTime = DateTime.now();
    final uebergeberController = TextEditingController();
    final uebernehmerController = TextEditingController();
    final notizenController = TextEditingController();
    bool keineVorkommnisse = true;
    bool isSaving = false;

    // Pre-fill Übergeber with current employee name
    final currentUserName = await _apiService.getStoredAngestellteName();
    if (currentUserName != null && currentUserName.isNotEmpty) {
      uebergeberController.text = currentUserName;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final zeitStr = DateFormat('dd.MM.yyyy HH:mm').format(selectedTime);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.published_with_changes, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Dienstablöse (DIN 77200)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white70, size: 22),
                  ),
                ],
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Selector
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.access_time, color: Colors.blueGrey),
                    title: const Text('Zeitpunkt der Ablösung', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(zeitStr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.edit_calendar, size: 20),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: selectedTime,
                        firstDate: DateTime.now().subtract(const Duration(days: 7)),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (pickedDate != null) {
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedTime),
                        );
                        if (pickedTime != null) {
                          setDialogState(() {
                            selectedTime = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            );
                          });
                        }
                      }
                    },
                  ),
                  const Divider(height: 16),

                  // Übergeber
                  TextField(
                    controller: uebergeberController,
                    decoration: const InputDecoration(
                      labelText: '👤 Übergeber (ablösende Person) *',
                      hintText: 'Vor- und Nachname',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Übernehmer
                  TextField(
                    controller: uebernehmerController,
                    decoration: const InputDecoration(
                      labelText: '👤 Übernehmer (neue Wache) *',
                      hintText: 'Vor- und Nachname',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Keine Vorkommnisse Checkbox
                  InkWell(
                    onTap: () => setDialogState(() => keineVorkommnisse = !keineVorkommnisse),
                    child: Row(
                      children: [
                        Checkbox(
                          value: keineVorkommnisse,
                          onChanged: (v) => setDialogState(() => keineVorkommnisse = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            '✅ Keine besonderen Vorkommnisse',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Notizen
                  TextField(
                    controller: notizenController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: keineVorkommnisse ? 'Notizen / Bemerkungen (optional)' : 'Vorkommnisse / Übergabenotizen *',
                      hintText: 'Schlüssel, Funkgeräte, Vorkommnisse, offene Aufträge...',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Compliance Note
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock, size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Revisionssicherer Eintrag gemäß DIN 77200 §7. Nach dem Speichern kann dieser Eintrag nicht mehr verändert oder gelöscht werden.',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton.icon(
                icon: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Ablösung speichern'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final uebergeber = uebergeberController.text.trim();
                        final uebernehmer = uebernehmerController.text.trim();
                        final notizen = notizenController.text.trim();

                        if (uebergeber.isEmpty || uebernehmer.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bitte Übergeber und Übernehmer angeben.')),
                          );
                          return;
                        }

                        if (!keineVorkommnisse && notizen.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bitte Vorkommnisse / Übergabenotizen beschreiben.')),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);

                        final postText = [
                          '🔄 **ABLÖSUNG** | $zeitStr',
                          '',
                          '**Übergeber:** $uebergeber',
                          '**Übernehmer:** $uebernehmer',
                          '',
                          keineVorkommnisse
                              ? '✅ **Keine besonderen Vorkommnisse**'
                              : '⚠️ **Vorkommnisse / Übergabenotizen:**',
                          if (notizen.isNotEmpty) notizen else if (!keineVorkommnisse) '_(keine Angabe)_',
                          '',
                          '---',
                          '_Revisionssicherer Ablöseeintrag gemäß DIN 77200 §7_'
                        ].join('\n');

                        final success = await _apiService.createNoteWithAttachments(
                          widget.wachbuch.id,
                          postText,
                          [],
                        );

                        if (success) {
                          Navigator.pop(ctx);
                          _loadNotes();
                          _apiService.triggerWachbuchUpdate(widget.wachbuch.id);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Ablösung revisionssicher gespeichert (DIN 77200 §7).'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else {
                          setDialogState(() => isSaving = false);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Fehler beim Speichern der Ablösung.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
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
    // Dark-Mode-CSS entfernen bevor es gerendert wird
    final cleanHtml = _sanitizeHtml(html);
    if (_stripHtml(cleanHtml).isEmpty) return const SizedBox.shrink();
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
              data: cleanHtml,
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

  Widget _filterChip(String label, String? position) {
    final selected = _filterPosition == position;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        selected: selected,
        onSelected: (_) => setState(() => _filterPosition = position),
        selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
        checkmarkColor: Theme.of(context).primaryColor,
        side: BorderSide(color: selected ? Theme.of(context).primaryColor : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    final position = _extractPosition(note.post);
    final auftrag  = _extractMeta(note.post, '📋');
    final zeit     = _extractMeta(note.post, '🕐');
    final content  = _mainContent(note.post);
    final isSystem = content.startsWith('📌');
    final isAbloesung = content.contains('ABLÖSUNG') || content.contains('DIN 77200');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isAbloesung ? const BorderSide(color: Color(0xFF1a3c5e), width: 1.5) : BorderSide.none,
      ),
      elevation: isAbloesung ? 2 : 1,
      color: isAbloesung ? const Color(0xFFF0F5FA) : (isSystem ? Colors.amber.shade50 : null),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header-Zeile: Autor + Timestamp
          Row(children: [
            Icon(isAbloesung ? Icons.published_with_changes : (isSystem ? Icons.info_outline : Icons.person), size: 16,
                color: isAbloesung ? const Color(0xFF1a3c5e) : (isSystem ? Colors.amber.shade800 : Theme.of(context).primaryColor)),
            const SizedBox(width: 6),
            Expanded(child: Text(
              isAbloesung ? 'DIN 77200 §7 Dienstablöse' : (isSystem ? 'Migration' : (note.createdByName ?? 'System')),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                  color: isAbloesung ? const Color(0xFF1a3c5e) : (isSystem ? Colors.amber.shade800 : Theme.of(context).primaryColor)),
            )),
            Text(_formatTimestamp(note.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),

          // Meta-Badges: Position + Zeit
          if (position != null || auftrag != null) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (position != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3)),
                  ),
                  child: Text('👷 $position', style: TextStyle(fontSize: 11, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600)),
                ),
              if (zeit != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('🕐 $zeit', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
            ]),
          ],

          // Inhalt
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            isSystem
                ? Text(content, style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontStyle: FontStyle.italic))
                : _linkifyText(content),
          ] else if ((note.post?.isEmpty ?? true)) ...[
            const SizedBox(height: 4),
            Text('[${note.type ?? "Systemeintrag"}]',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ],

          // Anhänge
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: note.attachments.map((att) {
              final isImage = att.type.startsWith('image/');
              final fileUrl = '${ServerConfig().baseUrl}/?entryPoint=download&id=${att.id}';
              return isImage
                  ? GestureDetector(
                      onTap: () => _showAttachment(context, att.name, att.type, fileUrl),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _AuthImage(url: fileUrl)),
                    )
                  : ActionChip(
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _showAttachment(context, att.name, att.type, fileUrl),
                    );
            }).toList()),
          ],
        ]),
      ),
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
            final fileUrl = '${ServerConfig().baseUrl}/?entryPoint=download&id=${att.id}';
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
    final wb = _fullWachbuch ?? widget.wachbuch;
    return Scaffold(
      
      appBar: AppBar(
        title: Text(wb.name),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.published_with_changes),
            tooltip: 'Dienstablöse erfassen (DIN 77200)',
            onPressed: _showAbloesungDialog,
          ),
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
                    _htmlFieldRow('Rechtsgrundlage & Aufbewahrungspflicht', wb.informationen, icon: Icons.gavel),
                    _attachmentRow('Dateien / Fotos', wb.dateinFotos),
                    if (_aclService.isAdmin) _fieldRow('Erstellt von', wb.createdByName, icon: Icons.person_add),
                    if (_aclService.isAdmin) _fieldRow('Erstellt am', _formatTimestamp(wb.createdAt), icon: Icons.access_time),
                    if (_aclService.isAdmin) _fieldRow('Zuletzt geändert von', wb.modifiedByName, icon: Icons.edit),
                    if (_aclService.isAdmin) _fieldRow('Zuletzt geändert am', _formatTimestamp(wb.modifiedAt), icon: Icons.history),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ─── ABLÖSE BUTTON (DIN 77200) ──────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.published_with_changes, color: Colors.white, size: 20),
                  label: const Text('Dienstablöse erfassen (DIN 77200 §7)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a3c5e),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                  onPressed: _showAbloesungDialog,
                ),
              ),
              const SizedBox(height: 16),

              // ─── STREAM ───────────────────────────────────────
              Row(children: const [
                Icon(Icons.forum, color: Colors.grey),
                SizedBox(width: 8),
                Text('Stream / Verlauf', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
              ]),
              const SizedBox(height: 10),

              // ── Suchfeld ──
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Einträge durchsuchen…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.shade300)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),

              // ── Filter-Chips (automatisch aus Positions-Metadaten) ──
              if (_uniquePositions.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Alle', null),
                      ..._uniquePositions.map((p) => _filterChip(p, p)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // ── Ergebnis-Info ──
              if (_searchQuery.isNotEmpty || _filterPosition != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${_filteredNotes.length} Einträge gefunden',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),

              // ── Notiz-Liste ──
              if (_allNotes.isEmpty && (_notesFuture != null))
                FutureBuilder<List<Note>>(
                  future: _notesFuture,
                  builder: (_, snap) {
                    if (snap.connectionState == ConnectionState.waiting)
                      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                    return const SizedBox.shrink();
                  },
                )
              else if (_filteredNotes.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Keine Einträge gefunden.'))),
                )
              else
                Column(children: _filteredNotes.map(_buildNoteCard).toList()),
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
