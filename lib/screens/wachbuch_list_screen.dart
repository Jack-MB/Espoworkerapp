import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/api_service.dart';
import '../services/sync_queue_service.dart';
import '../models/wachbuch.dart';
import '../models/slot.dart';
import 'wachbuch_detail_screen.dart';

class WachbuchListScreen extends StatefulWidget {
  final String? highlightId;
  const WachbuchListScreen({Key? key, this.highlightId}) : super(key: key);

  @override
  _WachbuchListScreenState createState() => _WachbuchListScreenState();
}

class _WachbuchListScreenState extends State<WachbuchListScreen> {
  final ApiService _apiService = ApiService();

  Future<List<Wachbuch>>? _wachbuchFuture;
  Slot?     _aktiveSchicht;
  Wachbuch? _aktiveWachbuch;
  bool      _schichtLoaded   = false;
  bool      _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _wachbuchFuture = _apiService.getWachbuchs();
    _loadAktiveSchicht();
  }

  Future<void> _loadAktiveSchicht() async {
    final info = await _apiService.getAktiveSchichtInfo();
    if (!mounted) return;
    setState(() {
      _schichtLoaded  = true;
      if (info != null) {
        _aktiveSchicht  = info['slot']     as Slot?;
        _aktiveWachbuch = info['wachbuch'] as Wachbuch?;
      }
    });
  }

  void _loadData() {
    setState(() {
      _wachbuchFuture = _apiService.getWachbuchs();
      _schichtLoaded   = false;
      _bannerDismissed = false;
    });
    _loadAktiveSchicht();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Aktive Schicht — Banner
  // ────────────────────────────────────────────────────────────────────────────

  Widget _buildSchichtBanner() {
    if (!_schichtLoaded || _aktiveSchicht == null || _bannerDismissed) {
      return const SizedBox.shrink();
    }

    final slot   = _aktiveSchicht!;
    final wb     = _aktiveWachbuch;
    final objekt = slot.objekteName ?? slot.name;
    final pos    = slot.positionsname ?? '';
    final start  = _formatTime(slot.dateStart);
    final end    = _formatTime(slot.dateEnd);
    final zeit   = (start.isNotEmpty && end.isNotEmpty) ? '$start – $end Uhr' : start;

    final bool hasWb  = wb != null;
    final Color color = hasWb
        ? const Color(0xFF1a3c5e)
        : const Color(0xFF2d4a1e);
    final String icon   = hasWb ? '🟢' : '🟡';
    final String label  = hasWb
        ? '✏️  Eintrag erstellen'
        : '➕  Wachbuch anlegen & Eintrag erstellen';

    return GestureDetector(
      onTap: () => hasWb
          ? _showNoteDialog(wb.id, wb.name, slot)
          : _autoCreateAndOpenDialog(slot),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 48, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Überschrift
                  Row(children: [
                    Text('$icon  Aktive Schicht erkannt',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        )),
                  ]),
                  const SizedBox(height: 4),
                  // Objekt + Position
                  Text(
                    pos.isNotEmpty ? '$objekt  ·  $pos' : objekt,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (zeit.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('🕐  $zeit',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.70),
                          fontSize: 12,
                        )),
                  ],
                  const SizedBox(height: 10),
                  // Button
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4), width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Schließen-Button
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white70, size: 20),
                onPressed: () =>
                    setState(() => _bannerDismissed = true),
                tooltip: 'Ausblenden',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Note-Dialog
  // ────────────────────────────────────────────────────────────────────────────

  void _showNoteDialog(String wbId, String wbName, Slot slot) {
    final controller = TextEditingController();
    final pos    = slot.positionsname ?? '';
    final objekt = slot.objekteName  ?? slot.name;
    final start  = _formatTime(slot.dateStart);
    final end    = _formatTime(slot.dateEnd);
    final zeit   = (start.isNotEmpty && end.isNotEmpty) ? '$start – $end Uhr' : start;
    final datum  = _formatDate(slot.dateStart);

    String mitarbeiter = '';
    _apiService.getStoredAngestellteName().then((n) {
      mitarbeiter = n ?? '';
    });

    final List<XFile> pendingFiles = [];
    final ImagePicker picker = ImagePicker();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickImage(ImageSource source) async {
            try {
              final file = await picker.pickImage(
                source: source,
                maxWidth: 1920,
                maxHeight: 1920,
                imageQuality: 80,
              );
              if (file != null) {
                setDialogState(() {
                  pendingFiles.add(file);
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler beim Öffnen: $e')),
                );
              }
            }
          }

          Future<void> pickFiles() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                allowMultiple: true,
                withData: true,
                type: FileType.custom,
                allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'txt'],
              );
              if (result != null && result.files.isNotEmpty) {
                setDialogState(() {
                  for (final f in result.files) {
                    if (f.bytes != null) {
                      pendingFiles.add(XFile.fromData(f.bytes!, name: f.name));
                    } else if (f.path != null) {
                      pendingFiles.add(XFile(f.path!, name: f.name));
                    }
                  }
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fehler beim Auswählen der Datei: $e')),
                );
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1a3c5e),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.menu_book, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '📓  $wbName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                InkWell(
                  onTap: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Icon(Icons.close, color: Colors.white70, size: 22),
                ),
              ]),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info-Block
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (datum.isNotEmpty)  _infoRow('📅', datum),
                        if (objekt.isNotEmpty) _infoRow('📋', objekt),
                        if (pos.isNotEmpty)    _infoRow('👷', pos),
                        if (zeit.isNotEmpty)   _infoRow('🕐', zeit),
                      ],
                    ),
                  ),
                  // Texteingabe
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    enabled: !isSaving,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Was ist passiert? Vorkommnisse, Übergabe-Info…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Anhänge: Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSaving ? null : () => pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('Kamera', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSaving ? null : () => pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library, size: 16),
                          label: const Text('Galerie', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSaving ? null : pickFiles,
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: const Text('Datei', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Anhänge: Vorschau
                  if (pendingFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: pendingFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final file = pendingFiles[index];
                          final isImg = file.name.toLowerCase().endsWith('.jpg') ||
                              file.name.toLowerCase().endsWith('.jpeg') ||
                              file.name.toLowerCase().endsWith('.png') ||
                              file.name.toLowerCase().endsWith('.webp');

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                  color: Colors.grey.shade100,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: isImg
                                    ? FutureBuilder<Uint8List>(
                                        future: file.readAsBytes(),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                          }
                                          return const Center(
                                            child: SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          );
                                        },
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.insert_drive_file, color: Colors.blueGrey, size: 24),
                                          const SizedBox(height: 2),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: Text(
                                              file.name,
                                              style: const TextStyle(fontSize: 8),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              if (!isSaving)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: GestureDetector(
                                    onTap: () {
                                      setDialogState(() {
                                        pendingFiles.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  // DIN-Hinweis
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '⚠️  Eintrag ist nach dem Speichern revisionssicher (DIN 77200 §7).',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF856404),
                      ),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a3c5e),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(isSaving ? 'Wird gespeichert…' : 'Speichern'),
                onPressed: isSaving
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty && pendingFiles.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Bitte einen Text oder ein Bild/Datei anhängen.')),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);

                        // Kontext-Info voranstellen
                        final lines = <String>[];
                        if (datum.isNotEmpty)       lines.add('📅 Datum: $datum');
                        if (objekt.isNotEmpty)      lines.add('📋 Auftrag: $objekt');
                        if (pos.isNotEmpty)         lines.add('👷 Position: $pos');
                        if (zeit.isNotEmpty)        lines.add('🕐 Zeit: $zeit');
                        if (mitarbeiter.isNotEmpty) lines.add('👤 Mitarbeiter: $mitarbeiter');
                        final fullText = lines.isNotEmpty
                            ? (text.isNotEmpty ? '${lines.join('\n')}\n---\n$text' : lines.join('\n'))
                            : text;

                        try {
                          final List<String> attachmentIds = [];
                          for (final file in pendingFiles) {
                            try {
                              final bytes = await file.readAsBytes();
                              final mimeType = _mimeFromExtension(file.name);
                              final id = await _apiService.uploadAttachment(
                                fileName: file.name,
                                mimeType: mimeType,
                                bytes: bytes,
                              );
                              if (id != null) attachmentIds.add(id);
                            } catch (uploadErr) {
                              debugPrint('Error uploading attachment ${file.name}: $uploadErr');
                            }
                          }

                          final ok = await _apiService.createNoteWithAttachments(
                            wbId,
                            fullText,
                            attachmentIds,
                          );

                          if (!mounted) return;
                          Navigator.pop(ctx);

                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('✅  Eintrag mit Anhängen gespeichert'),
                              backgroundColor: Colors.green,
                            ));
                            _apiService.triggerWachbuchUpdate(wbId);
                            setState(() {
                              _wachbuchFuture = _apiService.getWachbuchs();
                            });
                          } else {
                            await SyncQueueService().enqueueWachbuchNote(
                              wachbuchId: wbId,
                              text: fullText,
                              attachmentIds: attachmentIds,
                              description: 'Wachbuch ($wbName): ${text.length > 25 ? text.substring(0, 25) + '...' : text}',
                            );
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('⏳  Offline: In Warteschlange gespeichert. Wird bei Verbindung übertragen.'),
                              backgroundColor: Colors.orange,
                            ));
                          }
                        } catch (e) {
                          await SyncQueueService().enqueueWachbuchNote(
                            wachbuchId: wbId,
                            text: fullText,
                            description: 'Wachbuch ($wbName): ${text.length > 25 ? text.substring(0, 25) + '...' : text}',
                          );
                          if (!mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('⏳  In Warteschlange gespeichert ($e)'),
                            backgroundColor: Colors.orange,
                          ));
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

  Future<void> _autoCreateAndOpenDialog(Slot slot) async {
    // Name des Wachbuches = Name des Objektes
    final name  = slot.objekteName ?? slot.name;
    final objId = slot.objekteId;
    // Kein slotId/dateStart/dateEnd — das Wachbuch ist ein dauerhaftes Objektbuch
    final wbId  = await _apiService.createWachbuch(name, objId);
    if (!mounted) return;
    if (wbId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wachbuch konnte nicht angelegt werden.')),
      );
      return;
    }
    setState(() {
      _wachbuchFuture  = _apiService.getWachbuchs();
      _aktiveWachbuch  = Wachbuch(id: wbId, name: name, status: 'Active');
    });
    _showNoteDialog(wbId, name, slot);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  String _formatTime(String? dt) {
    if (dt == null || dt.isEmpty) return '';
    try {
      final local = DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(dt).toLocal();
      return DateFormat('HH:mm').format(local);
    } catch (_) {
      // Fallback: raw substring if parsing fails
      return dt.length >= 16 ? dt.substring(11, 16) : '';
    }
  }

  String _formatDate(String? dt) {
    if (dt == null || dt.isEmpty) return '';
    try {
      final local = DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(dt).toLocal();
      return DateFormat('dd.MM.yyyy').format(local);
    } catch (_) {
      if (dt.length < 10) return '';
      final parts = dt.substring(0, 10).split('-');
      return parts.reversed.join('.');
    }
  }

  Widget _infoRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Text('$icon  ',
            style: const TextStyle(fontSize: 13)),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF444444)))),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wachbuch'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<Wachbuch>>(
        future: _wachbuchFuture ?? Future.value([]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Column(children: [
              _buildSchichtBanner(),
              const Expanded(
                child: Center(
                    child: Text('Keine Wachbuch-Einträge gefunden.')),
              ),
            ]);
          }

          final list = snapshot.data!;

          // Auto-open bei highlightId
          if (widget.highlightId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final match =
                  list.where((w) => w.id == widget.highlightId).toList();
              if (match.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        WachbuchDetailScreen(wachbuch: match.first),
                  ),
                );
              }
            });
          }

          return Column(
            children: [
              // ── Aktive Schicht Banner ──
              _buildSchichtBanner(),

              // ── Liste ──
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final w = list[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        title: Text(
                          w.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  WachbuchDetailScreen(wachbuch: w),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
