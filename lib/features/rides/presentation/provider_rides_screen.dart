import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/provider/presentation/widgets/provider_momo_sheet.dart';
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/wallet/data/wallet_service.dart';
import 'package:montotem/features/wallet/domain/wallet_model.dart';
import 'package:montotem/features/rides/data/ride_driver_service.dart';
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';

/// Espace conducteur : en ligne / hors ligne, courses proches, course en cours.
class ProviderRidesScreen extends StatefulWidget {
  const ProviderRidesScreen({super.key});

  @override
  State<ProviderRidesScreen> createState() => _ProviderRidesScreenState();
}

class _ProviderRidesScreenState extends State<ProviderRidesScreen> {
  static const Duration _intervalle = Duration(seconds: 15);

  final RideService _rides = RideService();
  final RideDriverService _driver = RideDriverService();
  final MissionService _missions = MissionService();
  final WalletService _wallets = WalletService();
  final LocationService _location = LocationService();

  StreamSubscription<Position>? _gps;
  Timer? _poll;

  DriverInfo? _info;
  Wallet? _wallet;
  WalletConfig _config = const WalletConfig();
  Ride? _active;
  List<NearbyRide> _proches = const [];
  LatLng? _position;
  String? _erreurPosition;
  String? _error;
  bool _loading = true;
  bool _toggling = false;
  bool _redirige = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _demarrerPosition();
    _actualiser();
    _poll = Timer.periodic(_intervalle, (_) {
      if (mounted) _actualiser(silencieux: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _demarrerPosition() async {
    try {
      final p = await _location.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _position = LatLng(p.latitude, p.longitude);
        _erreurPosition = null;
      });
      _gps = _location.watchPosition().listen((Position q) {
        if (mounted) {
          setState(() => _position = LatLng(q.latitude, q.longitude));
        }
      }, onError: (_) {});
      _actualiser(silencieux: true);
    } on LocationPermissionException catch (e) {
      if (mounted) setState(() => _erreurPosition = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _erreurPosition = 'Impossible de vous localiser. Activez le GPS.',
        );
      }
    }
  }

