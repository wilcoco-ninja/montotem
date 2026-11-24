import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/services/weather_service.dart';
import 'package:montotem/core/theme/app_colors.dart';

/// Météo réelle (Open-Meteo) pour un point du globe, en pastille repliable.
///
/// Se met à jour toute seule : quand [position] s'éloigne de plus de 3 km,
/// puis toutes les 10 minutes. Jamais de valeur inventée : sans réseau ni
/// donnée récente, la pastille affiche « Météo indisponible » et un bouton
/// pour réessayer.
class LiveWeatherChip extends StatefulWidget {
  const LiveWeatherChip({super.key, required this.position});

  final LatLng position;

  @override
  State<LiveWeatherChip> createState() => _LiveWeatherChipState();
}

class _LiveWeatherChipState extends State<LiveWeatherChip> {
  final _service = WeatherService.instance;

  WeatherData? _data;
  bool _loading = true;
  bool _failed = false;
  bool _open = false;
  LatLng? _fetchedFor;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _data = _service.cached(
      widget.position.latitude,
      widget.position.longitude,
    );
    _load();
    _timer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _load(force: true),
    );
  }

  @override
  void didUpdateWidget(LiveWeatherChip old) {
    super.didUpdateWidget(old);
    final f = _fetchedFor;
    if (f == null) return;
    final km = WeatherService.kmBetween(
      f.latitude,
      f.longitude,
      widget.position.latitude,
      widget.position.longitude,
    );
    if (km > 3) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final at = widget.position;
    if (mounted) setState(() => _loading = true);
    final w = await _service.tryGetWeather(
      latitude: at.latitude,
      longitude: at.longitude,
      forceRefresh: force,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = w == null && _data == null;
      if (w != null) {
        _data = w;
        _fetchedFor = at;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = _data;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      elevation: 3,
      shadowColor: AppColors.navy.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: w == null
            ? () => _load(force: true)
            : () => setState(() => _open = !_open),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: w == null ? _empty() : _content(w, theme),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final theme = Theme.of(context);
    if (_loading && !_failed) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 18),
        const SizedBox(width: 6),
        const Text('Météo indisponible', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Icon(Icons.refresh_rounded, size: 16, color: theme.colorScheme.primary),
      ],
    );
  }

  Widget _content(WeatherData w, ThemeData theme) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    final head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(w.conditionEmoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              w.temperatureString,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(w.description, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
        const SizedBox(width: 6),
        if (_loading)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          )
        else
          Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
            color: muted,
          ),
      ],
    );

    if (!_open) return head;

    final wind = w.windCompass;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        head,
        const SizedBox(height: 8),
        _line(
          Icons.thermostat_rounded,
          'Ressenti ${w.feelsLike.round()}°C',
          AppColors.amber,
        ),
        _line(
          Icons.water_drop_outlined,
          'Humidité ${w.humidity} %',
          AppColors.navy,
        ),
        _line(
          Icons.air_rounded,
          'Vent ${w.windSpeedString}${wind == null ? '' : ' (du $wind)'}',
          AppColors.success,
        ),
        if (w.precipitation > 0)
          _line(
            Icons.umbrella_rounded,
            'Pluie ${w.precipitation.toStringAsFixed(1)} mm',
            AppColors.navy,
          ),
        if (w.isRaining || w.condition == WeatherCondition.stormy)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Chaussée glissante : prudence.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _line(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
