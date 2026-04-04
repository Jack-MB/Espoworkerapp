import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/urlaub.dart';
import '../core/constants.dart';
import '../services/acl_service.dart';

class UrlaubScreen extends StatefulWidget {
  const UrlaubScreen({Key? key}) : super(key: key);

  @override
  _UrlaubScreenState createState() => _UrlaubScreenState();
}

class _UrlaubScreenState extends State<UrlaubScreen> {
  final ApiService _apiService = ApiService();
  final AclService _aclService = AclService();
  late Future<List<Urlaub>> _urlaubsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _urlaubsFuture = _apiService.getUrlaubs();
    });
  }

  void _showCreateUrlaubSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return const _CreateUrlaubForm();
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
        title: const Text('Urlaubsanträge'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<Urlaub>>(
        future: _urlaubsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Urlaubsanträge gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final urlaub = list[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                              urlaub.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (urlaub.status == 'Genehmigt' ? Colors.green : Colors.orange).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: (urlaub.status == 'Genehmigt' ? Colors.green : Colors.orange).withOpacity(0.5)),
                            ),
                            child: Text(
                              urlaub.status,
                              style: TextStyle(
                                color: urlaub.status == 'Genehmigt' ? Colors.green.shade800 : Colors.orange.shade800,
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
                          Text(
                            '${urlaub.dateStartDate ?? "-"}  bis  ${urlaub.dateEndDate ?? "-"}',
                            style: TextStyle(color: Colors.grey.shade800),
                          ),
                        ],
                      ),
                      if (urlaub.description != null && urlaub.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(urlaub.description!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUrlaubSheet,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Neuer Antrag', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CreateUrlaubForm extends StatefulWidget {
  const _CreateUrlaubForm({Key? key}) : super(key: key);

  @override
  __CreateUrlaubFormState createState() => __CreateUrlaubFormState();
}

class __CreateUrlaubFormState extends State<_CreateUrlaubForm> {
  final _apiService = ApiService();
  final _descController = TextEditingController();
  DateTimeRange? _selectedRange;
  bool _isSubmitting = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() => _selectedRange = picked);
    }
  }

  Future<void> _submit() async {
    if (_selectedRange == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Zeitraum wählen')));
      return;
    }

    setState(() => _isSubmitting = true);

    // Format for API: "YYYY-MM-DD 00:00:00"
    final start = _selectedRange!.start;
    final end = _selectedRange!.end;
    
    final startStr = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
    final endStr = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';
    
    final success = await _apiService.createUrlaub(
      dateStart: startStr,
      dateEnd: endStr,
      description: _descController.text.trim(),
    );

    setState(() => _isSubmitting = false);

    if (success) {
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Urlaubsantrag erfolgreich eingereicht!')));
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Einreichen.')));
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
          const Text('Neuen Urlaub beantragen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(_selectedRange == null 
              ? 'Zeitraum auswählen' 
              : '${DateFormat('dd.MM.yyyy').format(_selectedRange!.start)} - ${DateFormat('dd.MM.yyyy').format(_selectedRange!.end)}'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Begründung / Bemerkung (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Antrag einreichen', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
