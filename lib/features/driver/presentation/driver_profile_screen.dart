
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/driver/data/driver_service.dart';

/// Profil conducteur : infos, indicateurs, wallet, dÃƒÂ©connexion.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final DriverService _driver = DriverService();

  DriverInfo? _info;
  Map<String, dynamic>? _wallet;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final info = await _driver.charger();
    final wallet = await _driver.wallet();
    if (!mounted) return;
    setState(() {
      _info = info;
      _wallet = wallet;
      _loading = false;
    });
  }

  Future<void> _deconnecter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se dÃƒÂ©connecter ?'),
        content: const Text('Vous pourrez vous reconnecter ÃƒÂ  tout moment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Se dÃƒÂ©connecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil conducteur')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _info == null
              ? const Center(child: Text('Profil introuvable'))
              : _contenu(_info!),
    );
  }

  Widget _contenu(DriverInfo info) {
    final scheme = Theme.of(context).colorScheme;
    final wallet = _wallet;
    final balance = (wallet?['balance_fcfa'] as num?)?.toInt() ?? 0;
    final blocked = wallet?['blocked'] == true;

    return ContentWidth(
      maxWidth: 640,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            child: Row(
              children: [
                Icon(
                  info.rideKind?.icone ?? Icons.two_wheeler_rounded,
                  size: 44,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.rideKind?.libelle ?? 'Conducteur',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        info.rideKind?.description ?? '',
                        style: TextStyle(
                            fontSize: 14, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Indicateurs'),
          SoftCard(
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.star_rounded,
                  label: 'Ma note',
                  value: info.noteMoyenne.toStringAsFixed(1),
                ),
                InfoRow(
                  icon: Icons.task_alt_rounded,
                  label: 'Courses terminÃƒÂ©es',
                  value: '${info.missionsCompletees}',
                ),
                InfoRow(
                  icon: Icons.verified_rounded,
                  label: 'Statut',
                  value: info.valide ? 'ValidÃƒÂ©' : info.statutValidation,
                ),
              ],
            ),
          ),
          const SectionTitle('Portefeuille'),
          SoftCard(
            onTap: () => context.push('/provider/wallet'),
            child: Row(
              children: [
                Icon(
                  blocked
                      ? Icons.lock_outline_rounded
                      : Icons.account_balance_wallet_outlined,
                  color: blocked ? scheme.error : scheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TravelFee.fcfa(balance),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        blocked
                            ? 'Portefeuille bloquÃƒÂ© Ã‚Â· Rechargez-le'
                            : 'Mon solde',
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                blocked ? scheme.error : context.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Se dÃƒÂ©connecter',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: _deconnecter,
          ),
        ],
      ),
    );
  }
}
