import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/domain/report_motifs.dart';
import 'package:montotem/features/admin/data/admin_control_service.dart';

/// Module d'arbitrage et de traitement des signalements pour MonTotem.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with AutomaticKeepAliveClientMixin {
  final AdminControlService _service = AdminControlService();
  RealtimeChannel? _canal;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;
  String? _busyId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
    _canal = _service.ecouter('provider_reports', () {
      if (mounted) _chargerDonnees(silencieux: true);
    });
  }

  @override
  void dispose() {
    if (_canal != null) _service.arreter(_canal!);
    super.dispose();
  }

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _items.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final data = await _service.signalements();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
        _isRefreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _loading = false;
        });
      } else {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _afficherMessage(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: erreur
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _traiterSignalement(
    Map<String, dynamic> r,
    String statut, {
    bool suspendre = false,
  }) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          suspendre
              ? 'Suspendre le prestataire ?'
              : 'Ajouter une note administrative',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            labelText: 'Note d’instruction interne (optionnel)',
            hintText: 'Ex. : Échange téléphonique effectué, avertissement émis',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: suspendre
                  ? Theme.of(ctx).colorScheme.error
                  : Theme.of(ctx).colorScheme.primary,
            ),
            child: Text(
              suspendre ? 'Confirmer la suspension' : 'Valider l’arbitrage',
            ),
          ),
        ],
      ),
    );

    controller.dispose();
    if (note == null || !mounted) return;

    final id = '${r['id']}';
    setState(() => _busyId = id);
    try {
      await _service.traiterSignalement(
        id,
        statut,
        note: note,
        suspendre: suspendre,
      );
      _afficherMessage(
        suspendre
            ? 'Prestataire suspendu et dossier clôturé.'
            : 'Statut du signalement mis à jour.',
      );
      await _chargerDonnees(silencieux: true);
    } catch (e) {
      _afficherMessage('$e'.replaceFirst('Exception: ', ''), erreur: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _nomClient(dynamic profil) {
    final p = profil is Map ? profil : const {};
    final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
    return n.isEmpty ? '${p['phone'] ?? 'Client'}' : n;
  }

  String _nomGarage(dynamic prov) =>
      prov is Map ? '${prov['business_name'] ?? 'Prestataire'}' : 'Prestataire';

  String _dateFormatee(dynamic iso) {
    final d = DateTime.tryParse('$iso')?.toLocal();
    if (d == null) return '';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} à ${pad(d.hour)}:${pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbitrage & Signalements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _loading ? null : () => _chargerDonnees(),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 900,
        child: Column(
          children: [
            if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildCorps()),
          ],
        ),
      ),
    );
  }

  Widget _buildCorps() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: () => _chargerDonnees()),
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _chargerDonnees(silencieux: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            const EmptyState(
              icon: Icons.flag_outlined,
              title: 'Aucun signalement en cours',
              message: 'Les litiges ou plaintes signalés par les clients apparaîtront ici.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _chargerDonnees(silencieux: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _carteSignalement(_items[i]),
      ),
    );
  }

  Widget _carteSignalement(Map<String, dynamic> r) {
    final scheme = Theme.of(context).colorScheme;
    final statut = '${r['status']}';
    final ouvert = statut == 'open' || statut == 'reviewing';
    final (couleur, libelle) = switch (statut) {
      'resolved' => (scheme.secondary, 'Résolu / Traité'),
      'dismissed' => (Colors.grey, 'Classé sans suite'),
      'reviewing' => (scheme.tertiary, 'En examen'),
      _ => (scheme.error, 'Nouveau signalement'),
    };
    final busy = _busyId == '${r['id']}';

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  libelleMotif('${r['motif']}'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: libelle, color: couleur),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Prestataire mis en cause : ${_nomGarage(r['provider'])}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Signalé par : ${_nomClient(r['reporter'])} • ${_dateFormatee(r['created_at'])}',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
          if ('${r['details'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${r['details']}',
                style: const TextStyle(fontSize: 14.5, height: 1.4),
              ),
            ),
          ],
          if ('${r['admin_note'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note interne d’instruction : ${r['admin_note']}',
              style: const TextStyle(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                color: Colors.blueGrey,
              ),
            ),
          ],
          if (ouvert) ...[
            const SizedBox(height: 16),
            if (busy)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _traiterSignalement(r, 'reviewing'),
                    child: const Text('Passer en examen'),
                  ),
                  OutlinedButton(
                    onPressed: () => _traiterSignalement(r, 'dismissed'),
                    child: const Text('Sans suite'),
                  ),
                  FilledButton(
                    onPressed: () => _traiterSignalement(r, 'resolved'),
                    child: const Text('Marquer résolu'),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.block_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                    ),
                    onPressed: () =>
                        _traiterSignalement(r, 'resolved', suspendre: true),
                    label: const Text('Suspendre le prestataire'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
