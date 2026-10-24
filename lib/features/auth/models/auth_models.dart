enum AuthFlowType {
  login,
  register,
}

class AuthUser {
  final String id;
  final String email;
  final String name;

  AuthUser({
    required this.id,
    required this.email,
    required this.name,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
    };
  }
}

class AuthApiResponse {
  final bool isSuccess;
  final String message;
  final String? token;
  final AuthUser? user;
  final bool isPendingBackend;

  AuthApiResponse({
    required this.isSuccess,
    required this.message,
    this.token,
    this.user,
    this.isPendingBackend = false,
  });

  factory AuthApiResponse.success({
    required String message,
    String? token,
    AuthUser? user,
  }) {
    return AuthApiResponse(
      isSuccess: true,
      message: message,
      token: token,
      user: user,
    );
  }

  factory AuthApiResponse.error(String message) {
    return AuthApiResponse(
      isSuccess: false,
      message: message,
    );
  }

  factory AuthApiResponse.pendingBackend(String message) {
    return AuthApiResponse(
      isSuccess: false,
      isPendingBackend: true,
      message: message,
    );
  }
}
