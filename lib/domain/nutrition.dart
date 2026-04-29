// Модель данных для дня питания (предполагаемая структура, аналогичная SleepDay)
// Если у вас другая модель, адаптируйте поля в классе ниже.
class NutritionDay {
  final DateTime date;
  final double calories; // ккал
  final double protein; // граммы
  final double fat; // граммы
  final double carbs; // граммы

  NutritionDay({
    required this.date,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  // Общая масса макронутриентов в граммах для расчета высоты столбца
  double get totalGrams => protein + fat + carbs;
}
