import 'package:flutter/material.dart';
import '../models/warehouse_depot.dart';
import '../models/ordnerkarte_item.dart';
import '../models/material_request.dart';
import '../services/warehouse_service.dart';
import 'warehouse_scanner_screen.dart';
import 'material_request_screen.dart';

class DepotDetailScreen extends StatefulWidget {
  final WarehouseDepot depot;

  const DepotDetailScreen({super.key, required this.depot});

  @override
  State<DepotDetailScreen> createState() => _DepotDetailScreenState();
}

class _DepotDetailScreenState extends State<DepotDetailScreen> {
  final WarehouseService _warehouseService = WarehouseService();
  List<DepotStockItem> _stockItems = [];
  List<OrdnerkarteItem> _ordnerkarten = [];
  List<MaterialRequestHeader> _requests = [];

  bool _isLoading = true;
  String _searchQuery = '';
  int _activeTab = 0; // 0: Bestand, 1: Ordnerkarten, 2: Anforderungen

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final stockFuture = _warehouseService.getDepotStock(widget.depot.id);
      final cardsFuture = _warehouseService.getDepotOrdnerkarten(widget.depot.id);
      final reqsFuture = _warehouseService.getMyMaterialAnforderungen(warehouseId: widget.depot.id);

      final results = await Future.wait([stockFuture, cardsFuture, reqsFuture]);

