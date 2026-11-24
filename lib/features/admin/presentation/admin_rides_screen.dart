import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';
import 'package:montotem/features/admin/data/admin_ride_service.dart';

/// Ãƒâ€°cran de production de supervision et gestion des courses (ZÃƒÂ©midjan / Tricycle Fret).
class AdminRidesScreen extends StatefulWidget {
  const AdminRidesScreen({super.key});

  @override
  State<AdminRidesScreen> createState() => _AdminRidesScreenState();
}

class _AdminRidesScreenState extends State<AdminRidesScreen> {
  final AdminRideService _service = AdminRideService();
  final DateFormat _format = DateFormat('dd/MM/yyyy ÃƒÂ  HH:mm');

  RealtimeChannel? _canal;
  Timer? _antiRebond;

  List<Ride> _rides = [];
  bool _seulementActives = true;
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
    _canal = _service.ecouter(_planifierSynchronisation);
  }

  @override
  void dispose() {
    _antiRebond?.cancel();
    if (_canal != null) _service.arreter(_canal!);
    super.dispose();
  }

  void _planifierSynchronisation() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) _chargerDonnees(silencieux: true);
    });
  }

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _rides.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final data = await _service.lister();
      if (!mounted) return;
      setState(() {
        _rides = data;
        _loading = false;
        _isRefreshing = false;
        _error = null;
      });
    } on AdminRideException catch (e) {
      if (!mounted) return;
      if (_rides.isEmpty) {
        setState(() {
          _error = e.message;
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

  List<Ride> get _visibles =>
      _rides.where((r) => !_seulementActives || !r.status.termine).toList();

  Future<void> _appelerUtilisateur(String? tel) async {
    if (tel == null || tel.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: tel.replaceAll(RegExp(r'\s+'), ''));
    try {
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> _annulerCourse(Ride r) async {
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Annulation administrative de course',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(
            labelText: 'Motif (transmis au client et au conducteur)',
            hintText: 'Ex. : Conducteur injoignable ou incident sur la route',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Confirmer lÃ¢â‚¬â„¢annulation'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (motif == null || !mounted) return;
    if (motif.length < 3) {
      _afficherMessage('Veuillez indiquer un motif valide.', erreur: true);
      return;
    }

    setState(() => _busyId = r.id);
    try {
      await _service.annuler(r.id, motif);
      _afficherMessage(
        'Course annulÃƒÂ©e avec succÃƒÂ¨s. Participants notifiÃƒÂ©s.',
      );
      await _chargerDonnees(silencieux: true);
    } on AdminRideException catch (e) {
      _afficherMessage(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _ouvrirDetailCourse(Ride r) {
    final chronologie = <(String, DateTime?)>[
      ('CrÃƒÂ©ation de la demande', r.createdAt),
      ('AcceptÃƒÂ©e par le conducteur', r.acceptedAt),
      ('Conducteur arrivÃƒÂ© au point', r.arrivedAt),
      ('Course en route', r.startedAt),
      ('Course terminÃƒÂ©e', r.completedAt),
      ('AnnulÃƒÂ©e', r.cancelledAt),
    ].where((e) => e.$2 != null).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                Icon(r.kind.icone, size: 32, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${r.kind.libelle} Ã¢â‚¬Â¢ ${TravelFee.fcfa(r.prixFcfa)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: r.status.libelle,
                color: r.status.couleur,
                icon: r.status.icone,
              ),
            ),
            const SizedBox(height: 14),
            InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Client',
              value: r.clientName,
              trailing: (r.clientPhone ?? '').isEmpty
                  ? null
                  : IconButton.filledTonal(
                      icon: const Icon(Icons.call_rounded, size: 18),
                      onPressed: () => _appelerUtilisateur(r.clientPhone),
                    ),
            ),
            InfoRow(
              icon: Icons.two_wheeler_rounded,
              label: 'Conducteur',
              value: r.providerName ?? 'En cours dÃ¢â‚¬â„¢attribution',
              trailing: (r.providerPhone ?? '').isEmpty
                  ? null
                  : IconButton.filledTonal(
                      icon: const Icon(Icons.call_rounded, size: 18),
                      onPressed: () => _appelerUtilisateur(r.providerPhone),
                    ),
            ),
            InfoRow(
              icon: Icons.trip_origin_rounded,
              label: 'Point de dÃƒÂ©part',
              value: (r.pickupAddress ?? '').isEmpty
                  ? '${r.pickup.latitude.toStringAsFixed(5)}, ${r.pickup.longitude.toStringAsFixed(5)}'
                  : r.pickupAddress!,
            ),
            InfoRow(
              icon: Icons.flag_rounded,
              label: 'Destination',
              value: (r.dropoffAddress ?? '').isEmpty
                  ? '${r.dropoff.latitude.toStringAsFixed(5)}, ${r.dropoff.longitude.toStringAsFixed(5)}'
                  : r.dropoffAddress!,
            ),
            InfoRow(
              icon: Icons.route_rounded,
              label: 'Distance estimÃƒÂ©e',
              value: r.distanceLibelle,
            ),
            InfoRow(
              icon: Icons.payments_outlined,
              label: 'Mode de paiement',
              value: r.payment.libelle,
            ),
            if (r.status == RideStatus.completed)
              InfoRow(
                icon: Icons.percent_rounded,
                label: 'Commission plateforme',
                value: r.payment.mobileMoney
                    ? 'Aucune (Mobile Money direct)'
                    : TravelFee.fcfa(r.commissionFcfa ?? 0),
              ),
            if ((r.cancelReason ?? '').isNotEmpty)
              InfoRow(
                icon: Icons.cancel_outlined,
                label: 'Motif dÃ¢â‚¬â„¢annulation',
                value: r.cancelReason!,
              ),
            const SectionTitle('Chronologie de lÃ¢â‚¬â„¢ÃƒÂ©vÃƒÂ©nement'),
            for (final e in chronologie)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_format.format(e.$2!)} Ã¢â‚¬â€ ${e.$1}',
                        style: const TextStyle(fontSize: 14.5),
                      ),
                    ),
                  ],
                ),
              ),
            if (!r.status.termine) ...[
              const SizedBox(height: 24),
              AppButton(
                label: 'Annuler cette course',
                icon: Icons.close_rounded,
                variant: AppButtonVariant.danger,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _annulerCourse(r);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Supervision des Courses'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualiser',
              onPressed: _loading ? null : () => _chargerDonnees(),
            ),
          ],
          bottom: const TabBar(
            labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'Liste en direct'),
              Tab(text: 'Carte interactive'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: SingleChildScrollView(
                  child: ErrorState(
                    message: _error!,
                    onRetry: () => _chargerDonnees(),
                  ),
                ),
              )
            : TabBarView(children: [_buildListeTab(), _buildCarteTab()]),
      ),
    );
  }

  Widget _buildListeTab() {
    final liste = _visibles;
    return ContentWidth(
      maxWidth: 900,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Courses actives')),
                ButtonSegment(value: false, label: Text('Historique / Toutes')),
              ],
              selected: {_seulementActives},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _seulementActives = s.first),
            ),
          ),
          if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: liste.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: Icons.two_wheeler_rounded,
                      title: 'Aucune course correspondante',
                      message: 'Les courses en temps rÃƒÂ©el apparaÃƒÂ®tront ici instantanÃƒÂ©ment.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _chargerDonnees(silencieux: true),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: liste.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _carteCourse(liste[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _carteCourse(Ride r) {
    final couleur = r.status.couleur;
    final busy = _busyId == r.id;
    return SoftCard(
      onTap: () => _ouvrirDetailCourse(r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.kind.icone, size: 28, color: context.readable(couleur)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${r.kind.libelle} Ã¢â‚¬Â¢ ${TravelFee.fcfa(r.prixFcfa)}',
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                StatusPill(
                  label: r.status.libelle,
                  color: couleur,
                  icon: r.status.icone,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${r.clientName}  Ã¢â€ â€™  ${r.providerName ?? 'En attente de conducteur'}',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            '${_format.format(r.createdAt)} Ã¢â‚¬Â¢ ${r.distanceLibelle} Ã¢â‚¬Â¢ ${r.payment.libelle}',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCarteTab() {
    final scheme = Theme.of(context).colorScheme;
    final actives = _rides.where((r) => !r.status.termine).toList();
    final lignes = <Polyline>[];
    final markers = <Marker>[];

    for (final r in actives) {
      lignes.add(
        Polyline(
          points: [r.pickup, r.dropoff],
          color: r.status.couleur.withValues(alpha: 0.65),
          strokeWidth: 3.5,
        ),
      );
      markers.add(
        Marker(
          point: r.pickup,
          width: 40,
          height: 40,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _ouvrirDetailCourse(r),
            child: Icon(
              Icons.location_on_rounded,
              size: 38,
              color: scheme.secondary,
            ),
          ),
        ),
      );
      final prov = r.providerPoint;
      if (prov != null && r.status.actif) {
        markers.add(
          Marker(
            point: prov,
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => _ouvrirDetailCourse(r),
              child: Container(
                decoration: BoxDecoration(
                  color: r.status.couleur,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: Icon(r.kind.icone, color: Colors.white, size: 20),
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
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'bj.totem.app',
            ),
            PolylineLayer(polylines: lignes),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('Ã‚Â© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 14,
          left: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6),
              ],
            ),
            child: Text(
              '${actives.length} course(s) active(s) en direct',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
