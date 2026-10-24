import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_service.dart';

class SupabaseAuthService {
  static final SupabaseAuthService instance = SupabaseAuthService._internal();
  SupabaseAuthService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => _client.auth.currentSession != null;

  Future<String?> sendEmailOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return 'Please enter a valid email address.';
    }

    try {
      await _client.auth.signInWithOtp(
        email: cleanEmail,
        shouldCreateUser: true,
      );
      return null; // Success (no error message)
    } on AuthException catch (e) {
      debugPrint('Supabase AuthException: ${e.message} (code: ${e.statusCode})');
      if (e.message.toLowerCase().contains('rate limit')) {
        return 'Too many attempts. Please wait a minute before trying again.';
      }
      return 'Unable to send OTP: ${e.message}';
    } on SocketException catch (_) {
      return 'Unable to connect. Check your internet connection.';
    } catch (e) {
      debugPrint('Unexpected OTP Send Error: $e');
      return 'Authentication service unreachable. Please try again.';
    }
  }

  Future<String?> verifyEmailOtp(String email, String otpToken) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanToken = otpToken.trim();

    if (cleanToken.length < 6) {
      return 'Please enter the complete 6-digit OTP code.';
    }

    try {
      final AuthResponse response = await _client.auth.verifyOTP(
        email: cleanEmail,
        token: cleanToken,
        type: OtpType.email,
      );

      final Session? session = response.session;
      final User? user = response.user;

      if (session != null && user != null) {
        // Synchronize with SubscriptionService & FastAPI backend
        await SubscriptionService.instance.setAuthToken(
          session.accessToken,
          user.email ?? cleanEmail,
        );
        return null; // Success
      } else {
        return 'This code is invalid or expired. Request a new code.';
      }
    } on AuthException catch (e) {
      debugPrint('Supabase Verify AuthException: ${e.message}');
      if (e.message.toLowerCase().contains('invalid') ||
          e.message.toLowerCase().contains('expired')) {
        return 'This code is invalid or expired. Request a new code.';
      }
      return 'Verification failed: ${e.message}';
    } on SocketException catch (_) {
      return 'Unable to connect. Check your internet connection.';
    } catch (e) {
      debugPrint('Unexpected OTP Verify Error: $e');
      return 'Unable to verify OTP. Please request a new code.';
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Supabase SignOut Error: $e');
    }
    await SubscriptionService.instance.logout();
  }
}
