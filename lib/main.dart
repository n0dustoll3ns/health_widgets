import 'package:flutter/material.dart';
import 'package:health/health.dart';

void main() {
  runApp(const HealthWidgetsApp());
}

class HealthWidgetsApp extends StatefulWidget {
  const HealthWidgetsApp({super.key});

  @override
  State<HealthWidgetsApp> createState() => _HealthWidgetsAppState();
}

class _HealthWidgetsAppState extends State<HealthWidgetsApp> {
Future<void> authorizeHealth() async {
  Health health = Health();
  
  // 1. Инициализация обязательна
  await health.configure(); 

  // 2. Проверяем статус SDK (установлено ли приложение или встроено в систему)
  var status = await health.getHealthConnectSdkStatus();
  if (status != HealthConnectSdkStatus.sdkAvailable) {
    print("Health Connect SDK не доступен. Статус: $status");
    // Здесь можно предложить пользователю установить Health Connect, если Android < 14
    return;
  }

  final types = [HealthDataType.SLEEP_SESSION];
  final permissions = [HealthDataAccess.READ];

  try {
    // 3. Проверяем, есть ли уже доступ, чтобы не спамить запросом
    bool? hasPermissions = await health.hasPermissions(types, permissions: permissions);
    
    if (hasPermissions == false) {
      // Запрашиваем доступ
      bool requested = await health.requestAuthorization(types, permissions: permissions);
      if (!requested) {
        print("В доступе отказано.");
        return;
      }
    }

    print("Доступ к Health Connect получен!");
    _fetchSleepData();
  } catch (e) {
    print("Исключение при авторизации: $e");
  }
}Future<void> _fetchSleepData() async {
    Health health = Health();
    // Явно настраиваем плагин на использование Health Connect
    await health.configure();
    var now = DateTime.now();
    var yesterday = now.subtract(Duration(days: 7)); // Берем за неделю

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: yesterday,
      endTime: now,
    );

    print("Получено записей о сне: ${healthData.length}");
    for (var d in healthData) {
      print("Тип: ${d.type}, Значение: ${d.value}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            child: Text('Connect!'),
            onPressed: () {
              authorizeHealth();
            },
          ),
        ),
      ),
    );
  }
}
