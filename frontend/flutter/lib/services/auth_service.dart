import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthService {
  final String baseUrl;

  AuthService({this.baseUrl = 'https://voice-ai-demo.your-domain.com'});

  // 请求 OTP
  Future<({bool success, String? message})> requestOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (success: data['success'] == true, message: data['message']);
      }
      return (success: false, message: 'Failed to request OTP');
    } catch (e) {
      return (success: false, message: 'Error: $e');
    }
  }

  // 验证 OTP
  Future<({bool success, String? token, String? message})> verifyOTP(
    String email,
    String code,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (
          success: data['success'] == true,
          token: data['token'],
          message: data['message']
        );
      }
      return (success: false, token: null, message: 'OTP verification failed');
    } catch (e) {
      return (success: false, token: null, message: 'Error: $e');
    }
  }

  // 验证 Session
  Future<({bool success, String? userId, Map<String, dynamic>? user})>
      verifySession(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/verify-session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (
          success: data['success'] == true,
          userId: data['userId'],
          user: data['user'] as Map<String, dynamic>?
        );
      }
      return (success: false, userId: null, user: null);
    } catch (e) {
      return (success: false, userId: null, user: null);
    }
  }
}
