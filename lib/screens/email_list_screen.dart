import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';
import '../models/email.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import '../core/server_config.dart';
import '../core/constants.dart';
import '../core/email_content_helper.dart';
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
      backgroundColor: Colors.transparent,
      builder: (context) => _EmailDetailModal(
        emailSummary: emailSummary,
        apiService: _apiService,
      ),
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

  bool _isDownloading = false;

  Future<void> _open() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final bytes = await ApiService().downloadAttachmentBytes(widget.attachment.id);
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final safeName = widget.attachment.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
        final file = File('${tempDir.path}/$safeName');
        await file.writeAsBytes(bytes);
        final res = await OpenFilex.open(file.path);
        if (res.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Anhang gespeichert: ${file.path}')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Herunterladen des Anhangs.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Öffnen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    IconData icon;
    Color iconColor;
    if (att.isPdf) {
      icon = Icons.picture_as_pdf_rounded;
      iconColor = Colors.redAccent;
    } else if (att.isImage) {
      icon = Icons.image_rounded;
      iconColor = Colors.greenAccent;
    } else if (att.isDoc) {
      icon = Icons.description_rounded;
      iconColor = Colors.blueAccent;
    } else {
      icon = Icons.attach_file_rounded;
      iconColor = isDark ? Colors.cyanAccent : AppConstants.primaryColor;
    }

    final subtitleParts = <String>[];
    if (att.type != null && att.type!.isNotEmpty) subtitleParts.add(att.type!);
    if (att.formattedSize.isNotEmpty) subtitleParts.add(att.formattedSize);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(att.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: subtitleParts.isNotEmpty
            ? Text(subtitleParts.join(' • '), style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600))
            : null,
        trailing: _isDownloading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.download_rounded, size: 20, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
        onTap: _open,
      ),
    );
  }
}

/// Detail-Modal für E-Mails mit Primus-Parser (HTML-Sanitization, Signatur-Abtrennung & Plaintext/Code-Modus)
class _EmailDetailModal extends StatefulWidget {
  final Email emailSummary;
  final ApiService apiService;

  const _EmailDetailModal({
    required this.emailSummary,
    required this.apiService,
  });

  @override
  State<_EmailDetailModal> createState() => _EmailDetailModalState();
}

class _EmailDetailModalState extends State<_EmailDetailModal> {
  late Future<Email?> _emailFuture;
  String _viewMode = 'formatted'; // 'formatted' | 'plaintext' | 'raw_code'
  bool _showLegalDisclaimer = false;

