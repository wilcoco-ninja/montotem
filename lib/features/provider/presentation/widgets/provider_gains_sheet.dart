
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/travel_fee.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../wallet/domain/wallet_model.dart';

/// Feuille Ã‚Â« Mes gains Ã‚Â» : encaissÃƒÂ©, graphique 7 jours, commissions MonTotem
/// et net estimÃƒÂ©.
class ProviderGainsSheet extends StatelessWidget {
  const ProviderGainsSheet({
    super.key,
    required this.jour,
    required this.semaine,
    required this.mois,
    required this.serie,
    required this.termineesMois,
    required this.commissionJour,
    required this.commissionSemaine,
    this.config,
  });

  final int jour;
  final int semaine;
  final int mois;
  final List<({DateTime date, int montant})> serie;
  final int termineesMois;
  final int commissionJour;
  final int commissionSemaine;
  final WalletConfig? config;

  static const _lettres = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  static String _court(int v) {
    if (v <= 0) return '';
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return '$v';
  }

  static String _taux(WalletConfig c) =>
      'Taux : ${c.commissionCashPct} % (espÃƒÂ¨ces), ${c.commissionMomoPct} % '
      '(Mobile Money), ${c.commissionTravelPct} % (dÃƒÂ©placement).';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxVal = serie.fold<int>(1, (a, e) => e.montant > a ? e.montant : a);
    final aujourdhui = DateTime.now();
    final netBrut = semaine - commissionSemaine;
    final net = netBrut < 0 ? 0 : netBrut;
    final c = config;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Mes gains',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Text('Aujourd\'hui',
              style: TextStyle(fontSize: 15, color: context.textSecondary)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(TravelFee.fcfa(jour),
                style:
                    const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 18),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('7 derniers jours',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final e in serie)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(_court(e.montant),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: context.textSecondary)),
                              const SizedBox(height: 4),
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                height: (e.montant / maxVal * 90)
                                    .clamp(4.0, 90.0)
                                    .toDouble(),
                                decoration: BoxDecoration(
                                  color: e.date.day == aujourdhui.day &&
                                          e.date.month == aujourdhui.month
                                      ? AppTheme.successColor
                                      : scheme.primary.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_lettres[e.date.weekday - 1],
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          InfoRow(
              icon: Icons.date_range_rounded,
              label: 'EncaissÃƒÂ© cette semaine',
              value: TravelFee.fcfa(semaine)),
          InfoRow(
              icon: Icons.calendar_month_rounded,
              label: 'EncaissÃƒÂ© ce mois-ci',
              value: TravelFee.fcfa(mois)),
          InfoRow(
              icon: Icons.task_alt_rounded,
              label: 'Interventions terminÃƒÂ©es',
              value: '$termineesMois'),
          const SectionTitle('Commission MonTotem'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow(
                    icon: Icons.percent_rounded,
                    label: 'Commission aujourd\'hui',
                    value: TravelFee.fcfa(commissionJour)),
                InfoRow(
                    icon: Icons.percent_rounded,
                    label: 'Commission sur 7 jours',
                    value: TravelFee.fcfa(commissionSemaine)),
                InfoRow(
                    icon: Icons.savings_rounded,
                    label: 'Net estimÃƒÂ© sur 7 jours',
                    value: TravelFee.fcfa(net)),
                const SizedBox(height: 6),
                Text(
                  'Estimation d\'aprÃƒÂ¨s vos derniers mouvements de portefeuille.'
                  '${c == null ? '' : ' ${_taux(c)}'}',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: context.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Fermer',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
