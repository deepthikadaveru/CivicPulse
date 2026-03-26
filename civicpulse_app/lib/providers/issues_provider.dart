import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/api_client.dart';
import '../core/constants/app_constants.dart';

class IssuesProvider extends ChangeNotifier {
  final _api = ApiClient();

  List<dynamic> _issues = [];
  List<dynamic> _categories = [];
  List<dynamic> _mapPins = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;
  String _mapFilter = 'all'; // all | active | resolved

  List<dynamic> get issues => _issues;
  List<dynamic> get categories => _categories;
  List<dynamic> get mapPins => _mapPins;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get mapFilter => _mapFilter;

  Future<String?> _getCityId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.cityKey);
  }

  Future<void> loadCategories({String? cityId}) async {
    final id = cityId ?? await _getCityId();
    if (id == null || id.isEmpty) {
      // Try fetching cities first then load categories
      try {
        final cities = await ApiClient().getCities();
        if (cities.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(AppConstants.cityKey, cities[0]['id']);
          _categories = await ApiClient().getCategories(cities[0]['id']);
          notifyListeners();
        }
      } catch (e) {
        _error = e.toString();
        notifyListeners();
      }
      return;
    }
    try {
      _categories = await ApiClient().getCategories(id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void setCategories(List<dynamic> cats) {
    _categories = cats;
    notifyListeners();
  }

  Future<void> loadIssues({bool refresh = false, String? status}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _issues = [];
    }
    if (!_hasMore) return;

    final cityId = await _getCityId();
    if (cityId == null) return;

    refresh ? _isLoading = true : _isLoadingMore = true;
    notifyListeners();

    try {
      final res = await _api.getIssues(
        cityId: cityId,
        status: status,
        page: _currentPage,
      );
      final newIssues = res['issues'] as List;
      final total = res['total'] as int;

      _issues.addAll(newIssues);
      _currentPage++;
      _hasMore = _issues.length < total;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadMapPins({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    final cityId = await _getCityId();
    if (cityId == null) return;
    try {
      _mapPins = await _api.getMapPins(
        cityId: cityId,
        minLng: minLng,
        minLat: minLat,
        maxLng: maxLng,
        maxLat: maxLat,
        status: _mapFilter,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void setMapFilter(String filter) {
    _mapFilter = filter;
    notifyListeners();
  }

  Future<Map<String, dynamic>> getIssueDetail(String issueId) async {
    return await _api.getIssueDetail(issueId);
  }

  Future<bool> toggleUpvote(String issueId) async {
    try {
      await _api.toggleUpvote(issueId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addComment(String issueId, String text) async {
    try {
      await _api.addComment(issueId, text);
      return true;
    } catch (_) {
      return false;
    }
  }
}
