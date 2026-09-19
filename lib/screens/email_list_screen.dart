import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../models/email.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/server_config.dart';
import 'email_compose_screen.dart';

class EmailFolderItem {
  final String id;
  final String name;
  final bool isInbound; // true if group inbox, false if custom folder
  final bool isGroupFolder; // true if GroupEmailFolder
  final String? status; // if standard pseudo-folder like 'Sent'

  EmailFolderItem({required this.id, required this.name, this.isInbound = false, this.isGroupFolder = false, this.status});
}

class EmailListScreen extends StatefulWidget {
  final String? initialEmailId;
  const EmailListScreen({Key? key, this.initialEmailId}) : super(key: key);

  @override
  _EmailListScreenState createState() => _EmailListScreenState();
}

class _EmailListScreenState extends State<EmailListScreen> {
  final ApiService _apiService = ApiService();
  
  List<Email> _emails = [];
  bool _isLoading = true;

  List<EmailFolderItem> _folders = [];
  EmailFolderItem? _selectedFolder;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initData();
    if (widget.initialEmailId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEmailDetails(Email(id: widget.initialEmailId!, name: 'Lade E-Mail...'));
      });
    }
  }

  Future<void> _initData() async {
    // Standardordner
    final List<EmailFolderItem> folders = [
      EmailFolderItem(id: 'all', name: 'Posteingang', status: 'Archived'),
      EmailFolderItem(id: 'sent', name: 'Gesendet', status: 'Sent'),
      EmailFolderItem(id: 'drafts', name: 'Entwürfe', status: 'Draft'),
    ];

    // Eingangsgruppen (Inbound Emails)
    final inboundList = await _apiService.getInboundEmails();
    for (var ib in inboundList) {
      folders.add(EmailFolderItem(id: ib['id'], name: 'Eingang: ${ib['name']}', isInbound: true));
    }

    // Gruppen-Ordner (GroupEmailFolder)
    final groupFolderList = await _apiService.getGroupEmailFolders();
    for (var gf in groupFolderList) {
      folders.add(EmailFolderItem(id: gf['id'], name: 'Gruppe: ${gf['name']}', isGroupFolder: true));
    }

    // Eigene Ordner (EmailFolder)
    final customList = await _apiService.getEmailFolders();
    for (var cf in customList) {
      folders.add(EmailFolderItem(id: cf['id'], name: 'Ordner: ${cf['name']}', isInbound: false));
    }

    // Persoenliche/Geteilte Accounts (EmailAccount)
    final accountList = await _apiService.getEmailAccounts();
    for (var ac in accountList) {
      folders.add(EmailFolderItem(id: ac['id'], name: 'Account: ${ac['name']}', isInbound: false)); 
    }

    if (mounted) {
      setState(() {
        _folders = folders;
        _selectedFolder = folders.first;
        _isInitialized = true;
      });
      _loadEmails();
    }
  }

  Future<void> _loadEmails() async {
    setState(() => _isLoading = true);
    
    List<Email> emails = [];
    if (_selectedFolder != null) {
      if (_selectedFolder!.isInbound) {
        emails = await _apiService.getEmails(inboundEmailId: _selectedFolder!.id);
      } else if (_selectedFolder!.isGroupFolder) {
        emails = await _apiService.getEmails(groupFolderId: _selectedFolder!.id);
      } else if (_selectedFolder!.status != null) {
        emails = await _apiService.getEmails(status: _selectedFolder!.status!);
      } else {
        emails = await _apiService.getEmails(folderId: _selectedFolder!.id);
      }
    } else {
      emails = await _apiService.getEmails(status: 'Archived');
    }
    
    if (mounted) {
      setState(() {
        _emails = emails;
        _isLoading = false;
      });
    }
  }

  void _openCompose() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EmailComposeScreen()),
    );
    if (result == true) {
      _loadEmails();
    }
  }

  void _openEmailDetails(Email emailSummary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<Email?>(
              future: _apiService.getEmailDetails(emailSummary.id),
              builder: (context, snapshot) {
                final email = snapshot.data ?? emailSummary;
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                
                final dateStr = email.dateSent ?? email.createdAt;
                final dateObj = dateStr != null ? DateTime.tryParse(dateStr) : null;
                final formattedDate = dateObj != null ? DateFormat('dd.MM.yyyy HH:mm').format(dateObj) : '-';

                return Column(
                  children: [
                    AppBar(
                      title: const Text('E-Mail'),
                      automaticallyImplyLeading: false,
                      actions: [
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Von: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                Expanded(child: Text(email.fromString ?? email.fromName ?? 'Unbekannt')),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('An: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                Expanded(child: Text(email.to ?? 'Unbekannt')),
                              ],
                            ),
                            Text('Datum: $formattedDate', style: const TextStyle(color: Colors.grey)),
                            const Divider(height: 32),
                            if (isLoading)
                              const Center(child: CircularProgressIndicator())
                            else if (email.isHtml && email.body != null)
                              Html(data: email.body!)
                            else
                              Text(email.bodyPlain ?? email.body ?? 'Kein Inhalt', style: const TextStyle(fontSize: 16)),

                            // ── Anhänge ──────────────────────────────────
                            if (!isLoading && email.attachments.isNotEmpty) ...[
                              const Divider(height: 32),
                              const Text('Anhänge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 8),
                              ...email.attachments.map((att) => _AttachmentTile(attachment: att)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Posteingang'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Ordner werden geladen...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _folders.isEmpty 
            ? const Text('Posteingang')
            : DropdownButtonHideUnderline(
                child: DropdownButton<EmailFolderItem>(
                  value: _selectedFolder,
                  dropdownColor: Theme.of(context).primaryColor,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                  items: _folders.map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f.name, style: const TextStyle(color: Colors.white)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null && val != _selectedFolder) {
                      setState(() => _selectedFolder = val);
                      _loadEmails();
                    }
                  },
                ),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEmails,
          )
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _emails.isEmpty
              ? const Center(child: Text('Keine E-Mails in diesem Ordner.'))
              : ListView.builder(
                  itemCount: _emails.length,
                  itemBuilder: (context, index) {
                    final email = _emails[index];
                    final dateStr = email.dateSent ?? email.createdAt;
                    final dateObj = dateStr != null ? DateTime.tryParse(dateStr) : null;
                    final formattedDate = dateObj != null ? DateFormat('dd.MM.yyyy HH:mm').format(dateObj) : '';
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Icon(Icons.email, color: Theme.of(context).primaryColor),
                      ),
                      title: Text(email.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${email.fromString ?? email.fromName ?? "Unbekannt"}\n$formattedDate', maxLines: 2, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      onTap: () => _openEmailDetails(email),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCompose,
        child: const Icon(Icons.edit),
        tooltip: 'Neue E-Mail',
      ),
    );
  }
}

/// Displays a single email attachment — image inline, other files as a tap-to-open tile.
class _AttachmentTile extends StatefulWidget {
  final EmailAttachment attachment;
  const _AttachmentTile({required this.attachment});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  Map<String, String>? _headers;

  @override
  void initState() {
    super.initState();
    SecureStorageService().getToken().then((t) {
      if (mounted) setState(() => _headers = t != null ? {'Authorization': t} : {});
    });
  }

  String get _downloadUrl =>
      '${ServerConfig().baseUrl}/?entryPoint=download&id=${widget.attachment.id}';

  Future<void> _open() async {
    final uri = Uri.parse(_downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;

    if (att.isImage && _headers != null) {
      // Inline image preview with tap-to-open
      return GestureDetector(
        onTap: _open,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              _downloadUrl,
              headers: _headers!,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) =>
                  progress == null ? child : const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              errorBuilder: (ctx, _, __) => _fileTile(att, context),
            ),
          ),
        ),
      );
    }

    return _fileTile(att, context);
  }

  Widget _fileTile(EmailAttachment att, BuildContext context) {
    IconData icon;
    if (att.isPdf) {
      icon = Icons.picture_as_pdf;
    } else if (att.isImage) {
      icon = Icons.image;
    } else {
      icon = Icons.attach_file;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: att.type != null ? Text(att.type!, style: const TextStyle(fontSize: 11)) : null,
        trailing: const Icon(Icons.download, size: 20),
        onTap: _open,
      ),
    );
  }
}
