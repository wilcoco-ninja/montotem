import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, Supabase, PostgrestException;

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/wallet/data/payment_account_service.dart';
import 'package:montotem/features/wallet/data/wallet_service.dart';
import 'package:montotem/features/wallet/domain/topup_request_model.dart';
import 'package:montotem/features/wallet/domain/wallet_model.dart';
import 'package:montotem/features/wallet/presentation/ledger_history_screen.dart';

/// Opérateurs Mobile Money acceptés pour payer une commission cash.
/// Codes alignés avec la base (mission_payments.operateur) et avec la
/// RPC `payer_commission_cash` (script finance/13).
class _OperateurPaiement {
  const _OperateurPaiement(this.code, this.libelle);
  final String code;
  final String libelle;
}

const List<_OperateurPaiement> _operateursPaiement = [
  _OperateurPaiement('mtn', 'MTN MoMo'),
  _OperateurPaiement('moov', 'Moov Money'),
  _OperateurPaiement('celtiis', 'Celtiis Cash'),
];

class ProviderWalletScreen extends StatefulWidget {
  const ProviderWalletScreen({super.key});

  @override
  State<ProviderWalletScreen> createState() => _ProviderWalletScreenState();
}

class _ProviderWalletScreenState extends State<ProviderWalletScreen> {
  final WalletService _service = WalletService();
  final PaymentAccountService _paymentAccountService =
      const PaymentAccountService();
  final DateFormat _format = DateFormat('dd/MM/yyyy HH:mm');

  RealtimeChannel? _canal;
  Timer? _antiRebond;

  WalletSnapshot? _snap;

  /// Photo du double ledger : RPC `solde_wallet_prestataire` (script 13).
  /// null si la RPC n'est pas encore déployée ou réseau indisponible :
  /// les pavés retombent alors sur le solde historique.
  Map<String, dynamic>? _ledger;

  /// Cash encaissé sur les 7 derniers jours :
  /// RPC `provider_earnings_summary(p_days := 7)` → `rides_cash_fcfa` (044).
  int? _cashEncaisse;

