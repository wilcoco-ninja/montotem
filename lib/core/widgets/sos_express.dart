
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/theme/app_colors.dart';

// =============================================================================
// SOS Express : bandeau 1-clic + bouton Ã‚Â« JE SUIS EN PANNE Ã‚Â».
// Fichier : lib/core/widgets/sos_express.dart
// =============================================================================

/// Jaune zÃƒÂ©midjan (signature MONTOTEM). Toujours avec du texte NAVY dessus.
const Color kVolt = Color(0xFFFFC400);
const Color _verre = Color(0xF21C1B3D);

/// Donne la position du client (null si le GPS est coupÃƒÂ© ou refusÃƒÂ©).
typedef PositionProvider = Future<LatLng?> Function();

// Ã¢â€â‚¬Ã¢â€â‚¬ MÃƒÂ©tiers du bandeau Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class SosMetier {
  const SosMetier(this.kind, this.label, this.icon);

  /// Valeur de providers.provider_kind.
  final String kind;
  final String label;
  final IconData icon;
}

const kSosMetiers = <SosMetier>[
  SosMetier('mecanicien', 'MÃƒÂ©cano', Icons.build_rounded),
  SosMetier('vulcanisateur', 'Vulca', Icons.tire_repair_rounded),
  SosMetier('electricien', 'Ãƒâ€°lectro', Icons.electrical_services_rounded),
  SosMetier('station', 'Carburant', Icons.local_gas_station_rounded),
  SosMetier('zemidjan', 'Zem', Icons.two_wheeler_rounded),
];

SosMetier _metierDe(String kind) => kSosMetiers
    .firstWhere((m) => m.kind == kind, orElse: () => kSosMetiers.first);

// Ã¢â€â‚¬Ã¢â€â‚¬ DonnÃƒÂ©es Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class Proche {
  const Proche({
    required this.id,
    required this.nom,
    required this.metier,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.distanceM,
    required this.etaMin,
    required this.fraisFcfa,
    required this.note,
    required this.disponible,
    this.telephone,
  });

  factory Proche.fromJson(Map<String, dynamic> j) => Proche(
        id: '${j['id']}',
        nom: (j['nom'] as String?) ?? 'Prestataire',
        metier: (j['metier'] as String?) ?? '',
        kind: (j['provider_kind'] as String?) ?? '',
        latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
        distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
        etaMin: (j['eta_min'] as num?)?.toInt() ?? 1,
        fraisFcfa: (j['travel_fee_fcfa'] as num?)?.toInt() ?? 0,
        note: (j['note_moyenne'] as num?)?.toDouble() ?? 0,
        disponible: (j['disponible'] as bool?) ?? true,
        telephone: j['telephone'] as String?,
      );

  final String id;
  final String nom;
  final String metier;
  final String kind;
  final double latitude;
  final double longitude;
  final int distanceM;
  final int etaMin;
  final int fraisFcfa;
  final double note;
  final bool disponible;
  final String? telephone;

  /// Ã‚Â« 450 m Ã‚Â» ou Ã‚Â« 1,2 km Ã‚Â».
  String get distanceTexte => distanceM < 1000
      ? '$distanceM m'
      : '${(distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Ã‚Â« 450 m Ã‚Â· 5 min Ã‚Â»
  String get resume => '$distanceTexte Ã‚Â· $etaMin min';
}

class SosService {
  SosService._();

