
import 'package:flutter/material.dart';

import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';
import 'package:montotem/features/admin/data/admin_service.dart';

class AdminLeaderboardScreen extends StatefulWidget {
  const AdminLeaderboardScreen({super.key});

  @override
  State<AdminLeaderboardScreen> createState() => _AdminLeaderboardScreenState();
}

class _AdminLeaderboardScreenState extends State<AdminLeaderboardScreen> {
  final AdminService _adminService = AdminService();
  List<Prestataire> _prestataires = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prestataires = await _adminService.obtenirPrestataires();
      prestataires.sort((a, b) => b.points.compareTo(a.points));
      if (!mounted) return;
      setState(() {
        _prestataires = prestataires;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de charger le classement.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classement des prestataires'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _charger,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: _charger),
        ),
      );
    }

    if (_prestataires.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'Aucun prestataire',
        ),
      );
    }

    return ContentWidth(
      maxWidth: 800,
      child: RefreshIndicator(
        onRefresh: _charger,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _prestataires.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _LeaderboardTile(rang: index + 1, p: _prestataires[index]),
        ),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.rang, required this.p});
  final int rang;
  final Prestataire p;

  Color get _rangColor {
    switch (rang) {
      case 1:
        return const Color(0xFFFFB300);
      case 2:
        return const Color(0xFF90A4AE);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _rangColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: _rangColor, width: 2),
            ),
            child: Text(
              '$rang',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color:
                    rang <= 3 ? _rangColor : onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.nom,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      p.verifie
                          ? Icons.verified_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: p.verifie ? scheme.secondary : scheme.error,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  p.metier,
                  style: TextStyle(
                    fontSize: 13,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(
                      label: p.noteMoyenne.toStringAsFixed(1),
                      color: Colors.amber.shade800,
                      icon: Icons.star_rounded,
                    ),
                    StatusPill(
                      label: '${p.points} pts',
                      color: Colors.deepPurple,
                      icon: Icons.emoji_events_outlined,
                    ),
                    StatusPill(
                      label: '${p.clientsSatisfaits}',
                      color: scheme.secondary,
                      icon: Icons.thumb_up_outlined,
                    ),
                    StatusPill(
                      label: '${p.clientsInsatisfaits}',
                      color: scheme.error,
                      icon: Icons.thumb_down_outlined,
                    ),
                    StatusPill(
                      label: '${p.missionsCompletees} missions',
                      color: Colors.blueGrey,
                      icon: Icons.task_alt_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
