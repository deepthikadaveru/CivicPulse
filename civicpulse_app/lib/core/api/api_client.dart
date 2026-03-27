import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // Attach JWT token to every request automatically
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: AppConstants.tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        return handler.next(error);
      },
    ));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final res =
        await _dio.post('/auth/send-otp', data: {'phone_number': phoneNumber});
    return res.data;
  }

  Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String otp, String name) async {
    final res = await _dio.post('/auth/verify-otp', data: {
      'phone_number': phoneNumber,
      'otp': otp,
      'name': name,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/auth/me');
    return res.data;
  }

  // ── Cities ────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getCities() async {
    final res = await _dio.get('/cities/');
    return res.data;
  }

  // ── Departments / Categories ──────────────────────────────────────────────

  Future<List<dynamic>> getCategories(String cityId) async {
    final res = await _dio
        .get('/departments/categories', queryParameters: {'city_id': cityId});
    return res.data;
  }

  // ── Issues ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> reportIssue(FormData formData) async {
    final res = await _dio.post(
      '/issues/',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getIssues({
    String? cityId,
    String? status,
    String? severity,
    int page = 1,
  }) async {
    final res = await _dio.get('/issues/', queryParameters: {
      if (cityId != null) 'city_id': cityId,
      if (status != null) 'status': status,
      if (severity != null) 'severity': severity,
      'page': page,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> getIssueDetail(String issueId) async {
    final res = await _dio.get('/issues/$issueId');
    return res.data;
  }

  Future<List<dynamic>> getMapPins({
    required String cityId,
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    String status = 'all',
  }) async {
    final res = await _dio.get('/issues/map-pins', queryParameters: {
      'city_id': cityId,
      'min_lng': minLng,
      'min_lat': minLat,
      'max_lng': maxLng,
      'max_lat': maxLat,
      'status': status,
    });
    return res.data;
  }

  Future<List<dynamic>> checkNearby({
    required double lat,
    required double lng,
    required String categoryId,
    required String cityId,
  }) async {
    final res = await _dio.get('/issues/check-nearby', queryParameters: {
      'latitude': lat,
      'longitude': lng,
      'category_id': categoryId,
      'city_id': cityId,
    });
    return (res.data['nearby_issues'] as List);
  }

  Future<Map<String, dynamic>> toggleUpvote(String issueId) async {
    final res = await _dio.post('/issues/$issueId/upvote');
    return res.data;
  }

  Future<Map<String, dynamic>> confirmCategory(
      String issueId, String categoryId) async {
    final res = await _dio.post('/issues/$issueId/confirm-category',
        data: {'category_id': categoryId});
    return res.data;
  }

  Future<Map<String, dynamic>> addComment(String issueId, String text) async {
    final res =
        await _dio.post('/issues/$issueId/comment', data: {'text': text});
    return res.data;
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<List<dynamic>> getNotifications() async {
    final res = await _dio.get('/notifications/');
    return res.data;
  }
}
