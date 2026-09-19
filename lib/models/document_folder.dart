class DocumentFolder {
  final String id;
  final String name;

  DocumentFolder({required this.id, required this.name});

  factory DocumentFolder.fromJson(Map<String, dynamic> json) {
    return DocumentFolder(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
