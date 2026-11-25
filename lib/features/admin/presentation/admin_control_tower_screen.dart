import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/requests/domain/report_motifs.dart';
import 'package:montotem/features/admin/data/admin_control_service.dart';
import 'package:montotem/features/admin/presentation/widgets/admin_style.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PALETTE locale (raccourcis vers AdminStyle pour les 700+ références)
// ═══════════════════════════════════════════════════════════════════════════
class _MC {
  _MC._();
  static const bg = AdminStyle.bg;
  static const surface = AdminStyle.surface;
  static const panel = AdminStyle.panel;
  static const line = AdminStyle.line;
  static const lineSoft = AdminStyle.lineSoft;
  static const ink = AdminStyle.ink;
  static const inkDim = AdminStyle.inkDim;
  static const inkFaint = AdminStyle.inkFaint;
  static const live = AdminStyle.live;
  static const warn = AdminStyle.warn;
  static const danger = AdminStyle.danger;
  static const info = AdminStyle.info;
  static const accent = AdminStyle.accent;
  static const purple = AdminStyle.purple;

  static const mono = AdminStyle.mono;
}

// ═══════════════════════════════════════════════════════════════════════════
// ÉCRAN PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════
class AdminControlTowerScreen extends StatefulWidget {
  const AdminControlTowerScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<AdminControlTowerScreen> createState() =>
      _AdminControlTowerScreenState();
}

class _AdminControlTowerScreenState extends State<AdminControlTowerScreen> {
  final AdminControlService _service = AdminControlService();
  RealtimeChannel? _canal;

  List<Map<String, dynamic>> _missions = [];
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
    try {
      _canal = _service.ecouter('missions', () {
        if (mounted) _chargerDonnees(silencieux: true);
      }, nom: 'mc-tower-missions');
    } catch (e) {
      debugPrint('Realtime Tour de contrôle : $e');
    }
  }

  @override
  void dispose() {
    if (_canal != null) _service.arreter(_canal!);
    super.dispose();
  }

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _missions.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }
    try {
      final data = await _service.missions();
      if (!mounted) return;
      setState(() {
        _missions = data;
        _loading = false;
        _isRefreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_missions.isEmpty) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _loading = false;
          _isRefreshing = false;
        });
      } else {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _ouvrirDetailMission(Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _MC.bg,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => _MissionDetailSheet(mission: m, service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AdminStyle.theme(),
      child: DefaultTabController(
        length: 4,
        initialIndex: widget.initialTab.clamp(0, 3),
        child: Scaffold(
          backgroundColor: _MC.bg,
          appBar: _McAppBar(
            isRefreshing: _isRefreshing,
            onRefresh: _loading ? null : () => _chargerDonnees(),
            missionCount: _missions.length,
            activeCount: _missions
                .where(
                  (m) =>
                      _statutMission(m).actif ||
                      _statutMission(m) == MissionStatus.pending,
                )
                .length,
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const McLoader();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: McErrorPanel(
            title: 'LINK LOST',
            message: _error!,
            onRetry: () => _chargerDonnees(),
          ),
        ),
      );
    }
    return TabBarView(
      children: [
        _LiveTab(
          missions: _missions,
          onTap: _ouvrirDetailMission,
          onRefresh: () => _chargerDonnees(silencieux: true),
        ),
        _MapTab(missions: _missions, onTap: _ouvrirDetailMission),
        _FinanceTab(service: _service),
        _ReportsTab(service: _service),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APP BAR
// ═══════════════════════════════════════════════════════════════════════════
class _McAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _McAppBar({
    required this.isRefreshing,
    required this.onRefresh,
    required this.missionCount,
    required this.activeCount,
  });

  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final int missionCount;
  final int activeCount;

  @override
  Size get preferredSize => const Size.fromHeight(118);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: _MC.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 62,
      automaticallyImplyLeading: true,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: _MC.ink,
        ),
        onPressed: () => context.pop(),
      ),
      titleSpacing: 4,
      title: Row(
        children: [
          const McPulseDot(color: _MC.live, size: 9),
          const SizedBox(width: 10),
          Text(
            'MISSION CONTROL',
            style: _MC.mono.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _MC.ink,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(width: 14),
          _McStat(label: 'TOTAL', value: '$missionCount'),
          const SizedBox(width: 10),
          _McStat(label: 'LIVE', value: '$activeCount', color: _MC.live),
        ],
      ),
      actions: [
        if (isRefreshing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _MC.info),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: _MC.inkDim),
          tooltip: 'Resync',
          onPressed: onRefresh,
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: _McTabBar(),
      ),
    );
  }
}

