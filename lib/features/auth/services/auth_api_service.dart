import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';
import '../../../core/security/secure_storage_helper.dart';
import '../models/auth_models.dart';

class AuthApiService {
  static final AuthApiService instance = AuthApiService._internal();
  AuthApiService._internal();

  static final _secureStorage = SecureStorageHelper.instance;

  static const String _accessTokenKey = 'phonecam_access_token';
  static const String _refreshTokenKey = 'phonecam_refresh_token';
  static const String _userEmailKey = 'phonecam_user_email';
  static const String _userNameKey = 'phonecam_user_name';

  String baseUrl = ApiConfig.baseUrl;

  bool isMockMode = false; // Real API mode active

  AuthUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;

  AuthUser? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  Map<String, String> get _headers => {
        ...ApiConfig.defaultHeaders,
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  Future<void> _writeSecure({required String key, required String value}) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<String?> _readSecure({required String key}) async {
    return await _secureStorage.read(key: key);
  }

  Future<void> _deleteSecure({required String key}) async {
    await _secureStorage.delete(key: key);
  }

  Future<void> initialize() async {
    try {
      _accessToken = await _readSecure(key: _accessTokenKey);
      _refreshToken = await _readSecure(key: _refreshTokenKey);
      final email = await _readSecure(key: _userEmailKey);
      final name = await _readSecure(key: _userNameKey);

      if (email != null && email.isNotEmpty) {
        _currentUser = AuthUser(
          id: 'usr_1',
          email: email,
          name: (name != null && name.isNotEmpty) ? name : email.split('@')[0],
        );
      }

      if (isAuthenticated) {
        await fetchUserProfile();
      }
    } catch (e) {
      debugPrint('Error initializing AuthApiService session: $e');
    }
  }

  String _parseErrorMessage(http.Response response, String fallbackMessage) {
    debugPrint('Backend HTTP ${response.statusCode} Response Body: ${response.body}');

    if (response.body.isEmpty) {
      return 'HTTP ${response.statusCode}: $fallbackMessage';
    }

    try {
      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final detail = data['detail'];

        if (detail is String) {
          return detail;
        } else if (detail is List && detail.isNotEmpty) {
          final List<String> errorMessages = [];
          for (var err in detail) {
            if (err is Map<String, dynamic>) {
              final loc = err['loc'];
              final msg = err['msg'] ?? err['type'] ?? 'Invalid value';
              final fieldName = (loc is List && loc.isNotEmpty) ? loc.last : 'field';
              errorMessages.add('$fieldName: $msg');
            } else {
              errorMessages.add(err.toString());
            }
          }
          return 'Validation Error: ${errorMessages.join(' | ')}';
        }

        if (data['message'] != null) {
          return data['message'].toString();
        }

        if (data['error'] != null) {
          return data['error'].toString();
        }
      }
    } catch (e) {
      debugPrint('Error parsing response JSON: $e');
    }

    if (response.statusCode == 422) {
      return 'Validation Error (HTTP 422): Input format does not match server schema.';
    }

    return 'HTTP ${response.statusCode}: $fallbackMessage';
  }

  Future<AuthApiResponse> sendRegistrationOtp(String name, String email) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();

    if (cleanName.isEmpty) {
      return AuthApiResponse.error('Full name is required.');
    }

