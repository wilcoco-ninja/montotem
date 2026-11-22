import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/admin/data/admin_finance_service.dart';
import 'package:montotem/features/admin/presentation/widgets/admin_style.dart';
import 'package:montotem/features/wallet/data/ledger_service.dart';
import 'package:montotem/features/wallet/domain/montant_local.dart';

const List<String> _clesConfig = [
  'cash_credit_limit_fcfa',
  'wallet_block_threshold_fcfa',
];

const List<String> _kindsLedger = [
  'tous',
  'cash_encaisse',
  'commission_cash',
  'commission_momo',
  'commission_travel',
  'momo_paiement',
  'topup',
  'debit_commission',
  'ajustement',
  'remboursement',
];

const Map<String, String> _labelsKinds = {
  'cash_encaisse': 'Cash encaisse',
  'commission_cash': 'Commission cash',
  'commission_momo': 'Commission MoMo',
  'commission_travel': 'Commission deplacement',
  'momo_paiement': 'Paiement MoMo',
  'topup': 'Recharge',
  'debit_commission': 'Paiement commission',
  'ajustement': 'Ajustement',
  'remboursement': 'Remboursement',
};

const List<(String, String)> _categoriesCommission = [
  ('ride_zemidjan', 'Course zemidjan (moto)'),
  ('ride_tricycle_passenger', 'Course kloboto passager'),
  ('ride_tricycle_fret', 'Course kloboto fret'),
  ('mission_moto', 'Depannage moto'),
  ('mission_tricycle', 'Depannage tricycle'),
  ('mission_voiture', 'Depannage voiture'),
  ('mission_bus', 'Depannage bus'),
  ('mission_camion', 'Depannage camion'),
  ('mission_remorquage', 'Remorquage garage'),
];

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key});

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  final AdminFinanceService _service = AdminFinanceService();

  final TextEditingController _plafondCtrl = TextEditingController();
  final TextEditingController _seuilCtrl = TextEditingController();

  List<Map<String, dynamic>> _devises = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _regles = [];
  List<Map<String, dynamic>> _ledger = [];
  Map<String, dynamic> _summary = {};
  Map<String, int> _config = {};

  String _filtreLedger = 'tous';
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chargerTout();
  }

  @override
  void dispose() {
    _plafondCtrl.dispose();
    _seuilCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerTout({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _isRefreshing = true);
    }
    try {
      final devises = await _service.listerDevises();
      final zones = await _service.listerZones();
      final regles = await _service.listerReglesCommission();
      final summary = await _service.resumeCommission();
      final config = await _service.chargerConfigCles(_clesConfig);
      final ledger = await _service.chargerLedger();
      if (!mounted) return;
      setState(() {
        _devises = devises;
        _zones = zones;
        _regles = regles;
        _summary = summary;
        _config = config;
        _ledger = ledger;
        _majControllers();
        _loading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
        _isRefreshing = false;
      });
    }
  }

  void _majControllers() {
    final plafond = _config['cash_credit_limit_fcfa'] ?? 0;
    final seuil = _config['wallet_block_threshold_fcfa'] ?? 0;
    if (!_plafondCtrl.hasFocus) _plafondCtrl.text = '$plafond';
    if (!_seuilCtrl.hasFocus) _seuilCtrl.text = '$seuil';
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor:
            erreur ? AdminStyle.danger : Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Devise _deviseDeLigne(Map<String, dynamic> d) => Devise.depuisCode(
        d['code'] as String?,
        minorUnits: (d['minor_units'] as num?)?.toInt(),
        roundingMode: d['rounding_mode'] as String?,
      );

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AdminStyle.theme(),
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
          backgroundColor: AdminStyle.bg,
          appBar: AppBar(
            title: const Text('FINANCE'),
            actions: [
              IconButton(
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Actualiser',
                onPressed: _loading ? null : () => _chargerTout(),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Devises'),
                Tab(text: 'Zones'),
                Tab(text: 'Commissions'),
                Tab(text: 'Plafond cash'),
                Tab(text: 'Grand livre'),
              ],
            ),
          ),
          body: _corps(),
        ),
      ),
    );
  }

  Widget _corps() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: _chargerTout),
        ),
      );
    }
    return TabBarView(
      children: [
        _ongletDevises(),
        _ongletZones(),
        _ongletCommissions(),
        _ongletPlafond(),
        _ongletLedger(),
      ],
    );
  }

  List<Widget> _enteteOnglet(String titre, String sousTitre) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(titre, style: AdminStyle.label(15, color: AdminStyle.ink)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            sousTitre,
            style: AdminStyle.label(11, color: AdminStyle.inkFaint, w: FontWeight.w500),
          ),
        ),
      ];

  // -- DEVISES ----------------------------------------------------------------

  Widget _ongletDevises() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        ..._enteteOnglet(
          'Devises du referentiel',
          'Unites mineures entieres (bigint serveur / int Dart). '
          'Arrondi applique UNIQUEMENT cote serveur (ROUND / FLOOR / CEIL).',
        ),
        for (final d in _devises) _carteDevise(d),
        if (_devises.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Icons.currency_exchange_rounded,
              title: 'Aucune devise',
              message:
                  'Executez le script finance/11 (devises_zones) dans Supabase.',
            ),
          ),
      ],
    );
  }

  Widget _carteDevise(Map<String, dynamic> d) {
    final devise = _deviseDeLigne(d);
    final exemple =
        Money.depuisParties(2500, devise.minorUnits == 2 ? 50 : 0, devise)
            .formatter();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminStyle.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminStyle.lineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${devise.code} - ${devise.libelle}',
                  style: AdminStyle.label(13, color: AdminStyle.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'Decimales : ${devise.minorUnits}   '
                  'Arrondi : ${d['rounding_mode'] ?? devise.arrondi.name}',
                  style: AdminStyle.label(
                    11,
                    color: AdminStyle.inkDim,
                    w: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                exemple,
                style: AdminStyle.label(13, color: AdminStyle.info),
              ),
              const SizedBox(height: 4),
              Text(
                'exemple 2 500 + ${devise.minorUnits == 2 ? '50 c' : '0'}',
                style: AdminStyle.label(
                  10,
                  color: AdminStyle.inkFaint,
                  w: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- ZONES ------------------------------------------------------------------

  Widget _ongletZones() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        ..._enteteOnglet(
          'Zones de service',
          'La devise d\'une course / prestation est dictée par la zone '
          '(pays / ville), jamais par un taux de change cote client.',
        ),
        for (final z in _zones) _carteZone(z),
        if (_zones.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Icons.public_rounded,
              title: 'Aucune zone',
              message:
                  'Executez le script finance/11 (devises_zones) dans Supabase.',
            ),
          ),
      ],
    );
  }

  Widget _carteZone(Map<String, dynamic> z) {
    final villes = (z['villes'] as List?)?.cast<Object>().toList() ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminStyle.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminStyle.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminStyle.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AdminStyle.line),
                ),
                child: Text(
                  '${z['code'] ?? '?'}',
                  style: AdminStyle.label(11, color: AdminStyle.info),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${z['pays'] ?? 'Zone'}',
                  style: AdminStyle.label(13, color: AdminStyle.ink),
                ),
              ),
              Text(
                '${z['devise_code'] ?? '?'}',
                style: AdminStyle.label(13, color: AdminStyle.warn),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            villes.isEmpty
                ? 'Aucune ville renseignee'
                : villes.map((v) => '$v').join(' - '),
            style: AdminStyle.label(
              11,
              color: AdminStyle.inkDim,
              w: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // -- COMMISSIONS ------------------------------------------------------------

  Widget _ongletCommissions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        ..._enteteOnglet(
          'Regles de commission',
          'Calcul definitif cote serveur. Pourcentage par categorie de '
          'service, avec cascade de repli (script 019).',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: _dialogCreerRegle,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nouvelle regle'),
            ),
          ),
        ),
        if (_summary.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Taux en vigueur (resume serveur)',
              style: AdminStyle.label(12, color: AdminStyle.inkDim),
            ),
          ),
          ..._cartesResume(),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Regles enregistrees (${_regles.length})',
            style: AdminStyle.label(12, color: AdminStyle.inkDim),
          ),
        ),
        for (final r in _regles) _carteRegle(r),
        if (_regles.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.rule_rounded,
              title: 'Aucune regle',
              message:
                  'Aucune regle personnalisee : le taux par defaut (15 %) '
                  's\'applique via la cascade du script 019.',
            ),
          ),
      ],
    );
  }

  List<Widget> _cartesResume() {
    final List<Widget> cartes = [];
    void ajouterListe(dynamic l) {
      if (l is List) {
        for (final e in l) {
          if (e is Map) {
            cartes.add(_carteResume(Map<String, dynamic>.from(e)));
          }
        }
      }
    }

    ajouterListe(_summary['courses']);
    ajouterListe(_summary['depannage']);
    final remorquage = _summary['remorquage'];
    if (remorquage is Map) {
      cartes.add(_carteResume(Map<String, dynamic>.from(remorquage)));
    }
    if (cartes.isEmpty) {
      cartes.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Resume indisponible : executez le script 043 dans Supabase.',
            style: AdminStyle.label(
              11,
              color: AdminStyle.warn,
              w: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return cartes;
  }

  Widget _carteResume(Map<String, dynamic> m) {
    final pct = (m['pct'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AdminStyle.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminStyle.lineSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${m['label'] ?? m['category'] ?? '?'}',
              style: AdminStyle.label(
                12,
                color: AdminStyle.ink,
                w: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Text(
            '$pct %',
            style: AdminStyle.label(13, color: AdminStyle.info),
          ),
        ],
      ),
    );
  }

  Widget _carteRegle(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final actif = (r['actif'] as bool?) ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminStyle.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: actif ? AdminStyle.line : AdminStyle.lineSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['service_category'] ?? '?'}',
                  style: AdminStyle.label(12, color: AdminStyle.ink),
                ),
              ),
              Text(
                '${(r['pct'] as num?)?.toInt() ?? 0} %',
                style: AdminStyle.label(13, color: AdminStyle.info),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Profil : ${_libelleOuTous(r['provider_kind'])}   '
            'Vehicule : ${_libelleOuTous(r['vehicle_type'])}',
            style: AdminStyle.label(
              11,
              color: AdminStyle.inkDim,
              w: FontWeight.w500,
            ),
          ),
          if ((r['note'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              r['note'] as String,
              style: AdminStyle.label(
                11,
                color: AdminStyle.inkFaint,
                w: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              StatusPill(
                label: actif ? 'ACTIVE' : 'INACTIVE',
                color: actif ? AdminStyle.live : AdminStyle.inkFaint,
                dense: true,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AdminStyle.inkDim,
                onPressed: () => _dialogModifierRegle(r),
              ),
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: AdminStyle.danger,
                onPressed: () => _supprimerRegle(id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _libelleOuTous(dynamic valeur) {
    final v = valeur as String?;
    return (v == null || v.isEmpty) ? 'tous' : v;
  }

  Future<void> _dialogCreerRegle() async {
    await _dialogRegle();
  }

  Future<void> _dialogModifierRegle(Map<String, dynamic> r) async {
    await _dialogRegle(regleExistante: r);
  }

  Future<void> _dialogRegle({Map<String, dynamic>? regleExistante}) async {
    final estCreation = regleExistante == null;
    String categorie = estCreation
        ? _categoriesCommission.first.$1
        : (regleExistante['service_category'] as String? ??
            _categoriesCommission.first.$1);
    final pctCtrl = TextEditingController(
      text: estCreation
          ? ''
          : '${(regleExistante['pct'] as num?)?.toInt() ?? 0}',
    );
    final noteCtrl =
        TextEditingController(text: estCreation ? '' : (regleExistante['note'] as String?) ?? '');
    var actif = estCreation ? true : (regleExistante['actif'] as bool?) ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            estCreation ? 'Nouvelle regle de commission' : 'Modifier la regle',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (estCreation)
                  DropdownButtonFormField<String>(
                    initialValue: categorie,
                    decoration: const InputDecoration(
                      labelText: 'Categorie de service',
                      border: OutlineInputBorder(),
                    ),
                    items: _categoriesCommission
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.$1,
                            child: Text('${c.$2} (${c.$1})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => categorie = v);
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      categorie,
                      style: AdminStyle.label(
                        12,
                        color: AdminStyle.inkDim,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Pourcentage (0 - 100)',
                  controller: pctCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 3,
                  helper: 'Ex. 15 pour une commission de 15 %',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Regle active',
                    style: AdminStyle.label(
                      12,
                      color: AdminStyle.ink,
                      letterSpacing: 0.4,
                    ),
                  ),
                  value: actif,
                  onChanged: (v) => setDialogState(() => actif = v),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  label: 'Note interne (optionnel)',
                  controller: noteCtrl,
                  maxLength: 300,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    pctCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;

    final pct = int.tryParse(pctCtrl.text.trim()) ?? -1;
    if (pct < 0 || pct > 100) {
      _message('Pourcentage invalide (0 a 100).', erreur: true);
      return;
    }
    try {
      await _service.enregistrerRegle(
        id: estCreation ? null : (regleExistante!['id'] as String),
        serviceCategory: categorie,
        pct: pct,
        actif: actif,
        providerKind: estCreation ? null : (regleExistante['provider_kind'] as String?),
        vehicleType: estCreation ? null : (regleExistante['vehicle_type'] as String?),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (!mounted) return;
      _message('Regle de commission enregistree.');
      await _chargerTout(silencieux: true);
    } catch (e) {
      _message('$e'.replaceFirst('Exception: ', ''), erreur: true);
    }
  }

  Future<void> _supprimerRegle(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette regle ?'),
        content: const Text(
          'La categorie retombera sur le taux par defaut (cascade du '
          'script 019). Cette action est definitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminStyle.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.supprimerRegle(id);
      if (!mounted) return;
      _message('Regle supprimee.');
      await _chargerTout(silencieux: true);
    } catch (e) {
      _message('$e'.replaceFirst('Exception: ', ''), erreur: true);
    }
  }

  // -- PLAFOND CASH -----------------------------------------------------------

  Widget _ongletPlafond() {
    final plafond = _config['cash_credit_limit_fcfa'] ?? 0;
    final seuil = _config['wallet_block_threshold_fcfa'] ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        ..._enteteOnglet(
          'Dette cash : plafonds globaux',
          'Ces cles app_config federent le comportement des apps sans '
          'recompiler. Un prestataire peut surcharger son propre plafond '
          '(wallets.credit_limit > 0).',
        ),
        _carteConfig(
          titre: 'Plafond global de dette cash',
          detail:
              'Au-dela de ce montant, les nouvelles commandes cash du '
              'prestataire sont bloquees (exception '
              'CASH_BLOQUE_PLAFOND_DEPASSE) tant qu\'il n\'a pas recharge '
              'son wallet par Mobile Money.',
          cle: 'cash_credit_limit_fcfa',
          valeur: plafond,
          controller: _plafondCtrl,
        ),
        const SizedBox(height: 10),
        _carteConfig(
          titre: 'Seuil de blocage du wallet',
          detail:
              'Blocage des commandes si le solde wallet passe sous -seuil '
              '(cle wallet_block_threshold_fcfa, lue par wallet_service).',
          cle: 'wallet_block_threshold_fcfa',
          valeur: seuil,
          controller: _seuilCtrl,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AdminStyle.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminStyle.lineSoft),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AdminStyle.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Priorite serveur : wallets.credit_limit > 0 ? valeur '
                  'specifique du prestataire : plafond global ci-dessus.',
                  style: AdminStyle.label(
                    11,
                    color: AdminStyle.inkDim,
                    w: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _carteConfig({
    required String titre,
    required String detail,
    required String cle,
    required int valeur,
    required TextEditingController controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminStyle.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminStyle.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titre,
                  style: AdminStyle.label(13, color: AdminStyle.ink),
                ),
              ),
              Text(
                '$valeur FCFA',
                style: AdminStyle.label(13, color: AdminStyle.warn),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: AdminStyle.label(
              11,
              color: AdminStyle.inkDim,
              w: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Nouvelle valeur (FCFA entiers)',
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 8,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 22),
                child: FilledButton(
                  onPressed: () => _enregistrerConfig(cle, controller),
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _enregistrerConfig(
    String cle,
    TextEditingController controller,
  ) async {
    final valeur = int.tryParse(controller.text.trim());
    if (valeur == null || valeur < 0) {
      _message('Entrez une valeur entiere positive.', erreur: true);
      return;
    }
    try {
      await _service.definirConfigInt(
        cle,
        valeur,
        note: 'Mise a jour via console admin finance',
      );
      if (!mounted) return;
      _message('$cle = $valeur enregistre.');
      await _chargerTout(silencieux: true);
    } catch (e) {
      _message('$e'.replaceFirst('Exception: ', ''), erreur: true);
    }
  }

  // -- GRAND LIVRE ------------------------------------------------------------

  Widget _ongletLedger() {
    final entrees = _filtreLedger == 'tous'
        ? _ledger
        : _ledger.where((e) => (e['kind'] as String?) == _filtreLedger).toList();
    return RefreshIndicator(
      onRefresh: () => _chargerTout(silencieux: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ..._enteteOnglet(
            'Grand livre append-only (litiges)',
            'Ecritures immuables des ${_ledger.length} derniers mouvements, '
            'tous prestataires. Ajuster uniquement via le bouton ci-dessous.',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _dialogAjustement,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Ajustement / remboursement'),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kindsLedger
                .map(
                  (k) => ChoiceChip(
                    label: Text(k == 'tous' ? 'Tous' : (_labelsKinds[k] ?? k)),
                    selected: _filtreLedger == k,
                    onSelected: (_) => setState(() => _filtreLedger = k),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          for (final e in entrees.take(300)) _carteLedger(e),
          if (entrees.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucune ecriture',
                message:
                    'Aucune ecriture pour ce filtre (ou executez le script '
                    'finance/12 pour la table ledger_entries).',
              ),
            ),
        ],
      ),
    );
  }

  Widget _carteLedger(Map<String, dynamic> row) {
    final l = LedgerEntry.fromMap(row);
    final provider = row['provider'];
    final nom = provider is Map && provider['business_name'] != null
        ? '${provider['business_name']}'
        : (provider is Map && provider['metier'] != null
            ? '${provider['metier']}'
            : 'Prestataire');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminStyle.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminStyle.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(l.icone, size: 20, color: AdminStyle.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${l.libelle}  -  $nom',
                  style: AdminStyle.label(
                    12,
                    color: AdminStyle.ink,
                    w: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                l.amountFormatter(),
                style: AdminStyle.label(
                  13,
                  color: l.estDebit ? AdminStyle.danger : AdminStyle.live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '#${l.id}  -  ${_date(l.createdAt)}  -  ${l.devise.code}',
            style: AdminStyle.label(
              11,
              color: AdminStyle.inkFaint,
              w: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Solde MoMo apres : ${l.soldeFormatter(l.payableAfter)}   '
            'Dette cash apres : ${l.soldeFormatter(l.debtAfter)}',
            style: AdminStyle.label(
              11,
              color: AdminStyle.inkDim,
              w: FontWeight.w500,
            ),
          ),
          if (l.referenceId != null || l.clientRequestId != null ||
              (l.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (l.referenceId != null) 'ref ${l.referenceId}',
                if (l.clientRequestId != null) 'req ${l.clientRequestId}',
                if ((l.note ?? '').isNotEmpty) l.note!,
              ].join('  -  '),
              style: AdminStyle.label(
                11,
                color: AdminStyle.inkFaint,
                w: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _dialogAjustement() async {
    Map<String, dynamic>? prestataire;
    String deviseCode = 'XOF';
    String genre = 'ajustement';
    var credit = true;
    final montantCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    List<Map<String, dynamic>> prestataires = [];

    _message('Chargement des prestataires...');
    try {
      prestataires = await _service.listerPrestataires();
    } catch (e) {
      _message('$e'.replaceFirst('Exception: ', ''), erreur: true);
      montantCtrl.dispose();
      noteCtrl.dispose();
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ajustement du grand livre'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: prestataire,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Prestataire',
                    border: OutlineInputBorder(),
                  ),
                  items: prestataires
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p['business_name'] ?? p['id']}'
                            '${p['metier'] != null ? ' (${p['metier']})' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => prestataire = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: genre,
                  decoration: const InputDecoration(
                    labelText: 'Genre d\'ecriture',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'ajustement',
                      child: Text('Ajustement'),
                    ),
                    DropdownMenuItem(
                      value: 'remboursement',
                      child: Text('Remboursement'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => genre = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: deviseCode,
                  decoration: const InputDecoration(
                    labelText: 'Devise',
                    border: OutlineInputBorder(),
                  ),
                  items: Devise.toutes
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.code,
                          child: Text('${d.code} - ${d.libelle}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => deviseCode = v);
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Montant (unites de la devise)',
                  controller: montantCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  helper:
                      'Positive : crediter la poche MoMo. L\'enregistrement '
                      'de la poche est calcule cote serveur (script 14).',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    credit ? 'Sens : credit (+)' : 'Sens : debit (-)',
                    style: AdminStyle.label(
                      12,
                      color:
                          credit ? AdminStyle.live : AdminStyle.danger,
                      letterSpacing: 0.4,
                    ),
                  ),
                  value: credit,
                  onChanged: (v) => setDialogState(() => credit = v),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  label: 'Note (litige, motif)',
                  controller: noteCtrl,
                  maxLength: 300,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: prestataire == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    montantCtrl.dispose();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;

    final montantUnites = int.tryParse(montantCtrl.text.trim()) ?? -1;
    if (montantUnites <= 0) {
      _message('Entrez un montant superieur a zero.', erreur: true);
      return;
    }
    final devise = Devise.depuisCode(deviseCode);
    Map<String, dynamic>? deviseLigne;
    for (final d in _devises) {
      if (d['code'] == deviseCode) {
        deviseLigne = d;
        break;
      }
    }
    final deviseServeur = Devise.depuisCode(
      deviseCode,
      minorUnits: (deviseLigne?['minor_units'] as num?)?.toInt(),
      roundingMode: deviseLigne?['rounding_mode'] as String?,
    );
    final minor = Money.depuisParties(montantUnites, 0, deviseServeur).minorUnits;
    final signe = credit ? 1 : -1;
    final requestId = 'admin-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await _service.ajusterLedger(
        providerId: prestataire!['id'] as String,
        deviseCode: devise.code,
        montantMinor: minor * signe,
        kind: genre,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        clientRequestId: requestId,
      );
      if (!mounted) return;
      _message('Ecriture $genre enregistree ($requestId).');
      await _chargerTout(silencieux: true);
    } catch (e) {
      _message('$e'.replaceFirst('Exception: ', ''), erreur: true);
    }
  }
}
