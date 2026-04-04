import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../models/angestellte.dart';
import '../core/angestellte_fields.dart';
import '../core/constants.dart';

class AngestellteProfileScreen extends StatefulWidget {
  final String angestellteId;

  const AngestellteProfileScreen({Key? key, required this.angestellteId}) : super(key: key);

  @override
  _AngestellteProfileScreenState createState() => _AngestellteProfileScreenState();
}

class _AngestellteProfileScreenState extends State<AngestellteProfileScreen> {
  final ApiService _apiService = ApiService();
  final SecureStorageService _storage = SecureStorageService();
  bool _isLoading = true;
  bool _isSaving = false;
  Angestellte? _angestellte;
  String? _authToken;
  
  // Track changes
  final Map<String, dynamic> _updates = {};

  // Controllers for text fields
  final Map<String, TextEditingController> _controllers = {};

  final List<Map<String, dynamic>> _panels = [
    {
      'title': 'Überblick',
      'fields': [
        ['firstName', 'personalnummer'],
        ['benutzername', 'lastName'],
        ['vertragsart', 'einstellungsdatum', 'austrittsdatum'],
        ':HEADER:Qualifikationen',
        'qualifikation',
        ['zertifikat34a', 'brandschutzZertifikat'],
        ['bewachungsregisterNummer', 'ePin'],
        ['unterweisungen', 'unterweisungen1'],
        ':HEADER:Kleidergrößen',
        ['jackenGre', 'pullovergre'],
        ['schuhgre', 'tShirtGre'],
        'westengre',
        ':HEADER:Kontakt',
        'phoneNumber',
        'addressStreet',
        ['addressPostalCode', 'addressCity'],
        ['addressCountry', 'addressState'],
        'emailAddress',
        ['notfallnummerName', 'notfallTelefonnummer'],
      ]
    },
    {
      'title': 'Buchhaltung',
      'fields': [
        ['stundenlohnBrutto', 'auertariflicheZulageBrutto'],
        ['gesamtstundenlohnBrutto', 'gesamtVergtungBrutto'],
        ['ausbildungsvergtungBrutto', 'steuernummer', 'steuerklasse'],
        'gehalt',
        ':HEADER:Bankverbindung',
        ['bankkontoInhaber', 'kreditinstitut'],
        ['iBAN', 'bic'],
        ':HEADER:Sozialversicherung',
        ['rentenversicherungsnummer', 'krankenkasse'],
        ':HEADER:Statistiken',
        ['gesamtKrankentage', 'gesamtUrlaub'],
      ]
    },
    {
      'title': 'Persönliche Informationen',
      'fields': [
        ['geburtsdatum', 'geburtsname'],
        ['geburtsort', 'geburtsland'],
        ['staatsname', 'kinder'],
        ['personalausweisnummer', 'religionKonfession'],
      ]
    }
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final tokenUrlPrefix = await _storage.getToken();
    final data = await _apiService.getAngestellteById(widget.angestellteId);
    if (data != null && mounted) {
      setState(() {
        _angestellte = data;
        _isLoading = false;
        if (tokenUrlPrefix != null) {
          _authToken = tokenUrlPrefix;
        }
      });
      
      // Init controllers
      for (final key in data.rawData.keys) {
        final def = AngestellteFields.definitions[key];
        if (def != null) {
          final type = def['type'] as String;
          if (_isTextType(type)) {
            _controllers[key] = TextEditingController(text: data.rawData[key]?.toString() ?? '');
          }
        }
      }
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Laden des Profils.')),
      );
    }
  }

  bool _isTextType(String type) {
    return type.startsWith('Text') || type.startsWith('Ganzzahl') || type.startsWith('E-Mail') || type.startsWith('Telefon') || type == 'Textbox';
  }

  bool _isReadonly(String type) {
    return type.contains('(Readonly)') || type == 'Datum-Uhrzeit';
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    
    // Apply text changes from controllers
    for (final entry in _controllers.entries) {
      final key = entry.key;
      final text = entry.value.text;
      final original = _angestellte!.rawData[key]?.toString() ?? '';
      
      if (text != original) {
        _updates[key] = text.isEmpty ? null : text;
      }
    }

    if (_updates.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine Änderungen vorgenommen.')));
      return;
    }

    final success = await _apiService.updateAngestellte(widget.angestellteId, _updates);
    
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _updates.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil erfolgreich gespeichert.')));
        _loadProfile();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Speichern.')));
      }
    }
  }

  Widget _buildField(String key) {
    if (_angestellte == null || !_angestellte!.rawData.containsKey(key)) {
      return const SizedBox.shrink(); // Not permitted to view or empty
    }
    
    final value = _angestellte!.rawData[key];
    final def = AngestellteFields.definitions[key];
    if (def == null) return const SizedBox.shrink();

    final label = def['label'] as String;
    final type = def['type'] as String;
    final isReadonly = _isReadonly(type);

    if (type == 'Bool') {
      final currentVal = _updates.containsKey(key) ? _updates[key] : value;
      final boolVal = currentVal == true;
      return SwitchListTile(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        value: boolVal,
        activeColor: Theme.of(context).colorScheme.secondary,
        onChanged: isReadonly ? null : (bool val) {
          setState(() {
            _updates[key] = val;
          });
        },
      );
    } else if (type == 'Liste' || type == 'Mehrfachauswahl') {
       final list = value is List ? value : [];
       return Padding(
         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
             const SizedBox(height: 4),
             if (list.isEmpty) const Text('-') else Wrap(
               spacing: 6,
               children: list.map((e) => Chip(
                 label: Text(e.toString()),
                 backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
               )).toList(),
             ),
             const Divider(),
           ],
         ),
       );
    } else if (_isTextType(type)) {
      if (!_controllers.containsKey(key)) return const SizedBox.shrink();
      
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          controller: _controllers[key],
          readOnly: isReadonly,
          maxLines: type == 'Textbox' ? 3 : 1,
          keyboardType: type.contains('Ganzzahl') ? TextInputType.number : (type.contains('E-Mail') ? TextInputType.emailAddress : TextInputType.text),
          decoration: InputDecoration(
            labelText: label,
            filled: isReadonly,
            fillColor: isReadonly ? Theme.of(context).disabledColor.withOpacity(0.05) : null,
            border: const OutlineInputBorder(),
          ),
        ),
      );
    } else {
      // Default readonly display for unknown types like Links
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          initialValue: value?.toString() ?? '-',
          readOnly: true,
          decoration: InputDecoration(
            labelText: label + ' (Nur Ansicht)',
            filled: true,
            fillColor: Theme.of(context).disabledColor.withOpacity(0.05),
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }
  }

  Widget _buildPanel(String title, List<dynamic> fieldKeys) {
    // Collect all unique keys in this panel (handling nested lists)
    final List<String> flatKeys = [];
    for (var item in fieldKeys) {
      if (item is String && !item.startsWith(':HEADER:')) {
        flatKeys.add(item);
      } else if (item is List) {
        flatKeys.addAll(item.cast<String>());
      }
    }

    // Check if user has permission to view any of these fields
    bool hasAnyField = flatKeys.any((key) => _angestellte!.rawData.containsKey(key));
    if (!hasAnyField) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconColor: Theme.of(context).colorScheme.primary,
          collapsedIconColor: Theme.of(context).colorScheme.primary,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: fieldKeys.map((item) {
                  if (item is String) {
                    if (item.startsWith(':HEADER:')) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.replaceFirst(':HEADER:', ''),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                            const Divider(height: 8),
                          ],
                        ),
                      );
                    }
                    return _buildField(item);
                  } else if (item is List) {
                    final List<String> rowKeys = item.cast<String>();
                    // Only show rows that have at least one visible field
                    if (!rowKeys.any((k) => _angestellte!.rawData.containsKey(k))) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rowKeys.map((k) => Expanded(child: _buildField(k))).toList(),
                    );
                  }
                  return const SizedBox.shrink();
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_angestellte == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: const Center(child: Text('Fehler beim Laden.')),
      );
    }

    // Determine unused fields that are in rawData but not in any panel
    final Set<String> usedFields = {};
    for (var p in _panels) {
      final fields = p['fields'] as List<dynamic>;
      for (var item in fields) {
        if (item is String) {
          usedFields.add(item);
        } else if (item is List) {
          usedFields.addAll(item.cast<String>());
        }
      }
    }
    // Also ignore system fields and fields requested to be hidden
    usedFields.addAll([
      'id', 
      'mitarbeiterfotoId', 
      'name', 
      'firstName', 
      'lastName',
      'internermitarbeiter',
      'emailAddressIsOptedOut',
      'emailAddressIsInvalid',
      'phoneNumberIsOptedOut',
      'phoneNumberIsInvalid',
      'createdByName',
      'modifiedByName',
      'createdAt',
      'modifiedAt',
      'assignedUserName', // Often requested to be hidden too
      'assignedUserId',
      'createdBy',
      'modifiedBy',
    ]);
    
    final List<String> otherFields = _angestellte!.rawData.keys
        .where((key) => !usedFields.contains(key) && AngestellteFields.definitions.containsKey(key))
        .toList();

    final String? fotoId = _angestellte!.rawData['mitarbeiterfotoId'];
    
    // Authorization header for image
    final Map<String, String>? imageHeaders = _authToken != null 
        ? (_authToken!.startsWith('ApiKey ') ? {'X-Api-Key': _authToken!.split(' ')[1]} : {'Authorization': _authToken!}) 
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil bearbeiten'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveProfile,
              tooltip: 'Speichern',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Header with Photo
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: ClipOval(
                  child: fotoId != null && _authToken != null
                      ? Image.network(
                          '${AppConstants.apiUrl}/Attachment/file/$fotoId',
                          headers: imageHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, trace) => CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor,
                            child: const Icon(Icons.person, size: 60, color: Colors.white),
                          ),
                        )
                      : CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            _angestellte!.firstName?.isNotEmpty == true ? _angestellte!.firstName![0] : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 48),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _angestellte!.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              _angestellte!.emailAddress ?? 'Keine E-Mail',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 16),
            ),
            const SizedBox(height: 16),
            
            // Render structured panels
            ..._panels.map((panel) => _buildPanel(panel['title'], panel['fields'] as List<dynamic>)).toList(),
            
            if (otherFields.isNotEmpty)
              _buildPanel('Weitere Daten', otherFields),
              
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
