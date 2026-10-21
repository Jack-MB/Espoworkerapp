import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../models/krankentage.dart';
import '../models/document.dart';
import 'document_viewer_screen.dart';

class KrankentageScreen extends StatefulWidget {
  final bool embedded;
  const KrankentageScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  _KrankentageScreenState createState() => _KrankentageScreenState();
}

class _KrankentageScreenState extends State<KrankentageScreen> {
  final ApiService _apiService = ApiService();
  Future<List<Krankentage>>? _krankentageFuture;
  Future<Map<String, dynamic>?>? _overviewFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _krankentageFuture = _apiService.getKrankentage();
      _overviewFuture = _apiService.getMyAbsenceOverview();
    });
  }

  void _showCreateKrankmeldungSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return const _CreateKrankmeldungForm();
      },
    ).then((created) {
      if (created == true) {
        _loadData();
      }
    });
  }

  Widget _buildSickLeaveHeader(Map<String, dynamic>? overview) {
    final krankData = overview?['krankentage'] as Map<String, dynamic>?;
    final tageJahr = krankData?['krankentageJahr'] ?? 0;
    final tageGesamt = krankData?['gesamtKrankentage'] ?? 0;
    final openWithoutAU = krankData?['openWithoutAUCount'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.healing, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              const Text(
                'Krankheitsübersicht',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 15, color: Colors.red.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Jahr 2026',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$tageJahr ${tageJahr == 1 ? "Schichttag" : "Schichttage"}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'EFZG Lohnfortzahlung',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history, size: 15, color: Colors.indigo),
                          const SizedBox(width: 6),
                          Text(
                            'Gesamte Historie',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$tageGesamt ${tageGesamt == 1 ? "Tag" : "Tage"}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Schichten ausgefallen',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (openWithoutAU > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 22, color: Colors.orange.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$openWithoutAU Krankmeldung(en) ohne AU-Bescheinigung. Bitte reiche das Dokument baldmöglichst nach.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBody = FutureBuilder<Map<String, dynamic>?>(
      future: _overviewFuture,
      builder: (context, overviewSnapshot) {
        final overview = overviewSnapshot.data;

        return RefreshIndicator(
          onRefresh: () async => _loadData(),
          child: Column(
            children: [
              _buildSickLeaveHeader(overview),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Krankentage>>(
                  future: _krankentageFuture ?? Future.value([]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 60),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.favorite_border, size: 48, color: Colors.green),
                                SizedBox(height: 12),
                                Text(
                                  'Keine Krankmeldungen vorhanden.',
                                  style: TextStyle(color: Colors.grey, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    final list = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 90),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final krank = list[index];
                        final bool hasAU = krank.krankenscheinId != null && krank.krankenscheinId!.isNotEmpty;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (!hasAU) {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                  ),
                                  builder: (ctx) => _UploadAUForm(krankId: krank.id),
                                ).then((uploaded) {
                                  if (uploaded == true) _loadData();
                                });
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DocumentViewerScreen(
                                      document: EspoDocument(
                                        id: krank.id,
                                        name: 'AU-Bescheinigung',
                                        status: 'Active',
                                        fileId: krank.krankenscheinId,
                                        fileName: krank.krankenscheinName ?? 'AU-Bescheinigung.pdf',
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          krank.name,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: krank.statusColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: krank.statusColor.withOpacity(0.5)),
                                        ),
                                        child: Text(
                                          krank.displayStatus,
                                          style: TextStyle(
                                            color: krank.statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.date_range, size: 16, color: Colors.grey.shade600),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          krank.formattedDateRange +
                                              (krank.kalendertage != null
                                                  ? ' (${krank.kalendertage} ${krank.kalendertage == 1 ? "Tag" : "Tage"})'
                                                  : ''),
                                          style: TextStyle(
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        hasAU ? Icons.check_circle : Icons.warning,
                                        size: 16,
                                        color: hasAU ? Colors.green : Colors.orange,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          hasAU
                                              ? 'AU: ${krank.krankenscheinName ?? "hochgeladen (tippen zum Anzeigen)"}'
                                              : 'Keine AU eingereicht – Hier tippen zum Nachreichen',
                                          style: TextStyle(
                                            color: hasAU ? Colors.green.shade700 : Colors.orange.shade800,
                                            fontSize: 13,
                                            fontWeight: hasAU ? FontWeight.normal : FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.embedded) {
      return scaffoldBody;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Krankmeldungen'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: scaffoldBody,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateKrankmeldungSheet,
        backgroundColor: Colors.red.shade600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Krankmelden', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CreateKrankmeldungForm extends StatefulWidget {
  const _CreateKrankmeldungForm({Key? key}) : super(key: key);

  @override
  __CreateKrankmeldungFormState createState() => __CreateKrankmeldungFormState();
}

class __CreateKrankmeldungFormState extends State<_CreateKrankmeldungForm> {
  final _apiService = ApiService();
  final _descController = TextEditingController();
  DateTimeRange? _selectedRange;
  Uint8List? _fileBytes;
  String? _fileName;
  bool _isSubmitting = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final f = result.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && !kIsWeb && f.path != null) {
        try {
          bytes = await File(f.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes != null) {
        setState(() {
          _fileBytes = bytes;
          _fileName = f.name;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Zeitraum wählen')));
      return;
    }

    setState(() => _isSubmitting = true);

    String? uploadedFileId;
    if (_fileBytes != null && _fileName != null) {
      final ext = _fileName!.split('.').last.toLowerCase();
      String mimeType = 'application/pdf';
      if (ext == 'png') mimeType = 'image/png';
      if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';

      uploadedFileId = await _apiService.uploadAttachment(
        fileName: _fileName!,
        mimeType: mimeType,
        bytes: _fileBytes!,
        parentType: 'CKrankenscheine',
        field: 'krankenschein',
      );
    }

    final start = _selectedRange!.start;
    final end = _selectedRange!.end;
    final startStr = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
    final endStr = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';

    final success = await _apiService.createKrankentage(
      dateStart: startStr,
      dateEnd: endStr,
      description: _descController.text.trim(),
      krankenscheinId: uploadedFileId,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Krankmeldung erfolgreich eingereicht!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Fehler beim Einreichen der Krankmeldung.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    int? days;
    if (_selectedRange != null) {
      days = _selectedRange!.end.difference(_selectedRange!.start).inDays + 1;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Neue Krankmeldung eintragen', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(
              _selectedRange == null
                  ? 'Ausfall-Zeitraum wählen'
                  : '${DateFormat('dd.MM.yyyy').format(_selectedRange!.start)} – ${DateFormat('dd.MM.yyyy').format(_selectedRange!.end)} ${days != null ? "($days Tage)" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Du hast eine Papier-AU (z.B. Notaufnahme, Krankenhaus oder Privatarzt)? Lade hier einfach ein Foto hoch!\nFalls du beim Kassenarzt warst, erfolgt die Meldung digital (eAU).',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: Icon(_fileName != null ? Icons.check_circle : Icons.camera_alt,
                color: _fileName != null ? Colors.green : null),
            label: Text(
              _fileName == null
                  ? 'Papier-AU / Notaufnahme fotografieren (optional)'
                  : 'Ausgewählt: $_fileName',
              style: TextStyle(
                fontWeight: _fileName != null ? FontWeight.bold : FontWeight.normal,
                color: _fileName != null ? Colors.green.shade800 : null,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Bemerkung (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Krank melden',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UploadAUForm extends StatefulWidget {
  final String krankId;
  const _UploadAUForm({Key? key, required this.krankId}) : super(key: key);

  @override
  __UploadAUFormState createState() => __UploadAUFormState();
}

class __UploadAUFormState extends State<_UploadAUForm> {
  final _apiService = ApiService();
  Uint8List? _fileBytes;
  String? _fileName;
  bool _isSubmitting = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final f = result.files.single;
      Uint8List? bytes = f.bytes;
      if (bytes == null && !kIsWeb && f.path != null) {
        try {
          bytes = await File(f.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes != null) {
        setState(() {
          _fileBytes = bytes;
          _fileName = f.name;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_fileBytes == null || _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datei auswählen')));
      return;
    }

    setState(() => _isSubmitting = true);

    final ext = _fileName!.split('.').last.toLowerCase();
    String mimeType = 'application/pdf';
    if (ext == 'png') mimeType = 'image/png';
    if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';

    final uploadedFileId = await _apiService.uploadAttachment(
      fileName: _fileName!,
      mimeType: mimeType,
      bytes: _fileBytes!,
      parentType: 'CKrankenscheine',
      field: 'krankenschein',
    );
    
    if (uploadedFileId == null) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Hochladen der AU-Bescheinigung.')),
        );
      }
      return;
    }

    final success = await _apiService.updateKrankentage(widget.krankId, uploadedFileId);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ AU-Bescheinigung erfolgreich nachgereicht!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Fehler beim Zuweisen der AU-Bescheinigung.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('AU-Bescheinigung nachreichen', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bescheinigung aus der Notaufnahme, dem Krankenhaus oder vom Privatarzt? Hier kannst du einfach ein Foto oder PDF hochladen.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: Icon(_fileName != null ? Icons.check_circle : Icons.camera_alt,
                color: _fileName != null ? Colors.green : null),
            label: Text(
              _fileName == null ? 'Papier-AU / Attest auswählen (PDF/Bild)' : 'Ausgewählt: $_fileName',
              style: TextStyle(
                fontWeight: _fileName != null ? FontWeight.bold : FontWeight.normal,
                color: _fileName != null ? Colors.green.shade800 : null,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Hochladen & Einreichen',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
