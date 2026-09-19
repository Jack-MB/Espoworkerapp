import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChatCreateScreen extends StatefulWidget {
  const ChatCreateScreen({Key? key}) : super(key: key);

  @override
  _ChatCreateScreenState createState() => _ChatCreateScreenState();
}

class _ChatCreateScreenState extends State<ChatCreateScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = true;
  bool _isCreating = false;
  String _searchQuery = '';
  Map<String, dynamic> _userGroups = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _startDirectChat(String userId, String userName) async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    final roomId = await _apiService.createDirectChat(userId);
    if (mounted) {
      setState(() => _isCreating = false);
      if (roomId != null) {
        Navigator.pop(context, true); // Return true to indicate a new chat was created
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Starten des Chats mit $userName.')),
        );
      }
    }
  }

  List<dynamic> _filterUsers(List<dynamic>? users) {
    if (users == null || users.isEmpty) return [];
    if (_searchQuery.isEmpty) return users;
    
    final query = _searchQuery.toLowerCase();
    return users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final userName = (u['userName'] ?? '').toString().toLowerCase();
      final company = (u['company'] ?? '').toString().toLowerCase();
      return name.contains(query) || userName.contains(query) || company.contains(query);
    }).toList();
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Widget _buildGroup(String title, List<dynamic>? rawUsers, IconData groupIcon, Color groupColor) {
    final users = _filterUsers(rawUsers);
    if (users.isEmpty) return const SizedBox.shrink();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(groupIcon, size: 18, color: groupColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: groupColor,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: groupColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${users.length}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: groupColor),
                ),
              ),
            ],
          ),
        ),
        ...users.map((u) {
          final name = (u['name'] ?? u['userName'] ?? 'Unbekannt').toString();
          final company = u['company']?.toString();
          final isOnline = u['online'] == true;
          final initials = _getInitials(name);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: groupColor.withOpacity(0.18),
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: groupColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.shade700,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E2127) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: company != null && company.isNotEmpty
                ? Text(
                    company,
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  )
                : null,
            trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.grey),
            onTap: () => _startDirectChat(u['id'], name),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    final internalFiltered = _filterUsers(_userGroups['internal']);
    final bueroFiltered = _filterUsers(_userGroups['buero']);
    final leitungFiltered = _filterUsers(_userGroups['leitung']);
    final gfFiltered = _filterUsers(_userGroups['gf']);
    final kpHeadsFiltered = _filterUsers(_userGroups['kpHeads']);
    final kpColleaguesFiltered = _filterUsers(_userGroups['kpColleagues']);

    final totalFilteredCount = internalFiltered.length +
        bueroFiltered.length +
        leitungFiltered.length +
        gfFiltered.length +
        kpHeadsFiltered.length +
        kpColleaguesFiltered.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neuer Chat'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Search Input
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: isDark ? const Color(0xFF1E2127) : Colors.white,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Mitarbeiter suchen (Name, Firma)...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF2B2F38) : Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (totalFilteredCount == 0 && _searchQuery.isNotEmpty)
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_search_rounded, size: 60, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  'Kein Mitarbeiter für „$_searchQuery“ gefunden.',
                                  style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 32),
                            children: [
                              _buildGroup('Intern / Mitarbeiter', _userGroups['internal'], Icons.person_rounded, primaryColor),
                              _buildGroup('Büro / Verwaltung', _userGroups['buero'], Icons.support_agent_rounded, Colors.teal),
                              _buildGroup('Einsatzleitung', _userGroups['leitung'], Icons.shield_rounded, Colors.indigo),
                              _buildGroup('Geschäftsführung', _userGroups['gf'], Icons.workspace_premium_rounded, Colors.deepPurple),
                              _buildGroup('Kooperationspartner Leitung', _userGroups['kpHeads'], Icons.business_rounded, Colors.orange.shade800),
                              _buildGroup('Kooperationspartner Kollegen', _userGroups['kpColleagues'], Icons.groups_rounded, Colors.blueGrey),
                            ],
                          ),
              ),
            ],
          ),
          if (_isCreating)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(width: 16),
                        Text('Chat wird erstellt...', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
