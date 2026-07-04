import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

class HistoryScreen extends StatefulWidget {
  final String sensorName;
  const HistoryScreen({super.key, required this.sensorName});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? selectedDay;

  @override
  Widget build(BuildContext context) {
    // 1. TRUY CẬP BOX HIVE VÀ XỬ LÝ DATA GỐC
    final box = Hive.box('sensor_history');

    List<Map<String, dynamic>> rawData = box.values
        .map((e) => jsonDecode(e as String) as Map<String, dynamic>)
        .toList();

    rawData.sort((a, b) => (a['ts'] ?? 0).compareTo(b['ts'] ?? 0));

    String keyData = 'temp';
    if (widget.sensorName.contains("Nhiệt độ")) {
      keyData = 'temp';
    } else if (widget.sensorName.contains("Bụi") ||
        widget.sensorName.contains("PM2.5")) {
      keyData = 'pm25';
    } else if (widget.sensorName.contains("CO2")) {
      keyData = 'co2';
    } else if (widget.sensorName.contains("CO")) {
      keyData = 'co';
    } else if (widget.sensorName.contains("Độ ẩm")) {
      keyData = 'humi';
    }

    Map<String, List<double>> hourlyGroups = {};
    Map<String, String> xLabelMap = {};
    final DateTime nowTime = DateTime.now();

    for (var item in rawData) {
      final DateTime date = DateTime.fromMillisecondsSinceEpoch(
        (item['ts'] ?? 0) * 1000,
      );

      String uniqueHourKey =
          "${date.year}_${date.month}_${date.day}_${date.hour}";
      String labelX = "${date.hour.toString().padLeft(2, '0')}:00";

      double val =
          double.tryParse(item[keyData].toString()) ??
          (widget.sensorName.contains("CO2") ? 400.0 : 25.0);

      if (!hourlyGroups.containsKey(uniqueHourKey)) {
        hourlyGroups[uniqueHourKey] = [];
      }
      hourlyGroups[uniqueHourKey]!.add(val);
      xLabelMap[uniqueHourKey] = labelX;
    }

    List<Map<String, dynamic>> computedHistoryList = [];

    hourlyGroups.forEach((key, list) {
      double sum = list.reduce((a, b) => a + b);
      double avg = sum / list.length;

      List<String> parts = key.split('_');
      DateTime parsedDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        int.parse(parts[3]),
      );

      computedHistoryList.add({'val': avg, 'dateTime': parsedDate});
    });

    computedHistoryList = computedHistoryList.reversed.toList();

    Map<String, List<Map<String, dynamic>>> groupedByDay = {};

    for (var item in computedHistoryList) {
      final DateTime dt = item['dateTime'] as DateTime;
      String dayHeader =
          "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";

      if (dt.day == nowTime.day &&
          dt.month == nowTime.month &&
          dt.year == nowTime.year) {
        dayHeader =
            "Hôm nay (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')})";
      } else if (dt.day == nowTime.day - 1 &&
          dt.month == nowTime.month &&
          dt.year == nowTime.year) {
        dayHeader =
            "Hôm qua (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')})";
      }

      if (!groupedByDay.containsKey(dayHeader)) {
        groupedByDay[dayHeader] = [];
      }
      groupedByDay[dayHeader]!.add(item);
    }

    if (selectedDay == null && groupedByDay.isNotEmpty) {
      selectedDay = groupedByDay.keys.first;
    }

    List<double> chartYValues = [];
    List<String> chartXLabels = [];

    if (selectedDay != null && groupedByDay.containsKey(selectedDay)) {
      var dayItems = groupedByDay[selectedDay]!.reversed.toList();
      for (var item in dayItems) {
        final DateTime dt = item['dateTime'] as DateTime;
        chartYValues.add(item['val'] as double);
        chartXLabels.add("${dt.hour.toString().padLeft(2, '0')}:00");
      }
    }

    if (chartYValues.isEmpty) {
      chartYValues = [25.0, 26.0, 28.0, 25.0];
      chartXLabels = ["00:00", "06:00", "12:00", "18:00"];
    }