  Future<void> _actualiser({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await Future.wait<Object?>([
        _driver.charger(),
        _wallets.lireWallet(),
        _wallets.lireConfig(),
        _rides.mesCourses(),
      ]);
      final info = res[0] as DriverInfo?;
      final wallet = res[1] as Wallet?;
      final config = res[2] as WalletConfig;
      final uid = _rides.currentUserId;
      final actives = (res[3] as List<Ride>)
          .where((r) => r.providerId == uid && r.status.actif)
          .toList();

      var proches = const <NearbyRide>[];
      final pos = _position;
      if (info != null &&
          info.conducteur &&
          info.valide &&
          info.abonnementActif &&
          info.disponible &&
          wallet?.blocked != true &&
          pos != null &&
          actives.isEmpty) {
        proches = await _rides.proches(lat: pos.latitude, lng: pos.longitude);
      }

      if (!mounted) return;
      setState(() {
        _info = info;
        _wallet = wallet;
        _config = config;
        _active = actives.isEmpty ? null : actives.first;
        _proches = proches;
        _error = null;
      });

      if (actives.isNotEmpty && !_redirige) {
        _redirige = true;
        _ouvrirCourse(actives.first.id);
      }
    } on RideException catch (e) {
      if (mounted && _info == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ouvrirCourse(String id) async {
    await context.push('/provider/rides/$id');
    if (mounted) _actualiser(silencieux: true);
  }

  Future<void> _basculer(bool enLigne) async {
    setState(() => _toggling = true);
    try {
      await _missions.definirDisponibilite(enLigne);
      await _actualiser(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _accepter(NearbyRide n) async {
    if (_busyId != null) return;
    setState(() => _busyId = n.id);
    try {
      await _rides.action(n.id, 'accept');
      if (!mounted) return;
      _redirige = true;
      await _ouvrirCourse(n.id);
    } on RideException catch (e) {
      if (mounted) {
        _msg(e.message);
        _actualiser(silencieux: true);
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  CommissionCalcul _calcul(NearbyRide n) =>
      _config.calculerCourse(n.fareFcfa, mobileMoney: n.payment.mobileMoney);

  String _age(DateTime d) {
    final min = DateTime.now().difference(d).inMinutes;
    return min < 1 ? 'À l\'instant' : 'Il y a $min min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes courses'),
        actions: [
          IconButton(
            tooltip: 'Mon wallet',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => context.push('/provider/wallet'),
          ),
        ],
      ),
      body: _corps(),
    );
  }

  Widget _corps() {
    if (_loading && _info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _info == null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: _actualiser),
        ),
      );
    }

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: _actualiser,
      child: ContentWidth(
        maxWidth: 720,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
          children: [
            _carteEnLigne(),
            ..._alertes(),
            if (_active != null) ...[
              const SectionTitle('Course en cours'),
              _carteActive(_active!),
            ],
            if (_active == null) ...[
              const SectionTitle('Courses proches'),
              ..._listeProches(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _carteEnLigne() {
    final info = _info;
    final enLigne = info?.disponible == true;
    final peut = info != null && info.conducteur && info.valide;
    final scheme = Theme.of(context).colorScheme;
    final color = enLigne ? scheme.secondary : Colors.grey;

    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              enLigne
                  ? Icons.wifi_tethering_rounded
                  : Icons.power_settings_new_rounded,
              color: context.readable(color),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enLigne ? 'En ligne' : 'Hors ligne',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  enLigne
                      ? 'Vous recevez les courses autour de vous.'
                      : 'Passez en ligne pour recevoir des courses.',
                  style: TextStyle(fontSize: 15, color: context.textSecondary),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 1.25,
            child: Switch(
              value: enLigne,
              onChanged: (!peut || _toggling) ? null : _basculer,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _alertes() {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    final liste = <Widget>[];

    void ajouter(Widget w) {
      liste.add(const SizedBox(height: 12));
      liste.add(w);
    }

    if (info == null) {
      ajouter(
        _Bandeau(
          icone: Icons.error_outline_rounded,
          couleur: scheme.error,
          titre: 'Dossier prestataire introuvable',
          texte: 'Reprenez votre inscription prestataire.',
        ),
      );
      return liste;
    }

    if (!info.conducteur) {
      ajouter(
        _Bandeau(
          icone: Icons.info_outline_rounded,
          couleur: scheme.tertiary,
          titre: 'Section réservée aux conducteurs',
          texte:
              'Votre activité n\'est pas un service de transport : les '
              'courses Zémidjan et Tricycle Fret ne vous sont pas proposées.',
        ),
      );
      return liste;
    }

    if (!info.valide) {
      ajouter(
        _Bandeau(
          icone: Icons.hourglass_top_rounded,
          couleur: scheme.primary,
          titre: 'Dossier en cours de validation',
          texte: 'Vous recevrez des courses dès que votre dossier est validé.',
          action: 'Voir mon dossier',
          onAction: () => context.push('/provider/identity'),
        ),
      );
    } else if (!info.abonnementActif) {
      ajouter(
        _Bandeau(
          icone: Icons.workspace_premium_outlined,
          couleur: scheme.error,
          titre: 'Abonnement inactif',
          texte: 'Sans abonnement actif, vous ne recevez aucune course.',
          action: 'Choisir une formule',
          onAction: () => context.push('/provider/subscription'),
        ),
      );
    }

    final w = _wallet;
    if (w != null && w.blocked) {
      ajouter(
        _Bandeau(
          icone: Icons.lock_outline_rounded,
          couleur: scheme.error,
          titre: 'Wallet bloqué',
          texte:
              'Solde ${formaterFcfaSigne(w.balanceFcfa)}. Rechargez-le pour '
              'recevoir de nouvelles courses.',
          action: 'Recharger',
          onAction: () => context.push('/provider/wallet'),
        ),
      );
    }

    if (_erreurPosition != null) {
      ajouter(
        _Bandeau(
          icone: Icons.location_off_outlined,
          couleur: scheme.tertiary,
          titre: 'Position GPS indisponible',
          texte: _erreurPosition!,
          action: 'Réessayer',
          onAction: _demarrerPosition,
        ),
      );
    }

    if (!info.momoConfigure) {
      ajouter(
        _Bandeau(
          icone: Icons.account_balance_wallet_outlined,
          couleur: scheme.primary,
          titre: 'Courses Mobile Money',
          texte:
              'Enregistrez votre numéro de réception pour pouvoir accepter '
              'les courses payées par MTN, Moov ou Celtiis.',
          action: 'Enregistrer',
          onAction: () => showProviderMomoSheet(context),
        ),
      );
    }

    return liste;
  }

  Widget _carteActive(Ride r) {
    final couleur = r.status.couleur;
    return SoftCard(
      onTap: () => _ouvrirCourse(r.id),
      child: Row(
        children: [
          Icon(r.status.icone, color: context.readable(couleur), size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.kind.libelle} · ${TravelFee.fcfa(r.prixFcfa)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                StatusPill(
                  label: r.status.libelle,
                  color: couleur,
                  icon: r.status.icone,
                ),
              ],
            ),
          ),
          const Text(
            'Reprendre',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }

  List<Widget> _listeProches() {
    final info = _info;
    if (info == null ||
        !info.conducteur ||
        !info.valide ||
        !info.abonnementActif) {
      return const [];
    }
    if (_wallet?.blocked == true) return const [];

    if (!info.disponible) {
      return const [
        EmptyState(
          icon: Icons.power_settings_new_rounded,
          title: 'Vous êtes hors ligne',
          message: 'Passez en ligne pour voir les courses autour de vous.',
        ),
      ];
    }
    if (_position == null) {
      return const [
        EmptyState(
          icon: Icons.location_searching_rounded,
          title: 'Recherche de votre position…',
          message: 'Les courses s\'affichent dès que votre GPS est trouvé.',
        ),
      ];
    }
    if (_proches.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Aucune course pour le moment',
          message:
              'Restez en ligne : les demandes à moins de 5 km arrivent '
              'ici et par notification.',
        ),
      ];
    }
    return [
      for (final n in _proches)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _carteProche(n),
        ),
    ];
  }

  Widget _carteProche(NearbyRide n) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyId == n.id;
    final cash = !n.payment.mobileMoney;
    final calcul = _calcul(n);
    final peut = _info?.peutRecevoir(n.payment) ?? false;
    final depart = (n.pickupAddress ?? '').trim();
    final arrivee = (n.dropoffAddress ?? '').trim();

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(n.kind.icone, size: 30, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  TravelFee.fcfa(n.fareFcfa),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusPill(
                label: n.payment.libelle,
                color: cash ? scheme.tertiary : scheme.secondary,
                icon: cash
                    ? Icons.payments_outlined
                    : Icons.phone_android_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(
                label: '${formaterDistance(n.distanceToPickupM)} du départ',
                color: AppTheme.primaryColor,
                icon: Icons.near_me_rounded,
              ),
              StatusPill(
                label: 'Trajet ${formaterDistance(n.tripDistanceM)}',
                color: Colors.blueGrey,
                icon: Icons.route_rounded,
              ),
            ],
          ),
          if (depart.isNotEmpty || arrivee.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (depart.isNotEmpty)
              Text('Départ : $depart', style: const TextStyle(fontSize: 15)),
            if (arrivee.isNotEmpty)
              Text('Arrivée : $arrivee', style: const TextStyle(fontSize: 15)),
          ],
          const SizedBox(height: 8),
          Text(
            'Commission ${calcul.pct} % : '
            '-${TravelFee.fcfa(calcul.commissionFcfa)} · Net '
            '${TravelFee.fcfa(calcul.netFcfa)}'
            '${cash ? '' : '\nLe client vous paie directement par '
                      '${n.payment.libelle} ; la commission est déduite de votre '
                      'wallet.'}',
            style: TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: context.textSecondary,
            ),
          ),
          Text(
            _age(n.createdAt),
            style: TextStyle(fontSize: 13.5, color: context.textSecondary),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: peut
                ? 'Accepter cette course'
                : 'Numéro ${n.payment.libelle} requis',
            icon: Icons.check_rounded,
            loading: busy,
            onPressed: peut ? () => _accepter(n) : null,
          ),
        ],
      ),
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.texte,
    this.action,
    this.onAction,
  });

  final IconData icone;
  final Color couleur;
  final String titre;
  final String texte;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final fg = context.readable(couleur);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: radius,
        border: Border.all(color: couleur.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: fg, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      texte,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (action != null && onAction != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(action!)),
            ),
        ],
      ),
    );
  }
}