class _McTabBar extends StatelessWidget {
  const _McTabBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _MC.line, width: 1)),
      ),
      child: const TabBar(
        isScrollable: true,
        indicatorColor: _MC.info,
        indicatorWeight: 2,
        labelColor: _MC.ink,
        unselectedLabelColor: _MC.inkFaint,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
        tabs: [
          Tab(text: 'LIVE OPS'),
          Tab(text: 'GEO MAP'),
          Tab(text: 'FINANCE'),
          Tab(text: 'INCIDENTS'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Utilitaires
// ═══════════════════════════════════════════════════════════════════════════
String _nomClient(dynamic profil) {
  final p = profil is Map ? profil : const {};
  final n = '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();
  return n.isEmpty ? '${p['phone'] ?? 'CLIENT'}' : n;
}

String _nomGarage(dynamic prov) =>
    prov is Map ? '${prov['business_name'] ?? 'PRESTATAIRE'}' : 'PRESTATAIRE';

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

String _heureFormat(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '--:--';
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)} ${t(d.hour)}:${t(d.minute)}:${t(d.second)}';
}

String _elapsed(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '—';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return '${diff.inSeconds}s';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) {
    final h = diff.inHours;
    final m = diff.inMinutes - h * 60;
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
  return '${diff.inDays}d';
}

MissionStatus _statutMission(Map<String, dynamic> m) =>
    MissionStatus.fromValue(m['status'] as String?);

Color _mcStatusColor(MissionStatus s) {
  if (s.actif) {
    return switch (s) {
      MissionStatus.accepted => _MC.info,
      MissionStatus.arrived => _MC.warn,
      MissionStatus.working => _MC.accent,
      _ => _MC.live,
    };
  }
  return s == MissionStatus.pending ? _MC.warn : _MC.inkFaint;
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 1 : LIVE OPS
// ═══════════════════════════════════════════════════════════════════════════
class _LiveTab extends StatefulWidget {
  const _LiveTab({
    required this.missions,
    required this.onTap,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> missions;
  final void Function(Map<String, dynamic>) onTap;
  final Future<void> Function() onRefresh;

  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  bool _seulementActives = true;

  @override
  Widget build(BuildContext context) {
    final liste = widget.missions.where((m) {
      final s = _statutMission(m);
      return !_seulementActives || s.actif || s == MissionStatus.pending;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              _McSegmented(
                selected: _seulementActives,
                onChange: (v) => setState(() => _seulementActives = v),
              ),
              const Spacer(),
              Text(
                '${liste.length} UNIT${liste.length > 1 ? 'S' : ''}',
                style: AdminStyle.label(
                  12,
                  color: _MC.inkDim,
                  letterSpacing: 1.8,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: liste.isEmpty
              ? const McEmpty(
                  title: 'NO ACTIVE UNITS',
                  message: 'Aucune mission en cours',
                )
              : RefreshIndicator(
                  color: _MC.info,
                  backgroundColor: _MC.surface,
                  onRefresh: widget.onRefresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: liste.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final m = liste[i];
                      return _MissionTile(
                        mission: m,
                        onTap: () => widget.onTap(m),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission, required this.onTap});
  final Map<String, dynamic> mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = _statutMission(mission);
    final couleur = _mcStatusColor(s);
    final total =
        _int(mission['travel_fee_fcfa']) + _int(mission['repair_fee_fcfa']);
    final paid = _int(mission['paid_fcfa']);
    final ratio = total == 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: _MC.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _MC.line, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: couleur,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: couleur.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (s.actif)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: McPulseDot(color: couleur, size: 7),
                            ),
                          Expanded(
                            child: Text(
                              '${mission['problem'] ?? 'MISSION'}'
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _MC.mono.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: _MC.ink,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          McBadge(label: s.libelle, color: couleur),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: _MC.inkFaint,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _nomClient(mission['client']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _MC.inkDim,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 12,
                              color: _MC.inkFaint,
                            ),
                          ),
                          const Icon(
                            Icons.build_outlined,
                            size: 13,
                            color: _MC.inkFaint,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _nomGarage(mission['provider']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _MC.inkDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _McTelemetry(
                            label: 'T+',
                            value: _elapsed(mission['created_at']),
                          ),
                          const SizedBox(width: 16),
                          _McTelemetry(
                            label: 'FEE',
                            value: TravelFee.fcfa(total),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _McProgress(
                              ratio: ratio.toDouble(),
                              label: 'PAID',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: _MC.inkFaint,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 2 : GEO MAP
// ═══════════════════════════════════════════════════════════════════════════
class _MapTab extends StatelessWidget {
  const _MapTab({required this.missions, required this.onTap});
  final List<Map<String, dynamic>> missions;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    final actives = missions
        .where(
          (m) =>
              _statutMission(m).actif ||
              _statutMission(m) == MissionStatus.pending,
        )
        .toList();
    final markers = <Marker>[];
    final lines = <Polyline>[];

    for (final m in actives) {
      final s = _statutMission(m);
      final couleur = _mcStatusColor(s);
      final lat = (m['client_lat'] as num?)?.toDouble();
      final lng = (m['client_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final client = LatLng(lat, lng);

      markers.add(
        Marker(
          point: client,
          width: 32,
          height: 32,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => onTap(m),
            child: Container(
              decoration: BoxDecoration(
                color: _MC.danger,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _MC.danger.withValues(alpha: 0.6),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );

      final plat = (m['provider_lat'] as num?)?.toDouble();
      final plng = (m['provider_lng'] as num?)?.toDouble();
      if (plat != null && plng != null) {
        final p = LatLng(plat, plng);
        lines.add(
          Polyline(
            points: [p, client],
            color: couleur.withValues(alpha: 0.8),
            strokeWidth: 2,
          ),
        );
        markers.add(
          Marker(
            point: p,
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () => onTap(m),
              child: Container(
                decoration: BoxDecoration(
                  color: couleur,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: couleur.withValues(alpha: 0.65),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.build_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(
              AppConstants.initialLatitude,
              AppConstants.initialLongitude,
            ),
            initialZoom: 12,
            backgroundColor: _MC.bg,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'bj.totem.app',
            ),
            PolylineLayer(polylines: lines),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap · CartoDB'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 14,
          left: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _MC.surface.withValues(alpha: 0.95),
              border: Border.all(color: _MC.line),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const McPulseDot(color: _MC.live, size: 7),
                const SizedBox(width: 8),
                Text(
                  '${actives.length} TRACKED',
                  style: AdminStyle.label(
                    12,
                    color: _MC.ink,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 3 : FINANCE
// ═══════════════════════════════════════════════════════════════════════════
class _FinanceTab extends StatefulWidget {
  const _FinanceTab({required this.service});
  final AdminControlService service;
  @override
  State<_FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<_FinanceTab>
    with AutomaticKeepAliveClientMixin {
  int _jours = 30;
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
      final d = await widget.service.finances(_jours);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [7, 30, 90]
                .map(
                  (j) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _McChoiceChip(
                      label: '${j}D',
                      selected: _jours == j,
                      onTap: () {
                        setState(() => _jours = j);
                        _charger();
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const McLoader()
              : _error != null || _d == null
              ? Center(
                  child: McErrorPanel(
                    title: 'FINANCE OFFLINE',
                    message: _error ?? 'Données indisponibles',
                    onRetry: _charger,
                  ),
                )
              : _contenu(_d!),
        ),
      ],
    );
  }

  Widget _contenu(Map<String, dynamic> d) {
    final series = ((d['series'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final incomes = series.map((e) => _int(e['income'])).toList();
    final maxInc = incomes.fold<int>(1, (a, b) => b > a ? b : a);

    final revenus =
        _int(d['subscriptions_fcfa']) + _int(d['missions_paid_fcfa']);
    final billed = _int(d['missions_billed_fcfa']);
    final paidOnCompleted = _int(d['missions_paid_on_completed_fcfa']);
    final reste = (billed - paidOnCompleted).clamp(0, 1 << 40).toInt();

    final kpis = <_KpiData>[
      _KpiData(
        'REVENUE',
        TravelFee.fcfa(revenus),
        _MC.live,
        Icons.trending_up_rounded,
      ),
      _KpiData(
        'SUBS',
        TravelFee.fcfa(_int(d['subscriptions_fcfa'])),
        _MC.accent,
        Icons.workspace_premium_outlined,
      ),
      _KpiData(
        'BILLED',
        TravelFee.fcfa(billed),
        _MC.info,
        Icons.receipt_long_outlined,
      ),
      _KpiData(
        'PENDING',
        TravelFee.fcfa(reste),
        _MC.warn,
        Icons.hourglass_top_rounded,
      ),
      _KpiData(
        'LOST',
        TravelFee.fcfa(_int(d['lost_fcfa'])),
        _MC.danger,
        Icons.trending_down_rounded,
      ),
      _KpiData(
        'COMPLETED',
        '${_int(d['missions_completed'])}/${_int(d['missions_total'])}',
        _MC.live,
        Icons.task_alt_rounded,
      ),
      _KpiData(
        'AVG TIME',
        '${_int(d['avg_work_minutes'])}min',
        _MC.purple,
        Icons.timer_outlined,
      ),
      _KpiData('RATING', '${d['avg_rating']}/5', _MC.warn, Icons.star_rounded),
      _KpiData(
        'INCIDENTS',
        '${_int(d['open_reports'])}',
        _MC.danger,
        Icons.flag_rounded,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        McPanel(
          title: 'REVENUE · DAILY PULSE',
          child: SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in series)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${e['day']} · ${TravelFee.fcfa(_int(e['income']))}',
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        height: (_int(e['income']) / maxInc * 110)
                            .clamp(3.0, 110.0)
                            .toDouble(),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [_MC.info, _MC.accent],
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.6,
          ),
          itemCount: kpis.length,
          itemBuilder: (_, i) => _KpiCard(data: kpis[i]),
        ),
      ],
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.value, this.color, this.icon);
  final String label;
  final String value;
  final Color color;
  final IconData icon;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _MC.panel,
        border: Border.all(color: _MC.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(data.icon, size: 12, color: data.color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminStyle.label(
                    9.5,
                    color: _MC.inkDim,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _MC.mono.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: data.color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ONGLET 4 : INCIDENTS
// ═══════════════════════════════════════════════════════════════════════════
class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.service});
  final AdminControlService service;
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab>
    with AutomaticKeepAliveClientMixin {
  RealtimeChannel? _canal;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _charger();
    try {
      _canal = widget.service.ecouter('provider_reports', () {
        if (mounted) _charger(silencieux: true);
      }, nom: 'mc-tower-reports');
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_canal != null) widget.service.arreter(_canal!);
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _loading = true);
    try {
      final data = await widget.service.signalements();
      if (mounted) {
        setState(() {
          _items = data;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && _items.isEmpty) {
        setState(() {
          _error = '$e'.replaceFirst('Exception: ', '');
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _traiter(
    Map<String, dynamic> r,
    String statut, {
    bool suspendre = false,
  }) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _MC.surface,
        title: Text(
          suspendre ? 'SUSPEND PROVIDER' : 'ADMIN NOTE',
          style: _MC.mono.copyWith(
            color: _MC.ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: _MC.ink),
          decoration: InputDecoration(
            labelText: 'Note / Raison (optionnel)',
            labelStyle: const TextStyle(color: _MC.inkDim),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _MC.line),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _MC.info),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ANNULER', style: TextStyle(color: _MC.inkDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: suspendre ? _MC.danger : _MC.info,
              foregroundColor: _MC.bg,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('CONFIRMER'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;

    final id = '${r['id']}';
    setState(() => _busyId = id);
    try {
      await widget.service.traiterSignalement(
        id,
        statut,
        note: note,
        suspendre: suspendre,
      );
      await _charger(silencieux: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: _MC.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const McLoader();
    if (_error != null) {
      return Center(
        child: McErrorPanel(
          title: 'INCIDENTS LINK DOWN',
          message: _error!,
          onRetry: () => _charger(),
        ),
      );
    }
    if (_items.isEmpty) {
      return const McEmpty(
        title: 'ALL CLEAR',
        message: 'Aucun signalement en attente',
      );
    }

    return RefreshIndicator(
      color: _MC.info,
      backgroundColor: _MC.surface,
      onRefresh: _charger,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final r = _items[i];
          final statut = '${r['status']}';
          final ouvert = statut == 'open' || statut == 'reviewing';
          final (couleur, libelle) = switch (statut) {
            'resolved' => (_MC.live, 'RESOLVED'),
            'dismissed' => (_MC.inkFaint, 'DISMISSED'),
            'reviewing' => (_MC.warn, 'REVIEWING'),
            _ => (_MC.danger, 'OPEN'),
          };
          final busy = _busyId == '${r['id']}';

          return Container(
            decoration: BoxDecoration(
              color: _MC.panel,
              border: Border.all(
                color: ouvert ? _MC.danger.withValues(alpha: 0.5) : _MC.line,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.12),
                    border: Border(
                      bottom: const BorderSide(color: _MC.line),
                      left: BorderSide(color: couleur, width: 3),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ouvert
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 14,
                        color: couleur,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          libelleMotif('${r['motif']}').toUpperCase(),
                          style: _MC.mono.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _MC.ink,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      McBadge(label: libelle, color: couleur),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      McRow(
                        label: 'PROVIDER',
                        value: _nomGarage(r['provider']),
                      ),
                      const SizedBox(height: 4),
                      McRow(
                        label: 'REPORTER',
                        value: _nomClient(r['reporter']),
                      ),
                      const SizedBox(height: 4),
                      McRow(
                        label: 'TIME',
                        value: _heureFormat(r['created_at']),
                      ),
                      if ('${r['details'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _MC.bg,
                            border: Border.all(color: _MC.lineSoft),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${r['details']}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _MC.inkDim,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                      if (ouvert) ...[
                        const SizedBox(height: 12),
                        busy
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _MC.info,
                                  ),
                                ),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  McAction(
                                    label: 'REVIEW',
                                    color: _MC.warn,
                                    onTap: () => _traiter(r, 'reviewing'),
                                  ),
                                  McAction(
                                    label: 'DISMISS',
                                    color: _MC.inkDim,
                                    onTap: () => _traiter(r, 'dismissed'),
                                  ),
                                  McAction(
                                    label: 'RESOLVE',
                                    color: _MC.live,
                                    onTap: () => _traiter(r, 'resolved'),
                                  ),
                                  McAction(
                                    label: 'SUSPEND',
                                    color: _MC.danger,
                                    onTap: () => _traiter(
                                      r,
                                      'resolved',
                                      suspendre: true,
                                    ),
                                  ),
                                ],
                              ),
                      ],
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════
// FEUILLE DE DÉTAIL MISSION
// ═══════════════════════════════════════════════════════════════════════════
class _MissionDetailSheet extends StatelessWidget {
  const _MissionDetailSheet({required this.mission, required this.service});
  final Map<String, dynamic> mission;
  final AdminControlService service;

  static const _events = {
    'created': 'DEMANDE CRÉÉE',
    'accepted': 'ACCEPTÉE',
    'refused': 'REFUSÉE',
    'arrived': 'ARRIVÉE',
    'work_started': 'DÉBUT INTERVENTION',
    'work_ended': 'FIN INTERVENTION',
    'cancelled': 'ANNULÉE',
    'payment_declared': 'PAIEMENT DÉCLARÉ',
    'payment_confirmed': 'PAIEMENT CONFIRMÉ',
  };

  @override
  Widget build(BuildContext context) {
    final id = '${mission['id']}';
    final s = _statutMission(mission);
    final total =
        _int(mission['travel_fee_fcfa']) + _int(mission['repair_fee_fcfa']);

    return Container(
      color: _MC.bg,
      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: Future.wait([
          service.evenements(id).catchError((_) => <Map<String, dynamic>>[]),
          service.messages(id).catchError((_) => <Map<String, dynamic>>[]),
          service.paiements(id).catchError((_) => <Map<String, dynamic>>[]),
        ]),
        builder: (context, snap) {
          final events = snap.data?[0] ?? const [];
          final msgs = snap.data?[1] ?? const [];
          final pays = snap.data?[2] ?? const [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Row(
                children: [
                  McPulseDot(color: _mcStatusColor(s), size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${mission['problem'] ?? 'MISSION'}'.toUpperCase(),
                      style: _MC.mono.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _MC.ink,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  McBadge(label: s.libelle, color: _mcStatusColor(s)),
                ],
              ),
              const SizedBox(height: 16),
              McPanel(
                title: 'TELEMETRY',
                child: Column(
                  children: [
                    McRow(
                      label: 'CLIENT',
                      value: _nomClient(mission['client']),
                    ),
                    const SizedBox(height: 6),
                    McRow(
                      label: 'PROVIDER',
                      value: _nomGarage(mission['provider']),
                    ),
                    const SizedBox(height: 6),
                    McRow(
                      label: 'FEE',
                      value: TravelFee.fcfa(total),
                      valueColor: _MC.info,
                    ),
                    const SizedBox(height: 6),
                    McRow(
                      label: 'PAID',
                      value: TravelFee.fcfa(_int(mission['paid_fcfa'])),
                      valueColor: _MC.live,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              McPanel(
                title: 'EVENT LOG · ${events.length}',
                child: events.isEmpty
                    ? Text(
                        '—',
                        style: TextStyle(color: _MC.inkFaint, fontSize: 12),
                      )
                    : Column(
                        children: [
                          for (final e in events)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(
                                      top: 5,
                                      right: 10,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: _MC.info,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${_heureFormat(e['created_at'])} · '
                                      '${_events['${e['kind']}'] ?? e['kind']}',
                                      style: _MC.mono.copyWith(
                                        fontSize: 11.5,
                                        color: _MC.inkDim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              McPanel(
                title: 'PAYMENTS · ${pays.length}',
                child: pays.isEmpty
                    ? Text(
                        '—',
                        style: TextStyle(color: _MC.inkFaint, fontSize: 12),
                      )
                    : Column(
                        children: [
                          for (final p in pays)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.payments_outlined,
                                    size: 12,
                                    color: _MC.live,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${_heureFormat(p['created_at'])} · '
                                      '${TravelFee.fcfa(_int(p['amount_fcfa']))} · '
                                      '${'${p['operateur']}'.toUpperCase()}',
                                      style: _MC.mono.copyWith(
                                        fontSize: 11.5,
                                        color: _MC.inkDim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              McPanel(
                title: 'COMMS · ${msgs.length}',
                child: msgs.isEmpty
                    ? Text(
                        '—',
                        style: TextStyle(color: _MC.inkFaint, fontSize: 12),
                      )
                    : Column(
                        children: [
                          for (final msg in msgs)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg['sender_id'] == mission['client_id']
                                        ? 'C'
                                        : 'P',
                                    style: _MC.mono.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          msg['sender_id'] ==
                                              mission['client_id']
                                          ? _MC.info
                                          : _MC.warn,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${msg['body'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: _MC.inkDim,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPOSANTS RÉUTILISABLES LOCAUX
// ═══════════════════════════════════════════════════════════════════════════
class _McStat extends StatelessWidget {
  const _McStat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AdminStyle.label(9.5, color: _MC.inkFaint, letterSpacing: 1.4),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: _MC.mono.copyWith(
            fontSize: 13,
            color: color ?? _MC.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _McTelemetry extends StatelessWidget {
  const _McTelemetry({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: AdminStyle.label(9.5, color: _MC.inkFaint, letterSpacing: 1.2),
        ),
        Text(
          value,
          style: _MC.mono.copyWith(
            fontSize: 11.5,
            color: _MC.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _McProgress extends StatelessWidget {
  const _McProgress({required this.ratio, required this.label});
  final double ratio;
  final String label;

  @override
  Widget build(BuildContext context) {
    final couleur = ratio >= 1
        ? _MC.live
        : (ratio > 0 ? _MC.warn : _MC.inkFaint);
    return Row(
      children: [
        Text(
          '$label ',
          style: AdminStyle.label(9.5, color: _MC.inkFaint, letterSpacing: 1.2),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: _MC.bg,
              color: couleur,
            ),
          ),
        ),
      ],
    );
  }
}

class _McSegmented extends StatelessWidget {
  const _McSegmented({required this.selected, required this.onChange});
  final bool selected;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _MC.surface,
        border: Border.all(color: _MC.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('LIVE', selected, () => onChange(true)),
          _seg('ALL', !selected, () => onChange(false)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _MC.info.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: AdminStyle.label(
            10.5,
            color: active ? _MC.info : _MC.inkDim,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _McChoiceChip extends StatelessWidget {
  const _McChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _MC.info.withValues(alpha: 0.18) : _MC.surface,
          border: Border.all(
            color: selected ? _MC.info : _MC.line,
            width: selected ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: AdminStyle.label(
            11,
            color: selected ? _MC.info : _MC.inkDim,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}
