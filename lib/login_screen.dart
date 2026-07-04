import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final VoidCallback onLogin;

  const LoginScreen({
    super.key,
    required this.userCtrl,
    required this.passCtrl,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(25.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_sync_rounded, size: 80, color: Colors.blue),
          const SizedBox(height: 20),
          TextField(
            controller: userCtrl,
            decoration: const InputDecoration(labelText: "Tên đăng nhập"),
          ),
          TextField(
            controller: passCtrl,
            decoration: const InputDecoration(labelText: "Mật khẩu"),
            obscureText: true,
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: onLogin,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text("ĐĂNG NHẬP"),
          ),
        ],
      ),
    );
  }
}
