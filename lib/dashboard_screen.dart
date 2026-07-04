import 'package:flutter/material.dart';
import 'dart:convert';
import 'history_screen.dart';

class DashboardScreen extends StatelessWidget {
  final String status,
      temp,
      humid,
      aqi,
      co2,
      co,
      dust,
      activeMode; // Tên Mode trả về từ ESP32 ("NORMAL", "NIGHT", "ECO")

  // [MỚI] 3 biến nhận chu kỳ đo (đơn vị: giây) từ chuỗi JSON của ESP32 gửi lên
  final int intNorm;
  final int intNight;
  final int intEco;

  final Function(String) onModeChanged;
  final Function(String) onSendMessage;
  final VoidCallback onLogout;

  // Thành phần đồng bộ màng lọc
  final double filterUsed; // Phần trăm màng lọc đã dùng (0.0 -> 100.0)
  final bool isFilterExpired; // Trạng thái màng lọc hết hạn
  final Function(int)
  onFilterMaxChanged; // Callback đổi tuổi thọ màng lọc (giờ)
  final VoidCallback onResetFilter; // Callback khôi phục bộ đếm màng lọc

  // Khởi tạo Static Controller bên ngoài hàm build để không bị reset khi re-render
  static final TextEditingController _filterMaxController =
      TextEditingController();
  static final TextEditingController _intervalController =
      TextEditingController();

