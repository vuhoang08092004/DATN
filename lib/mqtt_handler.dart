import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

class MqttHandler {
  late MqttServerClient client;
  final String server = "1cd0dd22e420445baf80ca06cb7c4851.s1.eu.hivemq.cloud";
  final String user = "vuhoang20222539";
  final String pass = "mklahoangA1";

  // Định nghĩa các Topic đồng bộ chính xác với mạch ESP32
  final String sensorTopic = "esp32/sensors";
  final String commandTopic = "esp32/control";

  Future<void> connect({
    required Function(String) onMessage,
    required Function onConnected,
    required Function onDisconnected,
  }) async {
    // Sinh Client ID ngẫu nhiên cho App để tránh trùng lặp
    final String uniqueClientId =
        'Flutter_Hoang_${DateTime.now().millisecondsSinceEpoch}';

    client = MqttServerClient.withPort(server, uniqueClientId, 8883);

    // --- KHU VỰC CẤU HÌNH BẢO MẬT (SSL/TLS BẮT BUỘC CHO HIVEMQ CLOUD) ---
    client.secure = true;
    client.securityContext = SecurityContext.defaultContext;
    client.onBadCertificate = (dynamic certificate) => true;
    // -----------------------------------------------------------------

    // Tăng thời gian KeepAlive lên 60s để HiveMQ không đá kết nối khi mạng hơi lag
    client.setProtocolV311();
    client.keepAlivePeriod = 60;

    // Bật log nội bộ của MQTT để nếu lỗi, Terminal sẽ in ra lỗi màu đỏ cực kỳ chi tiết
    client.logging(on: true);

    // Cấu hình các callback trạng thái
    client.onConnected = () {
      print("MQTT: Đã kết nối thành công tới HiveMQ Cloud!");
      onConnected();
    };
    client.onDisconnected = () {
      print("MQTT: Đã ngắt kết nối!");
      onDisconnected();
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(uniqueClientId)
        .authenticateAs(user, pass)
        .startClean();
    client.connectionMessage = connMessage;

    try {
      print("MQTT: Đang bắt đầu kết nối bảo mật...");
      await client.connect();

      // Lắng nghe dữ liệu (cảm biến)
      client.subscribe(sensorTopic, MqttQos.atLeastOnce);

      // Lắng nghe dữ liệu đổ về từ ESP32
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        print("MQTT: Nhận dữ liệu mới -> $message");
        onMessage(message);
      });
    } catch (e) {
      print("MQTT: Lỗi kết nối -> $e");
      client.disconnect();
    }
  }

  // Hàm gốc gửi chuỗi văn bản thuần xuống ESP32 (Giữ QoS 1)
  void sendCommand(String message) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);

      print("MQTT: Đang gửi lệnh -> $message");

      client.publishMessage(
        commandTopic,
        MqttQos.atLeastOnce, // Bắt buộc QoS 1 theo yêu cầu
        builder.payload!,
      );
    } else {
      print("MQTT: Không thể gửi lệnh, chưa kết nối Cloud!");
    }
  }

  // =========================================================================
  // CÁC HÀM MỞ RỘNG MỚI: ĐÃ DỌN DẸP SẠCH CÁC HÀM ĐIỀU KHIỂN CŨ
  // =========================================================================

  /// 1. Hàm gửi cấu hình Chế độ (NORMAL, NIGHT, ECO)
  void sendModeConfig(String modeCode) {
    Map<String, dynamic> payload = {"mode": modeCode};
    sendCommand(jsonEncode(payload));
  }

  /// 2. Hàm gửi cấu hình thay đổi Chu kỳ lấy mẫu dữ liệu (chế độ ECO)
  void sendUpdateInterval(int intervalSeconds) {
    Map<String, dynamic> payload = {"interval": intervalSeconds};
    sendCommand(jsonEncode(payload));
  }

  /// 3. Hàm gửi cấu hình đặt Ngưỡng tuổi thọ tối đa cho Màng lọc (Đơn vị: Giờ)
  void sendFilterMaxLifetime(int hours) {
    Map<String, dynamic> payload = {"set_filter_max": hours};
    sendCommand(jsonEncode(payload));
  }

  /// 4. Hàm gửi lệnh xác nhận đã thay màng lọc mới (Reset bộ đếm về 0)
  void sendResetFilterCommand() {
    Map<String, dynamic> payload = {"reset_filter": 1};
    sendCommand(jsonEncode(payload));
  }

  // =========================================================================
  void sendMuteAlarm() {
    Map<String, dynamic> payload = {"mute_alarm": 1};
    sendCommand(jsonEncode(payload));
  }

  void disconnect() {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      client.disconnect();
    }
  }
}
