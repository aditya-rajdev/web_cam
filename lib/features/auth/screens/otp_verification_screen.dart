import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../ui/android_home.dart';
import '../../ui/windows_home.dart';
import '../models/auth_models.dart';
import '../services/auth_api_service.dart';
import '../widgets/otp_input_field.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String? name;
  final AuthFlowType flow;
  final String? initialInfoMessage;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.name,
    required this.flow,
    this.initialInfoMessage,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _authApi = AuthApiService.instance;

  String _otpCode = '';
  bool _isLoading = false;
  String? _errorMessage;
  late String? _infoMessage;

  int _cooldownSeconds = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _infoMessage = widget.initialInfoMessage;
    _startCooldown();
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldownSeconds > 0) {
        setState(() => _cooldownSeconds--);
      } else {
        t.cancel();
      }
    });
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '$name***@$domain';
    return '${name[0]}***${name[name.length - 1]}@$domain';
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => Platform.isWindows ? const WindowsHomeScreen() : const AndroidHomeScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _handleVerify() async {
    if (_otpCode.length != 8) {
      setState(() => _errorMessage = 'Please enter all 8 digits of the OTP code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final AuthApiResponse response;
    if (widget.flow == AuthFlowType.login) {
      response = await _authApi.verifyLoginOtp(widget.email, _otpCode);
    } else {
      response = await _authApi.verifyRegistrationOtp(
        widget.name ?? '',
        widget.email,
        _otpCode,
      );
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (response.isSuccess) {
      _navigateToDashboard();
    } else if (response.isPendingBackend) {
      setState(() {
        _infoMessage = response.message;
      });
    } else {
      setState(() {
        _errorMessage = response.message;
      });
    }
  }

  Future<void> _handleResend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final AuthApiResponse response;
    if (widget.flow == AuthFlowType.register) {
      response = await _authApi.sendRegistrationOtp(widget.name ?? '', widget.email);
    } else {
      response = await _authApi.sendLoginOtp(widget.email);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (response.isSuccess || response.isPendingBackend) {
      setState(() {
        _infoMessage = response.message;
      });
      _startCooldown();
    } else {
      setState(() {
        _errorMessage = response.message;
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = widget.flow == AuthFlowType.register;
    final bool isVerifyEnabled = !_isLoading && _otpCode.length == 8;

    return Scaffold(
      appBar: AppBar(
        title: Text(isRegister ? 'Verify Registration' : 'Verify Email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Title Header
              Text(
                isRegister ? 'Verify Registration' : 'Verify Your Email',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              const Text(
                'We\'ve sent an 8-digit verification code to your email.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),

              // Target Email Card with Change option
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mark_email_read_outlined, size: 20, color: AppColors.primaryAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.name != null && widget.name!.isNotEmpty)
                            Text(
                              widget.name!,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          Text(
                            _maskEmail(widget.email),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Change Email', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Error Banner
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Info / Pending Notice Banner
              if (_infoMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondaryAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.secondaryAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _infoMessage!,
                          style: const TextStyle(color: AppColors.secondaryAccent, fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 8-Digit OTP Input Field Component
              OtpInputField(
                length: 8,
                enabled: !_isLoading,
                hasError: _errorMessage != null,
                onChanged: (code) {
                  setState(() {
                    _otpCode = code;
                    _errorMessage = null;
                  });
                },
                onCompleted: (code) {
                  setState(() {
                    _otpCode = code;
                  });
                  _handleVerify();
                },
              ),
              const SizedBox(height: 20),

              // Resend OTP Cooldown
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't receive the code? ", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  TextButton(
                    onPressed: (_cooldownSeconds > 0 || _isLoading) ? null : _handleResend,
                    child: Text(
                      _cooldownSeconds > 0 ? 'Resend in ${_cooldownSeconds}s' : 'Resend OTP',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Verify Primary Action Button (Enabled only when 8 digits are entered)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: isVerifyEnabled ? _handleVerify : null,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isRegister ? 'Verify & Create Account' : 'Verify & Sign In',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
