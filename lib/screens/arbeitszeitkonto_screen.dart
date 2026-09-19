import 'package:flutter/material.dart';
import '../models/arbeitszeitkonto.dart';
import '../services/api_service.dart';
import '../services/acl_service.dart';
import '../services/secure_storage_service.dart';
import '../core/constants.dart';

class ArbeitszeitkontoScreen extends StatefulWidget {
  const ArbeitszeitkontoScreen({Key? key}) : super(key: key);

  @override
  State<ArbeitszeitkontoScreen> createState() => _ArbeitszeitkontoScreenState();
}

class _ArbeitszeitkontoScreenState extends State<ArbeitszeitkontoScreen> {
  final ApiService _api = ApiService();
  final AclService _acl = AclService();
  final SecureStorageService _storage = SecureStorageService();

  List<Arbeitszeitkonto> _records = [];
  bool _isLoading = true;
  bool _canSearch = false;
  String? _myAngestellteId;

  // Local client-side filters — no API call needed
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _filterJahr;
  int? _filterMonat;

  static const _monatLabels = [
    '', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _acl.refresh();
    _canSearch = _acl.isAdmin || _acl.isAppManager;
    _myAngestellteId = await _storage.getAngestellteId(); // correct key: 'angestellteId'
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // Regular employees see only their own records; admins/managers see all internal records
    final records = await _api.getArbeitszeitkonten(
      angestellteId: _canSearch ? null : _myAngestellteId,
      limit: 500,
    );
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// All unique years present in loaded records (descending).
  List<int> get _availableJahre {
    final years = _records.map((r) => r.jahr).whereType<int>().toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Records filtered by name, year and month.
  List<Arbeitszeitkonto> get _filtered {
    return _records.where((r) {
      if (_searchQuery.isNotEmpty &&
          !(r.angestellteName ?? '').toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_filterJahr != null && r.jahr != _filterJahr) return false;
      if (_filterMonat != null && int.tryParse(r.monat ?? '') != _filterMonat) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Arbeitszeitkonten'),
        backgroundColor: AppConstants.primaryColor,
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
          // Filter bar — only for admins/managers
          if (_canSearch) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  // Name search
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        hintText: 'Name filtern...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Year dropdown
                  DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<int?>(
                        value: _filterJahr,
                        isDense: true,
                        hint: const Text('Jahr', style: TextStyle(fontSize: 13)),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Alle', style: TextStyle(fontSize: 13))),
                          ..._availableJahre.map((y) => DropdownMenuItem<int?>(
                            value: y,
                            child: Text('$y', style: const TextStyle(fontSize: 13)),
                          )),
                        ],
                        onChanged: (v) => setState(() => _filterJahr = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Month chips
            if (_filterJahr != null)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    final active = _filterMonat == m;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(_monatLabels[m], style: const TextStyle(fontSize: 12)),
                        selected: active,
                        onSelected: (_) => setState(() => _filterMonat = active ? null : m),
                        selectedColor: AppConstants.primaryColor.withOpacity(0.2),
                        checkmarkColor: AppConstants.primaryColor,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }),
                ),
              ),
            // Active filter count
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} von ${_records.length} Einträgen',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty || _filterJahr != null || _filterMonat != null) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _filterJahr = null;
                          _filterMonat = null;
                        });
                      },
                      child: Text(
                        'Filter zurücksetzen',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppConstants.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Records
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => _buildCard(_filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }


  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.access_time, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'Kein Eintrag für "$_searchQuery" gefunden'
                : 'Keine Arbeitszeitkonten gefunden',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Arbeitszeitkonto azk) {
    final isPositive = (azk.ueberstunden ?? 0) >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: AppConstants.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${azk.monatLabel} ${azk.jahr ?? ''}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (azk.angestellteName != null && azk.angestellteName!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.person, color: Colors.white60, size: 13),
                            const SizedBox(width: 4),
                            Text(
                              azk.angestellteName!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (azk.freigegeben)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('✓ Freigegeben', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ],
            ),
          ),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Hours row
                Row(
                  children: [
                    _statTile('Soll', '${(azk.sollStunden ?? 0).toStringAsFixed(1)} h', Icons.schedule, Colors.blue.shade700),
                    _statTile('Ist', '${azk.istStundenEffektiv.toStringAsFixed(1)} h', Icons.check_circle_outline, Colors.green.shade700),
                    _statTile(
                      'Überstunden',
                      '${isPositive ? '+' : ''}${(azk.ueberstunden ?? 0).toStringAsFixed(1)} h',
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      isPositive ? Colors.orange.shade700 : Colors.red.shade700,
                    ),
                  ],
                ),
                const Divider(height: 16),
                // Days row
                Row(
                  children: [
                    _statTile('Arbeitstage', '${azk.arbeitsTage ?? 0}', Icons.work_outline, Colors.blueGrey),
                    _kranktageTile(azk),
                    _urlaubTile(azk),
                  ],
                ),
                const Divider(height: 16),
                // Extra hours row
                Row(
                  children: [
                    _statTile('Nacht', '${(azk.nachtStunden ?? 0).toStringAsFixed(1)} h', Icons.nights_stay, Colors.indigo.shade400),
                    _statTile('Sa', '${(azk.samstagStunden ?? 0).toStringAsFixed(1)} h', Icons.weekend, Colors.purple.shade400),
                    _statTile('So/FT', '${((azk.sonntagStunden ?? 0) + (azk.feiertagStunden ?? 0)).toStringAsFixed(1)} h', Icons.wb_sunny_outlined, Colors.orange.shade400),
                  ],
                ),
                const Divider(height: 16),
                // Punctuality row — always shown
                Row(
                  children: [
                    _puenktlichkeitTile(azk.durchschnPuenktlichkeit),
                    _statTile('Einsatzorte', '${azk.einsatzorte ?? 0}', Icons.location_on_outlined, Colors.blueGrey),
                    if ((azk.verstossAnzahl ?? 0) > 0)
                      _statTile('AZ-Verstöße', '${azk.verstossAnzahl}', Icons.warning_amber, Colors.red.shade700)
                    else
                      _statTile('Verstöße', '0', Icons.verified, Colors.green.shade700),
                  ],
                ),

                if (azk.notizen != null && azk.notizen!.isNotEmpty) ...[
                  const Divider(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(azk.notizen!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sick days tile showing both categories with clear labels.
  Widget _kranktageTile(Arbeitszeitkonto azk) {
    final total = azk.krankTageEffektiv;
    final mitSchicht = azk.krankTageMitSchicht ?? 0;
    final ohneSchicht = azk.krankTageOhneSchicht ?? 0;
    final color = Colors.red.shade400;
    
    final krankH = (total * (azk.referenzStundenProTag ?? 0.0)).toStringAsFixed(1);

    return Expanded(
      child: Column(
        children: [
          Icon(Icons.local_hospital, color: color, size: 20),
          const SizedBox(height: 4),
          Text('$total T', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          Text('≈ $krankH h', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.9))),
          Text('Kranktage',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65)),
              textAlign: TextAlign.center),
          if (total > 0 && azk.hasKrankDetail) ...[
            const SizedBox(height: 2),
            Text(
              '🏥 $mitSchicht m.Schicht\n🏠 $ohneSchicht o.Schicht',
              style: TextStyle(fontSize: 9, color: color.withOpacity(0.8), height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _urlaubTile(Arbeitszeitkonto azk) {
    final total = azk.urlaubsTageEffektiv;
    final color = Colors.teal.shade600;
    
    final urlaubH = (total * (azk.referenzStundenProTag ?? 0.0)).toStringAsFixed(1);

    return Expanded(
      child: Column(
        children: [
          Icon(Icons.flight_takeoff, color: color, size: 20),
          const SizedBox(height: 4),
          Text('$total T', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          Text('≈ $urlaubH h', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.withOpacity(0.9))),
          Text('Urlaub',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          Text(label,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// Pünktlichkeit-Kachel mit Ampel-Logik.
  /// [minutes] = Ø Abweichung in Minuten relativ zum Schichtbeginn
  ///   negativ = früher als Schichtbeginn eingecheckt
  ///   positiv = später als Schichtbeginn eingecheckt
  ///
  /// 🟢 ≤ -30 Min → ≥30 Min vor Schichtbeginn eingecheckt (pünktlich)
  /// 🟡 -30 < x ≤ 0 → innerhalb der 30-Min-Pufferzone (noch ok)
  /// 🔴 > 0 Min → nach Schichtbeginn eingecheckt (verspätet)
  Widget _puenktlichkeitTile(double? minutes) {
    final min = minutes ?? 0;
    final String dot;
    final Color color;
    final String label;

    if (min <= -30) {
      dot = '🟢';
      color = Colors.green.shade700;
      label = '${min.abs().toStringAsFixed(0)} Min früher';
    } else if (min <= 0) {
      dot = '🟡';
      color = Colors.orange.shade700;
      label = min == 0 ? 'genau pünktlich' : '${min.abs().toStringAsFixed(0)} Min früher';
    } else {
      dot = '🔴';
      color = Colors.red.shade700;
      label = '+${min.toStringAsFixed(0)} Min verspätet';
    }

    return Expanded(
      child: Column(
        children: [
          Text(dot, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11)),
          Text('Ø Pünktlichkeit',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}


