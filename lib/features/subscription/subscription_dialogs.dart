import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'subscription_models.dart';
import 'subscription_service.dart';
import 'supabase_auth_service.dart';

class SubscriptionDialogs {
  static final _service = SubscriptionService.instance;
  static final _supaAuth = SupabaseAuthService.instance;

  static String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 2) return '$name***@$domain';
    return '${name[0]}***${name[name.length - 1]}@$domain';
  }

  static void showAuthDialog(BuildContext context, {required VoidCallback onSuccess}) {
    final emailController = TextEditingController();
    final otpController = TextEditingController();

    bool isOtpSent = false;
    bool isLoading = false;
    String? errorMessage;
    int cooldownSeconds = 0;
    Timer? cooldownTimer;

    void startCooldown() {
      cooldownSeconds = 60;
      cooldownTimer?.cancel();
      cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (cooldownSeconds > 0) {
          cooldownSeconds--;
        } else {
          t.cancel();
        }
      });
    }

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.surfaceBorder),
            ),
            title: Row(
              children: [
                const Icon(Icons.mark_email_read_rounded, color: AppColors.primaryAccent, size: 28),
                const SizedBox(width: 8),
                Text(
                  isOtpSent ? 'Enter OTP Code' : 'Sign In with Email OTP',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: AppColors.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (!isOtpSent) ...[
                    const Text(
                      'Enter your email address. We will send a 6-digit one-time pass code (OTP) to sign in securely without passwords.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        hintText: 'e.g. user@example.com',
                        prefixIcon: Icon(Icons.email_outlined, size: 18),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isLoading,
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_unread_outlined, size: 18, color: AppColors.primaryAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'OTP sent to ${_maskEmail(emailController.text)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    setState(() {
                                      isOtpSent = false;
                                      errorMessage = null;
                                      otpController.clear();
                                    });
                                  },
                            child: const Text('Change', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: otpController,
                      decoration: const InputDecoration(
                        labelText: '6-Digit OTP Code',
                        hintText: 'e.g. 123456',
                        prefixIcon: Icon(Icons.lock_clock_outlined, size: 18),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: (cooldownSeconds > 0 || isLoading)
                              ? null
                              : () async {
                                  setState(() {
                                    isLoading = true;
                                    errorMessage = null;
                                  });
                                  final err = await _supaAuth.sendEmailOtp(emailController.text);
                                  setState(() {
                                    isLoading = false;
                                    if (err != null) {
                                      errorMessage = err;
                                    } else {
                                      startCooldown();
                                    }
                                  });
                                },
                          child: Text(
                            cooldownSeconds > 0 ? 'Resend in ${cooldownSeconds}s' : 'Resend OTP Code',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        if (!isOtpSent) {
                          // Step 1: Send OTP
                          final err = await _supaAuth.sendEmailOtp(emailController.text);
                          setState(() {
                            isLoading = false;
                            if (err != null) {
                              errorMessage = err;
                            } else {
                              isOtpSent = true;
                              startCooldown();
                            }
                          });
                        } else {
                          // Step 2: Verify OTP
                          final err = await _supaAuth.verifyEmailOtp(
                            emailController.text,
                            otpController.text,
                          );

                          setState(() {
                            isLoading = false;
                          });

                          if (err == null) {
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              onSuccess();
                            }
                          } else {
                            setState(() {
                              errorMessage = err;
                            });
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isOtpSent ? 'Verify Code' : 'Send OTP Code'),
              ),
            ],
          );
        },
      ),
    );
  }

  static void showSubscriptionUpgradeSheet(BuildContext context, {required VoidCallback onUpdated}) async {
    List<SubscriptionPlan> plans = await _service.getPlans();
    String selectedPlanId = plans.isNotEmpty ? plans.first.planId : 'plan_monthly';
    bool isLoading = false;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: AppColors.primaryAccent, size: 28),
                      SizedBox(width: 8),
                      Text('PhoneCam Pro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.textPrimary)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_service.isLoggedIn && (_service.currentEntitlements?.trialStatus.hasClaimedTrial == false))
                Card(
                  color: AppColors.primaryAccent.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.primaryAccent, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt, color: AppColors.primaryAccent),
                            SizedBox(width: 6),
                            Text('3-Day Free Trial (72 Hours Exact)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('No credit card required. Free trial does NOT auto-charge.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              final success = await _service.startFreeTrial();
                              if (success && context.mounted) {
                                Navigator.pop(ctx);
                                onUpdated();
                              }
                            },
                            child: const Text('Start 72-Hour Free Trial'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              const Text('Select Subscription Plan:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 8),

              ...plans.map((p) {
                final isSelected = p.planId == selectedPlanId;
                return InkWell(
                  onTap: () => setState(() => selectedPlanId = p.planId),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryAccent.withValues(alpha: 0.15) : AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primaryAccent : AppColors.surfaceBorder,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSelected ? AppColors.primaryAccent : AppColors.textPrimary)),
                            Text('${p.billingInterval.toUpperCase()} Billing', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                        Text(p.formattedPrice, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),
              const Text('Pro Benefits:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              _buildBenefitItem('Full HD 1080p & 60 FPS Camera Streaming'),
              _buildBenefitItem('Up to 3 Linked Devices (Android + Windows)'),
              _buildBenefitItem('Manual Focus, Optical Zoom & Flashlight Torch'),
              _buildBenefitItem('DirectShow Windows Virtual WebCam Integration'),

              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (!_service.isLoggedIn) {
                            Navigator.pop(ctx);
                            showAuthDialog(context, onSuccess: () {
                              showSubscriptionUpgradeSheet(context, onUpdated: onUpdated);
                            });
                            return;
                          }

                          setState(() => isLoading = true);
                          final checkoutUrl = await _service.createCheckout(selectedPlanId);
                          setState(() => isLoading = false);

                          if (checkoutUrl != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Checkout Session Created: $checkoutUrl')),
                            );
                            Navigator.pop(ctx);
                            onUpdated();
                          }
                        },
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Text('Subscribe Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildBenefitItem(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  static void showDeviceManagementDialog(BuildContext context, {required VoidCallback onUpdated}) async {
    List<LinkedDevice> devices = await _service.getDevices();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final count = devices.length;
          final maxDev = _service.currentEntitlements?.maxDevices ?? 3;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.surfaceBorder),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.devices_rounded, color: AppColors.primaryAccent),
                    SizedBox(width: 8),
                    Text('Linked Devices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: count >= maxDev ? AppColors.warning.withValues(alpha: 0.2) : AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$count / $maxDev', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: count >= maxDev ? AppColors.warning : AppColors.success)),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: devices.isNotEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: devices.map((d) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.surfaceBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(d.platform == 'windows' ? Icons.laptop_windows : Icons.phone_android, color: AppColors.primaryAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.deviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                                    Text('ID: ${d.deviceId.length > 12 ? d.deviceId.substring(0, 12) : d.deviceId}...', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 18),
                                onPressed: () async {
                                  final ok = await _service.unlinkDevice(d.deviceId);
                                  if (ok) {
                                    final updated = await _service.getDevices();
                                    setState(() {
                                      devices = updated;
                                    });
                                    onUpdated();
                                  }
                                },
                                tooltip: 'Unlink device',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  : const Text('No devices currently linked.', style: TextStyle(color: AppColors.textSecondary)),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAccent, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
