import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/admin/domain/admin_notification_model.dart';

class AdminNotificationException implements Exception {
  const AdminNotificationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Notifications administrateur lues directement dans Supabase.
/// La sécurité repose sur la RLS : seul un admin voit les lignes `admins_only`
/// et il ne peut modifier que `read_at`.
class AdminNotificationService {
  AdminNotificationService({this.client});

  final SupabaseClient? client;

  SupabaseClient get _sb => client ?? Supabase.instance.client;

  static const String _colonnes =
      'id, type, title, body, payload, read_at, created_at';

  /// Plafond du compteur de non lues (évite de rapatrier toute la table).
  static const int _plafondNonLues = 1000;

  Future<T> _run<T>(String action, Future<T> Function() appel) async {
    try {
      return await appel();
    } on PostgrestException catch (e, stackTrace) {
      developer.log(
        'Échec $action (${e.code})',
        error: e,
        stackTrace: stackTrace,
        name: 'AdminNotificationService',
      );
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const AdminNotificationException(
          'Session administrateur expirée. Reconnectez-vous.',
        );
      }
      throw const AdminNotificationException(
        'Impossible de charger les notifications.',
      );
    } catch (e, stackTrace) {
      developer.log(
        'Échec $action',
        error: e,
        stackTrace: stackTrace,
        name: 'AdminNotificationService',
      );
      throw const AdminNotificationException('Serveur injoignable.');
    }
  }

  Future<int> _compterNonLues() async {
    final rows = await _sb
        .from('notifications')
        .select('id')
        .eq('admins_only', true)
        .isFilter('read_at', null)
        .limit(_plafondNonLues);
    return rows.length;
  }

  Future<AdminNotificationsPage> lister({
    bool nonLuesSeulement = false,
    int limite = 50,
  }) {
    return _run('lister', () async {
      var requete = _sb
          .from('notifications')
          .select(_colonnes)
          .eq('admins_only', true);
      if (nonLuesSeulement) {
        requete = requete.isFilter('read_at', null);
      }

      final resultats = await Future.wait<Object?>([
        requete.order('created_at', ascending: false).limit(limite),
        _compterNonLues(),
      ]);

      final items = (resultats[0] as List)
          .whereType<Map>()
          .map((e) => AdminNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return AdminNotificationsPage(items: items, nonLues: resultats[1] as int);
    });
  }

  /// Compteur seul : léger, utilisé par le tableau de bord.
  Future<int> compterNonLues() => _run('compterNonLues', _compterNonLues);

  Future<void> marquerLues(List<String> ids) {
    if (ids.isEmpty) return Future.value();
    return _run('marquerLues', () async {
      await _sb
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('admins_only', true)
          .inFilter('id', ids)
          .isFilter('read_at', null);
    });
  }

  Future<void> toutMarquerLu() {
    return _run('toutMarquerLu', () async {
      await _sb
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('admins_only', true)
          .isFilter('read_at', null);
    });
  }
}
