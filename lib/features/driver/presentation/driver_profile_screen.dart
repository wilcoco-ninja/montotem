import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/driver/data/driver_service.dart';
import 'package:montotem/features/provider/data/provider_identity_service.dart';
import 'package:montotem/features/provider/presentation/widgets/provider_momo_sheet.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';

/// Profil conducteur : infos, indicateurs, wallet, déconnexion.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final DriverService _driver = DriverService();
  final ProviderIdentityService _identiteService = ProviderIdentityService();

  DriverInfo? _info;
  IdentityStatus? _identite;
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
    final identite = await _identiteService.statut();
    if (!mounted) return;
    setState(() {
      _info = info;
      _wallet = wallet;
      _identite = identite;
      _loading = false;
    });
  }

  /// Ouvre la feuille de configuration Mobile Money puis recharge le profil.
  Future<void> _configurerMomo() async {
    await showProviderMomoSheet(context);
    if (!mounted) return;
    await _charger();
  }

  /// Dossier d'identité : photos prises à la caméra, vérifiées par l'admin.
  Widget _carteDossierIdentite(ColorScheme scheme, DriverInfo info) {
    final id = _identite;
    final soumis = id?.soumis ?? false;
    final statut = id?.statutValidation ?? info.statutValidation;

    final (icone, couleur, titre, sousTitre) = !soumis
        ? (
            Icons.photo_camera_rounded,
            scheme.error,
            'Dossier obligatoire — à envoyer',
            'Prenez en photo votre pièce d\'identité, votre visage et votre '
                'véhicule. Sans ce dossier, votre compte ne peut pas être '
                'validé.',
          )
        : switch (statut) {
            'approved' => (
              Icons.verified_rounded,
              AppColors.success,
              'Dossier validé',
              'Votre identité est vérifiée. Vous êtes visible des clients.',
            ),
            'rejected' => (
              Icons.error_outline_rounded,
              scheme.error,
              'Dossier refusé',
              'Corrigez et renvoyez vos photos : '
                  '${id?.motifRefus ?? 'motif communiqué par l\'administration'}.',
            ),
            _ => (
              Icons.hourglass_top_rounded,
              AppColors.amber,
              'En cours de vérification',
              'L\'administration MonTotem examine vos photos. '
                  'Vous serez notifié dès la décision.',
            ),
          };

    final aAction = !soumis || statut == 'rejected';
    return SoftCard(
      onTap: aAction
          ? () async {
              await context.push('/provider/identity');
              if (mounted) _charger();
            }
          : null,
      color: aAction ? couleur.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Icon(icone, size: 32, color: couleur),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: couleur,
                  ),
                ),
                Text(
                  sousTitre,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (aAction)
            const Icon(Icons.chevron_right_rounded)
          else
            Icon(Icons.check_rounded, size: 22, color: couleur),
        ],
      ),
    );
  }

  Future<void> _deconnecter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous pourrez vous reconnecter à tout moment.'),
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
            child: const Text('Se déconnecter'),
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
                        info.nomAffiche?.isNotEmpty == true
                            ? info.nomAffiche!
                            : (info.rideKind?.libelle ?? 'Conducteur'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        info.ville?.isNotEmpty == true
                            ? '${info.rideKind?.libelle ?? 'Conducteur'} · ${info.ville}'
                            : (info.rideKind?.description ?? 'Conducteur'),
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Mon dossier d\'identité'),
          _carteDossierIdentite(scheme, info),
          if (!info.valide) ...[
            const SizedBox(height: 12),
            if (info.rejete)
              SoftCard(
                color: scheme.error.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: scheme.error,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dossier refusé${info.rejectionReason == null ? '' : ' : ${info.rejectionReason}'}\n'
                        'Reprenez votre inscription pour corriger votre dossier.',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              SoftCard(
                color: AppColors.amber.withValues(alpha: 0.10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: AppColors.amber,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Votre dossier est en attente de validation par '
                        'l\'administration MonTotem. Vous recevrez une '
                        'notification dès validation.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SectionTitle('Mes courses'),
          SoftCard(
            onTap: () => context.push('/driver/rides'),
            child: const Row(
              children: [
                Icon(Icons.history_rounded, size: 30, color: AppColors.navy),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historique de mes courses',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('Courses terminées, en cours et annulées'),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded),
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
                  label: 'Courses terminées',
                  value: '${info.missionsCompletees}',
                ),
                InfoRow(
                  icon: Icons.verified_rounded,
                  label: 'Statut',
                  value: info.libelleValidation,
                ),
              ],
            ),
          ),
          const SectionTitle('Mobile Money'),
          SoftCard(
            onTap: _configurerMomo,
            child: Row(
              children: [
                Icon(
                  info.momoConfigure
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  color: info.momoConfigure
                      ? AppColors.success
                      : scheme.primary,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.momoConfigure
                            ? 'Compte configuré'
                            : 'Configurer mon compte',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        info.momoConfigure
                            ? '${PayMethod.fromCode(info.momoOperateur).libelle}'
                                  ' · ${info.momoNumero ?? ''}'
                            : 'Nécessaire pour recevoir les paiements '
                                  'Mobile Money des clients.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
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
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        blocked
                            ? 'Portefeuille bloqué · Rechargez-le'
                            : 'Mon solde',
                        style: TextStyle(
                          fontSize: 14,
                          color: blocked ? scheme.error : context.textSecondary,
                        ),
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
            label: 'Se déconnecter',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: _deconnecter,
          ),
        ],
      ),
    );
  }
}
