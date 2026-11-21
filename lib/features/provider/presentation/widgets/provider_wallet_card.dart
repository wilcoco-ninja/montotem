
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_ui.dart';
import '../../../wallet/data/wallet_service.dart';
import '../../../wallet/domain/wallet_model.dart';

/// Message affichÃƒÂ© quand un prestataire bloquÃƒÂ© tente de passer en ligne.
const String kMessageCompteBloque =
    'Compte bloquÃƒÂ© : rechargez votre portefeuille pour recevoir des demandes.';

/// Carte portefeuille de l'accueil : solde, ÃƒÂ©tat, commission, recharge.
class ProviderWalletCard extends StatelessWidget {
  const ProviderWalletCard({
    super.key,
    required this.snap,
    required this.onTap,
  });

  final WalletSnapshot? snap;
  final VoidCallback onTap;

  static String _commission(WalletConfig c) {
    if (c.commissionCashPct == c.commissionMomoPct &&
        c.commissionMomoPct == c.commissionTravelPct) {
      return 'Commission MonTotem : ${c.commissionCashPct} % sur chaque '
          'intervention payÃƒÂ©e via l\'application.';
    }
    return 'Commission MonTotem : ${c.commissionCashPct} % (espÃƒÂ¨ces), '
        '${c.commissionMomoPct} % (Mobile Money), '
        '${c.commissionTravelPct} % (dÃƒÂ©placement).';
  }

  @override
  Widget build(BuildContext context) {
    final s = snap;
    if (s == null) {
      return SoftCard(
        onTap: onTap,
        child: const Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Chargement du portefeuilleÃ¢â‚¬Â¦',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final w = s.wallet;
    final cfg = s.config;
    final bloque = w.blocked;
    final negatif = w.balanceFcfa < 0;
    final alerte = bloque || negatif;
    final Color couleur = bloque
        ? AppTheme.errorColor
        : (negatif ? AppTheme.warningColor : AppTheme.successColor);
    final marge = w.balanceFcfa - cfg.seuilBlocageFcfa;

    final String detail = bloque
        ? 'Les nouvelles demandes sont suspendues. Rechargez pour ÃƒÂªtre '
            'dÃƒÂ©bloquÃƒÂ©.'
        : (negatif
            ? 'Marge avant blocage : ${formaterFcfaSigne(marge)}.'
            : _commission(cfg));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: alerte ? couleur : Colors.transparent,
          width: 2,
        ),
      ),
      child: SoftCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    bloque
                        ? Icons.lock_outline_rounded
                        : Icons.account_balance_wallet_rounded,
                    size: 28,
                    color: context.readable(couleur),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mon portefeuille',
                        style: TextStyle(
                            fontSize: 14.5, color: context.textSecondary),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formaterFcfaSigne(w.balanceFcfa),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: context.readable(couleur),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: bloque ? 'BloquÃƒÂ©' : 'Actif',
                  color: couleur,
                  icon: bloque
                      ? Icons.lock_outline_rounded
                      : Icons.check_circle_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              style: TextStyle(
                  fontSize: 15, height: 1.35, color: context.textSecondary),
            ),
            if (s.fromCache) ...[
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 18),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Hors ligne : dernier solde connu.',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
            if (alerte) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Recharger mon portefeuille',
                icon: Icons.add_card_rounded,
                variant:
                    bloque ? AppButtonVariant.danger : AppButtonVariant.primary,
                onPressed: onTap,
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Voir le dÃƒÂ©tail',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy.withValues(alpha: 0.9),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
