import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain/nutrition.dart'; // Импорт вашей модели
import 'package:health_widgets/repo/health.dart';

class NutritionViewModel extends ChangeNotifier {
  static const dataTypes = [HealthDataType.NUTRITION];
  final HealthRepository repository;

  List<NutritionDay> _nutritionData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;

  // Геттеры
  List<NutritionDay> get nutritionData => _nutritionData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Вычисляемое свойство: среднее количество ккал за выбранный период
  double get averageCalories {
    if (_nutritionData.isEmpty) return 0;
    final totalCals = _nutritionData.fold<double>(0, (sum, item) => sum + item.calories);
    return totalCals / _nutritionData.length;
  }

  NutritionViewModel(this.repository);

  /// Инициализация: запрос прав и загрузка данных
  Future<void> authorizeAndFetchNutritionData() async {
    // Типы данных для питания в Health Connect / Apple Health
    // NUTRITION обычно возвращает агрегированные записи, но лучше запрашивать конкретные нутриенты,
    // если пакет health их поддерживает отдельно, или общий тип.
    // В пакете flutter_health часто используется HealthDataType.NUTRITION или отдельные флаги.
    // Проверьте документацию вашего пакета. Обычно это:

    try {
      bool granted = await repository.checkAndRequestPermissions(dataTypes);
      if (!granted) {
        _error = "Permission denied or SDK unavailable";
        notifyListeners();
        return;
      }
      await _fetchAndProcess();
    } catch (e) {
      _error = "Auth error: $e";
      notifyListeners();
    }
  }

  /// Смена количества отображаемых дней
  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners(); // Сразу уведомляем, чтобы UI показал лоадер
    await _fetchAndProcess();
  }

  /// Основная логика загрузки и обработки
  Future<void> _fetchAndProcess() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      // Берем данные с небольшим запасом, чтобы захватить полные дни
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays + 1));

      // 1. Получаем сырые данные
      // Примечание: Убедитесь, что ваш HealthRepository поддерживает передачу списка типов
      final rawPoints = await repository.fetchRawData(types: dataTypes, startDate: startDate, endDate: now);

      // 2. Обрабатываем данные: группируем по дням и суммируем БЖУ/Ккал
      _nutritionData = _processNutritionData(rawPoints: rawPoints, daysToAnalyze: _selectedDays, now: now);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to fetch nutrition data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Nutrition Error: $e");
    }
  }

  /// Логика агрегации данных (аналог SleepAnalyzer)
  List<NutritionDay> _processNutritionData({
    required List<HealthDataPoint> rawPoints,
    required int daysToAnalyze,
    required DateTime now,
  }) {
    // Карта для накопления данных по каждому дню
    // Ключ: строка даты "YYYY-MM-DD", Значение: объект-аккумулятор
    final Map<String, _DailyNutritionAccumulator> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней,
    // чтобы в графике были нулевые столбцы для дней без еды
    for (int i = 0; i < daysToAnalyze; i++) {
      final date = now.subtract(Duration(days: i));
      final key = _getDateKey(date);
      dailyMap[key] = _DailyNutritionAccumulator(date: date);
    }

    // Проходим по всем точкам из Health Connect
    for (var point in rawPoints) {
      final date = point.dateFrom; // Или dateTo, зависит от того, как приходят данные
      final key = _getDateKey(date);

      // Если дата входит в наш анализируемый период
      if (dailyMap.containsKey(key)) {
        final accumulator = dailyMap[key]!;

        // HealthDataPoint.value может быть разных типов.
        // Для NUTRITION это часто NutritionDataPoint или просто numeric value в зависимости от типа.
        // ВАЖНО: Структура HealthDataPoint в пакете 'health' может отличаться.
        // Ниже примерная логика парсинга. Вам нужно адаптировать её под реальный тип данных из пакета.

        _parseAndAddToAccumulator(point, accumulator);
      }
    }

    // Преобразуем карту в список и сортируем по дате (от старых к новым для графика слева направо)
    final result = dailyMap.values.toList();
    result.sort((a, b) => a.date.compareTo(b.date));

    return result
        .map(
          (acc) => NutritionDay(
            date: acc.date,
            calories: acc.calories,
            protein: acc.protein,
            fat: acc.fat,
            carbs: acc.carbs,
          ),
        )
        .toList();
  }

  void _parseAndAddToAccumulator(HealthDataPoint point, _DailyNutritionAccumulator acc) {
    // В пакете flutter_health данные о питании могут приходить как:
    // 1. Отдельные точки для каждого нутриента (тип зависит от HealthDataType)
    // 2. Одна точка Nutrition с полями.

    // Пример обработки (адаптируйте под вашу версию пакета):
    final value = point.value;
    final type = point.type;

    // Если значение - число (например, граммы или ккал)

    if (value is NumericHealthValue) {
      double val = value.numericValue.toDouble();

      switch (type) {
        case HealthDataType.DIETARY_ENERGY_CONSUMED:
        case HealthDataType.NUTRITION:
          acc.calories += val;
          break;
        case HealthDataType.DIETARY_PROTEIN_CONSUMED:
          acc.protein += val;
          break;
        case HealthDataType.DIETARY_FATS_CONSUMED:
          acc.fat += val;
          break;
        case HealthDataType.DIETARY_CARBS_CONSUMED:
          acc.carbs += val;
          break;
        default:
      }
    } else if (value is NutritionHealthValue) {
      acc.calories += value.calories?.toDouble() ?? 0.0;
      acc.protein += value.protein?.toDouble() ?? 0.0;
      acc.fat += value.fat?.toDouble() ?? 0.0;
      acc.carbs += value.carbs?.toDouble() ?? 0.0;
    }

    // Если значение - сложный объект (зависит от реализации пакета), распарсите его аналогично.
  }

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}

/// Вспомогательный класс для накопления данных за один день
class _DailyNutritionAccumulator {
  final DateTime date;
  double calories = 0;
  double protein = 0;
  double fat = 0;
  double carbs = 0;

  _DailyNutritionAccumulator({required this.date});
}
