import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/wachbuch.dart';
import 'wachbuch_detail_screen.dart';
import '../core/constants.dart';

class WachbuchListScreen extends StatefulWidget {
  final String? highlightId;
  const WachbuchListScreen({Key? key, this.highlightId}) : super(key: key);

  @override
  _WachbuchListScreenState createState() => _WachbuchListScreenState();
}

class _WachbuchListScreenState extends State<WachbuchListScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<Wachbuch>> _wachbuchFuture;

  @override
  void initState() {
    super.initState();
    _wachbuchFuture = _apiService.getWachbuchs();
  }

  void _loadData() {
    setState(() {
      _wachbuchFuture = _apiService.getWachbuchs();
    });
  }

  Color _getStatusColor(String status) {
    if (status == 'Active') return Colors.green;
    if (status == 'Closed') return Colors.grey;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wachbuch'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: FutureBuilder<List<Wachbuch>>(
        future: _wachbuchFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Wachbuch-Einträge gefunden.'));
          }

          final list = snapshot.data!;
          
          // Level 2: Auto-open if highlightId matches
          if (widget.highlightId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final match = list.where((w) => w.id == widget.highlightId).toList();
              if (match.isNotEmpty) {
                // Remove highlightId once handled (navigation only happens once)
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WachbuchDetailScreen(wachbuch: match.first),
                  ),
                );
              }
            });
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final w = list[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(
                    w.name, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WachbuchDetailScreen(wachbuch: w),
                      ),
                    );
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