  TopupRequest? _derniere;
  List<PaymentAccount> _comptes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _chargerComptes();
    _canal = _service.ecouter(_planifierRecharge);
  }

  @override
  void dispose() {
    _antiRebond?.cancel();
    final c = _canal;
    if (c != null) _service.arreter(c);
    super.dispose();
  }

  void _planifierRecharge() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _charger(silencieux: true);
    });
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final s = await _service.charger();
      final d = await _service.derniereDemande();
      if (!mounted) return;
      setState(() {
        _snap = s;
        _derniere = d;
        _error = null;
      });
    } on WalletException catch (e) {
      if (mounted && _snap == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _chargerLedger();
  }

  /// Ne lève jamais : si les RPC finance (script 13) ne sont pas encore
  /// exécutées ou si le réseau est coupé, l'écran reste fonctionnel avec
  /// les données historiques du wallet.
  Future<void> _chargerLedger() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'solde_wallet_prestataire',
      );
      if (!mounted) return;
      if (res is Map) setState(() => _ledger = Map<String, dynamic>.from(res));
    } catch (_) {
      if (mounted) setState(() => _ledger = null);
    }
    try {
      final res = await Supabase.instance.client.rpc(
        'provider_earnings_summary',
        params: {'p_days': 7},
      );
      if (!mounted) return;
      if (res is Map) {
        setState(
          () => _cashEncaisse = ((res['rides_cash_fcfa'] as num?) ?? 0).toInt(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _cashEncaisse = null);
    }
  }

  Future<void> _chargerComptes() async {
    final c = await _paymentAccountService.obtenirComptesPaiement();
    if (mounted) setState(() => _comptes = c);
  }

  Future<void> _copier(String texte) async {
    await Clipboard.setData(ClipboardData(text: texte));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Numéro copié.')));
  }

  Future<void> _declarer(WalletSnapshot snap) async {
    final dette = snap.wallet.balanceFcfa < 0 ? -snap.wallet.balanceFcfa : 0;
    var suggere = ((dette + 499) ~/ 500) * 500;
    if (suggere < kRechargeMinFcfa) suggere = kRechargeMinFcfa;
    if (suggere > kRechargeMaxFcfa) suggere = kRechargeMaxFcfa;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _TopupSheet(
          service: _service,
          comptes: _comptes,
          montantSuggere: dette > 0 ? suggere : null,
        ),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recharge déclarée. L\'administrateur la vérifie puis crédite votre wallet.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      _charger(silencieux: true);
    }
  }

  Future<void> _payerCommission(int commissionDue) async {
    FocusScope.of(context).unfocus();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _PaiementCommissionSheet(commissionDue: commissionDue),
      ),
    );
    if (ok == true && mounted) {
      _charger(silencieux: true);
    }
  }

  Color _couleurSolde(Wallet w, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (w.blocked) return scheme.error;
    if (balanceEffectifNegatif(w)) return scheme.error;
    return scheme.secondary;
  }

  /// Dette de commission cash, miroir du RPC `est_bloque_cash` (13) :
  /// ledger si disponible, sinon repli historique (solde négatif).
  int _commissionDue(WalletSnapshot snap) {
    final ledger = _ledger;
    if (ledger != null) {
      return ((ledger['cash_commission_debt'] as num?) ?? 0).toInt();
    }
    final w = snap.wallet;
    if (w.cashCommissionDebt > 0) return w.cashCommissionDebt;
    return w.balanceFcfa < 0 ? -w.balanceFcfa : 0;
  }

  /// Solde MoMo retirable (payable_balance), repli historique si absent.
  int _soldeMomo(WalletSnapshot snap) {
    final ledger = _ledger;
    if (ledger != null) {
      return ((ledger['payable_balance'] as num?) ?? 0).toInt();
    }
    final w = snap.wallet;
    if (w.payableBalance > 0) return w.payableBalance;
    return w.balanceFcfa > 0 ? w.balanceFcfa : 0;
  }

  /// true quand la dette historique est portée par le solde (repli).
  bool balanceEffectifNegatif(Wallet w) =>
      _ledger == null && w.payableBalance == 0 && w.balanceFcfa < 0;

  bool _bloqueCash() {
    final ledger = _ledger;
    if (ledger == null) return false;
    return ledger['bloque_cash'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon wallet'),
        actions: [
          IconButton(
            tooltip: 'Grand livre (audit)',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LedgerHistoryScreen()),
            ),
          ),
        ],
      ),
      body: _corps(),
    );
  }

  Widget _corps() {
    final snap = _snap;
    if (_loading && snap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snap == null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(
            message: _error ?? 'Wallet indisponible.',
            onRetry: _charger,
          ),
        ),
      );
    }

    final gutter = context.gutter;
    final demande = _carteDemande();
    return RefreshIndicator(
      onRefresh: _charger,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
        child: ContentWidth(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (snap.fromCache) _banniereHorsLigne(snap),
              _carteSolde(snap),
              const SizedBox(height: 12),
              _pavesLedger(snap),
              if (_bloqueCash() && !snap.wallet.blocked) ...[
                const SizedBox(height: 12),
                _cartePlafondCash(snap),
              ],
              if (snap.wallet.blocked) ...[
                const SizedBox(height: 12),
                _carteBlocage(snap),
              ],
              const SectionTitle('Comment ça marche'),
              _carteRegles(snap.config),
              if (_comptes.isNotEmpty) ...[
                const SectionTitle('Recharger mon wallet'),
                _carteRecharge(snap),
              ],
              if (demande != null) ...[const SizedBox(height: 12), demande],
              const SectionTitle('Historique'),
              ..._historique(snap),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banniereHorsLigne(WalletSnapshot snap) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hors ligne : dernier solde connu le '
              '${_format.format(snap.fetchedAt)}.',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteSolde(WalletSnapshot snap) {
    final w = snap.wallet;
    final couleur = _couleurSolde(w, context);
    final fg = context.readable(couleur);
    final marge = w.balanceFcfa - snap.config.seuilBlocageFcfa;

    final String detail;
    if (w.blocked) {
      detail = 'Les nouvelles demandes sont suspendues.';
    } else if (balanceEffectifNegatif(w)) {
      detail =
          'Marge avant blocage : ${formaterFcfaSigne(marge)} '
          '(seuil ${formaterFcfaSigne(snap.config.seuilBlocageFcfa)}).';
    } else {
      detail =
          'Paiements Mobile Money encaissés par MonTotem pour vous : '
          '${formaterFcfaSigne(_soldeMomo(snap))} (retirables).';
    }

    return SoftCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Solde du wallet',
                  style: TextStyle(fontSize: 16, color: context.textSecondary),
                ),
              ),
              StatusPill(
                label: w.blocked ? 'Bloqué' : 'Actif',
                color: couleur,
                icon: w.blocked
                    ? Icons.lock_outline_rounded
                    : Icons.check_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formaterFcfaSigne(w.balanceFcfa),
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Les 3 pavés du pilier 3 : Cash encaissé / Commission due / Solde MoMo.
  Widget _pavesLedger(WalletSnapshot snap) {
    final due = _commissionDue(snap);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Pave(
            titre: 'Cash encaissé',
            sousTitre: '7 derniers jours',
            texte: formaterFcfaSigne(_cashEncaisse ?? 0),
            icon: Icons.payments_rounded,
            couleur: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Pave(
            titre: 'Commission due',
            sousTitre: 'courses cash',
            texte: formaterFcfaSigne(due),
            icon: Icons.receipt_long_rounded,
            couleur: due > 0
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.secondary,
            bouton: due > 0
                ? AppButton(
                    label: 'Payer ma commission',
                    icon: Icons.currency_exchange_rounded,
                    onPressed: () => _payerCommission(due),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Pave(
            titre: 'Solde MoMo',
            sousTitre: 'retirable',
            texte: formaterFcfaSigne(_soldeMomo(snap)),
            icon: Icons.account_balance_wallet_outlined,
            couleur: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  /// Avertissement quand le serveur refuse désormais les courses cash
  /// (dette >= plafond de crédit, script finance/13).
  Widget _cartePlafondCash(WalletSnapshot snap) {
    final scheme = Theme.of(context).colorScheme;
    final ledger = _ledger;
    final plafond = ((ledger?['credit_limit'] as num?) ?? 0).toInt();
    final dette = _commissionDue(snap);
    final aPayer = dette > plafond ? dette : plafond;
    final fg = context.readable(scheme.error);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_rounded, color: fg, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plafond de dette cash atteint',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Vos nouvelles courses payées en cash sont refusées tant que '
                  'votre commission due (${formaterFcfaSigne(dette)}) atteint '
                  'votre plafond (${formaterFcfaSigne(plafond)}). Payez au '
                  'moins ${formaterFcfaSigne(aPayer)} par Mobile Money pour '
                  'recevoir de nouveau des courses cash.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: 'Payer ma commission',
                  icon: Icons.currency_exchange_rounded,
                  onPressed: () => _payerCommission(dette),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteBlocage(WalletSnapshot snap) {
    final scheme = Theme.of(context).colorScheme;
    final w = snap.wallet;
    final ecart = snap.config.seuilBlocageFcfa - w.balanceFcfa;
    final int pourDebloquer = ecart < 0 ? 0 : ecart;
    final int pourEquilibrer = w.balanceFcfa < 0 ? -w.balanceFcfa : 0;
    final fg = context.readable(scheme.error);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: fg, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compte bloqué',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Votre solde est passé sous '
                  '${formaterFcfaSigne(snap.config.seuilBlocageFcfa)}. '
                  'Rechargez au moins ${formaterFcfaSigne(pourDebloquer)} pour '
                  'être débloqué automatiquement, ou '
                  '${formaterFcfaSigne(pourEquilibrer)} pour repartir à zéro.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _puce(String texte) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.chevron_right_rounded, size: 22),
          ),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteRegles(WalletConfig c) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _puce(
            'Course payée en cash : ${c.commissionCashPct} % du prix '
            'augmentent votre commission due. Vous gardez 100 % du cash '
            'remis par le client, mais votre dette grandit.',
          ),
          _puce(
            'Course payée en Mobile Money : ${c.commissionMomoPct} % '
            'sont retenus automatiquement sur votre solde MoMo. Le client '
            'vous paie directement, MonTotem prélève sa commission sur '
            'votre solde encaissable.',
          ),
          _puce(
            'Frais de déplacement d\'une intervention : '
            '${c.commissionTravelPct} % sont déduits de votre wallet '
            'quand vous confirmez la réception du paiement.',
          ),
          _puce(
            'Si votre dette cash atteint votre plafond, les nouvelles '
            'courses payées en cash sont refusées jusqu\'au paiement de '
            'votre commission par Mobile Money.',
          ),
          _puce(
            'Si votre solde passe sous '
            '${formaterFcfaSigne(c.seuilBlocageFcfa)}, vous ne recevez plus '
            'de demandes jusqu\'à la recharge.',
          ),
        ],
      ),
    );
  }

  Widget _carteRecharge(WalletSnapshot snap) {
    final scheme = Theme.of(context).colorScheme;
    final enAttente = _derniere?.statut == StatutRecharge.enAttente;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '1. Envoyez le montant par Mobile Money à l\'un de ces numéros.\n'
            '2. Déclarez votre paiement avec la référence reçue par SMS.\n'
            '3. Un administrateur vérifie puis crédite votre wallet.',
            style: TextStyle(
              fontSize: 15.5,
              height: 1.45,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final c in _comptes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.libelleOperateur,
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textSecondary,
                            ),
                          ),
                          Text(
                            c.numero,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (c.titulaire.isNotEmpty)
                            Text(
                              'Au nom de ${c.titulaire}',
                              style: const TextStyle(fontSize: 14),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copier le numéro',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copier(c.numero),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          AppButton(
            label: 'J\'ai payé : déclarer ma recharge',
            icon: Icons.send_rounded,
            onPressed: enAttente ? null : () => _declarer(snap),
          ),
          if (enAttente)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Une recharge est déjà en cours de vérification.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: context.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _carteDemande() {
    final d = _derniere;
    if (d == null || d.statut == StatutRecharge.validee) return null;

    final scheme = Theme.of(context).colorScheme;
    final enAttente = d.statut == StatutRecharge.enAttente;
    final couleur = scheme.error;
    final fg = context.readable(couleur);
    final motif = (d.motifRefus ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: couleur.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enAttente
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            color: fg,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enAttente
                      ? 'Recharge en cours de vérification'
                      : 'Dernière recharge refusée',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formaterFcfaSigne(d.amountFcfa)} · ${d.libelleOperateur} · '
                  'réf. ${d.transactionRef}',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: context.textSecondary,
                  ),
                ),
                if (!enAttente && motif.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Motif : $motif',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historique(WalletSnapshot snap) {
    if (snap.transactions.isEmpty) {
      return const <Widget>[
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Aucun mouvement',
          message: 'Les commissions et les recharges apparaîtront ici.',
        ),
      ];
    }
    return [
      for (final t in snap.transactions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ligneTransaction(t),
        ),
    ];
  }

  Widget _ligneTransaction(WalletTransaction t) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = t.estCredit ? scheme.secondary : scheme.error;
    final complement = [
      if ((t.reference ?? '').isNotEmpty) 'réf. ${t.reference}',
      if ((t.note ?? '').isNotEmpty) t.note!,
    ].join(' · ');

    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              t.estCredit
                  ? Icons.add_circle_outline_rounded
                  : Icons.remove_circle_outline_rounded,
              color: context.readable(couleur),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.libelle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _format.format(t.createdAt.toLocal()),
                  style: TextStyle(fontSize: 14, color: context.textSecondary),
                ),
                if (complement.isNotEmpty)
                  Text(
                    complement,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: context.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${t.estCredit ? '+' : ''}${formaterFcfaSigne(t.amountFcfa)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.readable(couleur),
                ),
              ),
              Text(
                'Solde ${formaterFcfaSigne(t.balanceAfter)}',
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pavé compact du tableau de bord wallet (pilier 3).
class _Pave extends StatelessWidget {
  const _Pave({
    required this.titre,
    required this.sousTitre,
    required this.texte,
    required this.icon,
    required this.couleur,
    this.bouton,
  });

  final String titre;
  final String sousTitre;
  final String texte;
  final IconData icon;
  final Color couleur;
  final Widget? bouton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: couleur),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              texte,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: couleur == scheme.error ? couleur : null,
              ),
            ),
          ),
          Text(
            sousTitre,
            style: TextStyle(fontSize: 12.5, color: context.textSecondary),
          ),
          if (bouton != null) ...[const SizedBox(height: 8), bouton!],
        ],
      ),
    );
  }
}

