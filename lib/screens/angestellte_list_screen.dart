import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/angestellte.dart';

class AngestellteListScreen extends StatefulWidget {
  const AngestellteListScreen({Key? key}) : super(key: key);

  @override
  _AngestellteListScreenState createState() => _AngestellteListScreenState();
}

class _AngestellteListScreenState extends State<AngestellteListScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<Angestellte>> _zukunftigeAngestellte;

  @override
  void initState() {
    super.initState();
    _zukunftigeAngestellte = _apiService.getAngestellte();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Angestellte'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Angestellte>>(
        future: _zukunftigeAngestellte,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Angestellten gefunden.'));
          }

          final list = snapshot.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final a = list[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(a.firstName != null && a.firstName!.isNotEmpty ? a.firstName![0] : '?'),
                  ),
                  title: Text(a.name),
                  subtitle: Text(a.qualifikation ?? 'Keine Qualifikationen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: AngestellteDetailScreen
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Details für ${a.name} in Kürze!')));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
