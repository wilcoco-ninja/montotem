import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_model.dart';
import '../../rides/data/ride_service.dart';
import '../data/fun_service.dart';
import '../domain/rire_data.dart';

/// Écran « Coffres d'étoiles » : 15 étoiles ouvrent un coffre qui cache
/// 2 à 3 blagues ou devinettes, pour patienter pendant une course ou un
/// dépannage. Une sonde vérifie toutes les 8 secondes l'état du service :
/// dès qu'il est terminé, la partie s'arrête automatiquement.
class CoffresScreen extends StatefulWidget {
  const CoffresScreen({super.key});

  @override
  State<CoffresScreen> createState() => _CoffresScreenState();
}

class _CoffresScreenState extends State<CoffresScreen> {
  static const String _cleVus = 'fun_vus';

  final FunService _fun = FunService();
  final RideService _rides = RideService();
  final MissionService _missions = MissionService();
  final Random _alea = Random();

  int _solde = 0;
  bool _chargement = true;
  bool _ouvertureEnCours = false;
  String? _erreur;
  List<ItemRire> _cartes = const <ItemRire>[];

  /// Suivi de l'attente : null (inconnu), true (en attente), false (libre).
  bool? _serviceActif;

  /// Le service surveillé vient de se terminer : le jeu s'arrête.
  bool _serviceTermine = false;
  Timer? _sonde;
  final List<String> _vus = <String>[];

  @override
  void initState() {
    super.initState();
    _chargerTout();
  }

  @override
  void dispose() {
    _sonde?.cancel();
    super.dispose();
  }