  const DashboardScreen({
    super.key,
    required this.status,
    required this.temp,
    required this.humid,
    required this.aqi,
    required this.co2,
    required this.co,
    required this.dust,
    required this.activeMode,
    required this.intNorm,
    required this.intNight,
    required this.intEco,
    required this.onModeChanged,
    required this.onLogout,
    required this.onSendMessage,
    required this.filterUsed,
    required this.isFilterExpired,
    required this.onFilterMaxChanged,
    required this.onResetFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildConnectionStatus(),

          _sectionTitle("CHẾ ĐỘ HOẠT ĐỘNG"),
          _buildModeGrid(context),

          // [MỚI] Hiển thị chu kỳ đo hiện tại của chế độ đang chọn và nút chỉnh sửa
          _buildIntervalCard(context),

          // Banner cảnh báo tự động hiển thị nếu có chỉ số vượt ngưỡng an toàn
          _buildAlertBanner(),

          _sectionTitle("GIÁM SÁT DỮ LIỆU"),
          _buildDataMonitor(context),

          _sectionTitle("CÀI ĐẶT THÔNG SỐ THIẾT BỊ"),
          _buildAdvancedConfigSection(context),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[50],
            ),
            onPressed: onLogout,
            icon: const Icon(Icons.logout, color: Colors.black87),
            label: const Text(
              "Đăng xuất",
              style: TextStyle(color: Colors.black87),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // =========================================================================
  // [MỚI] KHỐI HIỂN THỊ VÀ CẬP NHẬT CHU KỲ ĐO (INTERVAL CARD)
  // =========================================================================
  int _getActiveInterval() {
    switch (activeMode) {
      case "NIGHT":
        return intNight;
      case "ECO":
        return intEco;
      case "NORMAL":
      default:
        return intNorm;
    }
  }

  String _formatInterval(int seconds) {
    if (seconds >= 60 && seconds % 60 == 0) {
      return "${seconds ~/ 60} phút ($seconds giây)";
    }
    return "$seconds giây";
  }

  Widget _buildIntervalCard(BuildContext context) {
    int currentSec = _getActiveInterval();
    String modeName = activeMode == "NORMAL"
        ? "Tiêu chuẩn"
        : (activeMode == "NIGHT" ? "Ban đêm" : "Tiết kiệm");
    Color cardColor = activeMode == "NORMAL"
        ? Colors.blue
        : (activeMode == "NIGHT" ? Colors.indigo : Colors.green);

    return Container(
      margin: const EdgeInsets.only(left: 15, right: 15, top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: cardColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Chu kỳ gửi dữ liệu ($modeName):",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  "${_formatInterval(currentSec)} / lần",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cardColor,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => _showEditIntervalDialog(context, currentSec),
            icon: const Icon(Icons.edit, color: Colors.white, size: 14),
            label: const Text(
              "Đổi chu kỳ",
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditIntervalDialog(BuildContext context, int currentSeconds) {
    _intervalController.text = currentSeconds.toString();
    String modeName = activeMode == "NORMAL"
        ? "Tiêu chuẩn (NORMAL)"
        : (activeMode == "NIGHT" ? "Ban đêm (NIGHT)" : "Tiết kiệm (ECO)");

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text(
                "Đổi Chu Kỳ Đo",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Đang cài đặt cho chế độ: $modeName",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Nhập số giây mới",
                  suffixText: "giây",
                  border: OutlineInputBorder(),
                  hintText: "Ví dụ: 30, 60, 1800...",
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "*Lưu ý: Normal tối thiểu 5s; Night và Eco tối thiểu 60s.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () {
                int? newSec = int.tryParse(_intervalController.text);
                if (newSec != null) {
                  // Validate giới hạn an toàn
                  if (activeMode == "NORMAL" && newSec < 5) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Chế độ Normal phải từ 5 giây trở lên!"),
                      ),
                    );
                    return;
                  }
                  if ((activeMode == "NIGHT" || activeMode == "ECO") &&
                      newSec < 60) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Chế độ Night/Eco phải từ 60 giây (1 phút) trở lên!",
                        ),
                      ),
                    );
                    return;
                  }

                  // Xác định key JSON cần gửi dựa theo chế độ đang chạy
                  String jsonKey = "set_normal_interval";
                  if (activeMode == "NIGHT") {
                    jsonKey = "set_night_interval";
                  } else if (activeMode == "ECO") {
                    jsonKey = "set_eco_interval";
                  }

                  // Gửi lệnh xuống ESP32
                  onSendMessage(jsonEncode({jsonKey: newSec}));
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Đã gửi lệnh đổi chu kỳ mới: $newSec giây!",
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                "Cập Nhật",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================================
  // LOGIC & GIAO DIỆN KHỐI: CẢNH BÁO MÔI TRƯỜNG
  // =========================================================================
  List<String> _getSystemAlerts() {
    List<String> alerts = [];

    double? t = double.tryParse(temp);
    if (t != null) {
      if (t > 32.0) {
        alerts.add("Nhiệt độ đang khá nóng (${t.toStringAsFixed(1)} °C)");
      } else if (t < 20.0) {
        alerts.add("Nhiệt độ phòng đang lạnh (${t.toStringAsFixed(1)} °C)");
      }
    }

    double? pm = double.tryParse(dust);
    if (pm != null) {
      if (pm > 150) {
        alerts.add("Rất nguy hại, Chỉ số bụi: ($pm µg/m³)");
      } else if (pm > 55) {
        alerts.add("Nguy hại, Chỉ số bụi: ($pm µg/m³)");
      } else if (pm > 35) {
        alerts.add("Kém, Chỉ số bụi: ($pm µg/m³)");
      } else if (pm > 12) {
        alerts.add("Trung bình, Chỉ số bụi: ($pm µg/m³)");
      }
    }

    double? a = double.tryParse(aqi);
    if (a != null) {
      if (a > 200) {
        alerts.add("Rất xấu/Nguy hại, chỉ số AQI:  ($a)");
      } else if (a > 150) {
        alerts.add("Xấu, chỉ số AQI: ($a)");
      } else if (a > 100) {
        alerts.add("Kém, chỉ số AQI: ($a)");
      } else if (a > 50) {
        alerts.add("Trung bình, chỉ số AQI: ($a)");
      }
    }

    return alerts;
  }

  Widget _buildAlertBanner() {
    List<String> alerts = _getSystemAlerts();
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 15, right: 15, bottom: 10, top: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Text(
                "CẢNH BÁO MÔI TRƯỜNG",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.redAccent, thickness: 0.5),
          ...alerts.map(
            (msg) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 8),
                    child: Icon(Icons.circle, size: 8, color: Colors.redAccent),
                  ),
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // GIAO DIỆN KHỐI: CHẾ ĐỘ HOẠT ĐỘNG (3 MODE)
  // =========================================================================
  Widget _buildModeGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          _modeBtn(
            context,
            "NORMAL",
            "Tiêu chuẩn",
            Icons.health_and_safety,
            Colors.blue,
          ),
          _modeBtn(context, "NIGHT", "Ban đêm", Icons.bedtime, Colors.indigo),
          _modeBtn(context, "ECO", "Tiết kiệm", Icons.eco, Colors.green),
        ],
      ),
    );
  }

  Widget _modeBtn(
    BuildContext context,
    String modeCode,
    String displayName,
    IconData icon,
    Color color,
  ) {
    bool isActive = activeMode == modeCode;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 40) / 2.1,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () => _changeMode(modeCode),
        icon: Icon(icon, color: isActive ? Colors.white : color),
        label: Text(
          displayName,
          style: TextStyle(
            color: isActive ? Colors.white : color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? color : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color, width: 1),
          ),
        ),
      ),
    );
  }

  void _changeMode(String modeCode) {
    onModeChanged(modeCode);
    onSendMessage(jsonEncode({"mode": modeCode}));
  }

  // =========================================================================
  // GIAO DIỆN KHỐI: GIÁM SÁT DỮ LIỆU CẢM BIẾN
  // =========================================================================
  Widget _buildDataMonitor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        children: [
          _dataCard(
            context,
            "Chỉ số AQI",
            aqi,
            Icons.wb_cloudy,
            Colors.green,
            "AQI",
          ),
          _dataCard(
            context,
            "Nhiệt độ",
            "$temp °C",
            Icons.thermostat,
            Colors.orange,
            "Nhiệt độ",
          ),
          _dataCard(
            context,
            "Độ ẩm",
            "$humid %",
            Icons.water_drop,
            Colors.blue,
            "Độ ẩm",
          ),
          _dataCard(
            context,
            "Nồng độ CO2",
            "$co2 ppm",
            Icons.co2,
            Colors.purple,
            "CO2",
          ),
          _dataCard(
            context,
            "Chỉ số CO",
            "$co ppm",
            Icons.gas_meter,
            Colors.deepOrange,
            "CO",
          ),
          _dataCard(
            context,
            "Bụi mịn PM2.5",
            "$dust μg/m3",
            Icons.grain,
            Colors.redAccent,
            "PM2.5",
          ),
        ],
      ),
    );
  }

  Widget _dataCard(
    BuildContext context,
    String t,
    String v,
    IconData i,
    Color c,
    String n,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(i, color: c),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(
          v,
          style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => HistoryScreen(sensorName: n)),
        ),
      ),
    );
  }

  // =========================================================================
  // GIAO DIỆN KHỐI: CÀI ĐẶT THÔNG SỐ THIẾT BỊ & KIỂM TRA MÀNG LỌC
  // =========================================================================
  Widget _buildAdvancedConfigSection(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Cài đặt giới hạn màng lọc:",
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                SizedBox(
                  width: 90,
                  height: 40,
                  child: TextField(
                    controller: _filterMaxController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "1500",
                      suffixText: "h",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.save_rounded, color: Colors.green),
                  onPressed: () {
                    int? hours = int.tryParse(_filterMaxController.text);
                    if (hours != null && hours >= 1) {
                      onFilterMaxChanged(hours);
                      onSendMessage(jsonEncode({"set_filter_max": hours}));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Đã lưu giới hạn màng lọc mới: $hours giờ",
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Thời gian đặt phải lớn hơn hoặc bằng 1 giờ!",
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 15),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.analytics_rounded, color: Colors.white),
                label: const Text(
                  "KIỂM TRA MÀNG LỌC",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onPressed: () => _showFilterCheckDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // THUẬT TOÁN & POPUP DIALOG CHI TIẾT
  // =========================================================================
  void _showFilterCheckDialog(BuildContext context) {
    int maxHours = int.tryParse(_filterMaxController.text) ?? 1500;
    double elapsedHours = (filterUsed / 100.0) * maxHours;
    double remainingHours = maxHours - elapsedHours;
    if (remainingHours < 0) remainingHours = 0;

    DateTime now = DateTime.now();
    DateTime estimatedReplaceDate = now.add(
      Duration(minutes: (remainingHours * 60).round()),
    );

    String estDateStr =
        "${estimatedReplaceDate.day.toString().padLeft(2, '0')}/"
        "${estimatedReplaceDate.month.toString().padLeft(2, '0')}/"
        "${estimatedReplaceDate.year}";

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.health_and_safety_rounded,
                color: isFilterExpired ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 10),
              const Text(
                "Phân Tích Màng Lọc",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              const SizedBox(height: 8),
              _infoPopupRow(
                "Mức độ hao mòn:",
                "${filterUsed.toStringAsFixed(1)} %",
                isFilterExpired ? Colors.red : Colors.orange,
              ),
              _infoPopupRow(
                "Thời hạn màng lọc:",
                "$maxHours giờ chạy",
                Colors.blueGrey,
              ),
              _infoPopupRow(
                "Đã sử dụng:",
                "${elapsedHours.toStringAsFixed(1)} giờ",
                Colors.indigo,
              ),
              _infoPopupRow(
                "Dự kiến thay mới:",
                isFilterExpired ? "CẦN THAY NGAY" : estDateStr,
                isFilterExpired ? Colors.red : Colors.green,
                isBoldValue: true,
              ),
              const SizedBox(height: 16),
              const Text(
                "*Thời gian dự kiến chỉ mang tính chất tham khảo.",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              child: const Text("Đóng lại"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                "VỪA THAY MÀNG",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              onPressed: () {
                onResetFilter();
                onSendMessage(jsonEncode({"reset_filter": 1}));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Đã Reset bộ đếm màng lọc trên bo mạch về 0 giờ!",
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _infoPopupRow(
    String label,
    String value,
    Color valueColor, {
    bool isBoldValue = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBoldValue ? FontWeight.w900 : FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    bool isC = status.contains("Đã kết nối");
    return Container(
      width: double.infinity,
      color: isC ? Colors.green[50] : Colors.red[50],
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Text(
          status,
          style: TextStyle(color: isC ? Colors.green : Colors.red),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.all(15),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        t,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
        ),
      ),
    ),
  );
}