    if (cleanEmail.isEmpty) {
      return AuthApiResponse.error('Email address is required.');
    }

    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return AuthApiResponse.error('Please enter a valid email address.');
    }

    if (isMockMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      return AuthApiResponse.pendingBackend(
        'Registration OTP code will be sent to $cleanEmail when connected to the backend API.',
      );
    }

    try {
      final payload = {
        'email': cleanEmail,
        'display_name': cleanName,
      };

      debugPrint('POST $baseUrl${ApiConfig.registerEndpoint} Payload: ${jsonEncode(payload)}');

      final response = await http
          .post(
            Uri.parse('$baseUrl${ApiConfig.registerEndpoint}'),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('POST ${ApiConfig.registerEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 202 || response.statusCode == 200 || response.statusCode == 201) {
        String msg = 'A verification code has been sent to $cleanEmail.';
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              msg = data['message'] ?? data['msg'] ?? data['detail'] ?? msg;
            }
          } catch (e) {
            debugPrint('Note: Response body was non-JSON: ${response.body}');
          }
        }
        return AuthApiResponse.success(message: msg);
      } else {
        return AuthApiResponse.error(_parseErrorMessage(response, 'Registration failed.'));
      }
    } on SocketException catch (_) {
      return AuthApiResponse.error('Unable to connect to $baseUrl. Check network connection.');
    } on TimeoutException catch (_) {
      return AuthApiResponse.error('Connection timed out connecting to backend.');
    } catch (e) {
      return AuthApiResponse.error('Server error occurred during registration.');
    }
  }

  Future<AuthApiResponse> sendLoginOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      return AuthApiResponse.error('Email address is required.');
    }

    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return AuthApiResponse.error('Please enter a valid email address.');
    }

    if (isMockMode) {
      await Future.delayed(const Duration(milliseconds: 600));
      return AuthApiResponse.pendingBackend(
        'A verification code will be sent to $cleanEmail when connected to the backend API.',
      );
    }

    try {
      final payload = {'email': cleanEmail};
      debugPrint('POST $baseUrl${ApiConfig.loginOtpEndpoint} Payload: ${jsonEncode(payload)}');

      final response = await http
          .post(
            Uri.parse('$baseUrl${ApiConfig.loginOtpEndpoint}'),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('POST ${ApiConfig.loginOtpEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 202 || response.statusCode == 200 || response.statusCode == 201) {
        String msg = 'A verification code has been sent to $cleanEmail.';
        if (response.body.isNotEmpty) {
          try {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic>) {
              msg = data['message'] ?? data['msg'] ?? data['detail'] ?? msg;
            }
          } catch (e) {
            debugPrint('Note: Response body was non-JSON: ${response.body}');
          }
        }
        return AuthApiResponse.success(message: msg);
      } else {
        return AuthApiResponse.error(_parseErrorMessage(response, 'Failed to send OTP code.'));
      }
    } on SocketException catch (_) {
      return AuthApiResponse.error('Unable to connect to $baseUrl. Check network connection.');
    } on TimeoutException catch (_) {
      return AuthApiResponse.error('Connection timed out connecting to backend.');
    } catch (e) {
      return AuthApiResponse.error('Server error occurred while requesting OTP code.');
    }
  }

  Future<AuthApiResponse> verifyRegistrationOtp(String name, String email, String otp) async {
    return _verifyOtp(email: email, otp: otp, name: name);
  }

  Future<AuthApiResponse> verifyLoginOtp(String email, String otp) async {
    return _verifyOtp(email: email, otp: otp);
  }

  Future<AuthApiResponse> _verifyOtp({required String email, required String otp, String? name}) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    if (cleanOtp.length < 6 || int.tryParse(cleanOtp) == null) {
      return AuthApiResponse.error('Please enter the complete numeric OTP code.');
    }

    if (isMockMode) {
      await Future.delayed(const Duration(milliseconds: 800));
      return AuthApiResponse.pendingBackend(
        'Frontend OTP verification UI ready. Waiting for backend API connection.',
      );
    }

    try {
      final payload = {
        'email': cleanEmail,
        'token': cleanOtp,
      };

      debugPrint('POST $baseUrl${ApiConfig.verifyOtpEndpoint} Payload: ${jsonEncode(payload)}');

      final response = await http
          .post(
            Uri.parse('$baseUrl${ApiConfig.verifyOtpEndpoint}'),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('POST ${ApiConfig.verifyOtpEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'] ?? data['token'];
        _refreshToken = data['refresh_token'];

        if (_accessToken != null) {
          await _writeSecure(key: _accessTokenKey, value: _accessToken!);
        }
        if (_refreshToken != null) {
          await _writeSecure(key: _refreshTokenKey, value: _refreshToken!);
        }

        await _writeSecure(key: _userEmailKey, value: cleanEmail);
        if (name != null && name.isNotEmpty) {
          await _writeSecure(key: _userNameKey, value: name);
          _currentUser = AuthUser(id: 'usr_1', email: cleanEmail, name: name);
        } else {
          _currentUser = AuthUser(id: 'usr_1', email: cleanEmail, name: cleanEmail.split('@')[0]);
        }

        // Fetch user profile and entitlements ONLY AFTER successful OTP verification
        await fetchUserProfile();
        await fetchEntitlements();

        return AuthApiResponse.success(
          message: 'Authentication successful!',
          token: _accessToken,
          user: _currentUser,
        );
      } else {
        return AuthApiResponse.error(_parseErrorMessage(response, 'Verification failed. Incorrect or expired code.'));
      }
    } on SocketException catch (_) {
      return AuthApiResponse.error('Unable to connect to $baseUrl. Check network connection.');
    } catch (e) {
      return AuthApiResponse.error('Verification failed. Server error occurred.');
    }
  }

  Future<void> fetchUserProfile() async {
    if (_accessToken == null) return;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl${ApiConfig.meEndpoint}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('GET ${ApiConfig.meEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentUser = AuthUser.fromJson(data);
        if (_currentUser?.email.isNotEmpty == true) {
          await _writeSecure(key: _userEmailKey, value: _currentUser!.email);
          await _writeSecure(key: _userNameKey, value: _currentUser!.name);
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Token is confirmed invalid/revoked by backend
        if (_refreshToken != null && _refreshToken!.isNotEmpty) {
          final refreshed = await attemptRefreshToken();
          if (!refreshed) {
            await logout();
          }
        } else {
          await logout();
        }
      }
    } on SocketException catch (_) {
      debugPrint('Network unavailable during profile check. Maintaining local authenticated session.');
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
  }

  Future<bool> attemptRefreshToken() async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh-token'),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'] ?? data['token'];
        if (data['refresh_token'] != null) {
          _refreshToken = data['refresh_token'];
          await _writeSecure(key: _refreshTokenKey, value: _refreshToken!);
        }
        if (_accessToken != null) {
          await _writeSecure(key: _accessTokenKey, value: _accessToken!);
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error refreshing token: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> fetchEntitlements() async {
    if (_accessToken == null) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl${ApiConfig.entitlementsEndpoint}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('GET ${ApiConfig.entitlementsEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching entitlements: $e');
    }
    return null;
  }

  Future<AuthApiResponse> resendOtp(String email, String purpose) async {
    final cleanEmail = email.trim().toLowerCase();

    if (isMockMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return AuthApiResponse.pendingBackend(
        'Resend request ready for backend API.',
      );
    }

    try {
      final payload = {'email': cleanEmail, 'purpose': purpose};
      final response = await http
          .post(
            Uri.parse('$baseUrl${ApiConfig.resendOtpEndpoint}'),
            headers: ApiConfig.defaultHeaders,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      debugPrint('POST ${ApiConfig.resendOtpEndpoint} Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
        return AuthApiResponse.success(message: 'A new verification code has been sent.');
      } else {
        return AuthApiResponse.error(_parseErrorMessage(response, 'Unable to resend OTP code.'));
      }
    } catch (e) {
      return AuthApiResponse.error('Unable to resend OTP. Check network connection.');
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    try {
      await _deleteSecure(key: _accessTokenKey);
      await _deleteSecure(key: _refreshTokenKey);
      await _deleteSecure(key: _userEmailKey);
      await _deleteSecure(key: _userNameKey);
    } catch (e) {
      debugPrint('Error clearing storage on logout: $e');
    }
  }
}
