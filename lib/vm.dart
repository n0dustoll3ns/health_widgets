import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain.dart'; // Убедитесь, что путь верный
import 'package:home_widget/home_widget.dart';

class SleepViewModel extends ChangeNotifier {
  SleepViewModel() {
    _init();
  }

  final Health _health = Health();

  List<SleepDay> _sleepData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;

  // Геттеры
  List<SleepDay> get sleepData => _sleepData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Инициализация и настройка Health
  Future<void> _init() async {
    await _health.configure();
  }

  /// Авторизация и запуск загрузки данных
  Future<void> authorizeAndFetch() async {
    var status = await _health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) {
      _error = "Health Connect SDK not available";
      notifyListeners();
      return;
    }

    // 1. Определяем типы данных
    final types = [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM];

    // 2. Исправление: Создаем список прав той же длины, что и список типов
    // Для каждого типа мы запрашиваем право на чтение (READ)
    final permissions = List.filled(types.length, HealthDataAccess.READ);

    try {
      // Теперь длины списков совпадают (3 и 3)
      bool? hasPermissions = await _health.hasPermissions(types, permissions: permissions);

      if (hasPermissions == false) {
        bool requested = await _health.requestAuthorization(types, permissions: permissions);
        if (!requested) {
          _error = "Permission denied";
          notifyListeners();
          return;
        }
      }
      await _fetchSleepData();
    } catch (e) {
      _error = "Authorization error: $e";
      notifyListeners();
    }
  }

  /// Изменение количества дней и перезагрузка
  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners();
    await _fetchSleepData();
  }

  /// Основная бизнес-логика получения и обработки данных
  Future<void> _fetchSleepData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      // Начало диапазона
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays - 1));

      // 2. Запрашиваем данные по всем типам фаз сразу
      // Пакет health вернет список HealthDataPoint, где у каждого будет свой тип (SLEEP_DEEP, SLEEP_LIGHT и т.д.)
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM],
        startTime: startDate,
        endTime: now,
      );

      // ГРУППИРОВКА ПО ДНЯМ
      // Группируем все точки (и глубокий, и легкий сон) по дате начала записи
      Map<DateTime, List<HealthDataPoint>> grouped = groupBy(healthData, (point) {
        return DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day);
      });

      List<SleepDay> processedData = [];

      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = startDate.add(Duration(days: i));
        DateTime key = DateTime(date.year, date.month, date.day);

        double dayDeep = 0;
        double dayLight = 0;
        double dayRem = 0;

        if (grouped.containsKey(key)) {
          var pointsForDay = grouped[key]!;

          for (var point in pointsForDay) {
            if (point.value is NumericHealthValue) {
              double minutes = (point.value as NumericHealthValue).numericValue.toDouble();
              double hours = minutes / 60;

              // 3. Распределяем данные в зависимости от ТИПА записи
              if (point.type == HealthDataType.SLEEP_DEEP) {
                dayDeep += hours;
              } else if (point.type == HealthDataType.SLEEP_LIGHT) {
                dayLight += hours;
              } else if (point.type == HealthDataType.SLEEP_REM) {
                dayRem += hours;
              }
            }
          }
        }

        processedData.add(SleepDay(date: key, deep: dayDeep, light: dayLight, rem: dayRem));
      }

      _sleepData = processedData;
      _isLoading = false;
      notifyListeners();

      if (_sleepData.isNotEmpty) {
        // Триггер для обновления виджета, если нужно
      }
    } catch (e) {
      _error = "Failed to fetch data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Error fetching sleep data: $e");
    }
  }

  /// Логика сохранения изображения и обновления Home Widget
  Future<void> updateSystemWidget(String imagePath) async {
    try {
      await HomeWidget.saveWidgetData<String>('chart_path', imagePath);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }
}
