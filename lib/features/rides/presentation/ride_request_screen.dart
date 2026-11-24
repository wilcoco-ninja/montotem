import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/data/ride_tariff_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';
import 'package:montotem/features/rides/domain/ride_tariff.dart';
import 'package:montotem/features/rides/presentation/ride_point_picker_screen.dart';
import 'package:montotem/features/wallet/domain/montant_local.dart';

/// Demande de course : service, départ, destination, prix fixe calculé, paiement.
class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({super.key, this.kind});

  final RideKind? kind;

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  static const int _tarifMin = 100;

  /// Devise de la zone de prise en charge (XOF au Bénin). La ville sera
  /// passée ici quand le parcours client la connaîtra (profil, géocodage).
  Devise get _devise => MontantLocal.deCourse();

  final RideService _rides = RideService();
  final RideTariffService _tarifsService = RideTariffService();
  final LocationService _location = LocationService();
  final RoutingService _routing = RoutingService();
  final TextEditingController _repereDepart = TextEditingController();
  final TextEditingController _repereArrivee = TextEditingController();

  late RideKind _kind = widget.kind ?? RideKind.zemidjan;
  RidePaymentMethod _paiement = RidePaymentMethod.cash;
  RideTariffs _tarifs = const RideTariffs();

  LatLng? _depart;
  LatLng? _arrivee;
  int? _distanceM;
  int? _durationSeconds; // Durée réelle récupérée par le service de routage
  bool _estimation = false; // true si l'itinéraire routier est indisponible
  int _tarif = 0; // Tarif calculé automatiquement par l'application

  bool _initialisation = true;
  bool _localisation = false;
  bool _calcul = false;
  bool _envoi = false;
  String? _erreurLocalisation;
  int _calculSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repereDepart.dispose();
    _repereArrivee.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _init() async {
    // Une course déjà en cours : on y retourne au lieu d'en créer une autre.
    try {
      final active = await _rides.courseActiveClient();
      if (active != null) {
        if (mounted) context.pushReplacement('/rides/${active.id}');
        return;
      }
    } on RideException {
      // Hors ligne : on laisse l'utilisateur continuer, le serveur refusera
      // au besoin (COURSE_EN_COURS).
    }

    final t = await _tarifsService.charger();
    if (!mounted) return;
    setState(() {
      _tarifs = t;
      _initialisation = false;
    });
    _localiser();
  }

  Future<void> _localiser() async {
    setState(() {
      _localisation = true;
      _erreurLocalisation = null;
    });
    try {
      final p = await _location.getCurrentLocation();
      if (!mounted) return;
      setState(() => _depart = LatLng(p.latitude, p.longitude));
      _recalculer();
    } on LocationPermissionException catch (e) {
      if (mounted) setState(() => _erreurLocalisation = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _erreurLocalisation =
              'Impossible de vous localiser. Activez le GPS ou choisissez le '
              'départ sur la carte.',
        );
      }
    } finally {
      if (mounted) setState(() => _localisation = false);
    }
  }

  Future<void> _choisirPoint({required bool depart}) async {
    final scheme = Theme.of(context).colorScheme;
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => RidePointPickerScreen(
          titre: depart ? 'Point de départ' : 'Destination',
          consigne: depart
              ? 'Touchez la carte à l\'endroit où le conducteur doit venir vous '
                    'chercher'
              : 'Touchez la carte à l\'endroit où vous allez',
          positionInitiale: depart ? _depart : (_arrivee ?? _depart),
          couleur: depart ? scheme.secondary : scheme.error,
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      if (depart) {
        _depart = r;
        _erreurLocalisation = null;
      } else {
        _arrivee = r;
      }
    });
    _recalculer();
  }

  Future<void> _recalculer() async {
    final d = _depart;
    final a = _arrivee;
    if (d == null || a == null) return;
    final seq = ++_calculSeq;
    setState(() => _calcul = true);

    final routeRes = await _routing.getRoute(origin: d, destination: a);
    if (!mounted || seq != _calculSeq) return;

    // Itinéraire indisponible : ligne droite × 1,25 (même coefficient routier
    // que les missions de dépannage).
    final coef = routeRes.isFallback ? 1.25 : 1.0;
    final metres = (routeRes.distanceMeters * coef).round();
    final secondes = (routeRes.durationSeconds * coef).round();

    // Calcul automatique et fixe du tarif par l'application (style Gozem)
    final tarifCalcule = _tarifs
        .pour(_kind)
        .estimer(metres, durationSeconds: secondes);

    setState(() {
      _distanceM = metres;
      _durationSeconds = secondes;
      _estimation = routeRes.isFallback;
      _calcul = false;
      _tarif = tarifCalcule;
    });
  }

  void _changerService(RideKind k) {
    if (_kind == k) return;
    final m = _distanceM;
    final s = _durationSeconds ?? 0;

    // Recalcule automatiquement le tarif selon le nouveau type de service choisi (Zémidjan ou Tricycle)
    final nouveauTarif = m != null
        ? _tarifs.pour(k).estimer(m, durationSeconds: s)
        : _tarif;

    setState(() {
      _kind = k;
      _tarif = nouveauTarif;
    });
  }

  String? _texteOuNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    final d = _depart;
    final a = _arrivee;
    final m = _distanceM;
    if (d == null) {
      _msg('Indiquez le point de départ.');
      return;
    }
    if (a == null) {
      _msg('Choisissez la destination sur la carte.');
      return;
    }
    if (m != null && m < 100) {
      _msg('Le départ et la destination sont trop proches.');
      return;
    }
    if (_tarif < _tarifMin) {
      _msg('Tarif invalide.');
      return;
    }

    setState(() => _envoi = true);
    try {
      final id = await _rides.creer(
        kind: _kind,
        depart: d,
        arrivee: a,
        tarifFcfa: _tarif,
        paiement: _paiement,
        adresseDepart: _texteOuNull(_repereDepart),
        adresseArrivee: _texteOuNull(_repereArrivee),
      );
      if (!mounted) return;
      context.pushReplacement('/rides/$id');
    } on RideException catch (e) {
      if (!mounted) return;
      if (e.code == 'COURSE_EN_COURS') {
        // Réseau lent : la première demande est peut-être déjà passée.
        // On ouvre la course existante au lieu d'afficher une erreur.
        try {
          final active = await _rides.courseActiveClient();
          if (active != null && mounted) {
            context.pushReplacement('/rides/${active.id}');
            return;
          }
        } on RideException {
          // On retombe sur le message d'erreur ci-dessous.
        }
      }
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demander une course'),
        actions: [
          IconButton(
            tooltip: 'Mes courses',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => context.push('/rides'),
          ),
        ],
      ),
      body: _initialisation
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ContentWidth(
                maxWidth: 720,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    context.gutter,
                    8,
                    context.gutter,
                    32,
                  ),
                  children: _contenu(),
                ),
              ),
            ),
    );
  }

  List<Widget> _contenu() {
    return [
      const SectionTitle('Quel service ?'),
      Row(
        children: [
          for (final k in RideKind.values) ...[
            if (k != RideKind.values.first) const SizedBox(width: 10),
            Expanded(
              child: _KindTile(
                kind: k,
                selected: _kind == k,
                onTap: () => _changerService(k),
              ),
            ),
          ],
        ],
      ),
      const SectionTitle('Départ'),
      _carteDepart(),
      const SectionTitle('Destination'),
      _carteArrivee(),
      if (_depart != null && _arrivee != null) ...[
        const SectionTitle('Tarif de la course'),
        _carteTarif(),
      ],
      const SectionTitle('Comment payez-vous ?'),
      _cartePaiement(),
      const SizedBox(height: 20),
      AppButton(
        label: 'Demander la course',
        icon: Icons.send_rounded,
        loading: _envoi,
        onPressed: _envoyer,
      ),
      const SizedBox(height: 10),
      Text(
        'Le conducteur voit votre numéro et votre point de départ exact '
        'seulement après avoir accepté.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: context.textSecondary),
      ),
    ];
  }

  Widget _carteDepart() {
    final scheme = Theme.of(context).colorScheme;
    final d = _depart;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.trip_origin_rounded,
                color: scheme.secondary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d != null
                          ? 'Position définie'
                          : (_localisation
                                ? 'Recherche de votre position…'
                                : 'Position inconnue'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (d != null)
                      Text(
                        '${d.latitude.toStringAsFixed(5)}, '
                        '${d.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (_localisation)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
            ],
          ),
          if (_erreurLocalisation != null) ...[
            const SizedBox(height: 8),
            Text(
              _erreurLocalisation!,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: context.readable(scheme.error),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Ma position',
                  icon: Icons.my_location_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: _localisation ? null : _localiser,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Sur la carte',
                  icon: Icons.map_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _choisirPoint(depart: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Repère de départ (facultatif)',
            hint: 'Ex. : devant le marché, près de la pharmacie',
            icon: Icons.signpost_outlined,
            controller: _repereDepart,
            maxLength: 120,
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }

  Widget _carteArrivee() {
    final scheme = Theme.of(context).colorScheme;
    final a = _arrivee;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: scheme.error, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a != null
                          ? 'Destination définie'
                          : 'Destination à choisir',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (a != null)
                      Text(
                        '${a.latitude.toStringAsFixed(5)}, '
                        '${a.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: a == null
                ? 'Choisir la destination sur la carte'
                : 'Modifier la destination',
            icon: a == null
                ? Icons.add_location_alt_outlined
                : Icons.edit_location_alt_outlined,
            variant: a == null
                ? AppButtonVariant.primary
                : AppButtonVariant.secondary,
            onPressed: () => _choisirPoint(depart: false),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Repère d\'arrivée (facultatif)',
            hint: 'Ex. : carrefour, nom du quartier',
            icon: Icons.signpost_outlined,
            controller: _repereArrivee,
            maxLength: 120,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  Widget _carteTarif() {
    final scheme = Theme.of(context).colorScheme;
    final distance = _distanceM;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _calcul || distance == null
                      ? 'Calcul de l\'itinéraire…'
                      : 'Distance : ${formaterDistance(distance)}',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_calcul)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _calcul
                        ? '...'
                        : MontantLocal.formater(_tarif, devise: _devise),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: context.readable(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _estimation
                      ? 'Tarif estimé (itinéraire indisponible)'
                      : 'Tarif officiel calculé (fixe)',
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Montant en ${_devise.libelle} · code ${_devise.code}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartePaiement() {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in RidePaymentMethod.values)
                ChoiceChip(
                  label: Text(m.libelle, style: const TextStyle(fontSize: 16)),
                  selected: _paiement == m,
                  onSelected: _envoi
                      ? null
                      : (_) => setState(() => _paiement = m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _paiement.mobileMoney
                ? 'Vous paierez directement le conducteur au numéro '
                      '${_paiement.libelle} qui s\'affichera quand il aura '
                      'accepté. Seuls les conducteurs qui reçoivent par '
                      '${_paiement.libelle} peuvent prendre cette course.'
                : 'Vous remettrez '
                      '${_tarif > 0 ? MontantLocal.formater(_tarif, devise: _devise) : 'le prix de la course'} en espèces au '
                      'conducteur, à l\'arrivée.',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final RideKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Semantics(
      button: true,
      selected: selected,
      label: kind.libelle,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.09)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            child: Column(
              children: [
                Icon(kind.icone, size: 40, color: scheme.primary),
                const SizedBox(height: 6),
                Text(
                  kind.libelle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kind.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
