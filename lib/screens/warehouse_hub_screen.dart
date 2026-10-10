import 'package:flutter/material.dart';
import '../models/warehouse_depot.dart';
import '../services/warehouse_service.dart';
import 'depot_detail_screen.dart';
import 'warehouse_scanner_screen.dart';

class WarehouseHubScreen extends StatefulWidget {
  const WarehouseHubScreen({super.key});

  @override
  State<WarehouseHubScreen> createState() => _WarehouseHubScreenState();
}

class _WarehouseHubScreenState extends State<WarehouseHubScreen> with SingleTickerProviderStateMixin {
  final WarehouseService _warehouseService = WarehouseService();
  late TabController _tabController;

  bool _isLoading = true;
  List<WarehouseDepot> _myDepots = [];
  List<WarehouseDepot> _allDepots = [];
  List<PersonalEquipmentItem> _myEquipment = [];
  bool _canManageAllDepots = false;
  Map<String, dynamic>? _angestellte;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final data = await _warehouseService.getOverview(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _myDepots = data['myDepots'] as List<WarehouseDepot>;
          _allDepots = data['allDepots'] as List<WarehouseDepot>;
          _myEquipment = data['myEquipment'] as List<PersonalEquipmentItem>;
          _canManageAllDepots = data['canManageAllDepots'] == true;
          _angestellte = data['angestellte'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Material, Kleidung & Depots',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFC084FC)),
            tooltip: 'Label scannen',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WarehouseScannerScreen()),
              ).then((_) => _loadData(forceRefresh: true));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _loadData(forceRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8B5CF6),
          labelColor: const Color(0xFFC084FC),
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'Meine Depots (${_myDepots.length})'),
            Tab(text: 'Meine Ausrüstung (${_myEquipment.length})'),
            Tab(text: _canManageAllDepots ? 'Alle Depots (${_allDepots.length})' : 'Übersicht'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMyDepotsTab(),
                _buildMyEquipmentTab(),
                _buildAllDepotsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF8B5CF6),
        icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
        label: const Text('Label scannen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WarehouseScannerScreen()),
          ).then((_) => _loadData(forceRefresh: true));
        },
      ),
    );
  }

  Widget _buildMyDepotsTab() {
    if (_myDepots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.white30, size: 54),
              const SizedBox(height: 16),
              const Text(
                'Keine persönlichen Depots zugeordnet',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sie sind aktuell für kein Objekt- oder Materialdepot als Hauptverantwortlicher hinterlegt.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Depot per QR-Code scannen'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WarehouseScannerScreen()),
                  ).then((_) => _loadData(forceRefresh: true));
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _myDepots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildDepotCard(_myDepots[i]),
    );
  }

  Widget _buildAllDepotsTab() {
    final depotsToShow = _canManageAllDepots ? _allDepots : _myDepots;

    if (depotsToShow.isEmpty) {
      return const Center(
        child: Text('Keine Depots vorhanden', style: TextStyle(color: Colors.white60)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: depotsToShow.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildDepotCard(depotsToShow[i]),
    );
  }

  Widget _buildDepotCard(WarehouseDepot depot) {
    Color typeColor = const Color(0xFF8B5CF6);
    if (depot.lagerTyp == 'Hauptlager') typeColor = Colors.blue;
    if (depot.lagerTyp == 'Objektlager') typeColor = Colors.teal;
    if (depot.lagerTyp == 'Mitarbeiterlager') typeColor = Colors.amber;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DepotDetailScreen(depot: depot)),
        ).then((_) => _loadData());
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: depot.isMaintenanceNeeded ? Colors.red.withOpacity(0.5) : const Color(0xFF334155),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.warehouse, color: typeColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    depot.name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          depot.lagerTyp,
                          style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (depot.isMaintenanceNeeded) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            depot.wartungStatus,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (depot.addressStreet != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${depot.addressStreet}, ${depot.addressCity ?? ""}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _buildAngestellteProfileCard() {
    if (_angestellte == null) return const SizedBox.shrink();

    final name = _angestellte!['name'] ?? 'Mitarbeiter';
    final personalnummer = _angestellte!['personalnummer'] ?? '';
    final jSize = _angestellte!['groesseJacke']?.toString();
    final hSize = _angestellte!['groesseHose']?.toString();
    final sSize = _angestellte!['groesseSchuhe']?.toString();
    final wSize = _angestellte!['groesseWeste']?.toString();
    final hemSize = _angestellte!['groesseHemd']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge, color: Color(0xFF60A5FA), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (personalnummer.isNotEmpty)
                      Text(
                        'Personal-Nr.: $personalnummer',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Stammdaten aktiv',
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 12),
          const Text(
            'Hinterlegte Kleider- & Schuhgrößen:',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSizeChip('Jacke', jSize),
              _buildSizeChip('Hose', hSize),
              _buildSizeChip('Schuhe', sSize),
              _buildSizeChip('Weste', wSize),
              _buildSizeChip('Hemd', hemSize),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeChip(String label, String? value) {
    final hasVal = value != null && value.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasVal ? const Color(0xFF8B5CF6).withOpacity(0.4) : const Color(0xFF334155),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(
            hasVal ? value : '-',
            style: TextStyle(
              color: hasVal ? const Color(0xFFC084FC) : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyEquipmentTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _buildAngestellteProfileCard(),
        if (_myEquipment.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.checkroom_outlined, color: Colors.white30, size: 54),
                  SizedBox(height: 16),
                  Text(
                    'Keine persönliche Ausrüstung ausgegeben',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ihnen ist im MB-SCC System aktuell keine persönliche Dienstkleidung oder Material zugewiesen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text(
              'Ausgegebene Kleidung & Ausstattung (${_myEquipment.length})',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          ..._myEquipment.map((item) {
            final isCloth = item.category?.contains('Kleidung') ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isCloth ? Colors.purple.withOpacity(0.15) : Colors.cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCloth ? Icons.checkroom : Icons.radio,
                      color: isCloth ? const Color(0xFFC084FC) : const Color(0xFF38BDF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.category ?? 'Dienstausstattung',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        if (item.serialNumber != null || item.size != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (item.size != null)
                                Text('Größe: ${item.size} • ', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                              if (item.serialNumber != null)
                                Text('SN: ${item.serialNumber}', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${item.quantity.toStringAsFixed(0)}x',
                      style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
