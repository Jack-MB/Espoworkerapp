class AppUpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final String clientVersion;
  final int clientBuild;
  final bool isUpdateAvailable;
  final bool isForceUpdate;
  final String releaseNotes;
  final String downloadUrl;
  final String? testFlightUrl;
  final String? appStoreUrl;
  final int fileSizeBytes;
  final String sha256;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.clientVersion,
    required this.clientBuild,
    required this.isUpdateAvailable,
    required this.isForceUpdate,
    required this.releaseNotes,
    required this.downloadUrl,
    this.testFlightUrl,
    this.appStoreUrl,
    required this.fileSizeBytes,
    required this.sha256,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      latestVersion: (json['latestVersion'] ?? '0.0.0').toString(),
      latestBuild: json['latestBuild'] is int
          ? json['latestBuild'] as int
          : int.tryParse(json['latestBuild']?.toString() ?? '0') ?? 0,
      clientVersion: (json['clientVersion'] ?? '0.0.0').toString(),
      clientBuild: json['clientBuild'] is int
          ? json['clientBuild'] as int
          : int.tryParse(json['clientBuild']?.toString() ?? '0') ?? 0,
      isUpdateAvailable: json['isUpdateAvailable'] == true,
      isForceUpdate: json['isForceUpdate'] == true,
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      testFlightUrl: json['testFlightUrl']?.toString(),
      appStoreUrl: json['appStoreUrl']?.toString() ?? json['testFlightUrl']?.toString(),
      fileSizeBytes: json['fileSizeBytes'] is int
          ? json['fileSizeBytes'] as int
          : int.tryParse(json['fileSizeBytes']?.toString() ?? '0') ?? 0,
      sha256: (json['sha256'] ?? '').toString(),
    );
  }

  String get formattedFileSize {
    if (fileSizeBytes <= 0) return '';
    final double mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