      if (mounted) {
        setState(() {
          _stockItems = results[0] as List<DepotStockItem>;
          _ordnerkarten = results[1] as List<OrdnerkarteItem>;
          _requests = results[2] as List<MaterialRequestHeader>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Depotdaten: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _confirmMaintenance(String type) async {
    final title = type == 'waesche' ? 'Wäsche-Turnus quittieren' : 'Materialprüfung quittieren';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          type == 'waesche'
              ? 'Wurden alle Wäschestücke dieses Depots gereinigt und wieder einsatzbereit eingeräumt?'
              : 'Wurden Einsatzmittel, Funkgeräte und Ausrüstung auf Unversehrtheit geprüft?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quittieren', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await _warehouseService.confirmMaintenance(widget.depot.id, type);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Erfolgreich quittiert!' : 'Fehler beim Quittieren.'),
            backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
        _loadAllData();
      }
    }
  }

  void _confirmMaterialDelivery(MaterialRequestHeader req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Icon(Icons.local_shipping, color: Color(0xFF38BDF8), size: 24),
            const SizedBox(width: 8),
            Text('Wareneingang quittieren', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Bestätigen Sie den Erhalt der Lieferung für "${req.bereich ?? widget.depot.name}" (${req.name}) vor Ort?\n\n'
          'Das gelieferte Material (${req.totalMenge.toInt()} Stück) wird damit automatisch in dieses Depot eingebucht.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wareneingang bestätigen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await _warehouseService.confirmMaterialDelivery(req.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Wareneingang erfolgreich quittiert!' : 'Fehler bei der Quittierung.'),
            backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
        _loadAllData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingDeliveries = _requests.where((r) => r.isPendingReceipt).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(widget.depot.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFC084FC)),
            tooltip: 'Artikel für dieses Depot scannen',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WarehouseScannerScreen(
                    preferredWarehouseId: widget.depot.id,
                    preferredWarehouseName: widget.depot.name,
                  ),
                ),
              ).then((_) => _loadAllData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Depot Header Summary Card with Multi-Responsibles and Material Request Button
          _buildDepotHeader(pendingDeliveries),
          // Tab Segmented Bar
          _buildTabBar(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                : _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDepotHeader(List<MaterialRequestHeader> pendingDeliveries) {
    final totalCards = _ordnerkarten.fold<int>(0, (sum, c) => sum + c.anzahl);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade900.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                    ),
                    child: Text(
                      widget.depot.lagerTyp,
                      style: const TextStyle(color: Color(0xFFC084FC), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.depot.userRole != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade400.withOpacity(0.3)),
                      ),
                      child: Text(
                        widget.depot.userRole!,
                        style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_shopping_cart, size: 16),
                label: const Text('Material anfordern', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MaterialRequestScreen(
                        warehouseId: widget.depot.id,
                        warehouseName: widget.depot.name,
                      ),
                    ),
                  ).then((val) {
                    if (val == true) _loadAllData();
                  });
                },
              ),
            ],
          ),
          if (widget.depot.addressStreet != null) ...[
            const SizedBox(height: 6),
            Text(
              '${widget.depot.addressStreet}, ${widget.depot.addressCity ?? ""}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          // Verantwortliche & Stellvertreter Zeile
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.depot.verantwortlicherName != null)
                  Row(
                    children: [
                      const Icon(Icons.shield, color: Color(0xFF38BDF8), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Objektleiter: ',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                      ),
                      Text(
                        widget.depot.verantwortlicherName!,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                if (widget.depot.weitereVerantwortlicheNames.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.people_alt, color: Color(0xFFA78BFA), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Stellvertreter: ',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                      ),
                      Expanded(
                        child: Text(
                          widget.depot.weitereVerantwortlicheNames.join(', '),
                          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Pending Deliveries Notice Banner
          if (pendingDeliveries.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _activeTab = 2),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🚚 ${pendingDeliveries.length} Lieferung(en) eingetroffen – bitte quittieren!',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Maintenance Actions & Cards Summary Chip
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                backgroundColor: const Color(0xFF334155),
                avatar: const Icon(Icons.local_laundry_service, color: Color(0xFF38BDF8), size: 15),
                label: const Text('Wäsche quittieren', style: TextStyle(color: Colors.white, fontSize: 11)),
                onPressed: () => _confirmMaintenance('waesche'),
              ),
              ActionChip(
                backgroundColor: const Color(0xFF334155),
                avatar: const Icon(Icons.verified, color: Color(0xFF34D399), size: 15),
                label: const Text('Prüfung quittieren', style: TextStyle(color: Colors.white, fontSize: 11)),
                onPressed: () => _confirmMaintenance('pruefung'),
              ),
              if (totalCards > 0)
                ActionChip(
                  backgroundColor: Colors.teal.shade900.withOpacity(0.5),
                  avatar: const Icon(Icons.badge, color: Color(0xFF2DD4BF), size: 15),
                  label: Text('$totalCards Ordnerkarten', style: const TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => setState(() => _activeTab = 1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          _buildTabButton(0, 'Bestand (${_stockItems.length})', Icons.inventory_2),
          _buildTabButton(1, 'Ordnerkarten (${_ordnerkarten.fold<int>(0, (s, c) => s + c.anzahl)})', Icons.badge),
          _buildTabButton(2, 'Anforderungen (${_requests.length})', Icons.shopping_bag),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFFC084FC) : Colors.white54),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 0:
        return _buildStockList();
      case 1:
        return _buildOrdnerkartenList();
      case 2:
        return _buildRequestsList();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStockList() {
    final filtered = _stockItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item.productName.toLowerCase().contains(q) ||
          (item.categoryName?.toLowerCase().contains(q) ?? false) ||
          (item.partNumber?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Artikel im Depot suchen...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty ? 'Keine passenden Artikel gefunden.' : 'Dieses Depot ist aktuell leer.',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final item = filtered[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: item.isLowStock ? Colors.amber.withOpacity(0.4) : const Color(0xFF334155),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              item.categoryName?.contains('Kleidung') ?? false ? Icons.checkroom : Icons.devices_other,
                              color: const Color(0xFFC084FC),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(item.categoryName ?? 'Artikel', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                if (item.isLowStock)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '⚠️ Mindestbestand (${item.minStock}) erreicht!',
                                      style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item.menge.toStringAsFixed(0)} ${item.unit ?? "Stk."}',
                                style: TextStyle(
                                  color: item.menge <= 0 ? Colors.red.shade400 : const Color(0xFF34D399),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (item.qrToken != null)
                                Text(item.qrToken!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOrdnerkartenList() {
    if (_ordnerkarten.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.badge, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            const Text('Keine Ordnerkarten an diesem Depot hinterlegt.', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 12),
            Text('Ordnerkarten können im CRM-Lagerort hinterlegt werden.', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ordnerkarten.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final card = _ordnerkarten[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade900.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.badge, color: Color(0xFF2DD4BF), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(card.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: card.isImDepot ? Colors.green.shade900.withOpacity(0.4) : Colors.orange.shade900.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      card.status,
                      style: TextStyle(
                        color: card.isImDepot ? const Color(0xFF34D399) : Colors.orange.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nummernkreis:', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                      Text(card.nummernkreis ?? '–', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Stückzahl:', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                      Text('${card.anzahl} Stück', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ],
              ),
              if (card.einzelnummern != null && card.einzelnummern!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Verfügbare Nummern: ${card.einzelnummern}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
              ],
              if (card.angestellteName != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFFA78BFA), size: 14),
                    const SizedBox(width: 4),
                    Text('Ausgegeben an: ${card.angestellteName}', style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestsList() {
    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_bag_outlined, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            const Text('Keine Materialanforderungen für dieses Depot.', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Jetzt Material anfordern'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MaterialRequestScreen(
                      warehouseId: widget.depot.id,
                      warehouseName: widget.depot.name,
                    ),
                  ),
                ).then((val) {
                  if (val == true) _loadAllData();
                });
              },
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final req = _requests[i];
        final isDelivered = req.isPendingReceipt;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDelivered ? const Color(0xFF10B981) : const Color(0xFF334155),
              width: isDelivered ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(req.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(req.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor(req.status).withOpacity(0.5)),
                    ),
                    child: Text(
                      req.status,
                      style: TextStyle(color: _statusColor(req.status), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (req.bereich != null)
                Text('Bereich vor Ort: ${req.bereich}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600)),
              Text('Angefordert von: ${req.anfordererName ?? "Unbekannt"} · ${req.createdAt.split(" ")[0]}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
              const SizedBox(height: 8),
              Text('${req.itemCount} Positionen · ${req.totalMenge.toInt()} Stück gesamt', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (req.begruendung != null && req.begruendung!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Grund: ${req.begruendung}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontStyle: FontStyle.italic)),
              ],
              if (isDelivered) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                    label: const Text('Wareneingang vor Ort quittieren', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _confirmMaterialDelivery(req),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Eingereicht':
        return Colors.orange;
      case 'Genehmigt':
        return Colors.blue;
      case 'In Kommissionierung':
      case 'In Zustellung':
        return const Color(0xFF38BDF8);
      case 'Geliefert':
      case 'Quittiert':
        return const Color(0xFF10B981);
      case 'Abgelehnt':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}


