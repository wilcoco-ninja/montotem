import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart'
    hide iconePourMetier;
import 'package:montotem/features/auth/data/matching_service.dart';

class MatchingScreen extends StatefulWidget {
  const MatchingScreen({super.key});

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  final MatchingService _matchingService = MatchingService();

  static const List<String> _categories = [
    'Tous',
    'MÃƒÂ©canicien',
    'Vulcanisateur',
    'Ãƒâ€°lectricien',
    'Station essence',
    'Garage',
  ];

  List<Prestataire> _prestatairesProches = [];
  String _categorieSelectionnee = 'Tous';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _rechercher();
  }

  Future<void> _rechercher() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final resultats = await _matchingService.trouverPrestatairesProches(
        AppConstants.initialLatitude,
        AppConstants.initialLongitude,
        AppConstants.defaultSearchRadiusKm,
      );
      if (!mounted) return;
      setState(() {
        _prestatairesProches = resultats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de charger les prestataires.';
        _isLoading = false;
      });
    }
  }

  bool _correspondCategorie(Prestataire p, String categorie) {
    if (categorie == 'Tous') return true;
    final m = p.metier.toLowerCase();
    switch (categorie) {
      case 'MÃƒÂ©canicien':
        return m.contains('mÃƒÂ©canic') || m.contains('mecanic');
      case 'Vulcanisateur':
        return m.contains('vulcanis') || m.contains('pneu');
      case 'Ãƒâ€°lectricien':
        return m.contains('ÃƒÂ©lectric') || m.contains('electric');
      case 'Station essence':
        return m.contains('essence') || m.contains('station');
      case 'Garage':
        return m.contains('garage');
      default:
        return true;
    }
  }

  List<Prestataire> get _resultatsFiltres => _prestatairesProches
      .where((p) => _correspondCategorie(p, _categorieSelectionnee))
      .toList();

  Future<void> _appeler(Prestataire p) async {
    if (p.telephone == null || p.telephone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NumÃƒÂ©ro du prestataire indisponible')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: p.telephone);

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de lancer l\'appel sur cet appareil'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune application tÃƒÂ©lÃƒÂ©phonique n\'a ÃƒÂ©tÃƒÂ© trouvÃƒÂ©e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prestataires proches')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return ChoiceChip(
                  label: Text(cat),
                  selected: cat == _categorieSelectionnee,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => _categorieSelectionnee = cat),
                );
              },
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _rechercher,
        tooltip: 'Actualiser',
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: _rechercher),
        ),
      );
    }

    final resultats = _resultatsFiltres;

    if (resultats.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Aucun prestataire trouvÃƒÂ©',
            message: 'Essayez une autre catÃƒÂ©gorie ou relancez la recherche.',
            actionLabel: 'Rechercher',
            onAction: _rechercher,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: resultats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCarte(resultats[index]),
    );
  }

  Widget _buildCarte(Prestataire p) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.colorScheme.secondary.withValues(
                  alpha: 0.15,
                ),
                backgroundImage: p.photoUrl != null
                    ? NetworkImage(p.photoUrl!)
                    : null,
                child: p.photoUrl == null
                    ? Icon(
                        iconePourMetier(p.metier),
                        color: theme.colorScheme.secondary,
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.nomAffiche,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          p.verifie
                              ? Icons.verified_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: p.verifie
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${p.metier} Ã¢â‚¬Â¢ ${p.noteMoyenne.toStringAsFixed(1)} Ã¢Ëœâ€¦',
                      style: TextStyle(
                        fontSize: 13,
                        color: onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (p.adresse != null && p.adresse!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        p.adresse!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (p.disponible)
                const StatusPill(
                  label: 'Disponible',
                  color: AppTheme.successColor,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Appeler',
                  icon: Icons.call_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _appeler(p),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'Demander',
                  icon: Icons.send_rounded,
                  onPressed: () => context.push('/nouvelle-demande', extra: p),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