  Future<void> _chargerTout() async {
    setState(() => _chargement = true);
    String? erreur;
    try {
      final solde = await _fun.soldeEtoiles();
      if (!mounted) return;
      setState(() => _solde = solde);
    } on FunException catch (e) {
      erreur = e.message;
    } catch (_) {
      erreur = 'Connexion impossible. Réessayez.';
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chargement = false;
      _erreur = erreur;
      _vus
        ..clear()
        ..addAll(prefs.getStringList(_cleVus) ?? <String>[]);
    });
    _serviceActif = await _serviceActifMaintenant();
    if (!mounted) return;
    setState(() {});
    _demarrerSonde();
  }

  Future<void> _memoriserVus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_cleVus, _vus);
  }

  /// true si une course ou un dépannage du client est en cours (attente).
  Future<bool> _serviceActifMaintenant() async {
    try {
      final ride = await _rides.courseActiveClient();
      if (ride != null) return true;
      final missions = await _missions.mesMissions();
      for (final m in missions) {
        if (m.status.actif || m.status == MissionStatus.pending) return true;
      }
    } catch (_) {
      // Réseau absent : on garde l'état courant, sans stopper le jeu.
      return _serviceActif ?? false;
    }
    return false;
  }

  /// Sonde d'attente : toutes les 8 secondes, on vérifie l'état du service.
  /// Passage d'actif à non-actif = fin du travail : le jeu s'arrête.
  void _demarrerSonde() {
    _sonde?.cancel();
    _sonde = Timer.periodic(const Duration(seconds: 8), (_) async {
      final actif = await _serviceActifMaintenant();
      if (!mounted || _serviceTermine) return;
      if (!actif && _serviceActif == true) {
        _sonde?.cancel();
        setState(() {
          _serviceActif = false;
          _serviceTermine = true;
        });
        return;
      }
      setState(() => _serviceActif = actif);
    });
  }

  Future<void> _ouvrir() async {
    setState(() {
      _ouvertureEnCours = true;
      _erreur = null;
    });
    try {
      final solde = await _fun.ouvrirCoffre();
      final nombre = 2 + _alea.nextInt(2);
      final cartes = tirerItems(nombre, _vus.toSet());
      if (!mounted) return;
      setState(() {
        _solde = solde;
        _cartes = cartes;
        for (final c in cartes) {
          _vus.add(c.id);
        }
      });
      await _memoriserVus();
    } on FunException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Connexion impossible. Vérifiez votre réseau et réessayez.';
      });
    }
    if (mounted) setState(() => _ouvertureEnCours = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Coffres d'étoiles"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: _chargement
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _carteSolde(scheme),
                    if (_serviceTermine) ...[
                      const SizedBox(height: 16),
                      _banniere(
                        scheme,
                        couleur: AppColors.success,
                        icone: Icons.celebration_rounded,
                        texte:
                            'Service terminé ! On arrête le jeu ici — '
                            'à bientôt pour une nouvelle attente. ',
                      ),
                    ] else if (_serviceActif == true) ...[
                      const SizedBox(height: 16),
                      _banniere(
                        scheme,
                        couleur: AppColors.amber,
                        icone: Icons.hourglass_top_rounded,
                        texte:
                            'Votre course ou dépannage est en cours : '
                            'ouvrez un coffre et faites-vous patienter '
                            'agréablement !',
                      ),
                    ],
                    const SizedBox(height: 16),
                    _zoneCoffre(scheme),
                    if (_erreur != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _erreur!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    for (var i = 0; i < _cartes.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _Apparition(
                          delai: Duration(milliseconds: 140 * i),
                          enfant: _CarteItem(item: _cartes[i], numero: i + 1),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _carteSolde(ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.stars_rounded, size: 36, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_solde points d\'étoiles',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '15 étoiles = 1 coffre à ouvrir',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banniere(
    ColorScheme scheme, {
    required Color couleur,
    required IconData icone,
    required String texte,
  }) {
    return Card(
      elevation: 0,
      color: couleur.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icone, color: couleur),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                texte,
                style: const TextStyle(fontSize: 14.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneCoffre(ColorScheme scheme) {
    final bloque =
        _chargement ||
        _ouvertureEnCours ||
        _serviceTermine ||
        _solde < kCoutCoffre;
    String titre = 'Ouvrir un coffre (15 ★)';
    if (_serviceTermine) {
      titre = 'Le service est terminé — jeu suspendu';
    } else if (_solde < kCoutCoffre) {
      titre = 'Il vous faut ${kCoutCoffre - _solde} étoiles de plus';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CoffrePulse(
          actif: !bloque && !_ouvertureEnCours,
          enfant: ElevatedButton.icon(
            onPressed: bloque ? null : _ouvrir,
            icon: _ouvertureEnCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.card_giftcard_rounded),
            label: Text(titre),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _serviceTermine
              ? 'La partie s\'arrête quand le travail est fini. Gain : des '
                    'souvenirs, pas des points !'
              : 'Vous gagnez des étoiles en laissant un avis (+10, +5 si le '
                    'commentaire fait 20 caractères ou plus).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
      ],
    );
  }
}

/// Une carte tirée du coffre : blague à dévoiler ou devinette à répondre.
class _CarteItem extends StatefulWidget {
  const _CarteItem({required this.item, required this.numero});

  final ItemRire item;
  final int numero;

  @override
  State<_CarteItem> createState() => _CarteItemState();
}

class _CarteItemState extends State<_CarteItem> {
  final TextEditingController _reponse = TextEditingController();
  bool? _juste;
  bool _revelee = false;

  @override
  void dispose() {
    _reponse.dispose();
    super.dispose();
  }

  /// Minuscules, sans accents et sans ponctuation, pour comparer calmement.
  String _normaliser(String s) {
    const avecAccents = 'àáâãäçèéêëìíîïñòóôõöùúûüýÿ';
    const sansAccents = 'aaaaaceeeeiiiinooooouuuuyy';
    final bas = s.toLowerCase();
    final buf = StringBuffer();
    for (final r in bas.runes) {
      final ch = String.fromCharCode(r);
      final i = avecAccents.indexOf(ch);
      buf.write(i >= 0 ? sansAccents[i] : ch);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
  }

  bool _bonneReponse() {
    final texte = _normaliser(_reponse.text);
    for (final mot in widget.item.motsAcceptes) {
      if (texte.contains(_normaliser(mot))) return true;
    }
    return false;
  }

  void _valider() {
    setState(() {
      _juste = _bonneReponse();
      _revelee = true;
    });
  }

  void _passer() {
    setState(() => _revelee = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final estDevinette = item.type == RireType.devinette;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  estDevinette
                      ? Icons.quiz_rounded
                      : Icons.emoji_emotions_rounded,
                  size: 22,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 8),
                Text(
                  'Carte ${widget.numero} · ${item.etiquette} · ${item.categorie}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(item.avant, style: const TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 12),
            if (estDevinette && !_revelee) ..._formulaireReponse(scheme),
            if (!estDevinette && !_revelee)
              OutlinedButton(
                onPressed: () => setState(() => _revelee = true),
                child: const Text('Voir la chute'),
              ),
            if (_revelee) ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutCubic,
                child: !estDevinette
                    ? const SizedBox.shrink(key: ValueKey<String>('blague'))
                    : _juste == true
                    ? _EtoilesBravo(
                        key: const ValueKey<String>('bravo'),
                        texte: 'Bravo ! Bonne réponse :',
                      )
                    : Padding(
                        key: const ValueKey<String>('verdict'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _verdictTexte(scheme),
                      ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 480),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.14),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Container(
                  key: const ValueKey<String>('reponse'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        estDevinette ? 'La réponse :' : 'La chute :',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.reponse,
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _formulaireReponse(ColorScheme scheme) {
    return [
      TextField(
        controller: _reponse,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _valider(),
        decoration: const InputDecoration(
          hintText: 'Votre réponse ici…',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _valider,
              child: const Text('Répondre'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _passer,
              child: const Text('Passer'),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _verdictTexte(ColorScheme scheme) {
    final juste = _juste == true;
    final passe = _juste == null;
    final texte = passe
        ? 'Pas grave ! Voici la réponse :'
        : juste
        ? 'Bravo ! Bonne réponse :'
        : 'Presque ! La bonne réponse :';
    final couleur = passe ? AppColors.navy : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texte,
        style: TextStyle(color: couleur, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Fait \u00ab respirer \u00bb le bouton du coffre pour donner envie de l'ouvrir.
/// Repos absolu quand le coffre est indisponible.
class _CoffrePulse extends StatefulWidget {
  const _CoffrePulse({required this.actif, required this.enfant});

  final bool actif;
  final Widget enfant;

  @override
  State<_CoffrePulse> createState() => _CoffrePulseState();
}

class _CoffrePulseState extends State<_CoffrePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0.985,
    upperBound: 1.02,
  );

  @override
  void initState() {
    super.initState();
    if (widget.actif) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _CoffrePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.actif && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.actif && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = _ctrl.upperBound;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _ctrl, child: widget.enfant);
}

/// Entree animee d'une carte tiree du coffre : glisse vers le haut + fondu,
/// avec un leger decalage entre les cartes (effet de distribution).
class _Apparition extends StatefulWidget {
  const _Apparition({required this.delai, required this.enfant});

  final Duration delai;
  final Widget enfant;

  @override
  State<_Apparition> createState() => _ApparitionState();
}

class _ApparitionState extends State<_Apparition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _courbe = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );
  Timer? _retard;

  @override
  void initState() {
    super.initState();
    _retard = Timer(widget.delai, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _retard?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.14),
        end: Offset.zero,
      ).animate(_courbe),
      child: FadeTransition(opacity: _courbe, child: widget.enfant),
    );
  }
}

/// Celebration d'une bonne reponse : une rafale d'etoiles qui jaillissent
/// une a une (courbe elastique) devant un petit feux d'artifice.
class _EtoilesBravo extends StatefulWidget {
  const _EtoilesBravo({super.key, required this.texte});

  final String texte;

  @override
  State<_EtoilesBravo> createState() => _EtoilesBravoState();
}

class _EtoilesBravoState extends State<_EtoilesBravo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: _EtoileAnimee(ctrl: _ctrl, debut: i * 0.1),
              ),
            const SizedBox(width: 6),
            const Text('\u{1F389}', style: TextStyle(fontSize: 22)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.texte,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.successText,
          ),
        ),
      ],
    );
  }
}

/// Une etoile qui jaillit avec un rebond elastique, cadencee par [debut].
class _EtoileAnimee extends StatelessWidget {
  const _EtoileAnimee({required this.ctrl, required this.debut});

  final Animation<double> ctrl;
  final double debut;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(debut, min(1.0, debut + 0.55), curve: Curves.elasticOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Transform.scale(
        scale: 0.2 + 0.8 * anim.value,
        child: Opacity(
          opacity: anim.value.clamp(0.0, 1.0).toDouble(),
          child: child,
        ),
      ),
      child: const Icon(Icons.star_rounded, color: AppColors.gold, size: 30),
    );
  }
}
