import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/wallet/data/ledger_service.dart';

/// Filtres de l'historique du grand livre.
enum _Filtre {
  tout('Tout'),
  commissions('Commissions'),
  credits('Recharges & encaissements');

  const _Filtre(this.libelle);
  final String libelle;

  bool accepte(LedgerEntry e) {
    switch (this) {
      case _Filtre.tout:
        return true;
      case _Filtre.commissions:
        return e.kind == 'commission_cash' ||
            e.kind == 'commission_momo' ||
            e.kind == 'commission_travel' ||
            e.kind == 'debit_commission';
      case _Filtre.credits:
        return e.kind == 'topup' ||
            e.kind == 'cash_encaisse' ||
            e.kind == 'momo_paiement' ||
            e.kind == 'remboursement' ||
            e.kind == 'ajustement';
    }
  }
}

/// Grand livre personnel du prestataire (pilier 3, audit anti-fraude) :
/// chaque écriture append-only avec le solde des deux poches après
/// opération, en unités mineures de la devise de l'écriture.
class LedgerHistoryScreen extends StatefulWidget {
  const LedgerHistoryScreen({super.key});

  @override
  State<LedgerHistoryScreen> createState() => _LedgerHistoryScreenState();
}

class _LedgerHistoryScreenState extends State<LedgerHistoryScreen> {
  final LedgerService _service = const LedgerService();
  final DateFormat _formatJour = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
  final DateFormat _formatHeure = DateFormat('HH:mm');

  List<LedgerEntry> _entries = const [];
  _Filtre _filtre = _Filtre.tout;
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
      final list = await _service.charger();
      if (!mounted) return;
      setState(() => _entries = list);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = _messagePostgres(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Grand livre indisponible. Vérifiez votre '
          'connexion puis réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messagePostgres(String message) {
    if (message.contains('JWT') || message.contains('401')) {
      return 'Session expirée. Reconnectez-vous.';
    }
    if (message.contains('permission')) {
      return 'Accès refusé au grand livre.';
    }
    return 'Lecture impossible pour le moment. Réessayez.';
  }

  List<LedgerEntry> get _filtrees =>
      [for (final e in _entries) if (_filtre.accepte(e)) e];

  /// Écritures groupées par jour (du jour le plus récent au plus ancien).
  Map<DateTime, List<LedgerEntry>> get _groupes {
    final map = <DateTime, List<LedgerEntry>>{};
    for (final e in _filtrees) {
      final jour =
          DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      map.putIfAbsent(jour, () => []).add(e);
    }
    final cles = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in cles) k: map[k]!};
  }

  String _jour(DateTime d) {
    final aujourdhui = DateTime.now();
    final hier = aujourdhui.subtract(const Duration(days: 1));
    if (d.year == aujourdhui.year &&
        d.month == aujourdhui.month &&
        d.day == aujourdhui.day) {
      return 'Aujourd\'hui';
    }
    if (d.year == hier.year && d.month == hier.month && d.day == hier.day) {
      return 'Hier';
    }
    return _formatJour.format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grand livre')),
      body: _corps(),
    );
  }

  Widget _corps() {
    final gutter = context.gutter;
    return RefreshIndicator(
      onRefresh: _charger,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
        child: ContentWidth(
          maxWidth: 720,
          child: _contenu(),
        ),
      ),
    );
  }

  Widget _contenu() {
    if (_loading && _entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _entries.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: _charger),
        ),
      );
    }

    final colonne = <Widget>[
      SectionTitle(
          'Chaque écriture, en détail · ${_entries.length} mouvements'),
      _filtres(),
      const SizedBox(height: 8),
    ];

    final groupes = _groupes;
    if (groupes.isEmpty) {
      colonne.add(
        const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Aucune écriture',
          message:
              'Les courses cash, commissions et recharges apparaîtront ici, '
              'lignes immuables vérifiables.',
        ),
      );
    } else {
      for (final entree in groupes.entries) {
        colonne.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              _jour(entree.key),
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: context.textSecondary),
            ),
          ),
        );
        for (final e in entree.value) {
          colonne.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ligne(e),
            ),
          );
        }
      }
      colonne.add(
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Grand livre append-only : aucune ligne ne peut être modifiée '
            'ou supprimée. Chaque paiement client porte un identifiant '
            'idempotent (anti double-débit).',
            style: TextStyle(
                fontSize: 13, height: 1.4, color: context.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: colonne,
    );
  }

  Widget _filtres() {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _Filtre.values)
          ChoiceChip(
            label: Text(f.libelle),
            selected: _filtre == f,
            onSelected: (sel) {
              if (sel) setState(() => _filtre = f);
            },
            selectedColor: scheme.secondary.withValues(alpha: 0.25),
          ),
      ],
    );
  }

  Widget _ligne(LedgerEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = e.estDebit ? scheme.error : scheme.secondary;
    final fg = context.readable(couleur);
    final complement = [
      if ((e.note ?? '').isNotEmpty) e.note!,
      if ((e.referenceId ?? '').isNotEmpty) 'source : ${e.referenceId}',
    ].join(' · ');

    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(e.icone, color: couleur, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.libelle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(
                  '${_formatHeure.format(e.createdAt)}'
                  '${complement.isNotEmpty ? ' · $complement' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: context.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Après : MoMo ${e.devise.soldeFormatter(e.payableAfter)} · '
                  'dette ${e.devise.soldeFormatter(e.debtAfter)}',
                  style:
                      TextStyle(fontSize: 12.5, color: context.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            e.amountFormatter(),
            style: TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w800, color: fg),
          ),
        ],
      ),
    );
  }
}
