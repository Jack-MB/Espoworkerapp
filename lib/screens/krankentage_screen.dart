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
  const KrankentageScreen({Key? key}) : super(key: key);

  @override
  _KrankentageScreenState createState() => _KrankentageScreenState();
}

class _KrankentageScreenState extends State<KrankentageScreen> {
  final ApiService _apiService = ApiService();
  Future<List<Krankentage>>? _krankentageFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _krankentageFuture = _apiService.getKrankentage();
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

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<List<Krankentage>>(
        future: _krankentageFuture ?? Future.value([]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Krankentage gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final krank = list[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (krank.krankenscheinId == null) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (ctx) => _UploadAUForm(krankId: krank.id),
                      ).then((uploaded) {
                        if (uploaded == true) _loadData();
                      });
                    } else {
                      // Open the uploaded document
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
                                krank.formattedDateRange + (krank.kalendertage != null ? ' (${krank.kalendertage} ${krank.kalendertage == 1 ? "Tag" : "Tage"})' : ''),
                                style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(krank.krankenscheinId != null ? Icons.check_circle : Icons.warning, 
                                 size: 16, 
                                 color: krank.krankenscheinId != null ? Colors.green : Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                krank.krankenscheinId != null 
                                    ? 'AU: ${krank.krankenscheinName ?? "hochgeladen"}' 
                                    : 'Keine AU eingereicht – Hier tippen zum Nachreichen',
                                style: TextStyle(
                                  color: krank.krankenscheinId != null ? Colors.green.shade700 : Colors.orange.shade800, 
                                  fontSize: 13,
                                  fontWeight: krank.krankenscheinId == null ? FontWeight.bold : FontWeight.normal,
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
      
      if (uploadedFileId == null) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Hochladen der AU-Bescheinigung.')));
        }
        return;
      }
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
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Neue Krankmeldung eintragen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(_selectedRange == null 
              ? 'Ausfall-Zeitraum wählen' 
              : '${DateFormat('dd.MM.yyyy').format(_selectedRange!.start)} - ${DateFormat('dd.MM.yyyy').format(_selectedRange!.end)}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName == null 
              ? 'AU-Bescheinigung hochladen (optional)' 
              : 'Ausgewählt: $_fileName'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Bemerkung (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
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
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Krank melden', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Hochladen der AU-Bescheinigung.')));
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
          const Text('AU-Bescheinigung nachreichen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName == null 
              ? 'Datei auswählen (PDF/Bild)' 
              : 'Ausgewählt: $_fileName'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.centerLeft,
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
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Hochladen & Einreichen', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
