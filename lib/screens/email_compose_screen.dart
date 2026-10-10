import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../models/email_template.dart';
import 'package:flutter_html/flutter_html.dart';

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
  String _sendProgressStatus = 'Senden...';

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

  final List<PlatformFile> _attachments = [];

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
      
      // If replying, load original email to prefill recipient and quote
      if (widget.replyToId != null) {
        final orig = await _apiService.getEmailDetails(widget.replyToId!);
        if (orig != null) {
          if (_toController.text.isEmpty) {
            _toController.text = orig.fromString ?? orig.fromName ?? '';
          }
          final subject = orig.name.trim();
          _subjectController.text = subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject';
          final originalSender = orig.fromString ?? orig.fromName ?? 'Unbekannt';
          final sentDate = orig.dateSent ?? orig.createdAt ?? '';
          final origBody = orig.bodyPlain ?? orig.body ?? '';
          _bodyController.text = '\n\n\n--- Ursprüngliche Nachricht von $originalSender ($sentDate) ---\n$origBody';
        }
      }

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
          _bodyController.text = template.body!;
        }
      }
    });
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _attachments.addAll(result.files);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Auswählen: $e')));
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
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

    setState(() {
      _isSending = true;
      _sendProgressStatus = _attachments.isNotEmpty ? 'Lade Anhänge hoch...' : 'Sende E-Mail...';
    });

    final List<String> attachmentsIds = [];

    // 1. Upload all selected attachments to EspoCRM
    if (_attachments.isNotEmpty) {
      for (int i = 0; i < _attachments.length; i++) {
        final f = _attachments[i];
        if (mounted) {
          setState(() => _sendProgressStatus = 'Lade Anhang ${i + 1}/${_attachments.length} hoch...');
        }

        List<int>? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        }

        if (bytes != null) {
          final ext = f.extension?.toLowerCase() ?? '';
          String mime = 'application/octet-stream';
          if (ext == 'pdf') mime = 'application/pdf';
          else if (['jpg', 'jpeg'].contains(ext)) mime = 'image/jpeg';
          else if (ext == 'png') mime = 'image/png';
          else if (ext == 'txt') mime = 'text/plain';

          final attId = await _apiService.uploadEmailAttachment(
            fileName: f.name,
            mimeType: mime,
            bytes: bytes,
          );

          if (attId != null) {
            attachmentsIds.add(attId);
          }
        }
      }
    }

    if (mounted) {
      setState(() => _sendProgressStatus = 'Übermittle Nachricht...');
    }

    final payload = {
      'to': _toController.text.trim(),
      'name': _subjectController.text.trim(),
      'subject': _subjectController.text.trim(),
      'body': _bodyController.text,
      'isHtml': true,
      'status': 'Sending',
      if (attachmentsIds.isNotEmpty) 'attachmentsIds': attachmentsIds,
      if (_selectedFrom != null) 'from': _selectedFrom,
      if (widget.replyToId != null) 'replyToId': widget.replyToId,
      if (widget.replyToId != null) 'inReplyToId': widget.replyToId,
      if (_parentId != null) 'parentType': _parentType,
      if (_parentId != null) 'parentId': _parentId,
    };

    final success = await _apiService.sendEmail(payload);

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-Mail erfolgreich gesendet!')));
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
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16.0),
               child: Row(
                 children: [
                   Text(_sendProgressStatus, style: const TextStyle(fontSize: 12)),
                   const SizedBox(width: 8),
                   const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                 ],
               ),
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
                if (_toController.text.isNotEmpty && controller.text.isEmpty) {
                  controller.text = _toController.text;
                }
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
            
            // ATTACHMENTS PICKER & LIST
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Anhang hinzufügen'),
                ),
                const SizedBox(width: 8),
                if (_attachments.isNotEmpty)
                  Text('${_attachments.length} Datei(en) ausgewählt', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),

            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: List.generate(_attachments.length, (index) {
                  final att = _attachments[index];
                  final sizeKb = att.size > 0 ? (att.size / 1024).toStringAsFixed(1) : '?';
                  return Chip(
                    avatar: const Icon(Icons.insert_drive_file, size: 16),
                    label: Text('${att.name} ($sizeKb KB)', style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeAttachment(index),
                  );
                }),
              ),
            ],

            const SizedBox(height: 16),
            
            // BODY field
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Nachricht (HTML / Text)', 
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 12,
            ),
            
            const SizedBox(height: 16),
            
            // Preview HTML body if there is HTML content
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
