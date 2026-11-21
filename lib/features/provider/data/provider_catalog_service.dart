import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/auth/data/quick_auth_service.dart'
    show QuickAuthException;
import 'package:montotem/features/provider/domain/provider_catalog_model.dart';

// Les écrans importent ServiceTarif / ProviderPublicCatalog depuis ce fichier.
export 'package:montotem/features/provider/domain/provider_catalog_model.dart';

class ProviderCatalogService {
  SupabaseClient get _sb => Supabase.instance.client;

  String? get idConnecte => _sb.auth.currentUser?.id;

  /// Accessible aux visiteurs (RPC publique, aucune donnée sensible).
  Future<ProviderPublicCatalog?> obtenirFiche(String providerId) async {
    try {
      final data = await _sb
          .rpc('provider_public_catalog', params: {'p_provider': providerId});
      if (data is! Map) return null;
      return ProviderPublicCatalog.fromJson(Map<String, dynamic>.from(data));
    } catch (e, st) {
      developer.log('obtenirFiche',
          error: e, stackTrace: st, name: 'ProviderCatalogService');
      return null;
    }
  }

  /// RPC `set_provider_catalog` : véhicules, prestations à prix fixe, frais
  /// kilométriques et rayon. Les prestations déjà existantes gardent leur
  /// identifiant (mise à jour du prix), les absentes sont retirées.
  Future<void> enregistrer({
    required List<String> vehicleTypes,
    required List<ServiceTarif> services,
    required int tarifKmFcfa,
    required int fraisMinFcfa,
    required int rayonKm,
    String? whatsapp,
  }) async {
    try {
      await _sb.rpc('set_provider_catalog', params: {
        'p_vehicle_types': vehicleTypes,
        'p_services': services.map((s) => s.toJson()).toList(),
        'p_tarif_km': tarifKmFcfa,
        'p_frais_min': fraisMinFcfa,
        'p_rayon_km': rayonKm,
        'p_whatsapp': (whatsapp == null || whatsapp.trim().isEmpty)
            ? null
            : whatsapp.trim(),
      });
    } on PostgrestException catch (e) {
      developer.log('enregistrer', error: e, name: 'ProviderCatalogService');
      throw QuickAuthException(_message(e));
    } catch (e) {
      developer.log('enregistrer inattendu',
          error: e, name: 'ProviderCatalogService');
      throw QuickAuthException(
          'Connexion impossible. Vérifiez votre réseau et réessayez.');
    }
  }

  String _message(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) {
      return 'Votre session a expiré. Reconnectez-vous.';
    }
    if (m.contains('PAS_PRESTATAIRE')) {
      return 'Dossier prestataire introuvable. Reprenez l\'inscription.';
    }
    if (m.contains('VEHICULES_OBLIGATOIRES')) {
      return 'Choisissez au moins un type de véhicule.';
    }
    if (m.contains('SERVICES_OBLIGATOIRES')) {
      return 'Ajoutez au moins une prestation avec son prix.';
    }
    if (m.contains('TARIF_INVALIDE')) {
      return 'Chaque prestation doit avoir un prix fixe supérieur à 0.';
    }
    if (m.contains('SERVICE_INVALIDE')) {
      return 'Une prestation est invalide (nom ou type de véhicule).';
    }
    return 'Impossible d\'enregistrer votre catalogue. Réessayez.';
  }
}
