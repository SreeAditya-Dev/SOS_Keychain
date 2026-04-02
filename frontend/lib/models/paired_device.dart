class PairedDevice {
  final String id;
  final String name;
  final DateTime pairedAt;

  PairedDevice({
    required this.id,
    required this.name,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pairedAt': pairedAt.toIso8601String(),
  };

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
    );
  }
}
