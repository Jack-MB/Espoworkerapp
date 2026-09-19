import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/angestellte.dart';
import 'angestellte_profile_screen.dart';

class AngestellteListScreen extends StatefulWidget {
  const AngestellteListScreen({Key? key}) : super(key: key);

  @override
  _AngestellteListScreenState createState() => _AngestellteListScreenState();
}

class _AngestellteListScreenState extends State<AngestellteListScreen> {
  final ApiService _apiService = ApiService();
  Future<List<Angestellte>>? _angestellteFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _angestellteFuture = _apiService.getAngestellte();
    });
  }

  void _showEmployeeDetails(Angestellte a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              CircleAvatar(
                radius: 36,
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  a.firstName != null && a.firstName!.isNotEmpty ? a.firstName![0] : (a.name.isNotEmpty ? a.name[0] : '?'),
                  style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                a.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (a.personalnummer != null && a.personalnummer!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Personal-Nr.: ${a.personalnummer}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
              if (a.qualifikation != null && a.qualifikation!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    a.qualifikation!,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Schnellaktionen
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (a.phoneNumber != null && a.phoneNumber!.isNotEmpty)
                    _actionButton(
                      icon: Icons.phone,
                      label: 'Anrufen',
                      color: Colors.green,
                      onTap: () async {
                        final uri = Uri.parse('tel:${a.phoneNumber}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                  if (a.emailAddress != null && a.emailAddress!.isNotEmpty)
                    _actionButton(
                      icon: Icons.email,
                      label: 'E-Mail',
                      color: Colors.blue,
                      onTap: () async {
                        final uri = Uri.parse('mailto:${a.emailAddress}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                  _actionButton(
                    icon: Icons.person,
                    label: 'Profil',
                    color: Theme.of(context).primaryColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AngestellteProfileScreen(angestellteId: a.id),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              if (a.phoneNumber != null && a.phoneNumber!.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.phone_outlined, size: 20),
                  title: const Text('Telefonnummer', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(a.phoneNumber!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  onTap: () async {
                    final uri = Uri.parse('tel:${a.phoneNumber}');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
              if (a.emailAddress != null && a.emailAddress!.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.email_outlined, size: 20),
                  title: const Text('E-Mail-Adresse', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  subtitle: Text(a.emailAddress!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  onTap: () async {
                    final uri = Uri.parse('mailto:${a.emailAddress}');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              radius: 24,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kollegen & Mitarbeiter'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Mitarbeiter suchen…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear())
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Angestellte>>(
              future: _angestellteFuture ?? Future.value([]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
                }
                final list = snapshot.data ?? [];
                final filtered = list.where((a) {
                  if (_searchQuery.isEmpty) return true;
                  final name = a.name.toLowerCase();
                  final pnum = (a.personalnummer ?? '').toLowerCase();
                  final qual = (a.qualifikation ?? '').toLowerCase();
                  return name.contains(_searchQuery) || pnum.contains(_searchQuery) || qual.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      list.isEmpty ? 'Keine Angestellten gefunden.' : 'Keine passenden Mitarbeiter gefunden.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final a = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.12),
                          child: Text(
                            a.firstName != null && a.firstName!.isNotEmpty ? a.firstName![0] : (a.name.isNotEmpty ? a.name[0] : '?'),
                            style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          a.qualifikation ?? (a.personalnummer != null ? 'PN: ${a.personalnummer}' : 'Mitarbeiter'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showEmployeeDetails(a),
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
  }
}
