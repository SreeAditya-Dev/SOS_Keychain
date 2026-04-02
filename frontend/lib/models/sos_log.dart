class SOSLog {
  final String id;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final List<String> contactsNotified;
  bool wasCancelled;

  SOSLog({
    required this.id,
    required this.timestamp,
    this.lat,
    this.lng,
    required this.contactsNotified,
    this.wasCancelled = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'lat': lat,
    'lng': lng,
    'contactsNotified': contactsNotified,
    'wasCancelled': wasCancelled,
  };

  factory SOSLog.fromJson(Map<String, dynamic> json) {
    return SOSLog(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      contactsNotified: List<String>.from(json['contactsNotified'] as List),
      wasCancelled: (json['wasCancelled'] as bool?) ?? false,
    );
  }
}
