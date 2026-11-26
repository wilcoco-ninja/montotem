import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/features/driver/data/driver_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';

/// Mes courses (conducteur) : historique complet des courses effectuées,
/// terminées ou annulées, avec détail au clic.
class DriverRidesScreen extends StatefulWidget {
  const DriverRidesScreen({super.key});

  @override
  State<DriverRidesScreen> createState() => _DriverRidesScreenState();
}

class _DriverRidesScreenState extends State<DriverRidesScreen> {
  final DriverService _driver = DriverService();
  final DateFormat _format = DateFormat('dd/MM/yyyy HH:mm');

  List<Ride> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _driver.mesCourses();
      if (!mounted) return;
      setState(() {
        _courses = data;
        _error = null;
      });
    } on DriverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes courses'),
        leading: BackButton(
          onPressed: () {
            // L'accueil conducteur est la carte : on y revient toujours.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/driver/home');
            }
          },
        ),
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
          message:
              'Passez en ligne depuis l\'accueil : les courses acceptées et '
              'terminées apparaîtront ici.',
        ),
      );
    }

    final terminees = _courses
        .where((r) => r.status == RideStatus.completed)
        .length;
    final gains = _courses
        .where((r) => r.status == RideStatus.completed)
        .fold<int>(0, (t, r) => t + r.prixFcfa);

    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: _charger,
      child: ContentWidth(
        maxWidth: 720,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
          children: [
            SoftCard(
              child: Row(
                children: [
                  _stat(
                    Icons.task_alt_rounded,
                    '$terminees',
                    'terminée${terminees > 1 ? 's' : ''}',
                    AppColors.success,
                  ),
                  const SizedBox(width: 16),
                  _stat(
                    Icons.payments_rounded,
                    TravelFee.fcfa(gains),
                    'gagnés',
                    AppColors.amber,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._courses.map(_carte),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icone, String valeur, String label, Color couleur) {
    return Expanded(
      child: Row(
        children: [
          Icon(icone, size: 30, color: couleur),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valeur,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carte(Ride r) {
    final couleur = r.status.couleur;
    final repere = (r.pickupAddress ?? '').isNotEmpty
        ? r.pickupAddress!
        : 'Départ choisi sur la carte';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () async {
          await context.push('/driver/rides/${r.id}');
          if (mounted) _charger();
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
              child: Icon(
                r.kind.icone,
                color: context.readable(couleur),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.kind.libelle} · ${TravelFee.fcfa(r.prixFcfa)}',
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    repere,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: context.textSecondary,
                    ),
                  ),
                  Text(
                    _format.format(r.createdAt),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: context.textSecondary,
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
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
