import 'package:geolocator/geolocator.dart';

class LocationPermissionException implements Exception {
  final String message;
  const LocationPermissionException(this.message);
  @override
  String toString() => message;
}

class LocationService {
  Future<Position> getCurrentLocation() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationPermissionException(
        'Les services de localisation sont désactivés.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationPermissionException(
          'Permission de localisation refusée.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Permission de localisation refusée définitivement. Activez-la dans les paramètres de l\'appareil.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  double distanceBetween(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) => Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
}
