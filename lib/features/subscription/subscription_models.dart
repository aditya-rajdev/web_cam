class UserAccount {
  final int id;
  final String email;
  final bool isAdmin;

  UserAccount({required this.id, required this.email, required this.isAdmin});

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id'] ?? 0,
      email: json['email'] ?? '',
      isAdmin: json['is_admin'] ?? false,
    );
  }
}

class TrialStatus {
  final bool hasClaimedTrial;
  final bool trialActive;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int remainingSeconds;

  TrialStatus({
    required this.hasClaimedTrial,
    required this.trialActive,
    this.startedAt,
    this.expiresAt,
    required this.remainingSeconds,
  });

  factory TrialStatus.fromJson(Map<String, dynamic> json) {
    return TrialStatus(
      hasClaimedTrial: json['has_claimed_trial'] ?? false,
      trialActive: json['trial_active'] ?? false,
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      remainingSeconds: json['remaining_seconds'] ?? 0,
    );
  }

  String get remainingHoursText {
    if (remainingSeconds <= 0) return 'Expired';
    final hours = remainingSeconds ~/ 3600;
    final mins = (remainingSeconds % 3600) ~/ 60;
    return '${hours}h ${mins}m remaining';
  }
}

class SubscriptionStatus {
  final bool hasActiveSubscription;
  final String? planId;
  final String? planName;
  final String? status;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;

  SubscriptionStatus({
    required this.hasActiveSubscription,
    this.planId,
    this.planName,
    this.status,
    this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
  });

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      hasActiveSubscription: json['has_active_subscription'] ?? false,
      planId: json['plan_id'],
      planName: json['plan_name'],
      status: json['status'],
      currentPeriodEnd: json['current_period_end'] != null ? DateTime.parse(json['current_period_end']) : null,
      cancelAtPeriodEnd: json['cancel_at_period_end'] ?? false,
    );
  }
}

class Entitlements {
  final int userId;
  final bool hasProAccess;
  final String accessReason; // "trial", "active_subscription", or "expired"
  final TrialStatus trialStatus;
  final SubscriptionStatus subscriptionStatus;
  final int linkedDeviceCount;
  final int maxDevices;

  Entitlements({
    required this.userId,
    required this.hasProAccess,
    required this.accessReason,
    required this.trialStatus,
    required this.subscriptionStatus,
    required this.linkedDeviceCount,
    required this.maxDevices,
  });

  factory Entitlements.fromJson(Map<String, dynamic> json) {
    return Entitlements(
      userId: json['user_id'] ?? 0,
      hasProAccess: json['has_pro_access'] ?? false,
      accessReason: json['access_reason'] ?? 'expired',
      trialStatus: TrialStatus.fromJson(json['trial_status'] ?? {}),
      subscriptionStatus: SubscriptionStatus.fromJson(json['subscription_status'] ?? {}),
      linkedDeviceCount: json['linked_device_count'] ?? 0,
      maxDevices: json['max_devices'] ?? 3,
    );
  }
}

class SubscriptionPlan {
  final String planId;
  final String name;
  final String billingInterval;
  final int priceCents;
  final String currency;
  final bool isActive;

  SubscriptionPlan({
    required this.planId,
    required this.name,
    required this.billingInterval,
    required this.priceCents,
    required this.currency,
    required this.isActive,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      planId: json['plan_id'] ?? '',
      name: json['name'] ?? '',
      billingInterval: json['billing_interval'] ?? '',
      priceCents: json['price_cents'] ?? 0,
      currency: json['currency'] ?? 'USD',
      isActive: json['is_active'] ?? true,
    );
  }

  String get formattedPrice {
    final dollars = priceCents / 100.0;
    return '\$${dollars.toStringAsFixed(2)} / ${billingInterval == "monthly" ? "mo" : "yr"}';
  }
}

class LinkedDevice {
  final int id;
  final String deviceId;
  final String platform;
  final String deviceName;
  final String appVersion;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  LinkedDevice({
    required this.id,
    required this.deviceId,
    required this.platform,
    required this.deviceName,
    required this.appVersion,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory LinkedDevice.fromJson(Map<String, dynamic> json) {
    return LinkedDevice(
      id: json['id'] ?? 0,
      deviceId: json['device_id'] ?? '',
      platform: json['platform'] ?? '',
      deviceName: json['device_name'] ?? '',
      appVersion: json['app_version'] ?? '1.0.0',
      createdAt: DateTime.parse(json['created_at']),
      lastSeenAt: DateTime.parse(json['last_seen_at']),
    );
  }
}
