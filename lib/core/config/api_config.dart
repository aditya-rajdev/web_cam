class ApiConfig {
  static const String defaultBaseUrl = 'https://webcam-backend-a03l.onrender.com';

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: defaultBaseUrl,
  );

  static const String registerEndpoint = '/auth/register';
  static const String loginOtpEndpoint = '/auth/login';
  static const String verifyOtpEndpoint = '/auth/verify-otp';
  static const String resendOtpEndpoint = '/auth/resend-otp';
  static const String meEndpoint = '/auth/me';
  static const String entitlementsEndpoint = '/entitlements';

  static Map<String, String> get defaultHeaders => {
        'Content-Type': 'application/json',
      };
}
