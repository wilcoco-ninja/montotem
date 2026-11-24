import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/admin/data/admin_notification_service.dart';
import 'package:montotem/features/admin/domain/admin_notification_model.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final AdminNotificationService _service = AdminNotificationService();

  List<AdminNotification> _items = [];
  int _nonLues = 0;
  bool _nonLuesSeulement = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final page = await _service.lister(nonLuesSeulement: _nonLuesSeulement);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _nonLues = page.nonLues;
        _isLoading = false;
      });
    } on AdminNotificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _toutMarquerLu() async {
    try {
      await _service.toutMarquerLu();
      if (!mounted) return;
      await _charger();
    } on AdminNotificationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _ouvrir(AdminNotification n) async {
    if (!n.lue) {
      // Mise à jour optimiste : l'UI réagit sans attendre le réseau.
      setState(() {
        _items = _items
            .map((e) => e.id == n.id ? e.copyWith(readAt: DateTime.now()) : e)
            .toList();
        _nonLues = _nonLues > 0 ? _nonLues - 1 : 0;
      });
      try {
        await _service.marquerLues([n.id]);
      } on AdminNotificationException {
        if (mounted) await _charger();
      }
    }
    if (!mounted) return;
    if (n.type == AdminNotificationType.providerRegistration) {
      await context.push('/admin/providers');
    }
  }

  String _formaterDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  ({IconData icon, Color color}) _style(
    ColorScheme scheme,
    AdminNotificationType type,
  ) => switch (type) {
    AdminNotificationType.providerRegistration => (
      icon: Icons.person_add_alt_1_outlined,
      color: scheme.primary,
    ),
    AdminNotificationType.paymentSucceeded => (
      icon: Icons.payments_outlined,
      color: scheme.secondary,
    ),
    AdminNotificationType.paymentAnomaly => (
      icon: Icons.warning_amber_rounded,
      color: scheme.error,
    ),
    AdminNotificationType.other => (
      icon: Icons.notifications_outlined,
      color: scheme.outline,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Tout marquer comme lu',
            onPressed: _isLoading || _nonLues == 0 ? null : _toutMarquerLu,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : _charger,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ContentWidth(
        maxWidth: 800,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(value: false, label: Text('Toutes')),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      _nonLues > 0 ? 'Non lues ($_nonLues)' : 'Non lues',
                    ),
                  ),
                ],
                selected: {_nonLuesSeulement},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _nonLuesSeulement = s.first);
                  _charger();
                },
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: _charger),
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            EmptyState(
              icon: Icons.notifications_none_rounded,
              title: _nonLuesSeulement
                  ? 'Aucune notification non lue'
                  : 'Aucune notification',
              message: 'Les nouveaux dossiers prestataires et les paiements apparaîtront ici.',
            ),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final n = _items[index];
          final style = _style(scheme, n.type);
          return SoftCard(
            onTap: () => _ouvrir(n),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(style.icon, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: n.lue ? FontWeight.w600 : FontWeight.w800,
                        ),
                      ),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          n.body,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _formaterDate(n.createdAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!n.lue)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 6, left: 8),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