  /// Appelle la fonction SQL `providers_nearest` (script 13).
  static Future<List<Proche>> chercher({
    required LatLng position,
    String? kind,
    String? vehicule,
    double rayonKm = 3,
    int limite = 3,
  }) async {
    final r = await Supabase.instance.client.rpc('providers_nearest', params: {
      'p_lat': position.latitude,
      'p_lng': position.longitude,
      'p_kind': kind,
      'p_vehicle': vehicule,
      'p_radius_km': rayonKm,
      'p_limit': limite,
    });
    return (r as List)
        .whereType<Map>()
        .map((e) => Proche.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class _SansPosition implements Exception {
  const _SansPosition();
}

String _fcfa(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

// =============================================================================
// 1. Bandeau flottant : 5 icÃƒÂ´nes gÃƒÂ©antes, 1 tap = rÃƒÂ©sultat
// =============================================================================

class SosExpressBar extends StatelessWidget {
  const SosExpressBar({super.key, required this.onSelect});

  final ValueChanged<SosMetier> onSelect;

  /// Hauteur fixe (icÃƒÂ´ne 20-28 px + libellÃƒÂ© sur une ligne).
  static const double hauteur = 66;

  static const double _gouttiere = 12;
  static const double _ecart = 8;
  static const double _largeurMini = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: hauteur,
      child: LayoutBuilder(
        builder: (context, c) {
          final n = kSosMetiers.length;
          final libre = c.maxWidth - 2 * _gouttiere - (n - 1) * _ecart;
          final largeur = libre / n;
          // Ãƒâ€°cran assez large : les 5 cases se partagent la largeur.
          // Ãƒâ€°cran trÃƒÂ¨s ÃƒÂ©troit : la rangÃƒÂ©e dÃƒÂ©file, rien n'est ÃƒÂ©crasÃƒÂ©.
          final defile = largeur < _largeurMini;
          final w = defile ? _largeurMini : largeur;
          final icone = (w * 0.38).clamp(20.0, 28.0).toDouble();

          Widget case_(SosMetier m) => SizedBox(
                width: w,
                child: _CaseMetier(
                  metier: m,
                  icone: icone,
                  onTap: () => onSelect(m),
                ),
              );

          if (!defile) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: _gouttiere),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [for (final m in kSosMetiers) case_(m)],
              ),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _gouttiere),
            itemCount: n,
            separatorBuilder: (_, __) => const SizedBox(width: _ecart),
            itemBuilder: (_, i) => case_(kSosMetiers[i]),
          );
        },
      ),
    );
  }
}

class _CaseMetier extends StatelessWidget {
  const _CaseMetier({
    required this.metier,
    required this.icone,
    required this.onTap,
  });

