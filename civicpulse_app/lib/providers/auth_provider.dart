import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/api/api_client.dart';
import '../core/constants/app_constants.dart';

class AuthProvider extends ChangeNotifier {
  final _api = ApiClient();
  final _storage = const FlutterSecureStorage();

  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _error;
  String? _otpDev; // stores OTP returned in dev mode

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get otpDev => _otpDev;
  bool get isLoggedIn => _user != null;
  String? get userId => _user?['id'];
  String? get userName => _user?['name'];
  String? get userRole => _user?['role'];

  Future<void> tryAutoLogin() async {
    final token = await _storage.read(key: AppConstants.tokenKey);
    final userData = await _storage.read(key: AppConstants.userKey);
    if (token != null && userData != null) {
      _user = jsonDecode(userData);
      notifyListeners();
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    debugPrint('Sending OTP to: ${AppConstants.baseUrl}/auth/send-otp');
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.sendOtp(phoneNumber);
      _otpDev = res['otp']?.toString(); // dev mode only
      return true;
    } catch (e) {
      _error = _parseError(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String otp, String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.verifyOtp(phoneNumber, otp, name);
      final token = res['access_token'];
      _user = res['user'];

      await _storage.write(key: AppConstants.tokenKey, value: token);
      await _storage.write(key: AppConstants.userKey, value: jsonEncode(_user));

      return true;
    } catch (e) {
      _error = _parseError(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _user = null;
    _otpDev = null;
    notifyListeners();
  }

  String _parseError(dynamic e) {
    try {
      return e.response?.data?['detail'] ?? e.toString();
    } catch (_) {
      return e.toString();
    }
  }
}
