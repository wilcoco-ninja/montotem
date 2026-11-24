import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/client_ui.dart';
import '../data/mission_service.dart';
import '../domain/mission_model.dart';

/// Activité du client : ses demandes de dépannage (et l'accès à ses courses).
///
/// [embedded] = onglet de l'espace client (grand titre, sans barre d'app) ;
/// sinon écran ouvert seul (route /mes-demandes) avec flèche de retour.
class MesDemandesScreen extends StatefulWidget {
  const MesDemandesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MesDemandesScreen> createState() => _MesDemandesScreenState();
}

class _MesDemandesScreenState extends State<MesDemandesScreen> {
  final MissionService _service = MissionService();
  RealtimeChannel? _canal;
  List<Mission> _missions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterMesMissions(() {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    final c = _canal;
    if (c != null) _service.arreter(c);
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final uid = _service.currentUserId;
      final data = await _service.mesMissions();
      if (!mounted) return;
      setState(() {
        _missions = data.where((m) => m.clientId == uid).toList();
        _errorMessage = null;
      });
    } on MissionException catch (e) {
      if (mounted && _missions.isEmpty) {
        setState(() => _errorMessage = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Mes demandes')),
      body: widget.embedded ? SafeArea(bottom: false, child: _body()) : _body(),
    );
  }

  Widget _body() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: _charger),
        ),
      );
    }

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          ContentWidth(
            maxWidth: 640,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.embedded) const ClientPageTitle('Activité'),
                  if (widget.embedded) const SizedBox(height: 8),
                  ClientGroup(
                    children: [
                      ClientListRow(
                        icon: Icons.two_wheeler_rounded,
                        title: 'Mes courses',
                        subtitle: 'Zémidjan et Tricycle Fret',
                        onTap: () => context.push('/rides'),
                      ),
                    ],
                  ),
                  const ClientSectionTitle('Dépannages'),
                  if (_missions.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Aucune demande pour le moment',
                      message: 'Vos demandes de dépannage apparaîtront ici.',
                    )
                  else
                    for (var i = 0; i < _missions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _carteMission(_missions[i]),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteMission(Mission m) {
    final couleur = m.status.couleur;
    return ClientCard(
      onTap: () => context.push('/mes-demandes/${m.id}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              m.status.icone,
              color: context.readable(couleur),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.problem,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  m.providerName,
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                StatusPill(
                  label: m.status.libelle,
                  color: couleur,
                  icon: m.status.icone,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.textTertiary),
        ],
      ),
    );
  }
}
