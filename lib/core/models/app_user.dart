/// Rôle applicatif d'un utilisateur MONTOTEM.
enum UserRole {
  client,
  provider,
  admin;

  String get value => name;

  static UserRole fromValue(String? v) => switch (v) {
        'provider' => UserRole.provider,
        'admin' => UserRole.admin,
        _ => UserRole.client,
      };
}

/// Profil applicatif d'un utilisateur (client, prestataire ou admin).
///
/// Le backend Django renvoie le profil prestataire **imbriqué** sous la clé
/// `prestataire` (voir accounts/serializers.py ProfileSerializer). Ce modèle
/// aplatit cette structure pour simplifier l'usage côté UI.
class AppUser {
  final String id;
  final String phone;
  final UserRole role;
  final bool inscriptionComplete;
  final String? name;
  final String? firstName;
  final bool isApproved;

  // Spécifiques prestataire (dénormalisés depuis `prestataire`)
  final String? businessName;
  final String? metier;
  final String? ville;
  final String? ifu;
  final String? photoProfilUrl;
  final String? photoCniUrl;
  final double? latitude;
  final double? longitude;

  const AppUser({
    required this.id,
    required this.phone,
    required this.role,
    this.inscriptionComplete = false,
    this.name,
    this.firstName,
    this.isApproved = false,
    this.businessName,
    this.metier,
    this.ville,
    this.ifu,
    this.photoProfilUrl,
    this.photoCniUrl,
    this.latitude,
    this.longitude,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final presta = json['prestataire'] as Map<String, dynamic>?;

    final lastName = (json['last_name'] as String?)?.trim();
    final rootName = (json['name'] as String?)?.trim();

    return AppUser(
      id: '${json['id'] ?? ''}',
      phone: (json['phone'] as String?) ?? '',
      role: UserRole.fromValue(json['role'] as String?),
      inscriptionComplete: (json['inscription_complete'] as bool?) ?? false,
      name: (lastName != null && lastName.isNotEmpty) ? lastName : rootName,
      firstName: json['first_name'] as String?,
      isApproved: (json['is_approved'] as bool?) ?? false,
      photoProfilUrl: json['photo_profil_url'] as String?,
      businessName: presta?['business_name'] as String?,
      metier: presta?['metier'] as String?,
      ville: presta?['ville'] as String?,
      ifu: presta?['ifu'] as String?,
      photoCniUrl: presta?['photo_cni_url'] as String?,
      latitude: (presta?['latitude'] as num?)?.toDouble(),
      longitude: (presta?['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'role': role.value,
        'inscription_complete': inscriptionComplete,
        if (name != null) 'last_name': name,
        if (firstName != null) 'first_name': firstName,
        'is_approved': isApproved,
        if (photoProfilUrl != null) 'photo_profil_url': photoProfilUrl,
      };
}
