class EmailTemplate {
  final String id;
  final String name;
  final String? subject;
  final String? body;

  EmailTemplate({
    required this.id,
    required this.name,
    this.subject,
    this.body,
  });

  factory EmailTemplate.fromJson(Map<String, dynamic> json) {
    return EmailTemplate(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unbenannt',
      subject: json['subject'] as String?,
      body: json['body'] as String?,
    );
  }
}
