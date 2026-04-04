class EspoDocument {
  final String id;
  final String name;
  final String status;
  final String? type;
  final String? fileId;
  final String? fileName;
  final String? createdAt;

  EspoDocument({
    required this.id,
    required this.name,
    required this.status,
    this.type,
    this.fileId,
    this.fileName,
    this.createdAt,
  });

  factory EspoDocument.fromJson(Map<String, dynamic> json) {
    return EspoDocument(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      status: json['status'] ?? '',
      type: json['type'],
      fileId: json['fileId'],
      fileName: json['fileName'],
      createdAt: json['createdAt'],
    );
  }
}
