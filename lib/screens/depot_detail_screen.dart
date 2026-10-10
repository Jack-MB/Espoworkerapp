import 'package:flutter/material.dart';
import '../models/warehouse_depot.dart';
import '../services/warehouse_service.dart';
import 'warehouse_scanner_screen.dart';

class DepotDetailScreen extends StatefulWidget {
  final WarehouseDepot depot;

  const DepotDetailScreen({super.key, required this.depot});

  @override
  State<DepotDetailScreen> createState() => _DepotDetailScreenState();
}

class _DepotDetailScreenState extends State<DepotDetailScreen> {
  final WarehouseService _warehouseService = WarehouseService();
  List<DepotStockItem> _stockItems = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    setState(() => _isLoading = true);
    try {
      final items = await _warehouseService.getDepotStock(widget.depot.id);
      if (mounted) {
        setState(() {
          _stockItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden des Bestands: $e'), backgroundColor: Colors.red.shade700),
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
        _loadStock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _stockItems.where((item) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return item.productName.toLowerCase().contains(q) ||
          (item.categoryName?.toLowerCase().contains(q) ?? false) ||
          (item.partNumber?.toLowerCase().contains(q) ?? false);
    }).toList();

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
              ).then((_) => _loadStock());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadStock,
          ),
        ],
      ),
      body: Column(
        children: [
          // Depot Header Summary Card
          Container(
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
                    if (widget.depot.qrToken != null)
                      Text(
                        'Token: ${widget.depot.qrToken}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                  ],
                ),
                if (widget.depot.addressStreet != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${widget.depot.addressStreet}, ${widget.depot.addressCity ?? ""}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                // Maintenance Actions
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      backgroundColor: const Color(0xFF334155),
                      avatar: const Icon(Icons.local_laundry_service, color: Color(0xFF38BDF8), size: 16),
                      label: const Text('Wäsche quittieren', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () => _confirmMaintenance('waesche'),
                    ),
                    ActionChip(
                      backgroundColor: const Color(0xFF334155),
                      avatar: const Icon(Icons.verified, color: Color(0xFF34D399), size: 16),
                      label: const Text('Prüfung quittieren', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () => _confirmMaintenance('pruefung'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Search Field
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
          // Stock Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6)))
                : filtered.isEmpty
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
                                    item.categoryName?.contains('Kleidung') ?? false
                                        ? Icons.checkroom
                                        : Icons.devices_other,
                                    color: const Color(0xFFC084FC),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.categoryName ?? 'Artikel',
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
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
                                      Text(
                                        item.qrToken!,
                                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