class _TopupSheet extends StatefulWidget {
  const _TopupSheet({
    required this.service,
    required this.comptes,
    this.montantSuggere,
  });

  final WalletService service;
  final List<PaymentAccount> comptes;
  final int? montantSuggere;

  @override
  State<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<_TopupSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _montant;
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _ref = TextEditingController();

  String? _operateur;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _montant = TextEditingController(
      text: widget.montantSuggere == null ? '' : '${widget.montantSuggere}',
    );
    if (widget.comptes.length == 1) _operateur = widget.comptes.first.operateur;
  }

  @override
  void dispose() {
    _montant.dispose();
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _validerMontant(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Saisissez le montant envoyé';
    if (n < kRechargeMinFcfa || n > kRechargeMaxFcfa) {
      return 'Entre $kRechargeMinFcfa et 1 000 000 FCFA';
    }
    return null;
  }

  String? _validerPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'Numéro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  String? _validerRef(String? v) => (v == null || v.trim().length < 6)
      ? 'Saisissez la référence reçue par SMS (6 caractères minimum)'
      : null;

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    final op = _operateur;
    if (op == null) {
      _msg('Choisissez l\'opérateur utilisé pour payer.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _envoi = true);
    try {
      await widget.service.declarerRecharge(
        montantFcfa: int.parse(_montant.text.trim()),
        operateur: op,
        payerPhone: AuthService.normalizePhone(_phone.text),
        reference: _ref.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on WalletException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _msg(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Déclarer ma recharge',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Renseignez le paiement que vous venez d\'envoyer. Votre wallet '
              'est crédité après vérification.',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Opérateur utilisé',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in widget.comptes)
                  ChoiceChip(
                    label: Text(
                      c.libelleOperateur,
                      style: const TextStyle(fontSize: 16),
                    ),
                    selected: _operateur == c.operateur,
                    onSelected: _envoi
                        ? null
                        : (_) => setState(() => _operateur = c.operateur),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Montant envoyé (FCFA)',
              hint: 'Ex. : 5000',
              helper: 'Entre $kRechargeMinFcfa et 1 000 000 FCFA',
              icon: Icons.payments_outlined,
              controller: _montant,
              enabled: !_envoi,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 7,
              validator: _validerMontant,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Numéro avec lequel vous avez payé',
              hint: '01 97 00 00 00',
              icon: Icons.phone_outlined,
              controller: _phone,
              enabled: !_envoi,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              validator: _validerPhone,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Référence de la transaction',
              helper: 'Reçue par SMS après le paiement',
              icon: Icons.receipt_long_outlined,
              controller: _ref,
              enabled: !_envoi,
              textInputAction: TextInputAction.done,
              validator: _validerRef,
              onSubmitted: (_) => _envoi ? null : _envoyer(),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Envoyer pour validation',
              icon: Icons.send_rounded,
              loading: _envoi,
              onPressed: _envoyer,
            ),
          ],
        ),
      ),
    );
  }
}

