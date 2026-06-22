import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mi_finca_app/features/auth/presentation/auth_screens.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AuthScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF4),
      body: Center(
        child: Image.asset(
          'assets/images/splash_mi_finca.png',
          width: 280,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}