    double minValue = chartYValues.reduce((a, b) => a < b ? a : b);
    double maxValue = chartYValues.reduce((a, b) => a > b ? a : b);
    int minIndex = chartYValues.indexOf(minValue);
    int maxIndex = chartYValues.indexOf(maxValue);

    double minYValue = (minValue - 3).clamp(0, double.infinity);
    double maxYValue = maxValue + 4;
    if (maxYValue - minYValue < 6) maxYValue = minYValue + 10;

    Color chartColor = Colors.orange;
    if (widget.sensorName.contains("Bụi") ||
        widget.sensorName.contains("PM2.5")) {
      chartColor = Colors.green;
    } else if (widget.sensorName.contains("CO2")) {
      chartColor = Colors.purple;
    } else if (widget.sensorName.contains("CO")) {
      chartColor = Colors.amber;
    } else if (widget.sensorName.contains("Độ ẩm")) {
      chartColor = Colors.cyan;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF111214),
      appBar: AppBar(
        title: Text(
          "Lịch sử ${widget.sensorName}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF1A1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: rawData.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                // --- TIÊU ĐỀ BIỂU ĐỒ ĐANG XEM NGÀY NÀO ---
                Padding(
                  padding: const EdgeInsets.only(top: 14, left: 16, right: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Biểu đồ diễn biến: $selectedDay",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: chartColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "Độ mịn: Giờ chẵn",
                          style: TextStyle(
                            color: chartColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- PHẦN 1: BIỂU ĐỒ CỐ ĐỊNH TRÊN CÙNG ---
                Container(
                  height: 220,
                  padding: const EdgeInsets.only(
                    top: 24,
                    bottom: 4,
                    left: 12,
                    right: 24,
                  ),
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: false,
                        horizontalInterval: (maxYValue - minYValue) / 4,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white.withValues(alpha: 0.04),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: minYValue,
                      maxY: maxYValue,
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (touchedSpot) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((touchedSpot) {
                              if (touchedSpot.spotIndex == maxIndex) {
                                return const LineTooltipItem(
                                  'C',
                                  TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                );
                              }
                              if (touchedSpot.spotIndex == minIndex) {
                                return const LineTooltipItem(
                                  'T',
                                  TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                );
                              }
                              return null;
                            }).toList();
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                '${value.toStringAsFixed(0)}${widget.sensorName.contains("Nhiệt độ") ? "°" : ""}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: chartYValues.length > 6
                                ? (chartYValues.length / 5).floorToDouble()
                                : 1.0,
                            getTitlesWidget: (value, meta) {
                              int index = value.toInt();
                              if (index >= 0 && index < chartXLabels.length) {
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    chartXLabels[index],
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                      minX: 0,
                      maxX: (chartYValues.length - 1).toDouble(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: chartYValues
                              .asMap()
                              .entries
                              .map((e) => FlSpot(e.key.toDouble(), e.value))
                              .toList(),
                          isCurved: true,
                          curveSmoothness: 0.25,
                          color: chartColor,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, barData) {
                              int index = barData.spots.indexOf(spot);
                              return index == maxIndex ||
                                  index == minIndex ||
                                  index == barData.spots.length - 1;
                            },
                            getDotPainter: (spot, percent, barData, index) {
                              bool isLast = index == barData.spots.length - 1;
                              return FlDotCirclePainter(
                                radius: isLast ? 5 : 4,
                                color: isLast
                                    ? Colors.white
                                    : const Color(0xFF111214),
                                strokeWidth: 2.5,
                                strokeColor: isLast
                                    ? chartColor
                                    : Colors.white60,
                              );
                            },
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                chartColor.withValues(alpha: 0.35),
                                chartColor.withValues(alpha: 0.08),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: Colors.white.withValues(alpha: 0.05)),
                ),

                // --- PHẦN 2: DANH SÁCH CHI TIẾT THEO NGÀY (CÓ ACCORDION) ---
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Dòng thời gian chi tiết (Ấn vào tên Ngày để xem)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: groupedByDay.keys.length,
                    itemBuilder: (context, index) {
                      String dayHeader = groupedByDay.keys.elementAt(index);
                      List<Map<String, dynamic>> dayItems =
                          groupedByDay[dayHeader]!;
                      bool isCurrentSelected = selectedDay == dayHeader;

                      // Kiểm tra xem thẻ này có phải là thẻ "Hôm nay" không
                      bool isTodayCard = dayHeader.startsWith("Hôm nay");

                      // 1. Nếu là "Hôm nay", hiển thị toàn bộ danh sách thẻ giờ không cần gập
                      if (isTodayCard) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ĐÃ FIX LỖI: Bọc InkWell để ấn vào "Hôm nay" có thể xem lại biểu đồ
                            InkWell(
                              onTap: () {
                                setState(() {
                                  selectedDay = dayHeader;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      dayHeader,
                                      style: TextStyle(
                                        // Đổi màu để báo hiệu đang xem biểu đồ ngày nào
                                        color: isCurrentSelected
                                            ? chartColor
                                            : Colors.white60,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      isCurrentSelected
                                          ? Icons.bar_chart_rounded
                                          : Icons.ads_click_rounded,
                                      color: isCurrentSelected
                                          ? chartColor
                                          : Colors.white38,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ...dayItems.map((item) {
                              final DateTime dt = item['dateTime'] as DateTime;
                              final double val = item['val'] as double;
                              return _buildCleanHistoryCard(
                                dt,
                                val,
                                chartColor,
                              );
                            }),
                          ],
                        );
                      }
                      // 2. Nếu là "Ngày cũ", sử dụng ExpansionTile để gập gọn lại
                      else {
                        return Theme(
                          // Ẩn hai đường kẻ gạch trên/dưới mặc định của ExpansionTile cho đẹp
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            // Đổi màu title khi nó đang là ngày được chọn vẽ trên biểu đồ
                            title: Text(
                              dayHeader,
                              style: TextStyle(
                                color: isCurrentSelected
                                    ? chartColor
                                    : Colors.white38,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            trailing: Icon(
                              isCurrentSelected
                                  ? Icons.bar_chart_rounded
                                  : Icons.expand_more,
                              color: isCurrentSelected
                                  ? chartColor
                                  : Colors.white24,
                              size: isCurrentSelected ? 18 : 24,
                            ),
                            // Khi user bấm bung thẻ ngày cũ ra, mình bắt sự kiện cập nhật Biểu đồ ở trên cùng
                            onExpansionChanged: (isExpanded) {
                              if (isExpanded) {
                                setState(() {
                                  selectedDay = dayHeader;
                                });
                              }
                            },
                            // Danh sách các thẻ giờ sẽ nằm bên trong children
                            children: dayItems.map((item) {
                              final DateTime dt = item['dateTime'] as DateTime;
                              final double val = item['val'] as double;
                              return _buildCleanHistoryCard(
                                dt,
                                val,
                                chartColor,
                              );
                            }).toList(),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 70, color: Colors.grey[800]),
          const SizedBox(height: 12),
          const Text(
            "Chưa có dữ liệu lịch sử đo",
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanHistoryCard(DateTime dt, double val, Color cColor) {
    String displayValue = "";
    IconData icon = Icons.grain;

    if (widget.sensorName.contains("Nhiệt độ")) {
      displayValue = "${val.toStringAsFixed(1)} °C";
      icon = Icons.device_thermostat;
    } else if (widget.sensorName.contains("Bụi") ||
        widget.sensorName.contains("PM2.5")) {
      displayValue = "${val.toStringAsFixed(0)} µg/m³";
      icon = Icons.grain;
    } else if (widget.sensorName.contains("CO2")) {
      displayValue = "${val.toStringAsFixed(0)} ppm";
      icon = Icons.co2;
    } else if (widget.sensorName.contains("CO")) {
      displayValue = "${val.toStringAsFixed(2)} ppm";
      icon = Icons.gas_meter;
    } else if (widget.sensorName.contains("Độ ẩm")) {
      displayValue = "${val.toStringAsFixed(0)} %";
      icon = Icons.water_drop;
    }

    final String hourStr = "${dt.hour.toString().padLeft(2, '0')}:00";

    return Card(
      color: const Color(0xFF1A1C1E),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: cColor.withValues(alpha: 0.7), size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                displayValue,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              hourStr,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
