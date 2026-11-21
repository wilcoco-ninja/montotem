import 'dart:convert';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/storage/local_cache.dart';
import 'package:montotem/features/wallet/domain/topup_request_model.dart';
import 'package:montotem/features/wallet/domain/wallet_model.dart';

class WalletException implements Exception {
  const WalletException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Photo du wallet à un instant donné ([fromCache] : lue sur le téléphone).
class WalletSnapshot {
  const WalletSnapshot({
    required this.wallet,
    required this.config,
    required this.transactions,
    required this.fetchedAt,
    required this.fromCache,
  });

  final Wallet wallet;
  final WalletConfig config;
  final List<WalletTransaction> transactions;
  final DateTime fetchedAt;
  final bool fromCache;
}

/// Wallet du prestataire connecté. Le solde ne se modifie que côté serveur
/// (triggers de commission, validation d'une recharge par un admin).
class WalletService {
  static const List<String> _clesConfig = [
    'commission_cash_pct',
    'commission_momo_pct',
    'commission_travel_pct',
    'wallet_block_threshold_fcfa',
  ];

  SupabaseClient get _sb => Supabase.instance.client;

  String? get currentUserId => _sb.auth.currentUser?.id;

  String _cle(String uid) => 'wallet_$uid';

  Future<WalletSnapshot> charger() async {
    final uid = currentUserId;
    if (uid == null) {
      throw const WalletException('Session expirée. Reconnectez-vous.');
    }

    try {
      final res = await Future.wait<Object?>([
        _sb.from('wallets').select().eq('provider_id', uid).maybeSingle(),
        _sb
            .from('wallet_transactions')
            .select()
            .eq('provider_id', uid)
            .order('created_at', ascending: false)
            .limit(50),
        _sb.from('app_config').select('key, value_int').inFilter(
              'key',
              _clesConfig,
            ),
      ]);

      final walletRow = res[0] as Map<String, dynamic>?;
      final txRows = (res[1] as List).whereType<Map>().toList();
      final configRows = (res[2] as List).whereType<Map>().toList();

      final snapshot = WalletSnapshot(
        wallet:
            walletRow == null ? Wallet.vide(uid) : Wallet.fromJson(walletRow),
        config: WalletConfig.fromRows(configRows),
        transactions: txRows
            .map(
                (e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        fetchedAt: DateTime.now(),
        fromCache: false,
      );

      // Une erreur d'écriture du cache ne doit jamais faire échouer un
      // chargement qui a réussi.
      try {
        await LocalCache.instance.ecrire(
          _cle(uid),
          jsonEncode({
            'at': snapshot.fetchedAt.toUtc().toIso8601String(),
            'wallet': snapshot.wallet.toJson(),
            'config': snapshot.config.toRows(),
            'tx': snapshot.transactions.map((t) => t.toJson()).toList(),
          }),
        );
      } catch (e) {
        developer.log('Écriture cache wallet impossible',
            error: e, name: 'WalletService');
      }
      return snapshot;
    } catch (e, stackTrace) {
      developer.log('Chargement wallet',
          error: e, stackTrace: stackTrace, name: 'WalletService');
      final cache = _depuisCache(uid);
      if (cache != null) return cache;
      throw const WalletException(
          'Impossible de charger votre wallet. Vérifiez votre connexion.');
    }
  }

  WalletSnapshot? _depuisCache(String uid) {
    try {
      final brut = LocalCache.instance.lire(_cle(uid));
      if (brut == null) return null;
      final j = jsonDecode(brut) as Map<String, dynamic>;
      return WalletSnapshot(
        wallet: Wallet.fromJson(Map<String, dynamic>.from(j['wallet'] as Map)),
        config: WalletConfig.fromRows(j['config'] as List),
        transactions: (j['tx'] as List)
            .whereType<Map>()
            .map(
                (e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        fetchedAt: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
        fromCache: true,
      );
    } catch (e) {
      developer.log('Cache wallet illisible', error: e, name: 'WalletService');
      return null;
    }
  }

  /// Lecture légère (solde et état) pour l'accueil. Ne lève jamais.
  Future<Wallet?> lireWallet() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('wallets')
          .select()
          .eq('provider_id', uid)
          .maybeSingle();
      return row == null ? null : Wallet.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Règles de commission en vigueur (app_config). Ne lève jamais : en cas
  /// d'échec, les valeurs par défaut (15 %) sont renvoyées.
  Future<WalletConfig> lireConfig() async {
    try {
      final rows = await _sb
          .from('app_config')
          .select('key, value_int')
          .inFilter('key', _clesConfig);
      return WalletConfig.fromRows(rows);
    } catch (e) {
      developer.log('lireConfig', error: e, name: 'WalletService');
      return const WalletConfig();
    }
  }

  /// Calcule la commission MonTotem sur des frais de déplacement ([montantFcfa]).
  ///
  /// Aperçu uniquement : le prélèvement réel sur le wallet est effectué par
  /// le serveur (apply_travel_commission, appelée par confirm_mission_payment
  /// quand kind = 'trajet'). Cette fonction n'écrit rien. Ne lève jamais.
  Future<CommissionCalcul> appliquerCommissionTrajet(
    int montantFcfa, {
    WalletConfig? config,
  }) async {
    final regles = config ?? await lireConfig();
    return regles.calculerTrajet(montantFcfa);
  }

  /// Dernière demande de recharge du prestataire. Ne lève jamais.
  Future<TopupRequest?> derniereDemande() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final rows = await _sb
          .from('wallet_topup_requests')
          .select()
          .eq('provider_id', uid)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return TopupRequest.fromJson(Map<String, dynamic>.from(rows.first));
    } catch (e) {
      developer.log('derniereDemande', error: e, name: 'WalletService');
      return null;
    }
  }

  /// Déclare une recharge déjà envoyée par Mobile Money. Le wallet n'est
  /// crédité qu'après vérification par un administrateur.
  Future<void> declarerRecharge({
    required int montantFcfa,
    required String operateur,
    required String payerPhone,
    required String reference,
  }) async {
    try {
      await _sb.rpc('submit_wallet_topup', params: {
        'p_amount': montantFcfa,
        'p_operateur': operateur,
        'p_payer_phone': payerPhone,
        'p_transaction_ref': reference.trim(),
      });
    } on PostgrestException catch (e) {
      developer.log('declarerRecharge', error: e, name: 'WalletService');
      throw WalletException(_message(e));
    } catch (e) {
      developer.log('declarerRecharge inattendu',
          error: e, name: 'WalletService');
      throw const WalletException(
          'Impossible d\'envoyer votre déclaration. Vérifiez votre connexion.');
    }
  }

  String _message(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) return 'Session expirée. Reconnectez-vous.';
    if (m.contains('PAS_PRESTATAIRE')) {
      return 'Dossier prestataire introuvable.';
    }
    if (m.contains('MONTANT_INVALIDE')) {
      return 'Le montant doit être compris entre $kRechargeMinFcfa et '
          '1 000 000 FCFA.';
    }
    if (m.contains('OPERATEUR_INVALIDE')) {
      return 'Cet opérateur n\'est pas accepté pour le moment.';
    }
    if (m.contains('TELEPHONE_INVALIDE')) {
      return 'Numéro de téléphone invalide. Exemple : 01 97 00 00 00';
    }
    if (m.contains('REFERENCE_INVALIDE')) {
      return 'Saisissez la référence reçue par SMS (6 caractères minimum).';
    }
    if (m.contains('REFERENCE_DEJA_UTILISEE')) {
      return 'Cette référence de transaction a déjà été utilisée.';
    }
    if (m.contains('DEMANDE_EN_COURS')) {
      return 'Une recharge est déjà en attente de validation.';
    }
    return 'Impossible d\'envoyer votre déclaration. Réessayez.';
  }

  /// Écoute le wallet ET les demandes de recharge du prestataire.
  RealtimeChannel ecouter(void Function() onChange) {
    final uid = currentUserId ?? 'anon';
    final canal = _sb.channel('wallet-$uid');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: uid,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_topup_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: uid,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  Future<void> arreter(RealtimeChannel canal) async {
    try {
      await _sb.removeChannel(canal);
    } catch (_) {}
  }
}