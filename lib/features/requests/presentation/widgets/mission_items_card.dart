
import 'package:flutter/material.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/mission_item_model.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';

/// DÃƒÂ©tail de la commande, identique pour le client et le prestataire :
/// chaque prestation avec son prix fixe, le dÃƒÂ©placement, puis le total.
class MissionItemsCard extends StatefulWidget {
  const MissionItemsCard({super.key, required this.mission});
  final Mission mission;

  @override
  State<MissionItemsCard> createState() => _MissionItemsCardState();
}

class _MissionItemsCardState extends State<MissionItemsCard> {
  final MissionService _service = MissionService();
  List<MissionItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final data = await _service.prestations(widget.mission.id);
      if (mounted) setState(() => _items = data);
    } on MissionException {
      // Le rÃƒÂ©capitulatif reste affichÃƒÂ© sans le dÃƒÂ©tail.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final scheme = Theme.of(context).colorScheme;

    Widget ligne(String l, int v, {bool fort = false, IconData? icone}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              if (icone != null) ...[
                Icon(icone, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontSize: fort ? 17 : 15.5,
                        fontWeight: fort ? FontWeight.w800 : FontWeight.w500)),
              ),
              Text(TravelFee.fcfa(v),
                  style: TextStyle(
                      fontSize: fort ? 18 : 15.5,
                      fontWeight: FontWeight.w800,
                      color: fort ? AppTheme.primaryColor : null)),
            ],
          ),
        );

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_items.isEmpty)
            ligne(m.problem, m.repairFeeFcfa, icone: Icons.build_outlined)
          else
            for (final i in _items)
              ligne(i.nom, i.prixFcfa, icone: Icons.build_outlined),
          Divider(height: 18, color: scheme.onSurface.withValues(alpha: 0.12)),
          ligne('DÃƒÂ©placement', m.travelFeeFcfa,
              icone: Icons.local_shipping_outlined),
          ligne('Total (prix fixes)', m.totalFcfa, fort: true),
        ],
      ),
    );
  }
}
