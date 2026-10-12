import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/urlaub.dart';

class UrlaubScreen extends StatefulWidget {
  final bool embedded;
  const UrlaubScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  _UrlaubScreenState createState() => _UrlaubScreenState();
}

class _UrlaubScreenState extends State<UrlaubScreen> {
  final ApiService _apiService = ApiService();
  Future<List<Urlaub>>? _urlaubsFuture;
  Future<Map<String, dynamic>?>? _overviewFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _urlaubsFuture = _apiService.getUrlaubs();
      _overviewFuture = _apiService.getMyAbsenceOverview();
    });
  }

  void _showCreateUrlaubSheet(int? restUrlaub) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _CreateUrlaubForm(availableRestUrlaub: restUrlaub);
      },
    ).then((created) {
      if (created == true) {
        _loadData();
      }
    });
  }

  Widget _buildKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    bool isPrimary = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? color.withOpacity(0.12) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary ? color.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
            width: isPrimary ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isPrimary ? color : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUrlaubskontoHeader(Map<String, dynamic>? overview) {
    if (overview == null || overview['urlaub'] == null) {
      return const SizedBox.shrink();
    }

    final urlaubData = overview['urlaub'] as Map<String, dynamic>;
    final rest = urlaubData['restUrlaub'] ?? 0;
    final gesamt = urlaubData['gesamtUrlaub'] ?? 0;
    final genommen = urlaubData['genommenUrlaub'] ?? 0;
    final geplant = urlaubData['geplanterUrlaub'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, size: 18, color: Colors.teal),
              const SizedBox(width: 8),
              const Text(
                'Dein Urlaubskonto 2026',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildKpiCard(
                context: context,
                title: 'Resturlaub',
                value: '$rest Tage',
                icon: Icons.check_circle_outline,
                color: rest > 0 ? Colors.teal : Colors.orange,
                subtitle: 'verfügbar',
                isPrimary: true,
              ),
              const SizedBox(width: 8),
              _buildKpiCard(
                context: context,
                title: 'Anspruch',
                value: '$gesamt Tage',
                icon: Icons.calendar_today,
                color: Colors.blue.shade700,
                subtitle: 'Gesamtjahr',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildKpiCard(
                context: context,
                title: 'Genommen',
                value: '$genommen Tage',
                icon: Icons.done_all,
                color: Colors.indigo,
                subtitle: 'Genehmigt',
              ),
              const SizedBox(width: 8),
              _buildKpiCard(
                context: context,
                title: 'Geplant',
                value: '$geplant Tage',
                icon: Icons.hourglass_top,
                color: Colors.amber.shade800,
                subtitle: 'In Prüfung',
              ),
            ],
          ),
        ],
      ),
    );
  }

  int? _currentRestUrlaub;

  @override
  Widget build(BuildContext context) {
    final scaffoldBody = FutureBuilder<Map<String, dynamic>?>(
      future: _overviewFuture,
      builder: (context, overviewSnapshot) {
        final overview = overviewSnapshot.data;
        if (overview?['urlaub']?['restUrlaub'] is int) {
          _currentRestUrlaub = overview!['urlaub']['restUrlaub'] as int;
        }

        return RefreshIndicator(
          onRefresh: () async => _loadData(),
          child: Column(
            children: [
              _buildUrlaubskontoHeader(overview),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Urlaub>>(
                  future: _urlaubsFuture ?? Future.value([]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Fehler beim Laden: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 60),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.beach_access, size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text(
                                  'Keine Urlaubsanträge gefunden.',
                                  style: TextStyle(color: Colors.grey, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    final list = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 90),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final urlaub = list[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: urlaub.statusColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: urlaub.statusColor.withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        urlaub.status,
                                        style: TextStyle(
                                          color: urlaub.statusColor,
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
                                        urlaub.formattedDateRange +
                                            (urlaub.werktage != null
                                                ? ' (${urlaub.werktage} ${urlaub.werktage == 1 ? "Werktag" : "Werktage"})'
                                                : ''),
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (urlaub.kalendertage != null && urlaub.kalendertage != urlaub.werktage) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const SizedBox(width: 22),
                                      Text(
                                        '${urlaub.kalendertage} Kalendertage (Mo–Sa zählend)',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                                if (urlaub.description != null && urlaub.description!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    urlaub.description!,
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
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
      },
    );

    if (widget.embedded) {
      return scaffoldBody;
    }

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
      body: scaffoldBody,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateUrlaubSheet(_currentRestUrlaub),
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Neuer Antrag', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _CreateUrlaubForm extends StatefulWidget {
  final int? availableRestUrlaub;
  const _CreateUrlaubForm({Key? key, this.availableRestUrlaub}) : super(key: key);

  @override
  __CreateUrlaubFormState createState() => __CreateUrlaubFormState();
}

class __CreateUrlaubFormState extends State<_CreateUrlaubForm> {
  final _apiService = ApiService();
  final _descController = TextEditingController();
  DateTimeRange? _selectedRange;
  bool _isSubmitting = false;

  int _countWerktage(DateTime start, DateTime end) {
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cur.isAfter(last)) {
      if (cur.weekday != DateTime.sunday) {
        count++;
      }
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

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

    final start = _selectedRange!.start;
    final end = _selectedRange!.end;
    
    final startStr = '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')} 00:00:00';
    final endStr = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} 23:59:59';
    
    final success = await _apiService.createUrlaub(
      dateStart: startStr,
      dateEnd: endStr,
      description: _descController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Urlaubsantrag erfolgreich eingereicht!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Fehler beim Einreichen des Urlaubsantrags.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    int? calculatedWerktage;
    int? calculatedKalendertage;

    if (_selectedRange != null) {
      calculatedWerktage = _countWerktage(_selectedRange!.start, _selectedRange!.end);
      calculatedKalendertage = _selectedRange!.end.difference(_selectedRange!.start).inDays + 1;
    }

    final bool exceedsResturlaub = widget.availableRestUrlaub != null &&
        calculatedWerktage != null &&
        calculatedWerktage > widget.availableRestUrlaub!;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Neuen Urlaub beantragen', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.date_range),
            label: Text(
              _selectedRange == null
                  ? 'Zeitraum auswählen'
                  : '${DateFormat('dd.MM.yyyy').format(_selectedRange!.start)} – ${DateFormat('dd.MM.yyyy').format(_selectedRange!.end)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          if (_selectedRange != null && calculatedWerktage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Berechnung: $calculatedWerktage ${calculatedWerktage == 1 ? "Werktag" : "Werktage"} (Mo–Sa) • $calculatedKalendertage Kalendertage',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (exceedsResturlaub) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hinweis: Beantragt ($calculatedWerktage Tage) übersteigt deinen aktuellen Resturlaub (${widget.availableRestUrlaub} Tage). Der Antrag wird zur manuellen Prüfung weitergeleitet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Begründung / Bemerkung (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Antrag einreichen',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
