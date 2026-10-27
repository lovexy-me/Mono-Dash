class FirewallBaseInfoDto {
  const FirewallBaseInfoDto({
    required this.name,
    required this.isExist,
    required this.isActive,
    required this.isInit,
    required this.isBind,
    required this.version,
    required this.pingStatus,
    this.backend = '',
    this.reason = '',
    this.syncError = '',
    this.lifecycleTaskID = '',
  });

  factory FirewallBaseInfoDto.fromJson(Map<String, dynamic> json) {
    return FirewallBaseInfoDto(
      name: json['name'] as String? ?? '',
      isExist: json['isExist'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      isInit: json['isInit'] as bool? ?? false,
      isBind: json['isBind'] as bool? ?? false,
      version: json['version'] as String? ?? '',
      pingStatus: json['pingStatus'] as String? ?? 'Disable',
      backend: json['backend'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      syncError: json['syncError'] as String? ?? '',
      lifecycleTaskID: json['lifecycleTaskID'] as String? ?? '',
    );
  }

  final String name;
  final bool isExist;
  final bool isActive;
  final bool isInit;
  final bool isBind;
  final String version;
  final String pingStatus;
  final String backend;
  final String reason;
  final String syncError;
  final String lifecycleTaskID;

  bool get isPingEnabled => pingStatus == 'Enable';
}
