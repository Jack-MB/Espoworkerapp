import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meeting.dart';
import '../services/api_service.dart';

class MeetingDetailScreen extends StatefulWidget {
  final String meetingId;
  const MeetingDetailScreen({Key? key, required this.meetingId}) : super(key: key);

  @override
  _MeetingDetailScreenState createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  final ApiService _apiService = ApiService();
  late Future<Meeting?> _meetingFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _meetingFuture = _apiService.getMeetingById(widget.meetingId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Meeting?>(
      future: _meetingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        final meeting = snapshot.data;
        if (meeting == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Fehler beim Laden des Meetings.')));
        }

        final start = meeting.dateStart != null ? DateFormat('dd.MM.yyyy HH:mm').format(DateFormat('yyyy-MM-dd HH:mm:ss').parse(meeting.dateStart!)) : '-';
        final end = meeting.dateEnd != null ? DateFormat('HH:mm').format(DateFormat('yyyy-MM-dd HH:mm:ss').parse(meeting.dateEnd!)) : '-';

        return Scaffold(
          appBar: AppBar(
            title: Text(meeting.name),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(meeting, start, end),
                const SizedBox(height: 20),
                const Text('Teilnehmer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (meeting.attendees != null && meeting.attendees!.isNotEmpty)
                  ...meeting.attendees!.map((a) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(a.name),
                    subtitle: Text(a.type),
                    trailing: Text(a.status ?? 'Eingeladen', style: TextStyle(color: _getAttendeeStatusColor(a.status))),
                  )).toList()
                else
                  const Text('Keine Teilnehmer gelistet.', style: TextStyle(color: Colors.grey)),
                
                const SizedBox(height: 30),
                if (meeting.status == 'Planned')
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Als abgehalten markieren', style: TextStyle(color: Colors.white, fontSize: 16)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () async {
                        final success = await _apiService.updateMeetingStatus(meeting.id, 'Held');
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status auf "Abgehalten" geändert.')));
                          _loadData();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Ändern des Status.')));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(Meeting m, String start, String end) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildRow(Icons.info_outline, 'Status', m.status),
            const Divider(),
            _buildRow(Icons.calendar_today, 'Zeitraum', '$start - $end'),
            if (m.parentName != null) ...[
              const Divider(),
              _buildRow(Icons.link, 'Bezieht sich auf', m.parentName!),
            ],
            if (m.description != null && m.description!.isNotEmpty) ...[
              const Divider(),
              _buildRow(Icons.description, 'Beschreibung', m.description!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getAttendeeStatusColor(String? status) {
    switch (status) {
      case 'Accepted': return Colors.green;
      case 'Declined': return Colors.red;
      case 'Tentative': return Colors.orange;
      default: return Colors.grey;
    }
  }
}
