enum AdminNotificationType {
  providerRegistration,
  paymentSucceeded,
  paymentAnomaly,
  other;

  static AdminNotificationType fromValue(String? v) => switch (v) {
    'provider_registration' => AdminNotificationType.providerRegistration,
    'payment_succeeded' => AdminNotificationType.paymentSucceeded,
    'payment_anomaly' => AdminNotificationType.paymentAnomaly,
    _ => AdminNotificationType.other,
  };
}

class AdminNotification {
  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final AdminNotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get lue => readAt != null;

  AdminNotification copyWith({DateTime? readAt}) => AdminNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    payload: payload,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );

  factory AdminNotification.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return AdminNotification(
      id: '${json['id']}',
      type: AdminNotificationType.fromValue(json['type'] as String?),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      createdAt:
          DateTime.tryParse('${json['created_at']}')?.toLocal() ??
          DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse('${json['read_at']}')?.toLocal()
          : null,
    );
  }
}

class AdminNotificationsPage {
  const AdminNotificationsPage({required this.items, required this.nonLues});

  final List<AdminNotification> items;
  final int nonLues;
}
