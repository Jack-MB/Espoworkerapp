import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/abwesenheit.dart';
import '../core/constants.dart';
import '../services/acl_service.dart';

class AbwesenheitScreen extends StatefulWidget {
  const AbwesenheitScreen({Key? key}) : super(key: key);

  @override
  _AbwesenheitScreenState createState() => _AbwesenheitScreenState();
}

class _AbwesenheitScreenState extends State<AbwesenheitScreen> {
  final ApiService _apiService = ApiService();
  final AclService _aclService = AclService();
  late Future<List<Abwesenheit>> _abwesenheitFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _abwesenheitFuture = _apiService.getAbwesenheiten();
    });
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return const _CreateAbwesenheitForm();
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
        title: const Text('Abwesenheitsnotizen'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<Abwesenheit>>(
        future: _abwesenheitFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Abwesenheiten gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
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
                              item.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.5)),
                            ),
                            child: Text(
                              'Termin',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item.dateStart != null ? DateFormat('dd.MM.yyyy HH:mm').format(DateFormat('yyyy-MM-dd HH:mm:ss').parse(item.dateStart!)) : '-'}  bis  ${item.dateEnd != null ? DateFormat('HH:mm').format(DateFormat('yyyy-MM-dd HH:mm:ss').parse(item.dateEnd!)) : '-'}',
                              style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                            ),
                          ),
                      if (item.description != null && item.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(item.description!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
        onPressed: _showCreateSheet,
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Neuer Termin', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CreateAbwesenheitForm extends StatefulWidget {
  const _CreateAbwesenheitForm({Key? key}) : super(key: key);

  @override
  __CreateAbwesenheitFormState createState() => __CreateAbwesenheitFormState();
}

class __CreateAbwesenheitFormState extends State<_CreateAbwesenheitForm> {
  final _apiService = ApiService();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 0);
  bool _isAllDay = false;
  
  bool _isSubmitting = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('de', 'DE'),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        // Auto-adjust end time to 1h after if it was before
        if (_endTime.hour < _startTime.hour || (_endTime.hour == _startTime.hour && _endTime.minute <= _startTime.minute)) {
          _endTime = TimeOfDay(hour: (_startTime.hour + 1) % 24, minute: _startTime.minute);
        }
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte einen Betreff eingeben')));
      return;
    }

    setState(() => _isSubmitting = true);

    // Build format: "YYYY-MM-DD HH:mm:ss"
    final startDt = _isAllDay 
        ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0)
        : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute);
        
    final endDt = _isAllDay
        ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59)
        : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _endTime.hour, _endTime.minute);
    
    final startStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(startDt);
    final endStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(endDt);
    
    final success = await _apiService.createAbwesenheit(
      name: _nameController.text.trim(),
      dateStart: startStr,
      dateEnd: endStr,
      description: _descController.text.trim(),
      isAllDay: _isAllDay,
    );

    setState(() => _isSubmitting = false);

    if (success) {
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abwesenheit erfolgreich eingetragen!')));
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Speichern.')));
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
              const Text('Abwesenheitsnotiz', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Betreff (z.B. Termin Arzt)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 16),
          
          SwitchListTile(
            title: const Text('Ganztägig'),
            value: _isAllDay,
            onChanged: (val) => setState(() => _isAllDay = val),
            activeColor: Theme.of(context).primaryColor,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          
          // Date Selector
          InkWell(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Datum: ${DateFormat('dd.MM.yyyy').format(_selectedDate)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Time Row (Only if not all day)
          if (!_isAllDay) ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickStartTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 20),
                          const SizedBox(width: 8),
                          Text('Von: ${_startTime.format(context)}'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickEndTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 20),
                          const SizedBox(width: 8),
                          Text('Bis: ${_endTime.format(context)}'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Beschreibung (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 2,
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
              : const Text('Speichern', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
