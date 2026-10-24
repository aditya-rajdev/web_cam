import 'models/auth_models.dart';
import 'services/auth_api_service.dart';

abstract class BaseAuthRepository {
  Future<AuthApiResponse> requestLoginOtp(String email);
  Future<AuthApiResponse> requestRegistrationOtp(String name, String email);
  Future<AuthApiResponse> verifyOtp({
    required String email,
    required String otp,
    required AuthFlowType flow,
    String? name,
  });
}

class AuthRepository implements BaseAuthRepository {
  static final AuthRepository instance = AuthRepository._internal();
  AuthRepository._internal();

  final _api = AuthApiService.instance;

  @override
  Future<AuthApiResponse> requestLoginOtp(String email) => _api.sendLoginOtp(email);

  @override
  Future<AuthApiResponse> requestRegistrationOtp(String name, String email) => _api.sendRegistrationOtp(name, email);

  @override
  Future<AuthApiResponse> verifyOtp({
    required String email,
    required String otp,
    required AuthFlowType flow,
    String? name,
  }) {
    if (flow == AuthFlowType.login) {
      return _api.verifyLoginOtp(email, otp);
    } else {
      return _api.verifyRegistrationOtp(name ?? '', email, otp);
    }
  }
}
