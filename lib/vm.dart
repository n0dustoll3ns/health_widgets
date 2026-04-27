import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain.dart';
import 'package:home_widget/home_widget.dart';

// Вспомогательный класс для работы с интервалами внутри алгоритма
class _SleepInterval {
  DateTime start;
  DateTime end;
  HealthDataType type;

  _SleepInterval({required this.start, required this.end, required this.type});
}

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

    final types = [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM];
    final permissions = List.filled(types.length, HealthDataAccess.READ);

    try {
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
      // Берем запас по дням + 1 день, чтобы захватить ночи, которые начались вчера, но закончились сегодня
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays + 1));

      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM],
        startTime: startDate,
        endTime: now,
      );

      // 1. Преобразуем HealthDataPoint в простые интервалы для сортировки
      List<_SleepInterval> intervals = [];
      for (var point in healthData) {
        if (point.value is NumericHealthValue) {
          // Проверяем, что длительность > 0, чтобы избежать ошибок
          if ((point.value as NumericHealthValue).numericValue > 0) {
            intervals.add(_SleepInterval(start: point.dateFrom, end: point.dateTo, type: point.type));
          }
        }
      }

      // 2. Сортируем интервалы по времени начала
      intervals.sort((a, b) => a.start.compareTo(b.start));

      // 3. ОБЪЕДИНЕНИЕ ПЕРЕСЕКАЮЩИХСЯ ИНТЕРВАЛОВ (MERGE OVERLAPS)
      // Это ключевой шаг для удаления дубликатов от разных источников (Xiaomi, Google Fit и т.д.)
      List<_SleepInterval> mergedIntervals = [];

      for (var current in intervals) {
        if (mergedIntervals.isEmpty) {
          mergedIntervals.add(current);
        } else {
          var last = mergedIntervals.last;

          // Если текущий интервал начинается раньше, чем заканчивается предыдущий
          // ИЛИ они совпадают по границе
          if (current.start.isBefore(last.end) || current.start.isAtSameMomentAs(last.end)) {
            // Обновляем конец предыдущего интервала, если текущий заканчивается позже
            if (current.end.isAfter(last.end)) {
              last.end = current.end;
            }
            // Примечание: Если типы разные (например, Deep и Light перекрылись),
            // мы все равно сливаем их геометрически, чтобы не считать одно время дважды.
            // Тип оставляем от первого интервала или можно игнорировать тип при слиянии,
            // но для простоты оставим тип последнего добавленного или первого.
            // В данном случае тип не критичен для слияния геометрии, главное - время.
          } else {
            // Нет пересечения, добавляем новый интервал
            mergedIntervals.add(current);
          }
        }
      }

      // 4. Распределение по дням
      // Создаем карту для накопления часов: Key = Дата (День пробуждения/Основной день)
      Map<String, Map<HealthDataType, double>> dailyStats = {};

      // Инициализируем карту для последних N дней нулями
      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        String key = _getDateKey(date);
        dailyStats[key] = {
          HealthDataType.SLEEP_DEEP: 0.0,
          HealthDataType.SLEEP_LIGHT: 0.0,
          HealthDataType.SLEEP_REM: 0.0,
        };
      }

      for (var interval in mergedIntervals) {
        // Определяем, какому дню принадлежит этот сон.
        // Логика: Если сон начался до 12:00 дня, считаем его принадлежащим этому дню (утренний сон).
        // Если сон начался после 12:00 дня (вечер), он принадлежит следующему дню (дню пробуждения).
        // Это стандартная логика для трекеров сна.

        DateTime targetDate = interval.start;
        if (interval.start.hour >= 12) {
          // Если начали спать в 22:00, это статистика для "завтрашнего" дня
          targetDate = interval.start.add(Duration(days: 1));
        }

        // Проверяем, попадает ли целевая дата в наш диапазон отображения
        String key = _getDateKey(targetDate);

        if (dailyStats.containsKey(key)) {
          double durationHours = interval.end.difference(interval.start).inMinutes / 60.0;

          switch (interval.type) {
            case HealthDataType.SLEEP_DEEP:
              dailyStats[key]![HealthDataType.SLEEP_DEEP] =
                  (dailyStats[key]![HealthDataType.SLEEP_DEEP] ?? 0) + durationHours;
              break;
            case HealthDataType.SLEEP_LIGHT:
              dailyStats[key]![HealthDataType.SLEEP_LIGHT] =
                  (dailyStats[key]![HealthDataType.SLEEP_LIGHT] ?? 0) + durationHours;
              break;
            case HealthDataType.SLEEP_REM:
              dailyStats[key]![HealthDataType.SLEEP_REM] =
                  (dailyStats[key]![HealthDataType.SLEEP_REM] ?? 0) + durationHours;
              break;
            default:
              break;
          }
        }
      }

      // 5. Формируем итоговый список
      List<SleepDay> processedData = [];
      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        String key = _getDateKey(date);

        var stats =
            dailyStats[key] ??
            {HealthDataType.SLEEP_DEEP: 0.0, HealthDataType.SLEEP_LIGHT: 0.0, HealthDataType.SLEEP_REM: 0.0};

        processedData.add(
          SleepDay(
            date: date,
            deep: stats[HealthDataType.SLEEP_DEEP] ?? 0.0,
            light: stats[HealthDataType.SLEEP_LIGHT] ?? 0.0,
            rem: stats[HealthDataType.SLEEP_REM] ?? 0.0,
          ),
        );
      }

      // Сортируем от старого к новому для графика (опционально, зависит от вашего UI)
      processedData.sort((a, b) => a.date.compareTo(b.date));

      _sleepData = processedData;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to fetch data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Error fetching sleep data: $e");
    }
  }

  // Helper для создания унифицированного ключа даты (без времени)
  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month}-${date.day}";
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
