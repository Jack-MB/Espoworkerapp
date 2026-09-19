import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatCreateScreen extends StatefulWidget {
  const ChatCreateScreen({Key? key}) : super(key: key);

  @override
  _ChatCreateScreenState createState() => _ChatCreateScreenState();
}

class _ChatCreateScreenState extends State<ChatCreateScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Map<String, dynamic> _userGroups = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final groups = await _apiService.getChatUsersFiltered();
    if (mounted) {
      setState(() {
        _userGroups = groups;
        _isLoading = false;
      });
    }
  }

  void _startDirectChat(String userId) async {
    setState(() => _isLoading = true);
    final roomId = await _apiService.createDirectChat(userId);
    if (mounted) {
      setState(() => _isLoading = false);
      if (roomId != null) {
        Navigator.pop(context, true); // Return true to indicate a new chat was created
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Erstellen des Chats.')),
        );
      }
    }
  }

  Widget _buildGroup(String title, List<dynamic>? users, IconData icon) {
    if (users == null || users.isEmpty) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor, fontSize: 16)),
        ),
        ...users.map((u) {
          final isOnline = u['online'] == true;
          return ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  child: Icon(icon, color: Colors.grey.shade600),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    ),
                  ),
              ],
            ),
            title: Text(u['name'] ?? 'Unbekannt'),
            subtitle: u['company'] != null ? Text(u['company']) : null,
            onTap: () => _startDirectChat(u['id']),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neuer Chat'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildGroup('Intern', _userGroups['internal'], Icons.person),
                _buildGroup('Büro', _userGroups['buero'], Icons.support_agent),
                _buildGroup('Leitung', _userGroups['leitung'], Icons.admin_panel_settings),
                _buildGroup('Geschäftsführung', _userGroups['gf'], Icons.cases),
                _buildGroup('Kooperationspartner Leitung', _userGroups['kpHeads'], Icons.business),
                _buildGroup('Kooperationspartner Mitarbeiter', _userGroups['kpColleagues'], Icons.groups),
              ],
            ),
    );
  }
}
