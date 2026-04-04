import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/meeting.dart';
import 'meeting_detail_screen.dart';

class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({Key? key}) : super(key: key);

  @override
  _MeetingListScreenState createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<Meeting>> _meetingsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _meetingsFuture = _apiService.getMeetings();
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Planned': return Colors.blue;
      case 'Held': return Colors.green;
      case 'Not Held': return Colors.red;
      case 'Canceled': return Colors.grey;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<Meeting>>(
        future: _meetingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Meetings gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final m = list[index];
              final DateTime startDt = m.dateStart != null ? DateFormat('yyyy-MM-dd HH:mm:ss').parse(m.dateStart!) : DateTime.now();
              final String start = m.dateStart != null ? DateFormat('dd.MM.yyyy HH:mm').format(startDt) : '-';
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(start, style: TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
                      if (m.parentName != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(m.parentName!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(m.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _getStatusColor(m.status).withOpacity(0.5)),
                    ),
                    child: Text(
                      m.status,
                      style: TextStyle(color: _getStatusColor(m.status), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingDetailScreen(meetingId: m.id)));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateMeetingSheet,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showCreateMeetingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _CreateMeetingForm(),
    ).then((created) {
      if (created == true) _loadData();
    });
  }
}

class _CreateMeetingForm extends StatefulWidget {
  const _CreateMeetingForm({Key? key}) : super(key: key);

  @override
  __CreateMeetingFormState createState() => __CreateMeetingFormState();
}

class __CreateMeetingFormState extends State<_CreateMeetingForm> {
  final _apiService = ApiService();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();
  final _usersSearchController = TextEditingController();
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  bool _isSubmitting = false;

  String _parentType = 'Angestellte';
  String? _parentId;
  String? _parentName;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  List<Map<String, dynamic>> _selectedParticipants = [];
  List<Map<String, dynamic>> _userSearchResults = [];
  bool _isSearchingUsers = false;

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await _apiService.searchEntities(_parentType, query);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() => _userSearchResults = []);
      return;
    }
    setState(() => _isSearchingUsers = true);
    final results = await _apiService.searchEntities('User', query);
    setState(() {
      _userSearchResults = results;
      _isSearchingUsers = false;
    });
  }

  Future<void> _pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      locale: const Locale('de', 'DE'),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _selectedStart = dt;
        if (_selectedEnd == null || _selectedEnd!.isBefore(dt)) {
          _selectedEnd = dt.add(const Duration(hours: 1));
        }
      } else {
        _selectedEnd = dt;
      }
    });
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty || _selectedStart == null || _selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte alle Pflichtfelder ausfüllen.')));
      return;
    }

    setState(() => _isSubmitting = true);

    final startStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedStart!);
    final endStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedEnd!);

    // Availability check
    List<String> busyUsers = [];
    for (var user in _selectedParticipants) {
      final busy = await _apiService.isUserBusy(user['id'] as String, startStr, endStr);
      if (busy) busyUsers.add(user['name'] ?? 'Unbekannt');
    }

    if (busyUsers.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Überschneidung!'),
          content: Text('Folgende Teilnehmer sind zu dieser Zeit bereits verplant:\n\n' + busyUsers.join('\n') + '\n\nDennoch fortfahren?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trotzdem planen')),
          ],
        ),
      );
      if (proceed != true) {
        setState(() => _isSubmitting = false);
        return;
      }
    }

    final success = await _apiService.createMeeting(
      name: _nameController.text.trim(),
      dateStart: startStr,
      dateEnd: endStr,
      description: _descController.text.trim(),
      parentId: _parentId,
      parentType: _parentType,
      usersIds: _selectedParticipants.map((u) => u['id'] as String).toList(),
    );

    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Erstellen des Meetings.')));
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
          const Text('Neues Meeting planen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name des Meetings*', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _parentType,
            decoration: const InputDecoration(labelText: 'Bezieht sich auf (Typ)', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Angestellte', child: Text('Mitarbeiter')),
              DropdownMenuItem(value: 'Contact', child: Text('Kontakt (Kunde)')),
              DropdownMenuItem(value: 'Lead', child: Text('Interessent')),
              DropdownMenuItem(value: 'User', child: Text('Espo-Benutzer')),
              DropdownMenuItem(value: 'Objekte', child: Text('Objekt (Einsatzort)')),
              DropdownMenuItem(value: 'Kooperationspartner', child: Text('Kooperationspartner')),
              DropdownMenuItem(value: 'Fahrzeuge', child: Text('Fahrzeug')),
            ],
            onChanged: (val) {
              setState(() {
                _parentType = val!;
                _parentId = null;
                _parentName = null;
                _searchController.clear();
                _searchResults = [];
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Suchen...',
              border: const OutlineInputBorder(),
              suffixIcon: _isSearching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.search),
              hintText: _parentName ?? 'Name eingeben',
            ),
            onChanged: _search,
          ),
          if (_searchResults.isNotEmpty)
            Container(
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (ctx, i) {
                  final resp = _searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(resp['name'] ?? ''),
                    onTap: () {
                      setState(() {
                        _parentId = resp['id'];
                        _parentName = resp['name'];
                        _searchController.text = _parentName!;
                        _searchResults = [];
                      });
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDateTime(true),
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_selectedStart == null ? 'Beginn*' : DateFormat('dd.MM HH:mm').format(_selectedStart!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDateTime(false),
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_selectedEnd == null ? 'Ende*' : DateFormat('dd.MM HH:mm').format(_selectedEnd!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(labelText: 'Beschreibung (optional)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text('Teilnehmer hinzufügen', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _usersSearchController,
            decoration: InputDecoration(
              hintText: 'Mitarbeiter suchen...',
              border: const OutlineInputBorder(),
              suffixIcon: _isSearchingUsers ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.person_add),
            ),
            onChanged: _searchUsers,
          ),
          if (_userSearchResults.isNotEmpty)
            Container(
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
              child: ListView.builder(
                itemCount: _userSearchResults.length,
                itemBuilder: (ctx, i) {
                  final u = _userSearchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(u['name'] ?? ''),
                    onTap: () {
                      setState(() {
                        if (!_selectedParticipants.any((p) => p['id'] == u['id'])) {
                          _selectedParticipants.add(u);
                        }
                        _usersSearchController.clear();
                        _userSearchResults = [];
                      });
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _selectedParticipants.map((p) => Chip(
              label: Text(p['name'] ?? ''),
              onDeleted: () => setState(() => _selectedParticipants.remove(p)),
            )).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Meeting erstellen', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
