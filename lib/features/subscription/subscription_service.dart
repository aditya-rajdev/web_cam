import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/api_config.dart';
import 'subscription_models.dart';

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._internal();
  SubscriptionService._internal();

  static const String _authTokenKey = 'phonecam_auth_token';
  static const String _deviceIdKey = 'phonecam_device_id';
  
  // Configurable Centralized Backend API Endpoint
  String baseUrl = ApiConfig.baseUrl;

  String? _token;
  String? _deviceId;
  UserAccount? _currentUser;
  Entitlements? _currentEntitlements;

  String? get token => _token;
  UserAccount? get currentUser => _currentUser;
  Entitlements? get currentEntitlements => _currentEntitlements;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_authTokenKey);
      _deviceId = prefs.getString(_deviceIdKey);

      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = 'dev_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString(_deviceIdKey, _deviceId!);
      }

      if (isLoggedIn) {
        await refreshState();
      }
    } catch (e) {
      debugPrint('Error initializing SubscriptionService: $e');
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<void> setAuthToken(String newToken, String email) async {
    _token = newToken;
    _currentUser = UserAccount(id: 1, email: email, isAdmin: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authTokenKey, _token!);
    } catch (_) {}
    await refreshState();
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _currentEntitlements = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authTokenKey);
    } catch (_) {}
  }

  Future<void> refreshState() async {
    if (!isLoggedIn) return;
    try {
      // 1. Fetch User Profile
      final meRes = await http.get(Uri.parse('$baseUrl/auth/me'), headers: _headers);
      if (meRes.statusCode == 200) {
        _currentUser = UserAccount.fromJson(jsonDecode(meRes.body));
      }

      // 2. Register Device
      await registerDevice();

      // 3. Fetch Entitlements
      final entRes = await http.get(Uri.parse('$baseUrl/entitlements'), headers: _headers);
      if (entRes.statusCode == 200) {
        _currentEntitlements = Entitlements.fromJson(jsonDecode(entRes.body));
      }
    } catch (e) {
      debugPrint('Error refreshing subscription state: $e');
    }
  }

  Future<bool> startFreeTrial() async {
    if (!isLoggedIn) return false;
    try {
      final res = await http.post(Uri.parse('$baseUrl/subscription/trial/start'), headers: _headers);
      if (res.statusCode == 200) {
        await refreshState();
        return true;
      }
    } catch (e) {
      debugPrint('Error starting free trial: $e');
    }
    return false;
  }

  Future<List<SubscriptionPlan>> getPlans() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/subscription/plans'), headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((item) => SubscriptionPlan.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching plans: $e');
    }
    return [];
  }

  Future<String?> createCheckout(String planId) async {
    if (!isLoggedIn) return null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/subscription/checkout'),
        headers: _headers,
        body: jsonEncode({'plan_id': planId}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['checkout_url'];
      }
    } catch (e) {
      debugPrint('Error creating checkout session: $e');
    }
    return null;
  }

  Future<bool> registerDevice() async {
    if (!isLoggedIn || _deviceId == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/devices/register'),
        headers: _headers,
        body: jsonEncode({
          'device_id': _deviceId,
          'platform': Platform.operatingSystem,
          'device_name': '${Platform.operatingSystem.toUpperCase()} Client',
          'app_version': '1.0.0',
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error registering device: $e');
    }
    return false;
  }

  Future<List<LinkedDevice>> getDevices() async {
    if (!isLoggedIn) return [];
    try {
      final res = await http.get(Uri.parse('$baseUrl/devices'), headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((item) => LinkedDevice.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching devices: $e');
    }
    return [];
  }

  Future<bool> unlinkDevice(String deviceId) async {
    if (!isLoggedIn) return false;
    try {
      final res = await http.delete(Uri.parse('$baseUrl/devices/$deviceId'), headers: _headers);
      if (res.statusCode == 200) {
        await refreshState();
        return true;
      }
    } catch (e) {
      debugPrint('Error unlinking device: $e');
    }
    return false;
  }
}
