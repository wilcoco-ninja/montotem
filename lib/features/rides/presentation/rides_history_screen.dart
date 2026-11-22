
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';
import 'package:montotem/features/wallet/domain/montant_local.dart';

/// Historique des courses du client.
class RidesHistoryScreen extends StatefulWidget {
  const RidesHistoryScreen({super.key});

  @override
  State<RidesHistoryScreen> createState() => _RidesHistoryScreenState();
}

class _RidesHistoryScreenState extends State<RidesHistoryScreen> {
  final RideService _service = RideService();

  /// Devise de la zone (XOF au Bénin) pour l'affichage des montants.
  Devise get _devise => MontantLocal.deCourse();
  final DateFormat _format = DateFormat('dd/MM/yyyy HH:mm');

  RealtimeChannel? _canal;
  List<Ride> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterMesCourses(() {
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
        _loading = true;
        _error = null;
      });
    }
    try {
      final uid = _service.currentUserId;
      final data = await _service.mesCourses();
      if (!mounted) return;
      setState(() {
        _courses = data.where((r) => r.clientId == uid).toList();
        _error = null;
      });
    } on RideException catch (e) {
      if (mounted && _courses.isEmpty) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes courses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/ride/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle course'),
      ),
      body: _corps(),
    );
  }

  Widget _corps() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: _charger),
        ),
      );
    }
    if (_courses.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.two_wheeler_rounded,
          title: 'Aucune course pour le moment',
          message: 'Vos courses Zémidjan et Tricycle Fret apparaîtront ici.',
        ),
      );
    }

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: _charger,
      child: ContentWidth(
        maxWidth: 720,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 96),
          itemCount: _courses.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _carte(_courses[i]),
        ),
      ),
    );
  }

  Widget _carte(Ride r) {
    final couleur = r.status.couleur;
    final repere = (r.pickupAddress ?? '').isNotEmpty
        ? r.pickupAddress!
        : 'Départ choisi sur la carte';

    return SoftCard(
      onTap: () async {
        await context.push('/rides/${r.id}');
        if (mounted) _charger(silencieux: true);
      },
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                Icon(r.kind.icone, color: context.readable(couleur), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.kind.libelle} · ${MontantLocal.formater(r.prixFcfa, devise: _devise)}',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
                Text(
                  repere,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 14.5, color: context.textSecondary),
                ),
                Text(
                  _format.format(r.createdAt),
                  style:
                      TextStyle(fontSize: 13.5, color: context.textSecondary),
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
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
