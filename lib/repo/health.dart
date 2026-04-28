import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthRepository {
  final Health _health = Health();

  // Кэшируем статус конфигурации, чтобы не вызывать configure каждый раз
  bool _isConfigured = false;

  Future<void> ensureConfigured() async {
    if (!_isConfigured) {
      await _health.configure();
      _isConfigured = true;
    }
  }

  Future<bool> checkAndRequestPermissions(List<HealthDataType> types) async {
    await ensureConfigured();
    
    // Проверка доступности SDK (Android specific mostly)
    var status = await _health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) {
      debugPrint("Health Connect SDK not available");
      return false;
    }

    final permissions = List.filled(types.length, HealthDataAccess.READ);
    
    bool? hasPermissions = await _health.hasPermissions(types, permissions: permissions);
    if (hasPermissions == true) return true;

    return await _health.requestAuthorization(types, permissions: permissions);
  }

  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await ensureConfigured();
    return await _health.getHealthDataFromTypes(
      types: types,
      startTime: startDate,
      endTime: endDate,
    );
  }
}