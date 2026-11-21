
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accessibility/accessibility_controller.dart';
import '../../../core/models/app_user.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/auth_service.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_payment_model.dart';
import '../data/provider_identity_service.dart';
import 'widgets/provider_momo_sheet.dart';

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key, this.onRetour});

  /// Dans la coque a onglets : revient a l'onglet Accueil.
  final VoidCallback? onRetour;

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  /// Niveaux affichÃƒÂ©s (affichage uniquement : seuil en missions terminÃƒÂ©es).
  static const List<(String, int)> _niveaux = [
    ('DÃƒÂ©butant', 0),
    ('ConfirmÃƒÂ©', 10),
    ('Expert', 50),
    ('Ãƒâ€°lite', 150),
  ];

  final AuthService _authService = AuthService();
  final ProviderIdentityService _identityService = ProviderIdentityService();
  final MissionService _missionService = MissionService();

  AppUser? _user;
  IdentityStatus? _identite;
  Map<String, dynamic>? _stats;
  MomoAccount? _momo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  /// Une donnÃƒÂ©e secondaire indisponible ne doit pas bloquer le profil.
  Future<T?> _sure<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _charger() async {
    setState(() => _isLoading = true);
    try {
      final res = await Future.wait<Object?>([
        _authService.fetchCurrentUser(),
        _sure(_identityService.statut),
        _sure(_missionService.maStats),
        _sure(_missionService.monMomo),
      ]);
      if (!mounted) return;
      setState(() {
        _user = res[0] as AppUser?;
        _identite = res[1] as IdentityStatus?;
        _stats = res[2] as Map<String, dynamic>?;
        _momo = res[3] as MomoAccount?;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur de chargement du profil')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _aller(String route) async {
    await context.push(route);
    if (mounted) _charger();
  }

  Future<void> _deconnecter() async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se dÃƒÂ©connecter ?'),
        content: const Text(
          'Vous devrez vous reconnecter pour recevoir des demandes.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Se dÃƒÂ©connecter'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _authService.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Calculs Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  int get _missions => (_stats?['missions_completees'] as num?)?.toInt() ?? 0;
  int get _satisfaits => (_stats?['clients_satisfaits'] as num?)?.toInt() ?? 0;
  int get _insatisfaits =>
      (_stats?['clients_insatisfaits'] as num?)?.toInt() ?? 0;
  double get _note => (_stats?['note_moyenne'] as num?)?.toDouble() ?? 0;

  int? get _satisfactionPct {
    final total = _satisfaits + _insatisfaits;
    if (total == 0) return null;
    return ((_satisfaits / total) * 100).round();
  }

  int get _indexNiveau {
    var idx = 0;
    for (var i = 0; i < _niveaux.length; i++) {
      if (_missions >= _niveaux[i].$2) idx = i;
    }
    return idx;
  }

  /// Fidelite : 50 missions terminees et une note d'au moins 4,5.
  bool get _fidele => _missions >= 50 && _note >= 4.5;

  // Ã¢â€â‚¬Ã¢â€â‚¬ UI Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_isLoading && _user == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_user == null) {
      body = Center(
        child: SingleChildScrollView(
          child: ErrorState(
            message: 'Impossible de charger le profil.',
            onRetry: _charger,
          ),
        ),
      );
    } else {
      body = _buildContenu(_user!);
    }
    return Scaffold(body: body);
  }

  Widget _buildContenu(AppUser user) {
    final nomAffiche =
        (user.businessName != null && user.businessName!.isNotEmpty)
            ? user.businessName!
            : (user.name ?? 'Mon profil');
    final sousTitre = [
      if (user.metier != null && user.metier!.isNotEmpty) user.metier!,
      if (user.ville != null && user.ville!.isNotEmpty) user.ville!,
    ].join(' Ã¢â‚¬Â¢ ');

    final gutter = context.gutter;

    final gauche = <Widget>[
      _carteIndicateurs(),
      const SectionTitle('Mon niveau'),
      _carteNiveau(),
      const SectionTitle('Mes badges'),
      _grilleBadges(user),
    ];
    final droite = <Widget>[
      const SectionTitle('Mon dossier'),
      _ligneIdentite(),
      const SizedBox(height: 10),
      _ligneMomo(),
      const SizedBox(height: 10),
      _Rangee(
        icone: Icons.psychology_alt_outlined,
        titre: 'Mes compÃƒÂ©tences',
        sousTitre: 'Vos spÃƒÂ©cialitÃƒÂ©s visibles par les clients',
        onTap: () => _aller('/provider/competences'),
      ),
      const SectionTitle('RÃƒÂ©glages'),
      _Rangee(
        icone: Icons.text_increase_rounded,
        titre: 'Taille du texte',
        sousTitre: 'Agrandir les caractÃƒÂ¨res pour mieux lire',
        onTap: () => showAccessibilitySheet(context),
      ),
      const SizedBox(height: 10),
      _Rangee(
        icone: Icons.local_hospital_outlined,
        titre: 'NumÃƒÂ©ros d\'urgence',
        sousTitre: 'Pompiers, police, hÃƒÂ´pital',
        onTap: () => context.push('/emergency'),
      ),
      const SizedBox(height: 28),
      AppButton(
        label: 'Se dÃƒÂ©connecter',
        icon: Icons.logout_rounded,
        variant: AppButtonVariant.secondary,
        onPressed: _deconnecter,
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _entete(user, nomAffiche, sousTinte: sousTitre),
            ContentWidth(
              maxWidth: 1000,
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth >= 860) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: gauche,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: droite,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [...gauche, ...droite],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ En-tÃƒÂªte Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _entete(AppUser user, String nom, {required String sousTinte}) {
    final aPhoto =
        user.photoProfilUrl != null && user.photoProfilUrl!.isNotEmpty;
    final gutter = context.gutter;
    final niveau = _niveaux[_indexNiveau].$1;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter - 8, 4, gutter, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    iconSize: 28,
                    color: Colors.white,
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: widget.onRetour ??
                        () => context.canPop()
                            ? context.pop()
                            : context.go('/provider/home'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: user.isApproved
                                      ? AppTheme.successColor
                                      : Colors.white.withValues(alpha: 0.4),
                                  width: 3,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.16),
                                backgroundImage: aPhoto
                                    ? NetworkImage(user.photoProfilUrl!)
                                    : null,
                                child: aPhoto
                                    ? null
                                    : const Icon(Icons.person_rounded,
                                        size: 46, color: Colors.white),
                              ),
                            ),
                            if (user.isApproved)
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.successColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: AppColors.navy, width: 3),
                                  ),
                                  child: const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nom,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (sousTinte.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    sousTinte,
                                    style: const TextStyle(
                                      color: AppColors.navyOnDark,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _PastilleEntete(
                                    icone: user.isApproved
                                        ? Icons.verified_rounded
                                        : Icons.hourglass_top_rounded,
                                    texte: user.isApproved
                                        ? 'Compte validÃƒÂ©'
                                        : 'En attente de validation',
                                  ),
                                  _PastilleEntete(
                                    icone: Icons.workspace_premium_rounded,
                                    texte: 'Niveau $niveau',
                                    dore: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Indicateurs, niveau, badges Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _carteIndicateurs() {
    final pct = _satisfactionPct;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              icone: Icons.star_rounded,
              couleur: AppColors.gold,
              valeur: _note.toStringAsFixed(1),
              label: 'Note',
            ),
          ),
          const _Separateur(),
          Expanded(
            child: _MiniStat(
              icone: Icons.task_alt_rounded,
              couleur: AppTheme.successColor,
              valeur: '$_missions',
              label: 'Missions',
            ),
          ),
          const _Separateur(),
          Expanded(
            child: _MiniStat(
              icone: Icons.thumb_up_alt_rounded,
              couleur: AppTheme.primaryColor,
              valeur: pct == null ? 'Ã¢â‚¬â€' : '$pct %',
              label: 'Satisfaits',
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteNiveau() {
    final idx = _indexNiveau;
    final actuel = _niveaux[idx];
    final suivant = idx + 1 < _niveaux.length ? _niveaux[idx + 1] : null;
    final scheme = Theme.of(context).colorScheme;

    final double progression;
    final String message;
    if (suivant == null) {
      progression = 1;
      message = 'Niveau maximum atteint. Bravo !';
    } else {
      final plage = suivant.$2 - actuel.$2;
      progression =
          ((_missions - actuel.$2) / plage).clamp(0.0, 1.0).toDouble();
      final reste = suivant.$2 - _missions;
      message =
          '$reste mission${reste > 1 ? 's' : ''} terminÃƒÂ©e${reste > 1 ? 's' : ''} avant le niveau ${suivant.$1}.';
    }

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.workspace_premium_rounded,
                    color: context.readable(AppColors.gold), size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Niveau ${actuel.$1}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900)),
                    Text(
                        '$_missions mission${_missions > 1 ? 's' : ''} terminÃƒÂ©e${_missions > 1 ? 's' : ''}',
                        style: TextStyle(
                            fontSize: 15, color: context.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progression,
              minHeight: 12,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(fontSize: 15, color: context.textSecondary)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _niveaux.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        i <= idx
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: i <= idx
                            ? AppTheme.successColor
                            : scheme.onSurface.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _niveaux[i].$1,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                i == idx ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grilleBadges(AppUser user) {
    final identiteOk = _identite?.statutValidation == 'approved';
    return AdaptiveGrid(
      minItemWidth: 150,
      maxColumns: 2,
      spacing: 12,
      runSpacing: 12,
      children: [
        _BadgeTile(
          icone: Icons.verified_rounded,
          titre: 'Compte validÃƒÂ©',
          obtenu: user.isApproved,
          couleur: AppTheme.successColor,
        ),
        _BadgeTile(
          icone: Icons.badge_rounded,
          titre: 'IdentitÃƒÂ© vÃƒÂ©rifiÃƒÂ©e',
          obtenu: identiteOk,
          couleur: AppTheme.primaryColor,
        ),
        _BadgeTile(
          icone: Icons.favorite_rounded,
          titre: 'Prestataire fidÃƒÂ¨le',
          obtenu: _fidele,
          couleur: AppColors.gold,
        ),
        _BadgeTile(
          icone: Icons.account_balance_wallet_rounded,
          titre: 'Mobile Money actif',
          obtenu: _momo != null,
          couleur: AppTheme.secondaryDark,
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Dossier Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _ligneIdentite() {
    final id = _identite;
    final soumis = id?.soumis ?? false;
    final statut = id?.statutValidation;

    final (couleur, libelle) = !soumis
        ? (AppTheme.warningColor, 'Ãƒâ‚¬ envoyer (obligatoire)')
        : switch (statut) {
            'approved' => (AppTheme.successColor, 'ValidÃƒÂ©'),
            'rejected' => (AppTheme.errorColor, 'RefusÃƒÂ© : ÃƒÂ  corriger'),
            _ => (AppTheme.primaryColor, 'En cours de vÃƒÂ©rification'),
          };

    return _Rangee(
      icone: Icons.verified_user_outlined,
      titre: 'IdentitÃƒÂ© et garage',
      sousTitre: (soumis && id?.documentType != null)
          ? libelleDocument(id!.documentType)
          : 'PiÃƒÂ¨ce d\'identitÃƒÂ©, visage et photo du garage',
      pastille: StatusPill(label: libelle, color: couleur),
      onTap: () => _aller('/provider/identity'),
    );
  }

  Widget _ligneMomo() {
    final m = _momo;
    return _Rangee(
      icone: Icons.account_balance_wallet_outlined,
      titre: 'Recevoir mes paiements',
      sousTitre: m == null
          ? 'Non renseignÃƒÂ© : les clients ne peuvent payer qu\'en espÃƒÂ¨ces'
          : '${m.methode.libelle} Ã‚Â· ${m.numero}',
      onTap: () async {
        await showProviderMomoSheet(context);
        if (mounted) _charger();
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Widgets
// ----------------------------------------------------------------------------

class _PastilleEntete extends StatelessWidget {
  const _PastilleEntete({
    required this.icone,
    required this.texte,
    this.dore = false,
  });

  final IconData icone;
  final String texte;
  final bool dore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dore
            ? AppColors.amber.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone,
              color: dore ? AppColors.amberTextDark : Colors.white, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texte,
              style: TextStyle(
                color: dore ? AppColors.amberTextDark : Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icone,
    required this.couleur,
    required this.valeur,
    required this.label,
  });

  final IconData icone;
  final Color couleur;
  final String valeur;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icone, size: 26, color: context.readable(couleur)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(valeur,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        Text(label,
            style: TextStyle(fontSize: 14.5, color: context.textSecondary)),
      ],
    );
  }
}

class _Separateur extends StatelessWidget {
  const _Separateur();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 56,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.icone,
    required this.titre,
    required this.obtenu,
    required this.couleur,
  });

  final IconData icone;
  final String titre;
  final bool obtenu;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = obtenu
        ? context.readable(couleur)
        : scheme.onSurface.withValues(alpha: 0.55);

    return Semantics(
      label: '$titre, ${obtenu ? 'obtenu' : 'ÃƒÂ  obtenir'}',
      excludeSemantics: true,
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        color: obtenu ? couleur.withValues(alpha: 0.08) : null,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: obtenu
                    ? couleur.withValues(alpha: 0.16)
                    : scheme.onSurface.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(icone, size: 30, color: fg),
            ),
            const SizedBox(height: 10),
            Text(
              titre,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: obtenu ? null : scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              obtenu ? 'Obtenu' : 'Ãƒâ‚¬ obtenir',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: obtenu ? fg : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rangee extends StatelessWidget {
  const _Rangee({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
    this.pastille,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;
  final Widget? pastille;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icone, color: scheme.primary, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w800)),
                Text(sousTitre,
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: context.textSecondary)),
                if (pastille != null) ...[
                  const SizedBox(height: 6),
                  pastille!,
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
