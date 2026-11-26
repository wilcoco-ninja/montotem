import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;

class StarEntry {
  const StarEntry({
    required this.delta,
    required this.raison,
    required this.date,
  });

  final int delta;
  final String raison;
  final DateTime date;

  String get libelle => switch (raison) {
    'avis' => 'Avis donné',
    'avis_detaille' => 'Avis détaillé (bonus)',
    _ => 'Points d\'étoiles',
  };
}

class ClientProfile {
  const ClientProfile({
    required this.nomAffiche,
    required this.starPoints,
    required this.historique,
    this.phone,
    this.email,
    this.photoUrl,
  });

  final String nomAffiche;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final int starPoints;
  final List<StarEntry> historique;
}

class ClientProfileService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<ClientProfile?> charger() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('profiles')
          .select(
            'first_name, last_name, phone, email, photo_profil_url, star_points',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;

      final hist = await _sb
          .from('star_points_ledger')
          .select('delta, reason, created_at')
          .eq('client_id', uid)
          .order('created_at', ascending: false)
          .limit(8);

      final nom = [
        '${row['first_name'] ?? ''}'.trim(),
        '${row['last_name'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).join(' ');

      final email = row['email'] as String?;

      return ClientProfile(
        nomAffiche: nom.isEmpty ? 'Mon compte' : nom,
        phone: row['phone'] as String?,
        email: email,
        photoUrl: _photoUrl(row, email),
        starPoints: (row['star_points'] as num?)?.toInt() ?? 0,
        historique: hist
            .map<StarEntry>(
              (r) => StarEntry(
                delta: (r['delta'] as num?)?.toInt() ?? 0,
                raison: '${r['reason']}',
                date:
                    DateTime.tryParse('${r['created_at']}')?.toLocal() ??
                    DateTime.now(),
              ),
            )
            .toList(),
      );
    } on PostgrestException catch (e) {
      developer.log('profil client', error: e, name: 'ClientProfileService');
      return null;
    }
  }

  Future<void> deconnecter() => AuthService().signOut();

  /// Photo de profil : photo du compte email en priorite.
  /// 1. photo_profil_url (choix de l'utilisateur),
  /// 2. avatar du compte Google (user_metadata.avatar_url),
  /// 3. avatar Gravatar construit depuis l'adresse email (md5).
  String? _photoUrl(Map<String, dynamic> row, String? email) {
    final personnelle = (row['photo_profil_url'] as String?)?.trim();
    if (personnelle != null && personnelle.isNotEmpty) return personnelle;

    final google = _sb.auth.currentUser?.userMetadata?['avatar_url'] as String?;
    final avatarGoogle = google?.trim();
    if (avatarGoogle != null && avatarGoogle.isNotEmpty) return avatarGoogle;

    final mail = email?.trim() ?? '';
    if (mail.isEmpty) return null;
    final empreinte = md5.convert(utf8.encode(mail.toLowerCase())).toString();
    return 'https://www.gravatar.com/avatar/$empreinte?s=200&d=mp';
  }
}
