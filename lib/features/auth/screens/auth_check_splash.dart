import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../subscription/subscription_service.dart';
import '../../ui/android_home.dart';
import '../../ui/windows_home.dart';
import '../services/auth_api_service.dart';
import 'auth_welcome_screen.dart';

class AuthCheckSplashScreen extends StatefulWidget {
  const AuthCheckSplashScreen({super.key});

  @override
  State<AuthCheckSplashScreen> createState() => _AuthCheckSplashScreenState();
}

class _AuthCheckSplashScreenState extends State<AuthCheckSplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAndRestoreSession();
  }

  Future<void> _checkAndRestoreSession() async {
    try {
      await AuthApiService.instance.initialize();
      await SubscriptionService.instance.initialize();
    } catch (e) {
      debugPrint('Error restoring session during splash: $e');
    }

    if (!mounted) return;

    final isAuthed = AuthApiService.instance.isAuthenticated || SubscriptionService.instance.isLoggedIn;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) {
          if (Platform.isWindows) {
            return const WindowsHomeScreen();
          } else {
            return isAuthed ? const AndroidHomeScreen() : const AuthWelcomeScreen();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                size: 60,
                color: AppColors.primaryAccent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PhoneCam',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppColors.primaryAccent, strokeWidth: 2.5),
            const SizedBox(height: 16),
            const Text(
              'Restoring session...',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
