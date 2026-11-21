import 'package:connectivity_plus/connectivity_plus.dart';

bool _aucuneConnexion(dynamic r) => r is List
    ? r.every((e) => e == ConnectivityResult.none)
    : r == ConnectivityResult.none;

/// true quand le téléphone n'a aucun réseau de données.
Future<bool> estHorsLigne() async {
  try {
    final dynamic r = await Connectivity().checkConnectivity();
    return _aucuneConnexion(r);
  } catch (_) {
    return false;
  }
}

Stream<bool> horsLigneStream() => Connectivity()
    .onConnectivityChanged
    .map<bool>((dynamic r) => _aucuneConnexion(r));
