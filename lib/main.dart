import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:health/health.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart'; // Полезно для группировки

void main() => runApp(const HealthWidgetsApp());

class SleepDay {
  final DateTime date;
  final double deep;
  final double light;
  final double rem;

  const SleepDay({required this.date, required this.deep, required this.light, required this.rem})
    : total = deep + light + rem;

  final double total;

  @override
  String toString() =>
      '\nSleepDay ${date.day}.${date.month}: deep = ${deep.toStringAsFixed(2)}; total = ${total.toStringAsFixed(2)}';
}

class HealthWidgetsApp extends StatefulWidget {
  const HealthWidgetsApp({super.key});
  @override
  State<HealthWidgetsApp> createState() => _HealthWidgetsAppState();
}

class _HealthWidgetsAppState extends State<HealthWidgetsApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  List<SleepDay> _sleepData = [];
  int _selectedDays = 7; // Состояние для выбора количества дней

  Future<void> authorizeHealth() async {
    Health health = Health();
    await health.configure();
    var status = await health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) return;

    final types = [HealthDataType.SLEEP_SESSION];
    final permissions = [HealthDataAccess.READ];

    try {
      bool? hasPermissions = await health.hasPermissions(types, permissions: permissions);
      if (hasPermissions == false) {
        bool requested = await health.requestAuthorization(types, permissions: permissions);
        if (!requested) return;
      }
      _fetchSleepData();
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _fetchSleepData() async {
    Health health = Health();
    await health.configure();
    final now = DateTime.now();
    // Используем выбранное количество дней
    final range = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays - 1));

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: range,
      endTime: now,
    );

    // ГРУППИРОВКА: Собираем данные по дням
    Map<DateTime, List<HealthDataPoint>> grouped = groupBy(healthData, (point) {
      return DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day);
    });

    List<SleepDay> processedData = [];

    // Проходим по каждой дате в выбранном интервале
    for (int i = 0; i < _selectedDays; i++) {
      DateTime date = range.add(Duration(days: i));
      DateTime key = DateTime(date.year, date.month, date.day);

      double dayDeep = 0, dayLight = 0, dayRem = 0;

      if (grouped.containsKey(key)) {
        for (var point in grouped[key]!) {
          print('point = ${point}');
          double totalHours = (point.value as NumericHealthValue).numericValue.toDouble() / 60;
          // Распределяем фазы (как в вашем примере)
          dayDeep += totalHours * 0.25;
          dayLight += totalHours * 0.55;
          dayRem += totalHours * 0.20;
        }
      }

      processedData.add(SleepDay(date: key, deep: dayDeep, light: dayLight, rem: dayRem));
    }

    setState(() {
      _sleepData = processedData;
    });

    if (_sleepData.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateWidget());

      print('_sleepData = ${_sleepData}');
    }
  }

  Future<void> _updateWidget() async {
    try {
      final context = _boundaryKey.currentContext;
      if (context == null) return;

      RenderRepaintBoundary boundary = context.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      var byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/sleep_chart.png').create();
      await file.writeAsBytes(byteData!.buffer.asUint8List());

      await HomeWidget.saveWidgetData<String>('chart_path', file.path);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Sleep Analytics'), centerTitle: true),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Last $_selectedDays Days",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    // Селект количества дней
                    DropdownButton<int>(
                      value: _selectedDays,
                      underline: Container(),
                      items: List.generate(
                        7,
                        (index) => index + 1,
                      ).map((d) => DropdownMenuItem(value: d, child: Text("$d d"))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDays = val);
                          _fetchSleepData();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: Container(
                        width: double.infinity,
                        height: 250,
                        color: Colors.transparent,
                        child: CustomPaint(painter: MultiPhaseSleepPainter(_sleepData)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    LegendItem(color: Color(0xFF1A237E), label: "Deep"),
                    LegendItem(color: Color(0xFF3F51B5), label: "Light"),
                    LegendItem(color: Color(0xFF9FA8DA), label: "REM"),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: authorizeHealth,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Update & Sync', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MultiPhaseSleepPainter extends CustomPainter {
  final List<SleepDay> data;
  MultiPhaseSleepPainter(this.data);

  // Вспомогательная функция для форматирования времени (например, 7h 20m)
  String _formatHours(double hours) {
    int h = hours.toInt();
    int m = ((hours - h) * 60).round();
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  // Вспомогательная функция для формата dd.mm
  String _formatDate(DateTime date) {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Находим максимум для масштабирования
    double maxVal = data.map((e) => e.total).reduce((a, b) => a > b ? a : b);
    if (maxVal < 8.0) maxVal = 8.0;

    // Оставляем 30px сверху для общего времени и 20px снизу для даты
    double chartHeight = size.height - 50;
    double spacing = 1.6;
    double barWidth = size.width / (data.length * spacing);

    final paintDeep = Paint()..color = const Color(0xFF1A237E);
    final paintLight = Paint()..color = const Color(0xFF3F51B5);
    final paintREM = Paint()..color = const Color(0xFF9FA8DA);

    for (int i = 0; i < data.length; i++) {
      double x = i * barWidth * spacing + (barWidth * (spacing - 1) / 2);
      if (data[i].total <= 0) {
        // Отрисуем хотя бы дату для пустых дней
        _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
        continue;
      }

      double totalHeight = (data[i].total / maxVal) * chartHeight;
      double currentY = size.height - 20; // Начало отрисовки (над датой)

      // 1. Deep (снизу)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].deep,
        data[i].total,
        paintDeep,
        isBottom: true,
      );
      currentY -= totalHeight * (data[i].deep / data[i].total);

      // 2. Light (середина)
      _drawSegment(canvas, x, currentY, barWidth, totalHeight, data[i].light, data[i].total, paintLight);
      currentY -= totalHeight * (data[i].light / data[i].total);

      // 3. REM (верх)
      _drawSegment(
        canvas,
        x,
        currentY,
        barWidth,
        totalHeight,
        data[i].rem,
        data[i].total,
        paintREM,
        isTop: true,
      );
      double topOfBar = currentY - (totalHeight * (data[i].rem / data[i].total));

      // --- ТЕКСТ: Общее время (над столбиком) ---
      _drawText(canvas, _formatHours(data[i].total), x, topOfBar - 18, barWidth, isBold: true);

      // --- ТЕКСТ: Дата dd.mm (под столбиком) ---
      _drawText(canvas, _formatDate(data[i].date), x, size.height - 15, barWidth, isDate: true);
    }
  }

  // Универсальный метод отрисовки текста
  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double width, {
    bool isBold = false,
    bool isDate = false,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDate ? Colors.white54 : Colors.white,
          fontSize: isDate ? 9 : 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: width + 10);

    textPainter.paint(canvas, Offset(x + (width - textPainter.width) / 2, y));
  }

  void _drawSegment(
    Canvas canvas,
    double x,
    double y,
    double width,
    double totalHeight,
    double phaseValue,
    double totalValue,
    Paint paint, {
    bool isTop = false,
    bool isBottom = false,
  }) {
    double h = totalHeight * (phaseValue / totalValue);
    if (h <= 0) return;

    Rect rect = Rect.fromLTWH(x, y - h, width, h);

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: isTop ? const Radius.circular(4) : Radius.zero,
        topRight: isTop ? const Radius.circular(4) : Radius.zero,
        bottomLeft: isBottom ? const Radius.circular(4) : Radius.zero,
        bottomRight: isBottom ? const Radius.circular(4) : Radius.zero,
      ),
      paint,
    );

    // Подпись внутри фазы (если влезет по высоте)
    if (h > 15) {
      final tp = TextPainter(
        text: TextSpan(
          text: _formatHours(phaseValue),
          style: const TextStyle(color: Colors.white, fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);

      tp.paint(canvas, Offset(x + (width - tp.width) / 2, y - h + (h - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant MultiPhaseSleepPainter oldDelegate) => oldDelegate.data != data;
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const LegendItem({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
      ],
    );
  }
}
