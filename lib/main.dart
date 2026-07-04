import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'mqtt_handler.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

// =========================================================================
// KHỞI TẠO BỘ ĐIỀU KHIỂN THÔNG BÁO TOÀN CỤC
// =========================================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('sensor_history');

  // Cấu hình Icon cho thông báo (Dùng icon mặc định của Android)
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: AirQualityApp()),
  );
}

class AirQualityApp extends StatefulWidget {
  const AirQualityApp({super.key});
  @override
  State<AirQualityApp> createState() => _AirQualityAppState();
}

class _AirQualityAppState extends State<AirQualityApp> {
  // Biến chặn spam thông báo: Chỉ kêu 1 lần khi bắt đầu có lỗi
  bool _hasPushedNotification = false;
  // Biến đếm thời gian để nhắc lại thông báo (Snooze)
  DateTime? _lastNotificationTime;
  bool _isLoggedIn = false;
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final MqttHandler _mqttHandler = MqttHandler();

  // BỘ LỌC THỜI GIAN ĐỂ CHỐNG GHI LỊCH SỬ LIÊN TỤC
  int lastRecordedHour = -1;

  // Các biến lưu trữ dữ liệu hiển thị cảm biến
  String temp = "--",
      humid = "--",
      aqi = "--",
      co2 = "--",
      coValue = "--",
      dust = "--";
  String connectionStatus = "Chưa kết nối";
  String currentMode = "NORMAL";

  // ---> [BƯỚC 1]: THÊM 3 BIẾN LƯU CHU KỲ ĐO (Đơn vị: Giây) <---
  int _intNorm = 30; // Mặc định 30s
  int _intNight = 1200; // Mặc định 20 phút (1200s)
  int _intEco = 1800; // Mặc định 30 phút (1800s)
  // -------------------------------------------------------------

  double filterUsedPercent = 0.0;
  bool isFilterExpired = false;

  // BIẾN TRẠNG THÁI BÁO ĐỘNG
  bool isAlarming = false;

