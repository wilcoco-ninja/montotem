import 'dart:async';
import 'dart:developer' as developer;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveau d'alerte batterie.
enum PowerLevel {
  /// Tout va bien (ou le téléphone est en charge).
  normal,

  /// ≤ 20 % : l'app passe en économie d'énergie.
  low,

  /// ≤ 10 % : l'app pousse à envoyer la position par SMS tout de suite.
  critical,
}

/// Surveille la batterie et le réseau du téléphone pour que MonTotem reste
/// utilisable jusqu'au bout, même quand :
///  - le téléphone va s'éteindre ;
///  - il n'y a plus d'internet (zone blanche, orage, saturation du réseau).
///
/// Ce contrôleur est lu par :
///  - `main.dart` : thème noir pur + animations coupées en mode éco ;
///  - `SurvivalShell` : bandeau d'alerte en haut de tous les écrans ;
///  - l'écran Kit de survie et l'inscription conducteur.
///
/// Toutes les lectures sont protégées : sur le web ou sur un appareil sans
/// capteur de batterie, l'app continue simplement sans ces informations.
class PowerModeController extends ChangeNotifier with WidgetsBindingObserver {
  PowerModeController();

  static const int seuilBas = 20;
  static const int seuilCritique = 10;
  static const String _cleEco = 'totem_eco_manuel';

  final Battery _battery = Battery();
  StreamSubscription<dynamic>? _reseauSub;
  StreamSubscription<BatteryState>? _etatSub;
  Timer? _minuteur;
  bool _demarre = false;

  int _niveau = 100;
  bool _batterieConnue = false;
  bool _enCharge = false;
  bool _modeEconomieSysteme = false;
  bool _horsLigne = false;
  bool _ecoManuel = false;

  // ── Lecture ───────────────────────────────────────────────────────────
  /// Pourcentage de batterie (100 si inconnu).
  int get niveau => _niveau;
  bool get batterieConnue => _batterieConnue;
  bool get enCharge => _enCharge;
  bool get horsLigne => _horsLigne;
  bool get ecoManuel => _ecoManuel;

  PowerLevel get alerte {
    if (!_batterieConnue || _enCharge) return PowerLevel.normal;
    if (_niveau <= seuilCritique) return PowerLevel.critical;
    if (_niveau <= seuilBas) return PowerLevel.low;
    return PowerLevel.normal;
  }

  /// L'économie d'énergie est-elle active ? Oui si l'utilisateur l'a
  /// demandée, ou (sur batterie) si le système est en économie d'énergie
  /// ou si la charge est ≤ 20 %.
  bool get ecoActive =>
      _ecoManuel ||
      (!_enCharge && (_modeEconomieSysteme || alerte != PowerLevel.normal));

  // ── Cycle de vie ──────────────────────────────────────────────────────
  Future<void> demarrer() async {
    if (_demarre) return;
    _demarre = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      final prefs = await SharedPreferences.getInstance();
      _ecoManuel = prefs.getBool(_cleEco) ?? false;
    } catch (_) {}

    await _lireBatterie();
    await _lireReseau();

    try {
      _etatSub = _battery.onBatteryStateChanged.listen(
        (_) => _lireBatterie(),
        onError: (_) {},
      );
    } catch (_) {}

    try {
      _reseauSub = Connectivity().onConnectivityChanged.listen((dynamic r) {
        final hors = _aucuneConnexion(r);
        if (hors != _horsLigne) {
          _horsLigne = hors;
          notifyListeners();
        }
      }, onError: (_) {});
    } catch (_) {}

    // La batterie n'a pas de flux de pourcentage : on relit toutes les
    // 60 secondes (lecture quasi gratuite).
    _minuteur = Timer.periodic(const Duration(seconds: 60), (_) {
      _lireBatterie();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lireBatterie();
      _lireReseau();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reseauSub?.cancel();
    _etatSub?.cancel();
    _minuteur?.cancel();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────
  Future<void> definirEcoManuel(bool actif) async {
    _ecoManuel = actif;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cleEco, actif);
    } catch (_) {}
  }

  // ── Lectures internes ─────────────────────────────────────────────────
  static bool _aucuneConnexion(dynamic r) => r is List
      ? r.isEmpty || r.every((e) => e == ConnectivityResult.none)
      : r == ConnectivityResult.none;

  Future<void> _lireReseau() async {
    try {
      final dynamic r = await Connectivity().checkConnectivity();
      final hors = _aucuneConnexion(r);
      if (hors != _horsLigne) {
        _horsLigne = hors;
        notifyListeners();
      }
    } catch (e) {
      developer.log('Lecture réseau', error: e, name: 'PowerModeController');
    }
  }

  Future<void> _lireBatterie() async {
    try {
      final n = await _battery.batteryLevel;
      final etat = await _battery.batteryState;
      var economieSysteme = false;
      try {
        economieSysteme = await _battery.isInBatterySaveMode;
      } catch (_) {}

      final charge = etat == BatteryState.charging || etat == BatteryState.full;

      if (!_batterieConnue ||
          n != _niveau ||
          charge != _enCharge ||
          economieSysteme != _modeEconomieSysteme) {
        _batterieConnue = true;
        _niveau = n;
        _enCharge = charge;
        _modeEconomieSysteme = economieSysteme;
        notifyListeners();
      }
    } catch (e) {
      // Web, émulateur, capteur absent : on ignore, l'app continue.
      developer.log('Lecture batterie', error: e, name: 'PowerModeController');
    }
  }
}

extension PowerContext on BuildContext {
  /// Lit le contrôleur et reconstruit le widget à chaque changement.
  PowerModeController get power => watch<PowerModeController>();

  /// Lit le contrôleur sans reconstruire (dans un callback).
  PowerModeController get powerRead => read<PowerModeController>();
}
