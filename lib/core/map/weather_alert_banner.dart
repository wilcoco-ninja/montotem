import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/services/weather_service.dart';
import 'package:montotem/core/theme/app_colors.dart';

/// Bandeau d'alerte météo du client : interroge les VRAIES prévisions
/// Open-Meteo (pluie, orage, canicule, beau temps) et prévient l'utilisateur
/// directement sur l'accueil carte. Ne lève jamais : sans réseau il reste
/// simplement silencieux, aucune donnée inventée.
class WeatherAlertBanner extends StatefulWidget {
  const WeatherAlertBanner({super.key, required this.position});

  final LatLng position;

  @override
  State<WeatherAlertBanner> createState() => _WeatherAlertBannerState();
}

class _WeatherAlertBannerState extends State<WeatherAlertBanner> {
  final WeatherService _meteo = WeatherService.instance;

  PrevisionMeteo? _prevision;
  Timer? _rafraichi;
  bool _ferme = false;

  @override
  void initState() {
    super.initState();
    _charger();
    // Les prévisions évoluent : on les réactualise discrètement toutes les
    // 15 minutes tant que l'écran est ouvert.
    _rafraichi = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) _charger();
    });
  }

  @override
  void didUpdateWidget(covariant WeatherAlertBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) _charger();
  }

  @override
  void dispose() {
    _rafraichi?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    final p = await _meteo.tryGetPrevisions(
      latitude: widget.position.latitude,
      longitude: widget.position.longitude,
    );
    if (!mounted) return;
    setState(() => _prevision = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prevision;
    final texte = p?.alerte;
    if (_ferme || p == null || texte == null) return const SizedBox.shrink();

    final orage = p.orageProche;
    final pluie = p.pluieProche;
    final couleurFond = orage || pluie
        ? AppColors.amber.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);
    final couleurBord = orage || pluie
        ? AppColors.amber.withValues(alpha: 0.6)
        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      child: Card(
        key: const ValueKey<String>('alerte-meteo'),
        elevation: 0,
        margin: EdgeInsets.zero,
        color: couleurFond,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: couleurBord),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Text(p.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texte,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Masquer',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _ferme = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
