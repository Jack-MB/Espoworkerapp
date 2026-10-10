import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/warehouse_depot.dart';
import '../services/warehouse_service.dart';
import 'depot_detail_screen.dart';

class WarehouseScannerScreen extends StatefulWidget {
  final String? preferredWarehouseId;
  final String? preferredWarehouseName;

  const WarehouseScannerScreen({
    super.key,
    this.preferredWarehouseId,
    this.preferredWarehouseName,
  });

  @override
  State<WarehouseScannerScreen> createState() => _WarehouseScannerScreenState();
}

class _WarehouseScannerScreenState extends State<WarehouseScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final WarehouseService _warehouseService = WarehouseService();
  bool _isProcessing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    _handleScanCode(rawValue.trim());
  }

  Future<void> _handleScanCode(String code) async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final result = await _warehouseService.resolveScan(
        code,
        warehouseId: widget.preferredWarehouseId,
      );

      if (!mounted) return;
      _showScanResultSheet(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan-Fehler: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _isProcessing = false);
    }
  }

  void _showManualInputDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Code manuell eingeben', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'z.B. WH-7EB2D29482C31B8E oder PR-...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            onPressed: () {
              final code = textController.text.trim();
              Navigator.pop(ctx);
              if (code.isNotEmpty) {
                _handleScanCode(code);
              }
            },
            child: const Text('Auflösen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showScanResultSheet(WarehouseScanResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (result.match == 'warehouse' && result.warehouse != null) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade900.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.warehouse_rounded, color: Color(0xFFC084FC), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.warehouse!.name,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Lager-Typ: ${result.warehouse!.lagerTyp} • ${result.warehouse!.qrToken ?? ""}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (result.warehouse!.addressStreet != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Standort: ${result.warehouse!.addressStreet}, ${result.warehouse!.addressCity ?? ""}',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.inventory_2, color: Colors.white),
                  label: const Text('Depot öffnen & Bestand einsehen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DepotDetailScreen(depot: result.warehouse!),
                      ),
                    );
                  },
                ),
              ] else if (result.match == 'product' && result.product != null) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.checkroom_rounded, color: Color(0xFF38BDF8), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.product!.productName,
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            result.product!.categoryName ?? 'Material / Kleidung',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Verfügbarer Gesamtbestand:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        '${result.product!.menge} ${result.product!.unit ?? "Stk."}',
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        label: const Text('Entnahme'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showQuickTransferDialog(result.product!, 'Entnahme');
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.white),
                        label: const Text('Rückgabe', style: TextStyle(color: Colors.white)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showQuickTransferDialog(result.product!, 'Rückgabe');
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Icon(Icons.info_outline, color: Colors.amber, size: 36),
                const SizedBox(height: 10),
                const Text('Unbekannter Code', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Code "${result.code}" konnte keinem Lagerort oder Artikel zugeordnet werden.', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Erneut scannen', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        );
      },
    ).whenComplete(() {
      setState(() => _isProcessing = false);
    });
  }

  void _showQuickTransferDialog(DepotStockItem item, String actionType) {
    double qty = 1.0;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('$actionType: ${item.productName}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                actionType == 'Entnahme' 
                    ? 'Ausgabe aus dem aktuellen Depot buchen.'
                    : 'Rücknahme in das Depot buchen.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.white70),
                    onPressed: qty > 1 ? () => setDlgState(() => qty--) : null,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text('$qty ${item.unit ?? "Stk."}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF8B5CF6)),
                    onPressed: () => setDlgState(() => qty++),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Bemerkung / Mitarbeiter',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await _warehouseService.quickBooking(
                  productId: item.productId,
                  menge: qty,
                  typ: actionType == 'Entnahme' ? 'Auftragsausgabe' : 'Auftragsruecknahme',
                  bemerkung: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? '$actionType erfolgreich gebucht!' : 'Buchung fehlgeschlagen.'),
                      backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  );
                }
              },
              child: const Text('Buchen', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Label / Barcode scannen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, color: _torchOn ? Colors.amber : Colors.white70),
            onPressed: () {
              _scannerController.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
            tooltip: 'Taschenlampe',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white70),
            onPressed: () => _scannerController.switchCamera(),
            tooltip: 'Kamera wechseln',
          ),
          IconButton(
            icon: const Icon(Icons.keyboard, color: Colors.white70),
            onPressed: _showManualInputDialog,
            tooltip: 'Code manuell eingeben',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // Viewfinder Overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF8B5CF6), width: 3),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // Top Info Banner
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                widget.preferredWarehouseName != null
                    ? 'Ziel: ${widget.preferredWarehouseName} • Barcode oder QR-Code im Rahmen zentrieren'
                    : 'QR-Code (Lagerort, Artikel, Zuweisung) im Rahmen zentrieren',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
              ),
            ),
        ],
      ),
    );
  }
}
