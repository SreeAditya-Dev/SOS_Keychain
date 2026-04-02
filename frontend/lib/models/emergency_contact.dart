class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final bool sendSMS;
  final bool sendWhatsApp;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.sendSMS,
    required this.sendWhatsApp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'sendSMS': sendSMS,
    'sendWhatsApp': sendWhatsApp,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      sendSMS: json['sendSMS'] as bool,
      sendWhatsApp: json['sendWhatsApp'] as bool,
    );
  }
}
