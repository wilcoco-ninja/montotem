import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../wallet/data/wallet_service.dart';
import '../../../wallet/domain/wallet_model.dart';

/// Explique le modÃƒÂ¨le ÃƒÂ©conomique : pas d'abonnement, une commission prÃƒÂ©levÃƒÂ©e
/// sur chaque intervention payÃƒÂ©e via l'application et dÃƒÂ©duite du portefeuille.
class ProviderCommissionCard extends StatefulWidget {
  const ProviderCommissionCard({super.key, required this.onVoirPortefeuille});

  final VoidCallback onVoirPortefeuille;

  @override
  State<ProviderCommissionCard> createState() => _ProviderCommissionCardState();
}

class _ProviderCommissionCardState extends State<ProviderCommissionCard> {
  late final Future<WalletConfig> _config = WalletService().lireConfig();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalletConfig>(
      future: _config,
      builder: (context, snap) {
        final c = snap.data ?? const WalletConfig();
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
                      color: AppTheme.successColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.percent_rounded,
                      size: 28,
                      color: context.readable(AppTheme.successColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aucun abonnement',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'MonTotem gagne uniquement quand vous travaillez.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Point(
                icone: Icons.payments_outlined,
                texte:
                    'Commission : ${c.commissionCashPct} % (espÃƒÂ¨ces), '
                    '${c.commissionMomoPct} % (Mobile Money), '
                    '${c.commissionTravelPct} % sur les frais de dÃƒÂ©placement.',
              ),
              const _Point(
                icone: Icons.account_balance_wallet_outlined,
                texte: 'Elle est dÃƒÂ©duite automatiquement de votre portefeuille.',
              ),
              _Point(
                icone: Icons.add_card_rounded,
                texte:
                    'Rechargez par Mobile Money. Sous '
                    '${formaterFcfaSigne(c.seuilBlocageFcfa)}, votre compte est '
                    'mis en pause jusqu\'ÃƒÂ  la recharge.',
              ),
              const SizedBox(height: 14),
              AppButton(
                label: 'Voir mon portefeuille',
                icon: Icons.savings_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: widget.onVoirPortefeuille,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: AppColors.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 15.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