  @override
  void initState() {
    super.initState();
    _emailFuture = widget.apiService.getEmailDetails(widget.emailSummary.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.mail_outline_rounded,
                        color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'E-Mail Depesche',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Scrollable Content
              Expanded(
                child: FutureBuilder<Email?>(
                  future: _emailFuture,
                  builder: (context, snapshot) {
                    final email = snapshot.data ?? widget.emailSummary;
                    final isLoading = snapshot.connectionState == ConnectionState.waiting;
                    final split = email.splitResult;

                    return SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Betreff & View Mode Switcher
                          Text(
                            email.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // View Mode Toggle Chips
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildModeChip('formatted', '📄 Formatiert', isDark),
                              _buildModeChip('plaintext', '📝 Klartext', isDark),
                              _buildModeChip('raw_code', '💻 HTML-Code', isDark),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 2. Metadaten-Karte (Von, An, CC, Datum, Status)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMetaRow('Von:', email.from, isDark, bold: true, highlight: true),
                                if (email.to != null && email.to!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _buildMetaRow('An:', email.to!, isDark),
                                ],
                                if (email.cc != null && email.cc!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _buildMetaRow('CC:', email.cc!, isDark),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Datum: ${email.displayDate}',
                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600),
                                    ),
                                    if (email.status != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isDark ? Colors.cyanAccent : AppConstants.primaryColor).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          email.status!.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.cyanAccent : AppConstants.primaryColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3. Anhänge
                          if (!isLoading && email.attachments.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.attach_file_rounded, size: 16, color: isDark ? Colors.cyanAccent : AppConstants.primaryColor),
                                const SizedBox(width: 6),
                                Text(
                                  'Anhänge (${email.attachments.length}):',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...email.attachments.map((att) => _AttachmentTile(attachment: att)),
                            const SizedBox(height: 16),
                          ],

                          const Divider(height: 1),
                          const SizedBox(height: 16),

                          // 4. Hauptnachricht & Code-Darstellung
                          if (isLoading)
                            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                          else ...[
                            if (_viewMode == 'formatted') ...[
                              Html(
                                data: split.hasSignature
                                    ? EmailContentHelper.sanitizeHtmlForTheme(split.messageBody, isDark: isDark)
                                    : email.cleanHtml,
                                style: {
                                  "body": Style(
                                    fontSize: FontSize(14.0),
                                    color: isDark ? Colors.grey.shade200 : Colors.black87,
                                    lineHeight: LineHeight.em(1.4),
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                  ),
                                },
                              ),
                            ] else if (_viewMode == 'plaintext') ...[
                              SelectableText(
                                split.hasSignature ? EmailContentHelper.htmlToPlainText(split.messageBody) : email.cleanPlainText,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: isDark ? Colors.grey.shade100 : Colors.black87,
                                  height: 1.45,
                                ),
                              ),
                            ] else ...[
                              // Raw HTML / MIME Inspector
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: SelectableText(
                                  email.body ?? email.bodyPlain ?? '(Kein Body-Code)',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Colors.greenAccent,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],

                            // 5. Separater Signatur- & Impressum-Block (wie Primus Tablet)
                            if (split.hasSignature && split.signatureBody != null && _viewMode != 'raw_code') ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.amber.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.amber.shade700.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.verified_rounded, color: Colors.amber.shade600, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'AUTORISIERTE SIGNATUR // MB-SCC DOKUMENTENSICHERUNG',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 12),
                                    if (email.isHtml)
                                      Html(
                                        data: EmailContentHelper.sanitizeHtmlForTheme(split.signatureBody!, isDark: isDark),
                                        style: {
                                          "body": Style(
                                            fontSize: FontSize(12.0),
                                            color: isDark ? Colors.grey.shade300 : Colors.black87,
                                            lineHeight: LineHeight.em(1.35),
                                            margin: Margins.zero,
                                            padding: HtmlPaddings.zero,
                                          ),
                                        },
                                      )
                                    else
                                      Text(
                                        split.signatureBody!,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: isDark ? Colors.grey.shade300 : Colors.black87,
                                          height: 1.35,
                                        ),
                                      ),

                                    // Ausklappbarer Rechtshinweis / Compliance-Disclaimer
                                    if (split.legalDisclaimer != null) ...[
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => setState(() => _showLegalDisclaimer = !_showLegalDisclaimer),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _showLegalDisclaimer ? Icons.expand_less : Icons.expand_more,
                                              size: 14,
                                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _showLegalDisclaimer
                                                  ? 'Rechtshinweis verbergen'
                                                  : 'Rechtshinweis & Vertraulichkeit einblenden',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_showLegalDisclaimer) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.black26 : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            split.legalDisclaimer!,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 9.5,
                                              color: isDark ? Colors.white38 : Colors.grey.shade700,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeChip(String mode, String label, bool isDark) {
    final isSelected = _viewMode == mode;
    final primary = isDark ? Colors.cyanAccent : AppConstants.primaryColor;

    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _viewMode = mode);
      },
      selectedColor: primary.withOpacity(0.18),
      backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? primary : (isDark ? Colors.white70 : Colors.grey.shade800),
      ),
      side: BorderSide(
        color: isSelected ? primary : (isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildMetaRow(String label, String value, bool isDark, {bool bold = false, bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white60 : Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: highlight
                  ? (isDark ? Colors.cyanAccent : AppConstants.primaryColor)
                  : (isDark ? Colors.white : Colors.black87),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
