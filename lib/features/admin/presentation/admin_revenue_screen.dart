
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/travel_fee.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_ui.dart';
import '../data/admin_revenue_service.dart';

/// Ãƒâ€°cran autonome Ã‚Â« Revenus MonTotem Ã‚Â» (route /admin/revenue).
class AdminRevenueScreen extends StatelessWidget {
  const AdminRevenueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revenus MonTotem')),
      body: const AdminRevenuePanel(),
    );
  }
}

/// Contenu sans Scaffold : rÃƒÂ©utilisÃƒÂ© par l'onglet Ã‚Â« Finances Ã‚Â» de la tour de
/// contrÃƒÂ´le.
class AdminRevenuePanel extends StatefulWidget {
  const AdminRevenuePanel({super.key});

  @override
  State<AdminRevenuePanel> createState() => _AdminRevenuePanelState();
}

class _AdminRevenuePanelState extends State<AdminRevenuePanel>
    with AutomaticKeepAliveClientMixin {
  static const List<int> _periodes = [7, 30, 90];

  final AdminRevenueService _service = AdminRevenueService();
  int _jours = 30;
  RevenueSummary? _r;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
      final r = await _service.resume(_jours);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _r;

    if (_loading && r == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (r == null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(
            message: _error ?? 'Erreur de chargement.',
            onRetry: _charger,
          ),
        ),
      );
    }

    return ContentWidth(
      maxWidth: 800,
      child: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final j in _periodes)
                  ChoiceChip(
                    label: Text('$j jours'),
                    selected: _jours == j,
                    onSelected: (_) {
                      if (_jours == j) return;
                      setState(() => _jours = j);
                      _charger();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _hero(r),
            const SectionTitle('RÃƒÂ©partition'),
            SoftCard(
              child: Column(
                children: [
                  _part('Courses en espÃƒÂ¨ces', r.commissionCash,
                      r.commissionTotal, AppColors.navy),
                  _part('Courses Mobile Money', r.commissionMomo,
                      r.commissionTotal, AppTheme.successColor),
                  _part('Frais de dÃƒÂ©placement', r.commissionTravel,
                      r.commissionTotal, AppColors.amber),
                ],
              ),
            ),
            const SectionTitle('Commissions par jour'),
            SoftCard(child: _BarresEmpilees(serie: r.series)),
            const SectionTitle('Portefeuilles et activitÃƒÂ©'),
            SoftCard(
              child: Column(
                children: [
                  InfoRow(
                    icon: Icons.add_card_rounded,
                    label: 'Recharges crÃƒÂ©ditÃƒÂ©es',
                    value: TravelFee.fcfa(r.topups),
                  ),
                  InfoRow(
                    icon: Icons.task_alt_rounded,
                    label: 'Courses terminÃƒÂ©es',
                    value: '${r.ridesCompleted}',
                  ),
                  InfoRow(
                    icon: Icons.route_rounded,
                    label: 'Volume des courses',
                    value: TravelFee.fcfa(r.ridesVolume),
                  ),
                  InfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Dette des portefeuilles',
                    value: TravelFee.fcfa(r.walletDebt),
                  ),
                  InfoRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Prestataires bloquÃƒÂ©s',
                    value: '${r.providersBlocked}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Valider les recharges',
              icon: Icons.add_card_rounded,
              onPressed: () => context.push('/admin/topups'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(RevenueSummary r) {
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.percent_rounded,
                size: 30, color: context.readable(AppTheme.successColor)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commissions MonTotem',
                    style:
                        TextStyle(fontSize: 15, color: context.textSecondary)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    TravelFee.fcfa(r.commissionTotal),
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                ),
                Text('sur ${r.days} jours',
                    style:
                        TextStyle(fontSize: 14, color: context.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _part(String label, int montant, int total, Color couleur) {
    final ratio =
        total <= 0 ? 0.0 : (montant / total).clamp(0.0, 1.0).toDouble();
    final pct = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration:
                    BoxDecoration(color: couleur, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text('${TravelFee.fcfa(montant)} Ã‚Â· $pct %',
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: couleur,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Histogramme empilÃƒÂ© : dÃƒÂ©placement (haut), Mobile Money, espÃƒÂ¨ces (bas).
class _BarresEmpilees extends StatelessWidget {
  const _BarresEmpilees({required this.serie});

  final List<RevenueDay> serie;

  @override
  Widget build(BuildContext context) {
    if (serie.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aucune donnÃƒÂ©e.', style: TextStyle(fontSize: 15)),
      );
    }
    final maxTotal = serie.fold<int>(1, (a, d) => d.total > a ? d.total : a);
    final fin = serie.length <= 14;

    Widget seg(int v, Color c) {
      if (v <= 0) return const SizedBox.shrink();
      return Container(
        height: (v / maxTotal * 140).clamp(2.0, 140.0).toDouble(),
        color: c,
      );
    }

    String d(DateTime x) => '${x.day}/${x.month}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final j in serie)
                Expanded(
                  child: Tooltip(
                    message: '${d(j.date)} : ${TravelFee.fcfa(j.total)}',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: fin ? 3 : 0.5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(fin ? 4 : 1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            seg(j.travel, AppColors.amber),
                            seg(j.momo, AppTheme.successColor),
                            seg(j.cash, AppColors.navy),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(d(serie.first.date),
                style: TextStyle(fontSize: 13, color: context.textSecondary)),
            Text(d(serie[serie.length ~/ 2].date),
                style: TextStyle(fontSize: 13, color: context.textSecondary)),
            Text(d(serie.last.date),
                style: TextStyle(fontSize: 13, color: context.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Legende(couleur: AppColors.navy, texte: 'EspÃƒÂ¨ces'),
            _Legende(couleur: AppTheme.successColor, texte: 'Mobile Money'),
            _Legende(couleur: AppColors.amber, texte: 'DÃƒÂ©placement'),
          ],
        ),
      ],
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende({required this.couleur, required this.texte});

  final Color couleur;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(texte, style: const TextStyle(fontSize: 13.5)),
      ],
    );
  }
}
