import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
import 'dart:ui' as ui;
import 'dart:convert';
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
  int _activeTab = 0; // 0: Bestand, 1: Ordnerkarten, 2: Anforderungen, 3: Ausrüstung
  bool _canManageHandover = false;
  List<dynamic> _issuedItems = [];
  List<dynamic> _availableHandoverItems = [];
  List<dynamic> _equipmentCatalog = [];

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
      final handoverFuture = _warehouseService.getDepotHandover(widget.depot.id);

      final results = await Future.wait([stockFuture, cardsFuture, reqsFuture, handoverFuture]);

      if (mounted) {
        final hData = results[3] as Map<String, dynamic>;
        setState(() {
          _stockItems = results[0] as List<DepotStockItem>;
          _ordnerkarten = results[1] as List<OrdnerkarteItem>;
          _requests = results[2] as List<MaterialRequestHeader>;
          _canManageHandover = hData['canManage'] == true;
          _issuedItems = hData['issuedItems'] as List;
          _availableHandoverItems = hData['availableItems'] as List;
          _equipmentCatalog = hData['equipmentCatalog'] as List;
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
          _buildTabButton(1, 'Karten (${_ordnerkarten.fold<int>(0, (s, c) => s + c.anzahl)})', Icons.badge),
          _buildTabButton(2, 'Bestellung (${_requests.length})', Icons.shopping_bag),
          _buildTabButton(3, 'Ausgabe (${_issuedItems.length})', Icons.handshake),
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
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 10.5,
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
      case 3:
        return _buildHandoverTab();
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

  // ==========================================
  // TAB 3: AUSRÜSTUNGSAUSGABE & RÜCKNAHME (WMS)
  // ==========================================

  Widget _buildHandoverTab() {
    return Column(
      children: [
        // Permission & Quick Action Header
        Container(
          padding: const EdgeInsets.all(14),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _canManageHandover ? const Color(0xFF064E3B) : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _canManageHandover ? const Color(0xFF10B981) : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _canManageHandover ? Icons.verified_user : Icons.lock_outline,
                      color: _canManageHandover ? const Color(0xFF10B981) : Colors.white60,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _canManageHandover ? 'Freigabe: Ausgabe aktiv' : 'Nur Ansicht (Keine Freigabe)',
                      style: TextStyle(
                        color: _canManageHandover ? const Color(0xFF10B981) : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_canManageHandover)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.handshake, size: 16, color: Colors.white),
                  label: const Text('Ausgeben', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _showIssueEquipmentDialog,
                ),
            ],
          ),
        ),

        // List of issued gear
        Expanded(
          child: _issuedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      const Text(
                        'Keine Ausrüstung aktuell verliehen',
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Alle Funkgeräte, Schlüssel und Ausstattungen befinden sich im Depot.',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      if (_canManageHandover) ...[
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('Erste Ausrüstung an Posten übergeben', style: TextStyle(color: Colors.white)),
                          onPressed: _showIssueEquipmentDialog,
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _issuedItems.length,
                  itemBuilder: (context, idx) {
                    final item = _issuedItems[idx] as Map<String, dynamic>;
                    final name = item['name']?.toString() ?? 'Ausrüstung';
                    final recipient = item['issuedToName']?.toString() ?? 'Mitarbeiter';
                    final persNr = item['issuedToPersonalnummer']?.toString();
                    final cat = item['category']?.toString() ?? 'other';
                    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toDouble() : 1.0;
                    final serial = item['serialNumber']?.toString();
                    final desc = item['description']?.toString();

                    IconData iconData = Icons.devices_other;
                    if (cat == 'radio') iconData = Icons.cell_tower;
                    if (cat == 'keys') iconData = Icons.vpn_key;
                    if (cat == 'flashlight') iconData = Icons.flashlight_on;
                    if (cat == 'clothing') iconData = Icons.shield;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(iconData, color: const Color(0xFFFBBF24), size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    if (serial != null && serial.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'SN / Barcode: $serial',
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${qty.toInt()}x Verliehen',
                                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person, color: Color(0xFF38BDF8), size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    persNr != null ? '$recipient (Pers.-Nr. $persNr)' : recipient,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (desc != null && desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              desc,
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          ],
                          if (_canManageHandover) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF10B981)),
                                  foregroundColor: const Color(0xFF10B981),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                label: const Text('Rücknahme quittieren', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: () => _showReturnEquipmentDialog(item),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showIssueEquipmentDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _IssueEquipmentSheet(
        warehouseId: widget.depot.id,
        availableItems: _availableHandoverItems,
        equipmentCatalog: _equipmentCatalog,
        warehouseService: _warehouseService,
        onSuccess: () {
          _loadAllData();
        },
      ),
    );
  }

  void _showReturnEquipmentDialog(Map<String, dynamic> item) async {
    String returnStatus = 'Zurückgegeben';
    final remarkCtrl = TextEditingController();
    String? signatureBase64;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.assignment_return_outlined, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 8),
              const Text('Rücknahme quittieren', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['name']?.toString() ?? 'Ausrüstung',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Von: ${item['issuedToName'] ?? "Mitarbeiter"}',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(height: 14),
              const Text('Zustand des Gegenstands:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _returnStatusChip('Zurückgegeben', 'Einwandfrei', returnStatus, (s) => setDlgState(() => returnStatus = s), const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _returnStatusChip('Beschädigt', 'Beschädigt', returnStatus, (s) => setDlgState(() => returnStatus = s), Colors.orange),
                  const SizedBox(width: 8),
                  _returnStatusChip('Verloren', 'Verloren', returnStatus, (s) => setDlgState(() => returnStatus = s), Colors.red),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: remarkCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Bemerkung (optional)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              if (signatureBase64 != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Rücknahme-Signatur erfasst',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      InkWell(
                        onTap: () => setDlgState(() => signatureBase64 = null),
                        child: const Icon(Icons.close, size: 14, color: Colors.white54),
                      ),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.draw_rounded, color: Color(0xFF38BDF8), size: 15),
                  label: const Text('Unterschrift erfassen (Optional)', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                  onPressed: () async {
                    final sig = await _showSignatureDialog(
                      context: context,
                      title: 'Rücknahme quittieren',
                      subtitle: 'Bitte unterschreibe auf dem Display zur Bestätigung der Rückgabe.',
                    );
                    if (sig != null) {
                      setDlgState(() => signatureBase64 = sig);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: returnStatus == 'Verloren' ? Colors.red.shade700 : const Color(0xFF10B981),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setDlgState(() => isSubmitting = true);
                      final zuweisungId = item['zuweisungId']?.toString() ?? item['id']?.toString() ?? '';
                      final res = await _warehouseService.returnDepotItem(
                        zuweisungId: zuweisungId,
                        warehouseId: widget.depot.id,
                        status: returnStatus,
                        bemerkung: remarkCtrl.text.trim().isNotEmpty ? remarkCtrl.text.trim() : null,
                        signature: signatureBase64,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['message'] ?? 'Rücknahme verbucht.'),
                            backgroundColor: res['success'] == true ? const Color(0xFF10B981) : Colors.red.shade700,
                          ),
                        );
                        _loadAllData();
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Quittieren', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _returnStatusChip(String id, String label, String currentStatus, Function(String) onSelect, Color color) {
    final isSelected = currentStatus == id;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.25) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : const Color(0xFF334155)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color : Colors.white70,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _showSignatureDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
}) async {
  final GlobalKey<SfSignaturePadState> signaturePadKey = GlobalKey();

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.draw_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    SfSignaturePad(
                      key: signaturePadKey,
                      strokeColor: Colors.white,
                      backgroundColor: const Color(0xFF0F172A),
                      minimumStrokeWidth: 2.0,
                      maximumStrokeWidth: 4.0,
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        icon: const Icon(Icons.clear, size: 14, color: Colors.white70),
                        label: const Text('Löschen', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        onPressed: () {
                          signaturePadKey.currentState?.clear();
                        },
                      ),
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: IgnorePointer(
                        child: Text(
                          'Hier unterschreiben ✍️',
                          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Ohne Unterschrift', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            icon: const Icon(Icons.check, size: 16, color: Colors.white),
            label: const Text('Bestätigen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              try {
                final image = await signaturePadKey.currentState!.toImage(pixelRatio: 2.0);
                final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                if (byteData != null) {
                  final bytes = byteData.buffer.asUint8List();
                  final b64 = base64Encode(bytes);
                  if (ctx.mounted) {
                    Navigator.pop(ctx, b64);
                  }
                  return;
                }
              } catch (e) {
                debugPrint('Signature capture error: $e');
              }
              if (ctx.mounted) {
                Navigator.pop(ctx, null);
              }
            },
          ),
        ],
      ),
    ),
  );
}

class _IssueEquipmentSheet extends StatefulWidget {
  final String warehouseId;
  final List<dynamic> availableItems;
  final List<dynamic> equipmentCatalog;
  final WarehouseService warehouseService;
  final VoidCallback onSuccess;

  const _IssueEquipmentSheet({
    required this.warehouseId,
    required this.availableItems,
    required this.equipmentCatalog,
    required this.warehouseService,
    required this.onSuccess,
  });

  @override
  State<_IssueEquipmentSheet> createState() => _IssueEquipmentSheetState();
}

class _IssueEquipmentSheetState extends State<_IssueEquipmentSheet> {
  final TextEditingController _empSearchCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _employeeSuggestions = [];
  Map<String, dynamic>? _selectedEmployee;
  bool _isSearchingEmp = false;
  bool _isSubmitting = false;
  String? _signatureBase64;

  String? _selectedProductId;
  String? _selectedProductName;

  @override
  void initState() {
    super.initState();
    _loadInitialEmployees();
    // Default product selection
    if (widget.availableItems.isNotEmpty) {
      final first = widget.availableItems.first as Map<String, dynamic>;
      _selectedProductId = first['productId']?.toString();
      _selectedProductName = first['name']?.toString();
    } else if (widget.equipmentCatalog.isNotEmpty) {
      final first = widget.equipmentCatalog.first as Map<String, dynamic>;
      _selectedProductId = first['id']?.toString();
      _selectedProductName = first['name']?.toString();
    }
  }

  @override
  void dispose() {
    _empSearchCtrl.dispose();
    _remarkCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialEmployees() async {
    setState(() => _isSearchingEmp = true);
    final res = await widget.warehouseService.searchEmployees(warehouseId: widget.warehouseId);
    if (mounted) {
      setState(() {
        _employeeSuggestions = res;
        _isSearchingEmp = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _isSearchingEmp = true);
    final res = await widget.warehouseService.searchEmployees(query: query, warehouseId: widget.warehouseId);
    if (mounted) {
      setState(() {
        _employeeSuggestions = res;
        _isSearchingEmp = false;
      });
    }
  }

  Future<void> _submitIssue() async {
    if (_isSubmitting) return;

    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wählen Sie einen Ausrüstungsgegenstand aus.')),
      );
      return;
    }

    if (_selectedEmployee == null && _empSearchCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wählen Sie einen Mitarbeiter aus.')),
      );
      return;
    }

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 1.0;
    final angId = _selectedEmployee?['id']?.toString() ?? '';

    if (angId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte wählen Sie einen gültigen Mitarbeiter aus der Liste aus.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final res = await widget.warehouseService.issueDepotItem(
      warehouseId: widget.warehouseId,
      productId: _selectedProductId!,
      angestellteId: angId,
      quantity: qty,
      bemerkung: _remarkCtrl.text.trim().isNotEmpty ? _remarkCtrl.text.trim() : null,
      signature: _signatureBase64,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Ausrüstung ausgegeben.'),
          backgroundColor: res['success'] == true ? const Color(0xFF10B981) : Colors.red.shade700,
        ),
      );
      if (res['success'] == true) {
        widget.onSuccess();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Combine available items and catalog for selection
    final Map<String, String> productOptions = {};
    for (var a in widget.availableItems) {
      if (a is Map<String, dynamic>) {
        final id = a['productId']?.toString();
        final name = a['name']?.toString();
        final qty = a['stockQuantity']?.toString();
        if (id != null && name != null) {
          productOptions[id] = qty != null ? '$name ($qty im Depot)' : name;
        }
      }
    }
    for (var c in widget.equipmentCatalog) {
      if (c is Map<String, dynamic>) {
        final id = c['id']?.toString();
        final name = c['name']?.toString();
        if (id != null && name != null && !productOptions.containsKey(id)) {
          productOptions[id] = name;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handshake, color: Color(0xFFC084FC), size: 24),
              const SizedBox(width: 10),
              const Text(
                'Ausrüstung vor Ort ausgeben',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Product Selector
          const Text('Ausrüstungsgegenstand', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProductId,
                dropdownColor: const Color(0xFF1E293B),
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFC084FC)),
                items: productOptions.entries.map((e) {
                  return DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedProductId = val;
                      _selectedProductName = productOptions[val];
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Employee Search
          const Text('Empfänger / Mitarbeiter', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: _empSearchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Name oder Personalnummer suchen...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFC084FC), size: 18),
              suffixIcon: _isSearchingEmp
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC084FC))))
                  : null,
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),

          // Suggestion list
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: _employeeSuggestions.isEmpty
                ? Center(
                    child: Text(
                      _isSearchingEmp ? 'Lade Mitarbeiter...' : 'Kein Mitarbeiter gefunden',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _employeeSuggestions.length,
                    itemBuilder: (context, idx) {
                      final emp = _employeeSuggestions[idx];
                      final isSelected = _selectedEmployee?['id'] == emp['id'];
                      final isToday = emp['heuteImDienst'] == true;

                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF8B5CF6).withOpacity(0.2),
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: isToday ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
                          child: Icon(
                            Icons.person,
                            size: 14,
                            color: isToday ? const Color(0xFF10B981) : Colors.white60,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              emp['name'] ?? '',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFC084FC) : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                            if (isToday) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF064E3B),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text('Heute im Dienst', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: emp['personalnummer'] != null
                            ? Text('Pers.-Nr: ${emp['personalnummer']}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10))
                            : null,
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6), size: 16) : null,
                        onTap: () {
                          setState(() {
                            _selectedEmployee = emp;
                            _empSearchCtrl.text = emp['name'] ?? '';
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Menge', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bemerkung (Posten / Anlass)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _remarkCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'z.B. Haupttor, Bühne...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_signatureBase64 != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Digitale Empfangsunterschrift erfasst ✓',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white60, size: 18),
                    tooltip: 'Unterschrift verwerfen',
                    onPressed: () => setState(() => _signatureBase64 = null),
                  ),
                ],
              ),
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.draw_rounded, color: Color(0xFF38BDF8), size: 18),
              label: const Text(
                'Digitale Unterschrift erfassen (Optional)',
                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final sig = await _showSignatureDialog(
                  context: context,
                  title: 'Ausrüstungs-Ausgabe quittieren',
                  subtitle: 'Bitte unterschreibe auf dem Display zur Bestätigung der Aushändigung von „${_selectedProductName ?? "Ausrüstung"}“.',
                );
                if (sig != null) {
                  setState(() => _signatureBase64 = sig);
                }
              },
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, color: Colors.white),
              label: Text(
                _isSubmitting ? 'Wird verbucht...' : 'Ausgabe verbindlich buchen',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: _isSubmitting ? null : _submitIssue,
            ),
          ),
        ],
      ),
    );
  }
}
