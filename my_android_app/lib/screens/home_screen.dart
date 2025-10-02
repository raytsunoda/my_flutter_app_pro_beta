// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'navigation_screen.dart';
import 'package:my_android_app/utils/notification_helper.dart';


class HomeScreen extends StatelessWidget {
  final List<List<dynamic>> csvData;

  const HomeScreen({super.key, required this.csvData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFBEE9E8),
              Color(0xFFE3F6F5),
              Color(0xFFEDF6F9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '幸せ感ナビに\nようこそ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: sendTestNotification,
                child: Text('テスト通知を送信'),
              ),


              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NavigationScreen(csvData: csvData),
                    ),
                  );
                },
                child: const Text("ナビゲーション画面へ"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

