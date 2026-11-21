import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/router/app_router.dart';

/// Alertes MONTOTEM, SANS Firebase.
///
/// Les alertes arrivent par Supabase Realtime : chaque ligne insérée dans
/// `public.notifications` (la RLS ne livre que celles du compte connecté, ou
/// celles des admins) s'affiche en notification locale. Au toucher, l'écran
/// concerné s'ouvre.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const AndroidNotificationChannel _canal = AndroidNotificationChannel(
    'montotem_default',
    'Alertes MONTOTEM',
    description: 'Demandes, arrivée du dépanneur, paiements et messages.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  SupabaseClient get _sb => Supabase.instance.client;

  bool _initialise = false;
  String? _role;
  RealtimeChannel? _flux;

  Future<void> init() async {
    if (_initialise || kIsWeb) return;
    _initialise = true;

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (reponse) {
        final p = reponse.payload;
        if (p == null || p.isEmpty) return;
        try {
          // Correction ici : encapsulation explicite de l'appel asynchrone pour respecter unawaited_futures
          unawaited(_ouvrir(Map<String, dynamic>.from(jsonDecode(p) as Map)));
        } catch (_) {}
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_canal);

    _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut) {
        _role = null;
        unawaited(_arreter());
      } else if (s.session != null &&
          (s.event == AuthChangeEvent.signedIn ||
              s.event == AuthChangeEvent.initialSession)) {
        unawaited(_activer());
      }
    });
    if (_sb.auth.currentSession != null) unawaited(_activer());
  }

  /// Demande la permission puis écoute les nouvelles notifications du compte.
  Future<void> _activer() async {
    try {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      await _arreter();
      _flux = _sb
          .channel('notifications_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            callback: (payload) => _afficher(payload.newRecord),
          )
          .subscribe();
    } catch (e) {
      developer.log('activation alertes', error: e, name: 'PushService');
    }
  }

  Future<void> _arreter() async {
    final f = _flux;
    _flux = null;
    if (f != null) {
      try {
        await _sb.removeChannel(f);
      } catch (_) {}
    }
  }

  Future<void> desinscrire() async {
    if (!_initialise) return;
    await _arreter();
  }

  void _afficher(Map<String, dynamic> n) {
    final titre = '${n['title'] ?? ''}'.trim();
    if (titre.isEmpty) return;
    final payload = n['payload'];
    final data = <String, dynamic>{
      'type': n['type'],
      if (payload is Map) ...Map<String, dynamic>.from(payload),
    };
    unawaited(_local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: titre,
      body: n['body'] as String?,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canal.id,
          _canal.name,
          channelDescription: _canal.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      payload: jsonEncode(data),
    ));
  }

  Future<void> _ouvrir(Map<String, dynamic> data) async {
    final route = await _routePour(data);
    if (route == null) return;
    AppRouter.router.push(route);
  }

  Future<String?> _routePour(Map<String, dynamic> d) async {
    final type = '${d['type'] ?? ''}';
    final missionId = d['mission_id'] == null ? '' : '${d['mission_id']}';

    if (missionId.isNotEmpty) {
      return switch (await _roleActuel()) {
        'provider' => '/provider/mission/$missionId',
        'admin' => '/admin/control',
        _ => '/mes-demandes/$missionId',
      };
    }
    return switch (type) {
      'provider_approved' ||
      'provider_rejected' ||
      'provider_pending' =>
        '/provider/profile',
      'subscription_approved' ||
      'subscription_rejected' =>
        '/provider/subscription',
      'provider_registration' || 'identity_submitted' => '/admin/providers',
      'payment_declared' => '/admin/control?tab=2',
      'provider_reported' => '/admin/control?tab=3',
      _ => null,
    };
  }

  Future<String?> _roleActuel() async {
    if (_role != null) return _role;
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row =
          await _sb.from('profiles').select('role').eq('id', uid).maybeSingle();
      _role = row?['role'] as String?;
    } catch (_) {}
    return _role;
  }
}
