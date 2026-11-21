
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/admin/data/admin_topup_service.dart';

/// Recharges de wallet dÃƒÂ©clarÃƒÂ©es par les prestataires (Mobile Money).
/// L'admin vÃƒÂ©rifie dans son application MoMo que l'argent est reÃƒÂ§u, puis
/// valide : le wallet est crÃƒÂ©ditÃƒÂ© immÃƒÂ©diatement (et dÃƒÂ©bloquÃƒÂ© si besoin).
class AdminTopupsScreen extends StatefulWidget {
  const AdminTopupsScreen({super.key});

  @override
  State<AdminTopupsScreen> createState() => _AdminTopupsScreenState();
}

class _AdminTopupsScreenState extends State<AdminTopupsScreen> {
  static const _filtres = <String, String>{
    'awaiting_validation': 'Ãƒâ‚¬ vÃƒÂ©rifier',
    'approved': 'ValidÃƒÂ©es',
    'rejected': 'RefusÃƒÂ©es',
  };

  final AdminTopupService _service = AdminTopupService();
  RealtimeChannel? _canal;

  List<Map<String, dynamic>> _demandes = [];
  String _filtre = 'awaiting_validation';
  bool _isLoading = true;
  String? _errorMessage;
  String? _actionEnCoursId;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouter(() {
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
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final data = await _service.lister(statut: _filtre);
      if (!mounted) return;
      setState(() {
        _demandes = data;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de charger les recharges.';
        _isLoading = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.secondary,
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Actions Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _valider(Map<String, dynamic> d) async {
    final id = '${d['id']}';
    final montant = TravelFee.fcfa(_int(d['amount_fcfa']));
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Argent bien reÃƒÂ§u ?'),
        content: Text(
          'Avant de valider, vÃƒÂ©rifiez dans votre application '
          '${_operateur(d['operateur'])} que la transaction ${d['transaction_ref']} '
          'de $montant est bien arrivÃƒÂ©e.\n\n'
          'Valider crÃƒÂ©ditera immÃƒÂ©diatement le wallet du prestataire.',
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Pas encore'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check),
            label: const Text('Oui, crÃƒÂ©diter'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() => _actionEnCoursId = id);
    try {
      await _service.valider(id);
      if (!mounted) return;
      _message('Wallet crÃƒÂ©ditÃƒÂ©, le prestataire est notifiÃƒÂ©.');
      await _charger(silencieux: true);
    } catch (e) {
      if (!mounted) return;
      _message(_nettoyer(e), erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCoursId = null);
    }
  }

  Future<void> _refuser(Map<String, dynamic> d) async {
    final id = '${d['id']}';
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser cette recharge'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'Motif (envoyÃƒÂ© au prestataire)',
            hintText: 'Ex. : montant non reÃƒÂ§u, rÃƒÂ©fÃƒÂ©rence introuvable',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (motif == null || !mounted) return;
    if (motif.isEmpty) {
      _message('Indiquez un motif pour refuser.', erreur: true);
      return;
    }

    setState(() => _actionEnCoursId = id);
    try {
      await _service.refuser(id, motif);
      if (!mounted) return;
      _message('Recharge refusÃƒÂ©e, le prestataire est notifiÃƒÂ©.');
      await _charger(silencieux: true);
    } catch (e) {
      if (!mounted) return;
      _message(_nettoyer(e), erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCoursId = null);
    }
  }

  Future<void> _appeler(String? tel) async {
    if (tel == null || tel.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: tel.replaceAll(RegExp(r'\s+'), ''));
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> _copier(String texte) async {
    await Clipboard.setData(ClipboardData(text: texte));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CopiÃƒÂ©'), duration: Duration(seconds: 1)),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Aides d'affichage Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  String _nettoyer(Object e) => e.toString().replaceFirst('Exception: ', '');

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  String _operateur(dynamic code) => switch ('$code') {
        'mtn' => 'MTN MoMo',
        'moov' => 'Moov Money',
        'celtiis' => 'Celtiis Cash',
        _ => '$code',
      };

  String _date(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // Ã¢â€â‚¬Ã¢â€â‚¬ Interface Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recharges de wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _charger,
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 800,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Wrap(
                spacing: 8,
                children: _filtres.entries
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _filtre == e.key,
                        onSelected: (_) {
                          if (_filtre == e.key) return;
                          setState(() => _filtre = e.key);
                          _charger();
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(child: _corps()),
          ],
        ),
      ),
    );
  }

  Widget _corps() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: _charger),
        ),
      );
    }
    if (_demandes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: _filtre == 'awaiting_validation'
                  ? 'Aucune recharge ÃƒÂ  vÃƒÂ©rifier'
                  : 'Aucun ÃƒÂ©lÃƒÂ©ment',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _demandes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _carte(_demandes[i]),
      ),
    );
  }

  Widget _carte(Map<String, dynamic> d) {
    final scheme = Theme.of(context).colorScheme;
    final id = '${d['id']}';
    final prov = _map(d['providers']);
    final profil = _map(prov['profiles']);
    final nom = ('${prov['business_name'] ?? ''}').trim().isNotEmpty
        ? '${prov['business_name']}'
        : '${profil['first_name'] ?? ''} ${profil['last_name'] ?? ''}'.trim();
    final tel = profil['phone'] as String?;
    final statut = '${d['statut']}';
    final enAttente = statut == 'awaiting_validation';
    final enCours = _actionEnCoursId == id;

    final (couleur, libelle) = switch (statut) {
      'approved' => (scheme.secondary, 'ValidÃƒÂ©e'),
      'rejected' => (scheme.error, 'RefusÃƒÂ©e'),
      _ => (scheme.tertiary, 'Ãƒâ‚¬ vÃƒÂ©rifier'),
    };

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nom.isEmpty ? 'Prestataire' : nom,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: libelle, color: couleur),
            ],
          ),
          if (('${prov['metier'] ?? ''}').isNotEmpty)
            Text(
              '${prov['metier']}'
              '${('${prov['ville'] ?? ''}').isNotEmpty ? ' Ã¢â‚¬Â¢ ${prov['ville']}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: context.textSecondary),
            ),
          const Divider(height: 20),
          _ligne('Montant', TravelFee.fcfa(_int(d['amount_fcfa'])), fort: true),
          _ligne('OpÃƒÂ©rateur', _operateur(d['operateur'])),
          _ligne('PayÃƒÂ© depuis', '${d['payer_phone']}',
              copie: '${d['payer_phone']}'),
          _ligne('RÃƒÂ©fÃƒÂ©rence', '${d['transaction_ref']}',
              copie: '${d['transaction_ref']}'),
          _ligne('DÃƒÂ©clarÃƒÂ©e le', _date(d['created_at'])),
          if (statut != 'awaiting_validation' && d['reviewed_at'] != null)
            _ligne('TraitÃƒÂ©e le', _date(d['reviewed_at'])),
          if (statut == 'rejected' &&
              ('${d['rejection_reason'] ?? ''}').isNotEmpty)
            _ligne('Motif du refus', '${d['rejection_reason']}'),
          if (tel != null && tel.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _appeler(tel),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text('Appeler $tel'),
              ),
            ),
          if (enAttente) ...[
            const SizedBox(height: 8),
            if (enCours)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _refuser(d),
                      icon: Icon(Icons.close_rounded, color: scheme.error),
                      label: Text('Refuser',
                          style: TextStyle(color: scheme.error)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: scheme.error),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _valider(d),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('CrÃƒÂ©diter'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.successText,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _ligne(
    String label,
    String valeur, {
    bool fort = false,
    String? copie,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: TextStyle(fontSize: 14, color: context.textSecondary)),
          ),
          Expanded(
            child: Text(
              valeur,
              style: TextStyle(
                fontSize: fort ? 17 : 15,
                fontWeight: fort ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (copie != null)
            InkWell(
              onTap: () => _copier(copie),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded,
                    size: 18, color: context.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
