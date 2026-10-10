import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/services/place_formatter.dart';

enum LocationError {
  /// Location is turned off on the phone
  serviceOff,
  denied,

  /// Don't ask again → must be turned on in the phone's settings
  deniedForever,

  /// Could not get coordinates or an address
  unavailable,
}

class LocationLookupException implements Exception {
  const LocationLookupException(this.error);
  final LocationError error;

  @override
  String toString() => 'LocationLookupException($error)';
}

/// Phone location and time zone (wraps geolocator, geocoding and flutter_timezone; swappable so the Cubit can be tested).
/// Coordinates are turned into an address in here and never leave it (they are not sent to the speaker; design document Section 3.0)
abstract class LocationService {
  /// Asks for permission and returns the address parts of the current location. Throws [LocationLookupException] on failure
  Future<PlaceParts> currentPlace();

  /// Phone IANA time zone (null if it can't be read)
  Future<String?> phoneTimezone();

  /// The app permission screen in the phone's settings
  Future<void> openSettings();
}

class DeviceLocationService implements LocationService {
  @override
  Future<PlaceParts> currentPlace() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationLookupException(LocationError.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) throw const LocationLookupException(LocationError.deniedForever);
    if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
      throw const LocationLookupException(LocationError.denied);
    }
    final Position position;
    try {
      // Only the neighborhood is needed, so low accuracy (saves battery and time)
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) throw const LocationLookupException(LocationError.unavailable);
      return _place(last);
    } catch (_) {
      throw const LocationLookupException(LocationError.unavailable);
    }
    return _place(position);
  }

  Future<PlaceParts> _place(Position p) async {
    final List<Placemark> marks;
    try {
      // The address must come back in Korean to build the "서울 강남구 역삼동" form (abroad, the country name comes back in Korean)
      marks = await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude, locale: const Locale('ko', 'KR'));
    } catch (_) {
      throw const LocationLookupException(LocationError.unavailable);
    }
    if (marks.isEmpty) throw const LocationLookupException(LocationError.unavailable);
    final m = marks.first;
    return PlaceParts(
      isoCountryCode: m.isoCountryCode,
      country: m.country,
      administrativeArea: m.administrativeArea,
      subAdministrativeArea: m.subAdministrativeArea,
      locality: m.locality,
      subLocality: m.subLocality,
      thoroughfare: m.thoroughfare,
      name: m.name,
    );
  }

  @override
  Future<String?> phoneTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}