  final SosMetier metier;
  final double icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final forme = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: kVolt.withValues(alpha: 0.45), width: 1.2),
    );
    return Semantics(
      button: true,
      label: '${metier.label} le plus proche',
      excludeSemantics: true,
      child: Material(
        color: _verre,
        shape: forme,
        child: InkWell(
          customBorder: forme,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(metier.icon, size: icone, color: kVolt),
                const SizedBox(height: 4),
                // Le libellÃƒÂ© rÃƒÂ©trÃƒÂ©cit au lieu de dÃƒÂ©border (petits ÃƒÂ©crans,
                // texte agrandi par le systÃƒÂ¨me).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metier.label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
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

/// Clic sur une icÃƒÂ´ne : localise, trouve le plus proche, affiche distance,
/// frais de dÃƒÂ©placement et le gros bouton d'appel.
Future<void> montrerPlusProche(
  BuildContext context, {
  required SosMetier metier,
  required PositionProvider position,
  String? vehicule,
  void Function(Proche)? onVoirCarte,
}) {
  return _ouvrirFeuille(
    context,
    _NearestSheet(
      metier: metier,
      position: position,
      vehicule: vehicule,
      onVoirCarte: onVoirCarte,
    ),
  );
}

// =============================================================================
// 2. Bouton central Ã‚Â« JE SUIS EN PANNE Ã‚Â»
// =============================================================================

class PanneButton extends StatefulWidget {
  const PanneButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double hauteur = 54;

  @override
  State<PanneButton> createState() => _PanneButtonState();
}

class _PanneButtonState extends State<PanneButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respecte Ã‚Â« rÃƒÂ©duire les animations Ã‚Â» du tÃƒÂ©lÃƒÂ©phone.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: kVolt.withValues(alpha: 0.20 + 0.22 * _c.value),
              blurRadius: 10 + 10 * _c.value,
              spreadRadius: 0.5 + 2 * _c.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Semantics(
        button: true,
        label:
            'Je suis en panne. Trouver 3 dÃƒÂ©panneurs ÃƒÂ  moins de 3 kilomÃƒÂ¨tres',
        excludeSemantics: true,
        child: FilledButton.icon(
          onPressed: widget.onPressed,
          icon: const Icon(Icons.warning_amber_rounded, size: 24),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('JE SUIS EN PANNE', maxLines: 1),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: kVolt,
            foregroundColor: AppColors.navy,
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(PanneButton.hauteur),
            textStyle: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Une pression : cherche ÃƒÂ  3 km les 3 mÃƒÂ©tiers adaptÃƒÂ©s au vÃƒÂ©hicule.
/// [vehicule] (moto / voiture / camion) saute la question ; sinon elle est
/// posÃƒÂ©e une seule fois puis mÃƒÂ©morisÃƒÂ©e.
Future<void> montrerPanne(
  BuildContext context, {
  required PositionProvider position,
  String? vehicule,
  void Function(Proche)? onVoirCarte,
}) {
  return _ouvrirFeuille(
    context,
    _PanneSheet(
      position: position,
      vehicule: vehicule,
      onVoirCarte: onVoirCarte,
    ),
  );
}

// =============================================================================
// Feuilles
// =============================================================================

Future<void> _ouvrirFeuille(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => child,
  );
}

// Ã¢â€â‚¬Ã¢â€â‚¬ 1-clic : le plus proche d'un mÃƒÂ©tier Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _NearestSheet extends StatefulWidget {
  const _NearestSheet({
    required this.metier,
    required this.position,
    this.vehicule,
    this.onVoirCarte,
  });

  final SosMetier metier;
  final PositionProvider position;
  final String? vehicule;
  final void Function(Proche)? onVoirCarte;

  @override
  State<_NearestSheet> createState() => _NearestSheetState();
}

class _NearestSheetState extends State<_NearestSheet> {
  double _rayon = 5;
  late Future<Proche?> _future = _chercher();

  Future<Proche?> _chercher() async {
    final pos = await widget.position();
    if (pos == null) throw const _SansPosition();
    final r = await SosService.chercher(
      position: pos,
      kind: widget.metier.kind,
      vehicule: widget.vehicule,
      rayonKm: _rayon,
      limite: 1,
    );
    return r.isEmpty ? null : r.first;
  }

  void _relancer({double? rayon}) {
    setState(() {
      if (rayon != null) _rayon = rayon;
      _future = _chercher();
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metier;
    return FutureBuilder<Proche?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Chargement(
              texte: 'Je cherche le ${m.label} le plus procheÃ¢â‚¬Â¦');
        }
        if (snap.hasError) {
          final gps = snap.error is _SansPosition;
          return _Message(
            icon: gps ? Icons.location_off_rounded : Icons.wifi_off_rounded,
            texte: gps
                ? 'Activez la localisation (GPS) de votre tÃƒÂ©lÃƒÂ©phone, '
                    'puis rÃƒÂ©essayez.'
                : 'Connexion impossible. VÃƒÂ©rifiez votre rÃƒÂ©seau et rÃƒÂ©essayez.',
            action: 'RÃƒÂ©essayer',
            onAction: () => _relancer(),
          );
        }
        final p = snap.data;
        if (p == null) {
          final loin = _rayon < 15;
          return _Message(
            icon: Icons.search_off_rounded,
            texte: 'Aucun ${m.label} disponible ÃƒÂ  ${_rayon.toInt()} km.',
            action: loin ? 'Chercher ÃƒÂ  15 km' : null,
            onAction: loin ? () => _relancer(rayon: 15) : null,
          );
        }
        return _ResultatProche(
          p: p,
          metier: m,
          onVoirCarte: widget.onVoirCarte == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onVoirCarte!(p);
                },
        );
      },
    );
  }
}

class _ResultatProche extends StatelessWidget {
  const _ResultatProche(
      {required this.p, required this.metier, this.onVoirCarte});

  final Proche p;
  final SosMetier metier;
  final VoidCallback? onVoirCarte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconeMetier(icon: metier.icon, taille: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nom,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      p.metier,
                      style:
                          TextStyle(fontSize: 16, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${p.resume}${p.note > 0 ? ' Ã‚Â· ${p.note.toStringAsFixed(1)} Ã¢Ëœâ€¦' : ''}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Frais de dÃƒÂ©placement',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Text(
                  _fcfa(p.fraisFcfa),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _BoutonAppel(p: p, label: 'Appeler le dÃƒÂ©panneur maintenant'),
          if (onVoirCarte != null)
            TextButton.icon(
              onPressed: onVoirCarte,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Voir sur la carte'),
            ),
        ],
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Ã‚Â« JE SUIS EN PANNE Ã‚Â» : 3 mÃƒÂ©tiers adaptÃƒÂ©s au vÃƒÂ©hicule Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _Choix {
  const _Choix(this.metier, this.proche);
  final SosMetier metier;
  final Proche? proche;
}

class _PanneSheet extends StatefulWidget {
  const _PanneSheet({required this.position, this.vehicule, this.onVoirCarte});

  final PositionProvider position;
  final String? vehicule;
  final void Function(Proche)? onVoirCarte;

  @override
  State<_PanneSheet> createState() => _PanneSheetState();
}

class _PanneSheetState extends State<_PanneSheet> {
  static const _cle = 'sos_vehicle';

  String? _vehicule;
  bool _pret = false;
  double _rayon = 3;
  Future<List<_Choix>>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.vehicule != null) {
      _vehicule = widget.vehicule;
      _pret = true;
      _future = _charger();
    } else {
      _lirePrefs();
    }
  }

  Future<void> _lirePrefs() async {
    String? v;
    try {
      v = (await SharedPreferences.getInstance()).getString(_cle);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _vehicule = v;
      _pret = true;
      if (v != null) _future = _charger();
    });
  }

  Future<void> _choisir(String v) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_cle, v);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _vehicule = v;
      _future = _charger();
    });
  }

  /// Moto : pneu d'abord. Auto / camion : mÃƒÂ©canique d'abord.
  List<String> get _ordre => _vehicule == 'moto'
      ? const ['vulcanisateur', 'mecanicien', 'station']
      : const ['mecanicien', 'vulcanisateur', 'electricien'];

  Future<List<_Choix>> _charger() async {
    final pos = await widget.position();
    if (pos == null) throw const _SansPosition();
    final ordre = _ordre;
    final res = await Future.wait(ordre.map((k) => SosService.chercher(
          position: pos,
          kind: k,
          vehicule: _vehicule,
          rayonKm: _rayon,
          limite: 1,
        )));
    return [
      for (var i = 0; i < ordre.length; i++)
        _Choix(_metierDe(ordre[i]), res[i].isEmpty ? null : res[i].first),
    ];
  }

  void _elargir() {
    setState(() {
      _rayon = 10;
      _future = _charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_pret) return const _Chargement(texte: 'Ã¢â‚¬Â¦');
    if (_vehicule == null || _future == null) {
      return _ChoixVehicule(onChoix: _choisir);
    }

    return FutureBuilder<List<_Choix>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _Chargement(
              texte: 'Je scanne ${_rayon.toInt()} km autour de vousÃ¢â‚¬Â¦');
        }
        if (snap.hasError) {
          final gps = snap.error is _SansPosition;
          return _Message(
            icon: gps ? Icons.location_off_rounded : Icons.wifi_off_rounded,
            texte: gps
                ? 'Activez la localisation (GPS) de votre tÃƒÂ©lÃƒÂ©phone, '
                    'puis rÃƒÂ©essayez.'
                : 'Connexion impossible. VÃƒÂ©rifiez votre rÃƒÂ©seau et rÃƒÂ©essayez.',
            action: 'RÃƒÂ©essayer',
            onAction: () => setState(() => _future = _charger()),
          );
        }
        final choix = snap.data ?? const <_Choix>[];
        final trouves = choix.where((c) => c.proche != null).length;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trouves == 0
                          ? 'Personne ÃƒÂ  moins de ${_rayon.toInt()} km'
                          : 'Du secours ÃƒÂ  moins de ${_rayon.toInt()} km',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _vehicule = null;
                      _future = null;
                    }),
                    child: Text(_vehicule == 'moto' ? 'Moto Ã¢Å“Å½' : 'Auto Ã¢Å“Å½'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final c in choix) ...[
                _CarteChoix(
                  choix: c,
                  rayon: _rayon,
                  onVoirCarte: widget.onVoirCarte == null || c.proche == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onVoirCarte!(c.proche!);
                        },
                ),
                const SizedBox(height: 10),
              ],
              if (_rayon < 10)
                OutlinedButton.icon(
                  onPressed: _elargir,
                  icon: const Icon(Icons.zoom_out_map_rounded),
                  label: Text(trouves < choix.length
                      ? 'Ãƒâ€°largir la recherche ÃƒÂ  10 km'
                      : 'Chercher plus loin (10 km)'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChoixVehicule extends StatelessWidget {
  const _ChoixVehicule({required this.onChoix});

  final ValueChanged<String> onChoix;

  @override
  Widget build(BuildContext context) {
    Widget tuile(String cle, String label, IconData icon) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Material(
              color: kVolt,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onChoix(cle),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      Icon(icon, size: 52, color: AppColors.navy),
                      const SizedBox(height: 6),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Quel vÃƒÂ©hicule est en panne ?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Une seule fois : nous le mÃƒÂ©morisons.',
              style: TextStyle(fontSize: 15, color: context.textSecondary)),
          const SizedBox(height: 16),
          Row(
            children: [
              tuile('voiture', 'Auto', Icons.directions_car_rounded),
              const SizedBox(width: 12),
              tuile('moto', 'Moto', Icons.two_wheeler_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteChoix extends StatelessWidget {
  const _CarteChoix(
      {required this.choix, required this.rayon, this.onVoirCarte});

  final _Choix choix;
  final double rayon;
  final VoidCallback? onVoirCarte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = choix.metier;
    final p = choix.proche;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: p == null
          ? Row(
              children: [
                _IconeMetier(icon: m.icon, taille: 44, actif: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aucun ${m.label} ÃƒÂ  ${rayon.toInt()} km',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondary),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconeMetier(icon: m.icon, taille: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900)),
                          Text(
                            '${m.label} Ã‚Â· ${p.resume}',
                            style: TextStyle(
                                fontSize: 15, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _fcfa(p.fraisFcfa),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _BoutonAppel(p: p, label: 'Appeler', compact: true),
                if (onVoirCarte != null)
                  TextButton(
                    onPressed: onVoirCarte,
                    child: const Text('Voir sur la carte'),
                  ),
              ],
            ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ PiÃƒÂ¨ces communes Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _IconeMetier extends StatelessWidget {
  const _IconeMetier(
      {required this.icon, required this.taille, this.actif = true});

  final IconData icon;
  final double taille;
  final bool actif;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: actif ? kVolt : Colors.grey.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
      child: Icon(icon,
          size: taille * 0.55,
          color: actif ? AppColors.navy : context.textSecondary),
    );
  }
}

class _BoutonAppel extends StatelessWidget {
  const _BoutonAppel(
      {required this.p, required this.label, this.compact = false});

  final Proche p;
  final String label;
  final bool compact;

  Future<void> _appeler(BuildContext context, String tel) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'tel', path: tel));
    } catch (_) {}
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Impossible d\'appeler. NumÃƒÂ©ro : $tel')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tel = p.telephone;
    final hauteur = compact ? 52.0 : 64.0;
    final style = FilledButton.styleFrom(
      backgroundColor: kVolt,
      foregroundColor: AppColors.navy,
      minimumSize: Size.fromHeight(hauteur),
      shape: const StadiumBorder(),
      textStyle:
          TextStyle(fontSize: compact ? 17 : 20, fontWeight: FontWeight.w900),
    );

    if (tel == null || tel.isEmpty) {
      // InvitÃƒÂ© : le numÃƒÂ©ro est rÃƒÂ©servÃƒÂ© aux comptes connectÃƒÂ©s.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.go('/register/quick?role=client');
            },
            icon: const Icon(Icons.person_rounded),
            label: const Text('Se connecter pour appeler'),
            style: style,
          ),
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Le numÃƒÂ©ro s\'affiche aprÃƒÂ¨s connexion avec votre tÃƒÂ©lÃƒÂ©phone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.textSecondary),
              ),
            ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: () => _appeler(context, tel),
      icon: Icon(Icons.call_rounded, size: compact ? 24 : 28),
      label: Text(label),
      style: style,
    );
  }
}

class _Chargement extends StatelessWidget {
  const _Chargement({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(texte,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.texte,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String texte;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 48, color: context.textSecondary),
          const SizedBox(height: 12),
          Text(texte,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: kVolt,
                foregroundColor: AppColors.navy,
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
                textStyle:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}
