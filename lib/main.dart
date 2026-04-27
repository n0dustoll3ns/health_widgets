import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:health/health.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

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
  String toString() => '\nSleepDay $date: deep = $deep; light = $light; rem = $rem; ';
}

class HealthWidgetsApp extends StatefulWidget {
  const HealthWidgetsApp({super.key});
  @override
  State<HealthWidgetsApp> createState() => _HealthWidgetsAppState();
}

class _HealthWidgetsAppState extends State<HealthWidgetsApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  List<SleepDay> _sleepData = [];

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
    var now = DateTime.now();
    var range = now.subtract(const Duration(days: 7));

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: range,
      endTime: now,
    );

    setState(() {
      _sleepData = healthData.map((e) {
        double totalMinutes = (e.value as NumericHealthValue).numericValue.toDouble();
        double totalHours = totalMinutes / 60;

        if (totalHours <= 0) return SleepDay(date: e.dateFrom, deep: 0, light: 0, rem: 0);

        return SleepDay(
          date: e.dateFrom,
          deep: totalHours * 0.25,
          light: totalHours * 0.55,
          rem: totalHours * 0.20,
        );
      }).toList();
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
                const Text("Last 7 Days", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    double maxVal = data.map((e) => e.total).reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) maxVal = 8.0; // Заглушка на 8 часов, если данных нет

    double spacing = 1.6;
    double barWidth = size.width / (data.length * spacing);

    final paintDeep = Paint()..color = const Color(0xFF1A237E);
    final paintLight = Paint()..color = const Color(0xFF3F51B5);
    final paintREM = Paint()..color = const Color(0xFF9FA8DA);

    for (int i = 0; i < data.length; i++) {
      if (data[i].total <= 0) continue;

      double x = i * barWidth * spacing;
      double totalHeight = (data[i].total / maxVal) * size.height;

      // Защита от деления на 0 для сегментов
      double deepRatio = data[i].deep / data[i].total;
      double lightRatio = data[i].light / data[i].total;
      double remRatio = data[i].rem / data[i].total;

      double currentY = size.height;

      // Deep
      double hDeep = totalHeight * deepRatio;
      canvas.drawRect(Rect.fromLTWH(x, currentY - hDeep, barWidth, hDeep), paintDeep);
      currentY -= hDeep;

      // Light
      double hLight = totalHeight * lightRatio;
      canvas.drawRect(Rect.fromLTWH(x, currentY - hLight, barWidth, hLight), paintLight);
      currentY -= hLight;

      // REM
      double hRem = totalHeight * remRatio;
      canvas.drawRect(Rect.fromLTWH(x, currentY - hRem, barWidth, hRem), paintREM);
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
