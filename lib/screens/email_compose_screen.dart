import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/email_template.dart';
import 'package:flutter_html/flutter_html.dart'; // used for previewing templates

class EmailComposeScreen extends StatefulWidget {
  final String? replyToId;
  final String? prefillTo;

  const EmailComposeScreen({Key? key, this.replyToId, this.prefillTo}) : super(key: key);

  @override
  _EmailComposeScreenState createState() => _EmailComposeScreenState();
}

class _EmailComposeScreenState extends State<EmailComposeScreen> {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  bool _isSending = false;

  List<String> _fromAddresses = [];
  String? _selectedFrom;
  
  List<EmailTemplate> _templates = [];
  EmailTemplate? _selectedTemplate;

  String _parentType = 'Account';
  String? _parentId;
  final TextEditingController _parentNameController = TextEditingController();

  final TextEditingController _toController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.prefillTo != null) {
      _toController.text = widget.prefillTo!;
    }
    _loadComposerData();
  }

  Future<void> _loadComposerData() async {
    try {
      final addresses = await _apiService.getAvailableFromAddresses();
      final templates = await _apiService.getEmailTemplates();
      
      if (mounted) {
        setState(() {
          _fromAddresses = addresses;
          if (addresses.isNotEmpty) {
            _selectedFrom = addresses.first;
          }
          _templates = templates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Laden der E-Mail-Daten')));
      }
    }
  }

  void _applyTemplate(EmailTemplate? template) {
    setState(() {
      _selectedTemplate = template;
      if (template != null) {
        if (template.subject != null && template.subject!.isNotEmpty) {
          _subjectController.text = template.subject!;
        }
        if (template.body != null && template.body!.isNotEmpty) {
          // Templates in Espo are usually HTML. For a simple text editor we might just append it, 
          // but if it's HTML, we'll send the email as HTML.
          _bodyController.text = template.body!;
        }
      }
    });
  }

  Future<void> _sendEmail() async {
    if (_toController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Empfänger angeben.')));
      return;
    }
    if (_subjectController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben.')));
      return;
    }

    setState(() => _isSending = true);

    final payload = {
      'to': _toController.text.trim(),
      'subject': _subjectController.text.trim(),
      'body': _bodyController.text,
      'isHtml': true, // Assuming body contains HTML template signatures
      'status': 'Sending',
      if (_selectedFrom != null) 'from': _selectedFrom,
      if (widget.replyToId != null) 'replyToId': widget.replyToId,
      if (_parentId != null) 'parentType': _parentType,
      if (_parentId != null) 'parentId': _parentId,
    };

    final success = await _apiService.sendEmail(payload);

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-Mail wird gesendet!')));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Senden der E-Mail.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('E-Mail verfassen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Mail verfassen'),
        actions: [
          if (_isSending)
             const Padding(
               padding: EdgeInsets.all(16.0),
               child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
             )
          else
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendEmail,
              tooltip: 'Senden',
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // FROM dropdown
            if (_fromAddresses.isNotEmpty)
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Absender (Von)'),
                value: _selectedFrom,
                items: _fromAddresses.map((addr) {
                  return DropdownMenuItem(value: addr, child: Text(addr));
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedFrom = val);
                },
              ),
            if (_fromAddresses.isEmpty)
               const Text('Keine erlaubten Absenderadressen gefunden.', style: TextStyle(color: Colors.red)),
            
            const SizedBox(height: 16),
            
            // TO field with Autocomplete
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text.isEmpty || textEditingValue.text.length < 3) {
                  return const Iterable<String>.empty();
                }
                // Search Contacts and Accounts for email
                final contacts = await _apiService.searchEntities('Contact', textEditingValue.text);
                final accounts = await _apiService.searchEntities('Account', textEditingValue.text);
                final List<String> results = [];
                for (var c in contacts) {
                  if (c['emailAddress'] != null) results.add(c['emailAddress']);
                }
                for (var a in accounts) {
                  if (a['emailAddress'] != null) results.add(a['emailAddress']);
                }
                return results.where((e) => e.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (String selection) {
                _toController.text = selection;
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // Keep controllers in sync if initialized with prefill
                if (_toController.text.isNotEmpty && controller.text.isEmpty) {
                  controller.text = _toController.text;
                }
                // Update our main controller when this changes
                controller.addListener(() {
                  _toController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Empfänger (An)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                );
              },
            ),
            
            const SizedBox(height: 16),
            
            // SUBJECT field
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(labelText: 'Betreff', border: OutlineInputBorder()),
            ),

            const SizedBox(height: 16),
            
            // PARENT PICKER (Bezieht sich auf)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Typ', border: OutlineInputBorder()),
                    value: _parentType,
                    items: ['Account', 'Contact', 'Lead', 'Opportunity', 'Case'].map((t) {
                      return DropdownMenuItem(value: t, child: Text(t));
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _parentType = val!;
                        _parentId = null;
                        _parentNameController.clear();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.isEmpty || textEditingValue.text.length < 2) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      return await _apiService.searchEntities(_parentType, textEditingValue.text);
                    },
                    displayStringForOption: (option) => option['name'] ?? '',
                    onSelected: (option) {
                      setState(() {
                        _parentId = option['id'];
                        _parentNameController.text = option['name'];
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(labelText: 'Bezieht sich auf', border: OutlineInputBorder()),
                      );
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),

            // SIGNATURE / TEMPLATE dropdown
            if (_templates.isNotEmpty)
              DropdownButtonFormField<EmailTemplate>(
                decoration: const InputDecoration(labelText: 'Signatur / Vorlage einfügen'),
                value: _selectedTemplate,
                items: [
                  const DropdownMenuItem<EmailTemplate>(value: null, child: Text('Keine Signatur')),
                  ..._templates.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
                ],
                onChanged: _applyTemplate,
              ),

            const SizedBox(height: 16),
            
            // BODY field
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Nachricht (HTML)', 
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 12,
            ),
            
            const SizedBox(height: 16),
            
            // Preview HTML body if there is HTML content (like a signature)
            if (_bodyController.text.contains('<'))
              Card(
                color: Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vorschau (Formatierung):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const Divider(),
                      Html(data: _bodyController.text),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _parentNameController.dispose();
    super.dispose();
  }
}