  // =========================================================================
  // HÀM BẮN THÔNG BÁO RA MÀN HÌNH KHÓA ĐIỆN THOẠI
  // =========================================================================
  Future<void> _showDangerNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'high_danger_channel', // ID Kênh
          'Cảnh báo Khí Độc', // Tên Kênh
          channelDescription:
              'Kênh thông báo khẩn cấp khi phát hiện khí độc CO/CO2',
          importance: Importance.max, // Ưu tiên tối đa để nảy popup
          priority: Priority.high,
          ticker: 'ticker',
          color: Color(0xFFF44336), // Đổi màu icon thông báo thành đỏ
          enableVibration: true,
          playSound: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      id: 0,
      title: '⚠️ NGUY HIỂM: CHẤT LƯỢNG KHÔNG KHÍ XẤU',
      notificationDetails: platformChannelSpecifics,
    );
  }

  void _login() {
    if (_userController.text == "hoang" && _passController.text == "123456") {
      setState(() => _isLoggedIn = true);

      // Yêu cầu quyền gửi thông báo khi vừa đăng nhập thành công (Dành cho Android 13+)
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      _mqttHandler.connect(
        onMessage: (msg) {
          try {
            Map<String, dynamic> data = jsonDecode(msg);

            final int ts =
                data['ts'] ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
            DateTime timestampDate = DateTime.fromMillisecondsSinceEpoch(
              ts * 1000,
            );
            int currentHour = timestampDate.hour;

            // --- LOGIC LƯU TRỮ LỊCH SỬ (7 NGÀY) ---
            if (currentHour != lastRecordedHour) {
              var box = Hive.box('sensor_history');
              box.put(ts, msg);

              lastRecordedHour = currentHour;
              debugPrint("Đã chốt lưu lịch sử cho mốc: $currentHour giờ");

              final int retentionDays = 7;
              final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              final int expirationBoundary =
                  now - (retentionDays * 24 * 60 * 60);

              var expiredKeys = box.keys
                  .where((key) => key < expirationBoundary)
                  .toList();
              if (expiredKeys.isNotEmpty) {
                box.deleteAll(expiredKeys);
              }
            }

            // --- CẬP NHẬT GIAO DIỆN LIÊN TỤC ---
            setState(() {
              temp = data['temp']?.toString() ?? "--";
              humid = data['humi']?.toString() ?? "--";
              aqi = data['aqi']?.toString() ?? "--";
              co2 = data['co2']?.toString() ?? "--";
              coValue = data['co']?.toString() ?? "--";
              dust = data['pm25']?.toString() ?? "--";

              if (data.containsKey('mode')) {
                currentMode = data['mode'].toString().toUpperCase();
              }

              // ---> [BƯỚC 2]: CẬP NHẬT CHU KỲ TỪ MQTT JSON CỦA ESP32 <---
              if (data.containsKey('int_norm'))
                _intNorm = (data['int_norm'] as num).toInt();
              if (data.containsKey('int_night'))
                _intNight = (data['int_night'] as num).toInt();
              if (data.containsKey('int_eco'))
                _intEco = (data['int_eco'] as num).toInt();
              // -------------------------------------------------------------

              if (data.containsKey('filter_used')) {
                filterUsedPercent = (data['filter_used'] as num).toDouble();
              }
              if (data.containsKey('filter_alert')) {
                isFilterExpired = data['filter_alert'] == 1;
              }

              // =============================================================
              // LOGIC KÍCH HOẠT THÔNG BÁO VÀ GIAO DIỆN CẢNH BÁO
              // =============================================================
              if (data.containsKey('alarm')) {
                bool newAlarmState = data['alarm'] == 1;

                if (newAlarmState == true) {
                  DateTime now = DateTime.now();

                  // 1. Nếu đây là lúc VỪA BẮT ĐẦU phát hiện khí độc -> Kêu ngay lập tức
                  if (!_hasPushedNotification) {
                    _showDangerNotification();
                    _hasPushedNotification = true;
                    _lastNotificationTime = now; // Chốt mốc thời gian bắt đầu
                  }
                  // 2. Nếu đã báo rồi, nhưng khí VẪN ĐỘC và ĐÃ QUÁ 5 PHÚT -> Báo nhắc lại!
                  else if (_lastNotificationTime != null &&
                      now.difference(_lastNotificationTime!).inMinutes >= 5) {
                    _showDangerNotification();
                    _lastNotificationTime = now; // Cập nhật lại mốc 5 phút mới
                    debugPrint(
                      "App: Đã qua 5 phút, gửi thông báo nhắc nhở rò rỉ khí độc!",
                    );
                  }
                }
                // 3. Nếu không khí ĐÃ SẠCH -> Reset mọi cờ báo động để chuẩn bị cho lần nguy hiểm sau
                else if (newAlarmState == false) {
                  _hasPushedNotification = false;
                  _lastNotificationTime = null;
                }

                isAlarming = newAlarmState;
              }
            });
          } catch (e) {
            debugPrint("Lỗi xử lý dữ liệu: $e");
          }
        },
        onConnected: () =>
            setState(() => connectionStatus = "Đã kết nối Cloud"),
        onDisconnected: () =>
            setState(() => connectionStatus = "Bị ngắt kết nối"),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("DATN - HUST - Vu Hoang"),
        backgroundColor: isAlarming ? Colors.redAccent : Colors.blueAccent,
      ),
      body: _isLoggedIn
          ? Column(
              children: [
                // =========================================================
                // BANNER CẢNH BÁO ĐỎ CHÓT HIỆN RA KHI CÓ KHÍ ĐỘC
                // =========================================================
                if (isAlarming)
                  Container(
                    width: double.infinity,
                    color: Colors.red,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "NGUY HIỂM: KHÔNG KHÍ ĐỘC HẠI!",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red,
                            elevation: 2,
                          ),
                          onPressed: () {
                            // Gửi lệnh Mute xuống ESP32
                            _mqttHandler.sendMuteAlarm();

                            // Hiển thị thông báo Toast nhỏ cho người dùng biết
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã gửi lệnh tắt còi! Chú ý vẫn phải mở cửa.',
                                ),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          },
                          child: const Text(
                            "TẮT CÒI",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                // =========================================================
                // GIAO DIỆN CHÍNH (Đẩy xuống dưới banner bằng Expanded)
                // =========================================================
                Expanded(
                  child: DashboardScreen(
                    status: connectionStatus,
                    temp: temp,
                    humid: humid,
                    aqi: aqi,
                    co2: co2,
                    co: coValue,
                    dust: dust,
                    activeMode: currentMode,

                    // ---> [BƯỚC 3]: TRUYỀN 3 BIẾN NÀY VÀO LÀ HẾT LỖI ĐỎ <---
                    intNorm: _intNorm,
                    intNight: _intNight,
                    intEco: _intEco,

                    // -------------------------------------------------------
                    onModeChanged: (newMode) =>
                        setState(() => currentMode = newMode),
                    onSendMessage: (jsonMsg) =>
                        _mqttHandler.sendCommand(jsonMsg),

                    onLogout: () {
                      _mqttHandler.disconnect();
                      setState(() {
                        _isLoggedIn = false;
                        currentMode = "NORMAL";
                        lastRecordedHour = -1;
                        isAlarming = false;
                        _hasPushedNotification =
                            false; // Xóa cờ spam khi đăng xuất
                      });
                    },

                    filterUsed: filterUsedPercent,
                    isFilterExpired: isFilterExpired,
                    onFilterMaxChanged: (hours) {
                      debugPrint(
                        "App: Thiết lập giới hạn màng lọc -> $hours giờ",
                      );
                    },
                    onResetFilter: () {
                      setState(() {
                        filterUsedPercent = 0.0;
                        isFilterExpired = false;
                      });
                    },
                  ),
                ),
              ],
            )
          : LoginScreen(
              userCtrl: _userController,
              passCtrl: _passController,
              onLogin: _login,
            ),
    );
  }
}
