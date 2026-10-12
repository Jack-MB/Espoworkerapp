import 'package:flutter/material.dart';
import '../models/material_request.dart';
import '../services/warehouse_service.dart';

/// Screen für Verantwortliche zur Anforderung von Material für einen Bereich / Objektlager
class MaterialRequestScreen extends StatefulWidget {
  final String warehouseId;
  final String warehouseName;

  const MaterialRequestScreen({
    super.key,
    required this.warehouseId,
    required this.warehouseName,
  });

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen> {
  final WarehouseService _warehouseService = WarehouseService();
  final TextEditingController _bereichController = TextEditingController();
  final TextEditingController _begruendungController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _dringlichkeit = 'Standard'; // 'Standard', 'Hoch', 'Notfall'
  DateTime _benoetigtBis = DateTime.now().add(const Duration(days: 1, hours: 4));

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  Map<String, List<CatalogProduct>> _catalog = {};
  String? _selectedCategory;
  final List<Map<String, dynamic>> _cart = [];

  final List<String> _clothingSizes = [
    'XS', 'S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', 'Einheitsgröße'
  ];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _bereichController.dispose();
    _begruendungController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cats = await _warehouseService.getMaterialKatalog();
      if (mounted) {
        setState(() {
          _catalog = cats;
          if (cats.isNotEmpty) {
            _selectedCategory = cats.keys.first;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _addToCart(CatalogProduct prod, {String? size, double quantity = 1.0}) {
    final existingIndex = _cart.indexWhere(
      (item) => item['productId'] == prod.id && item['groesse'] == size,
    );

    setState(() {
      if (existingIndex >= 0) {
        _cart[existingIndex]['menge'] = (_cart[existingIndex]['menge'] as double) + quantity;
      } else {
        _cart.add({
          'productId': prod.id,
          'productName': prod.name,
          'category': prod.category,
          'menge': quantity,
          'einheit': 'Stk.',
          'groesse': size,
          'bemerkung': '',
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${prod.name} ${size != null ? "($size) " : ""}hinzugefügt'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _updateCartQty(int index, double delta) {
    setState(() {
      final newQty = (_cart[index]['menge'] as double) + delta;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index]['menge'] = newQty;
      }
    });
  }

  Future<void> _submitRequest() async {
    final bereich = _bereichController.text.trim();
    if (bereich.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte den Einsatzbereich vor Ort angeben (z. B. VIP-Bereich, Einlass West).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens einen Artikel in den Warenkorb legen.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final success = await _warehouseService.createMaterialAnforderung(
        zielLagerId: widget.warehouseId,
        bereich: bereich,
        dringlichkeit: _dringlichkeit,
        benoetigtBis: _benoetigtBis,
        begruendung: _begruendungController.text.trim(),
        items: _cart,
      );

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        if (success) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text('Erfolgreich beantragt'),
                ],
              ),
              content: Text(
                'Ihre Materialanforderung für "$bereich" (${widget.warehouseName}) wurde an die Disposition übermittelt.\n\n'
                'Sie werden benachrichtigt, sobald die Lieferung gepackt ist.',
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, true);
                  },
                  child: const Text('Schließen'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fehler beim Einreichen der Anforderung.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Material anfordern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.warehouseName, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomCartBar(theme),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _loadCatalog, child: const Text('Erneut versuchen')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    _buildScopeCard(theme),
                    const SizedBox(height: 16),
                    _buildCatalogCard(theme),
                  ],
                ),
    );
  }

  Widget _buildScopeCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Einsatzort & Dringlichkeit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bereichController,
              decoration: InputDecoration(
                labelText: 'Bereich vor Ort *',
                hintText: 'z. B. Einlass West, Nordtribüne Block B, VIP-Zelt',
                prefixIcon: const Icon(Icons.pin_drop_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            const Text('Dringlichkeit:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildPriorityChip('Standard', Colors.blue),
                const SizedBox(width: 8),
                _buildPriorityChip('Hoch', Colors.orange),
                const SizedBox(width: 8),
                _buildPriorityChip('Notfall', Colors.red),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _begruendungController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Begründung / Hinweis an Lager',
                hintText: 'z. B. Erhöhtes Besucheraufkommen, Ersatz für defekte Funktechnik',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityChip(String label, Color color) {
    final isSelected = _dringlichkeit == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: isSelected ? color : Colors.grey.shade300),
      onSelected: (val) {
        if (val) setState(() => _dringlichkeit = label);
      },
    );
  }

  Widget _buildCatalogCard(ThemeData theme) {
    final categories = _catalog.keys.toList();
    final currentProducts = _catalog[_selectedCategory] ?? [];
    final searchQuery = _searchController.text.trim().toLowerCase();

    final filteredProducts = currentProducts.where((p) {
      if (searchQuery.isEmpty) return true;
      return p.name.toLowerCase().contains(searchQuery) ||
          (p.partNumber != null && p.partNumber!.toLowerCase().contains(searchQuery));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Material-Katalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${filteredProducts.length} Artikel', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Artikel oder Art.-Nr. filtern …',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _searchController.clear()))
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          ),
        ),
        const SizedBox(height: 10),
        if (categories.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final isSelected = cat == _selectedCategory;
                return ChoiceChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (v) {
                    if (v) setState(() => _selectedCategory = cat);
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        if (filteredProducts.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text('Keine passenden Artikel in "$_selectedCategory" gefunden.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          ...filteredProducts.map((p) => _buildProductRow(theme, p)),
      ],
    );
  }

  Widget _buildProductRow(ThemeData theme, CatalogProduct prod) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: prod.isCard
                    ? Colors.teal.withOpacity(0.12)
                    : (prod.hasSizes ? Colors.amber.withOpacity(0.12) : theme.colorScheme.primaryContainer.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                prod.isCard ? Icons.badge : (prod.hasSizes ? Icons.checkroom : Icons.inventory_2),
                color: prod.isCard ? Colors.teal : (prod.hasSizes ? Colors.amber.shade800 : theme.colorScheme.primary),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prod.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (prod.partNumber != null)
                    Text('Art.-Nr.: ${prod.partNumber}', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (prod.hasSizes)
              IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Größe wählen',
                onPressed: () => _promptSizePicker(prod),
              )
            else
              IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Hinzufügen',
                onPressed: () => _addToCart(prod),
              ),
          ],
        ),
      ),
    );
  }

  void _promptSizePicker(CatalogProduct prod) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Größe wählen für:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _clothingSizes.map((sz) {
                return ActionChip(
                  label: Text(sz),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addToCart(prod, size: sz);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCartBar(ThemeData theme) {
    final totalItems = _cart.fold<double>(0.0, (sum, item) => sum + (item['menge'] as double));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            InkWell(
              onTap: _cart.isNotEmpty ? _showCartBottomSheet : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Badge(
                      label: Text(totalItems.toInt().toString()),
                      isLabelVisible: totalItems > 0,
                      child: Icon(Icons.shopping_cart, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Warenkorb', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${_cart.length} Positionen', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_cart.isEmpty || _isSubmitting) ? null : _submitRequest,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text(_isSubmitting ? 'Wird gesendet …' : 'Jetzt anfordern'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gewählte Artikel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  itemCount: _cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = _cart[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['productName'], style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: item['groesse'] != null
                          ? Text('Größe: ${item['groesse']}', style: const TextStyle(fontSize: 12))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: () {
                              _updateCartQty(i, -1);
                              setSheetState(() {});
                              setState(() {});
                            },
                          ),
                          Text('${(item['menge'] as double).toInt()} Stk.', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              _updateCartQty(i, 1);
                              setSheetState(() {});
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fertig'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