/// Paiement de la commission due par Mobile Money : RPC
/// `payer_commission_cash` (script finance/13), idempotent via
/// `client_request_id` (anti double-débit en réseau instable).
class _PaiementCommissionSheet extends StatefulWidget {
  const _PaiementCommissionSheet({required this.commissionDue});

  final int commissionDue;

  @override
  State<_PaiementCommissionSheet> createState() =>
      _PaiementCommissionSheetState();
}

class _PaiementCommissionSheetState extends State<_PaiementCommissionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _montant;
  final TextEditingController _phone = TextEditingController();

  /// Identifiant de requête client généré UNE fois à l'ouverture : si le
  /// réseau coupe après le paiement, un nouvel essai avec le même
  /// identifiant renvoie `deja_traite` au lieu de débiter deux fois.
  late final String _clientRequestId;

  String? _operateur;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _montant = TextEditingController(text: '${widget.commissionDue}');
    _clientRequestId = 'cashpay-${DateTime.now().microsecondsSinceEpoch}';
    _montant.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _montant.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _validerMontant(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return 'Saisissez le montant payé';
    if (n <= 0) return 'Le montant doit être supérieur à 0';
    if (n > widget.commissionDue) {
      return 'Maximum ${formaterFcfaSigne(widget.commissionDue)} (votre '
          'commission due)';
    }
    return null;
  }

  String? _validerPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'Numéro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  String _messageRpc(String message) {
    if (message.contains('NON_CONNECTE')) {
      return 'Session expirée. Reconnectez-vous.';
    }
    if (message.contains('MONTANT_SUPERIEUR_DETTE')) {
      return 'Le montant dépasse votre commission due.';
    }
    if (message.contains('MONTANT_INVALIDE')) {
      return 'Montant invalide.';
    }
    return 'Paiement impossible pour le moment. Réessayez.';
  }

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    final op = _operateur;
    if (op == null) {
      _msg('Choisissez l\'opérateur utilisé pour payer.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _envoi = true);
    try {
      final res = await Supabase.instance.client.rpc(
        'payer_commission_cash',
        params: {
          'p_montant': int.parse(_montant.text.trim()),
          'p_client_request_id': _clientRequestId,
          'p_operateur': op,
          'p_phone': _phone.text.trim().isEmpty
              ? null
              : AuthService.normalizePhone(_phone.text),
        },
      );
      if (!mounted) return;
      final dejaTraite = res is Map && res['deja_traite'] == true;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dejaTraite
                ? 'Ce paiement a déjà été enregistré.'
                : 'Commission payée. Votre dette est mise à jour.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _msg(_messageRpc(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _msg(
        'Paiement envoyé mais réponse perdue : rouvrez la feuille pour '
        'vérifier votre dette avant de payer à nouveau.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final payeTotal =
        int.tryParse(_montant.text.trim()) == widget.commissionDue;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Payer ma commission',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Vous avez gardé le cash des courses : envoyez le montant par '
              'Mobile Money pour solder votre commission due '
              '(${formaterFcfaSigne(widget.commissionDue)}).',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Opérateur utilisé',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final o in _operateursPaiement)
                  ChoiceChip(
                    label: Text(
                      o.libelle,
                      style: const TextStyle(fontSize: 16),
                    ),
                    selected: _operateur == o.code,
                    onSelected: _envoi
                        ? null
                        : (_) => setState(() => _operateur = o.code),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Montant payé (FCFA)',
              helper:
                  'Maximum ${formaterFcfaSigne(widget.commissionDue)} (votre '
                  'dette). Paiement partiel accepté.',
              icon: Icons.currency_exchange_rounded,
              controller: _montant,
              enabled: !_envoi,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 7,
              validator: _validerMontant,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Numéro avec lequel vous payez (facultatif)',
              hint: '01 97 00 00 00',
              icon: Icons.phone_outlined,
              controller: _phone,
              enabled: !_envoi,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              validator: _validerPhone,
              onSubmitted: (_) => _envoi ? null : _envoyer(),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: payeTotal ? 'Payer la totalité' : 'Payer ce montant',
              icon: Icons.send_rounded,
              loading: _envoi,
              onPressed: _envoyer,
            ),
          ],
        ),
      ),
    );
  }
}
