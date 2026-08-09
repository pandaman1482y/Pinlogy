import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class DeviceLocationResult {
  const DeviceLocationResult({required this.point, this.approximate = false});

  final LatLng point;
  final bool approximate;
}

/// 端末の現在地取得。
abstract class DeviceLocationService {
  /// まず最後の既知位置があればすぐ返し、なければ現在位置を取る。
  Future<DeviceLocationResult> locateFast();

  /// より精度の高い現在位置。
  Future<LatLng> locatePrecise();
}

class GeolocatorLocationService implements DeviceLocationService {
  @override
  Future<DeviceLocationResult> locateFast() async {
    await _ensurePermission();

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      return DeviceLocationResult(
        point: LatLng(last.latitude, last.longitude),
        approximate: true,
      );
    }

    final current = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return DeviceLocationResult(
      point: LatLng(current.latitude, current.longitude),
    );
  }

  @override
  Future<LatLng> locatePrecise() async {
    await _ensurePermission();
    final current = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LatLng(current.latitude, current.longitude);
  }

  Future<void> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('位置情報がオフです。端末の設定からオンにしてください。');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('位置情報の許可が必要です。');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('位置情報が拒否されています。設定アプリから許可してください。');
    }
  }
}

/// テスト／オフライン用。
class MockDeviceLocationService implements DeviceLocationService {
  MockDeviceLocationService({this.point = const LatLng(35.6812, 139.7671)});

  final LatLng point;

  @override
  Future<DeviceLocationResult> locateFast() async =>
      DeviceLocationResult(point: point);

  @override
  Future<LatLng> locatePrecise() async => point;
}
