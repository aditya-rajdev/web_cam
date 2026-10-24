import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/auth_welcome_screen.dart';
import 'features/subscription/subscription_service.dart';
import 'features/ui/windows_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (e) {
    debugPrint('Supabase init notice: $e');
  }

  try {
    await SubscriptionService.instance.initialize();
  } catch (e) {
    debugPrint('SubscriptionService init error: $e');
  }

  runApp(const PhoneCamApp());
}

class PhoneCamApp extends StatelessWidget {
  const PhoneCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhoneCam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: Platform.isWindows ? const WindowsHomeScreen() : const AuthWelcomeScreen(),
    );
  }
}
