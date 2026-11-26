import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/auth/data/auth_service.dart'
    show AuthService, UploadKind;
import 'package:montotem/features/provider/data/image_quality_service.dart';

enum IdDocumentType {
  cni('cni', 'Carte nationale d\'identité (CNI)', true),
  passeport('passeport', 'Passeport', false),
  permis('permis', 'Permis de conduire', true),
  carteElecteur('carte_electeur', 'Carte d\'électeur', true);

  const IdDocumentType(this.code, this.libelle, this.avecVerso);
  final String code;
  final String libelle;
  final bool avecVerso;
}

String libelleDocument(String? code) => IdDocumentType.values
    .firstWhere((t) => t.code == code, orElse: () => IdDocumentType.cni)
    .libelle;

class IdentityException implements Exception {
  const IdentityException(this.message);
  final String message;
  @override
  String toString() => message;
}

class IdentityStatus {
  const IdentityStatus({
    required this.documentType,
    required this.soumis,
    required this.statutValidation,
    this.motifRefus,
    this.providerKind,
  });

  final String? documentType;
  final bool soumis;
  final String statutValidation; // pending | approved | rejected
  final String? motifRefus;

  /// zemidjan | tricycle_fret | mecanicien | ... (déduit du métier).
  final String? providerKind;

  /// Conducteurs : la 4e photo est celle du véhicule (moto ou tricycle).
  bool get estTransport =>
      providerKind == 'zemidjan' ||
      providerKind == 'tricycle_fret' ||
      providerKind == 'tricycle_passenger';
}

class ProviderIdentityService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<IdentityStatus?> statut() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('providers')
          .select(
            'id_document_type, identity_submitted_at, '
            'statut_validation, rejection_reason, provider_kind',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return IdentityStatus(
        documentType: row['id_document_type'] as String?,
        soumis: row['identity_submitted_at'] != null,
        statutValidation: '${row['statut_validation']}',
        motifRefus: row['rejection_reason'] as String?,
        providerKind: row['provider_kind'] as String?,
      );
    } catch (e) {
      developer.log(
        'statut identité',
        error: e,
        name: 'ProviderIdentityService',
      );
      return null;
    }
  }

  /// Téléverse les 3 à 4 photos puis enregistre le dossier.
  /// Visage et garage/véhicule : bucket public « avatars ».
  /// Pièces : bucket privé « documents ».
  Future<void> soumettre({
    required IdDocumentType type,
    required String numero,
    required VerifiedPhoto selfie,
    required VerifiedPhoto recto,
    VerifiedPhoto? verso,
    required VerifiedPhoto garage,
    String? description,
  }) async {
    final auth = AuthService();

    final selfieUrl = await auth.uploaderDocument(
      selfie.bytes,
      'selfie.jpg',
      kind: UploadKind.avatar,
      folder: 'providers',
    );
    final rectoUrl = await auth.uploaderDocument(
      recto.bytes,
      'document_recto.jpg',
      kind: UploadKind.identity,
      folder: 'providers',
    );
    final versoUrl = verso == null
        ? null
        : await auth.uploaderDocument(
            verso.bytes,
            'document_verso.jpg',
            kind: UploadKind.identity,
            folder: 'providers',
          );
    final garageUrl = await auth.uploaderDocument(
      garage.bytes,
      'garage.jpg',
      kind: UploadKind.avatar,
      folder: 'providers',
    );

    final texte = description?.trim() ?? '';
    try {
      await _sb.rpc(
        'submit_provider_identity',
        params: {
          'p_doc_type': type.code,
          'p_doc_number': numero.trim(),
          'p_selfie_url': selfieUrl,
          'p_doc_front_url': rectoUrl,
          'p_doc_back_url': versoUrl,
          'p_garage_photo_url': garageUrl,
          'p_garage_description': texte.isEmpty ? null : texte,
          'p_checks': {
            'selfie': selfie.check.metrics,
            'recto': recto.check.metrics,
            if (verso != null) 'verso': verso.check.metrics,
            'garage': garage.check.metrics,
          },
        },
      );
    } on PostgrestException catch (e) {
      developer.log(
        'soumettre identité',
        error: e,
        name: 'ProviderIdentityService',
      );
      throw IdentityException(_message(e));
    }
  }

  String _message(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) return 'Session expirée. Reconnectez-vous.';
    if (m.contains('PAS_PRESTATAIRE')) {
      return 'Dossier prestataire introuvable. Reprenez l\'inscription.';
    }
    if (m.contains('DOCUMENT_INVALIDE')) {
      return 'Choisissez un type de document.';
    }
    if (m.contains('NUMERO_INVALIDE')) {
      return 'Le numéro du document doit avoir entre 4 et 30 caractères.';
    }
    if (m.contains('SELFIE_OBLIGATOIRE')) {
      return 'La photo du visage est obligatoire.';
    }
    if (m.contains('VERSO_OBLIGATOIRE')) {
      return 'Le verso du document est obligatoire.';
    }
    if (m.contains('DOCUMENT_OBLIGATOIRE')) {
      return 'La photo du document est obligatoire.';
    }
    if (m.contains('PHOTO_GARAGE_OBLIGATOIRE')) {
      return 'La photo du garage ou du véhicule est obligatoire.';
    }
    if (m.contains('URL_INVALIDE')) {
      return 'Une photo n\'a pas été enregistrée correctement. Reprenez-la.';
    }
    return 'Impossible d\'envoyer votre dossier. Réessayez.';
  }
}
