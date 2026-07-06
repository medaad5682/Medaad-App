class AppVersionModel {
  final String minVersion;
  final String latestVersion;
  final bool forceUpdate;
  final String message;
  final String storeUrl;

  AppVersionModel({
    required this.minVersion,
    required this.latestVersion,
    required this.forceUpdate,
    required this.message,
    required this.storeUrl,
  });

  factory AppVersionModel.fromJson(Map<String, dynamic> json) {
    return AppVersionModel(
      minVersion: json['min_version'],
      latestVersion: json['latest_version'],
      forceUpdate: json['force_update'],
      message: json['message'],
      storeUrl: json['store_url'],
    );
  }
}