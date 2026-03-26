import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/issues_provider.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  XFile? _photoFile;
  Uint8List? _photoBytes;
  XFile? _videoFile;
  double? _latitude;
  double? _longitude;
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedCategorySlug;
  String _roadType = 'none';
  bool _isSubmitting = false;
  bool _isGettingLocation = false;
  bool _categoriesLoading = false;
  bool _loadingStarted = false;

  // Road-related category slugs — only show road type for these
  final _roadRelatedSlugs = {
    'pothole',
    'road-damage',
    'broken-footpath',
    'missing-sign',
    'drainage-blocked',
    'flooding'
  };

  bool get _showRoadType =>
      _selectedCategorySlug != null &&
      _roadRelatedSlugs.contains(_selectedCategorySlug);

  final _roadTypes = [
    {'label': 'Lane / bylane', 'value': 'lane'},
    {'label': 'Main road', 'value': 'main_road'},
    {'label': 'Highway', 'value': 'highway'},
  ];

  @override
  void initState() {
    super.initState();
    _ensureCategoriesLoaded();
  }

  Future<void> _ensureCategoriesLoaded() async {
    if (_loadingStarted) return;
    _loadingStarted = true;
    setState(() => _categoriesLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? cityId = prefs.getString(AppConstants.cityKey);
      debugPrint('City ID from prefs: $cityId');

      // If no city saved, fetch cities and save the first one
      if (cityId == null || cityId.isEmpty) {
        debugPrint('No city found, fetching cities...');
        final cities = await ApiClient().getCities();
        debugPrint('Cities fetched: ${cities.length}');
        if (cities.isNotEmpty) {
          cityId = cities[0]['id'];
          await prefs.setString(AppConstants.cityKey, cityId!);
          debugPrint('City saved: $cityId');
        } else {
          debugPrint('No cities in database!');
          return;
        }
      }

      debugPrint('Fetching categories for city: $cityId');
      final categories = await ApiClient().getCategories(cityId);
      debugPrint('Categories fetched: ${categories.length}');

      if (categories.isEmpty) {
        debugPrint(
            'No categories found — make sure you ran the seed endpoint!');
        debugPrint(
            'Run: POST /api/v1/admin/seed/$cityId from http://127.0.0.1:8000/docs');
      } else {
        debugPrint('First category: ${categories[0]}');
        if (mounted) {
          context.read<IssuesProvider>().setCategories(categories);
        }
      }
    } catch (e, stack) {
      debugPrint('Error loading categories: $e');
      debugPrint('Stack: $stack');
    } finally {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _photoFile = picked;
        _photoBytes = bytes;
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (picked != null) setState(() => _videoFile = picked);
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      if (!kIsWeb) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.deniedForever) {
          throw Exception('Location permission denied permanently');
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _addressController.text =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Location error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  void _selectCategory() {
    final categories = context.read<IssuesProvider>().categories;

    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Categories still loading, please wait...'),
        backgroundColor: AppColors.moderate,
      ));
      return;
    }

    // Group by department
    final Map<String, List<dynamic>> grouped = {};
    for (final cat in categories) {
      final dept = cat['department_name'] ?? 'Other';
      grouped.putIfAbsent(dept, () => []).add(cat);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Select Category',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                children: grouped.entries
                    .map((entry) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...entry.value.map((cat) => ListTile(
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.category_outlined,
                                        color: AppColors.primary, size: 18),
                                  ),
                                  title: Text(cat['name'],
                                      style: const TextStyle(fontSize: 14)),
                                  selected: _selectedCategoryId == cat['id'],
                                  selectedTileColor: AppColors.primaryLight,
                                  onTap: () {
                                    setState(() {
                                      _selectedCategoryId = cat['id'];
                                      _selectedCategoryName = cat['name'];
                                      _selectedCategorySlug = cat['slug'];
                                      // Reset road type if not relevant
                                      if (!_roadRelatedSlugs
                                          .contains(cat['slug'])) {
                                        _roadType = 'none';
                                      }
                                    });
                                    Navigator.pop(context);
                                  },
                                )),
                          ],
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_photoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a photo of the issue'),
        backgroundColor: AppColors.moderate,
      ));
      return;
    }

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please get your location first'),
        backgroundColor: AppColors.moderate,
      ));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final cityId = prefs.getString(AppConstants.cityKey) ?? '';

      MultipartFile photoMultipart;
      if (kIsWeb) {
        final bytes = await _photoFile!.readAsBytes();
        photoMultipart = MultipartFile.fromBytes(bytes, filename: 'photo.jpg');
      } else {
        photoMultipart = await MultipartFile.fromFile(
          _photoFile!.path,
          filename: 'photo.jpg',
        );
      }

      final formData = FormData.fromMap({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'latitude': _latitude.toString(),
        'longitude': _longitude.toString(),
        'address': _addressController.text.trim(),
        'road_type': _showRoadType ? _roadType : 'none',
        'city_id': cityId,
        if (_selectedCategoryId != null) 'category_id': _selectedCategoryId,
        'photo': photoMultipart,
        if (_videoFile != null)
          'video': kIsWeb
              ? MultipartFile.fromBytes(await _videoFile!.readAsBytes(),
                  filename: 'video.mp4')
              : await MultipartFile.fromFile(_videoFile!.path,
                  filename: 'video.mp4'),
      });

      final result = await ApiClient().reportIssue(formData);
      if (!mounted) return;

      if (result['ai_suggested_category_name'] != null &&
          _selectedCategoryId == null) {
        _showAiSuggestionDialog(result);
      } else {
        _showSuccessDialog();
      }

      context.read<IssuesProvider>().loadIssues(refresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showAiSuggestionDialog(Map<String, dynamic> issue) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('AI Category Suggestion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI suggests this is a:'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(issue['ai_suggested_category_name'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.primary,
                  )),
            ),
            const SizedBox(height: 8),
            Text(
              'Confidence: ${((issue['ai_confidence'] ?? 0) * 100).toStringAsFixed(0)}%',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (issue['ai_reasoning'] != null) ...[
              const SizedBox(height: 8),
              Text(issue['ai_reasoning'], style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessDialog();
            },
            child: const Text('Accept'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _selectCategory();
            },
            child: const Text('Change category'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Issue Reported!'),
        content: const Text(
          'Your issue has been submitted successfully. '
          'You will be notified when the status changes.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForm();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _titleController.clear();
    _descController.clear();
    _addressController.clear();
    setState(() {
      _photoFile = null;
      _photoBytes = null;
      _videoFile = null;
      _latitude = null;
      _longitude = null;
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _selectedCategorySlug = null;
      _roadType = 'none';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Photo picker ─────────────────────────────────────────────
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: _photoBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _photoBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 44,
                              color: AppColors.textSecondary.withOpacity(0.5)),
                          const SizedBox(height: 8),
                          const Text('Tap to select a photo',
                              style: TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: 4),
                          const Text('Required',
                              style: TextStyle(
                                  color: AppColors.critical, fontSize: 12)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Video picker ─────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(_videoFile != null
                  ? 'Video selected ✓'
                  : 'Add video (optional)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _videoFile != null
                    ? AppColors.resolved
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // ── Title ────────────────────────────────────────────────────
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Issue title *',
                hintText: 'e.g. Large pothole near bus stop',
              ),
              validator: (v) => (v == null || v.trim().length < 5)
                  ? 'Enter at least 5 characters'
                  : null,
            ),
            const SizedBox(height: 12),

            // ── Description ──────────────────────────────────────────────
            TextFormField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe the issue in detail...',
              ),
            ),
            const SizedBox(height: 12),

            // ── Location ─────────────────────────────────────────────────
            TextFormField(
              controller: _addressController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Location *',
                hintText: 'Tap to detect GPS location',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: _isGettingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: _getLocation,
                      ),
              ),
              onTap: _getLocation,
              validator: (_) =>
                  _latitude == null ? 'Location is required' : null,
            ),
            const SizedBox(height: 12),

            // ── Category picker ──────────────────────────────────────────
            GestureDetector(
              onTap: _selectCategory,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.category_outlined,
                      color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _categoriesLoading
                        ? const Row(children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Loading categories...',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ])
                        : Text(
                            _selectedCategoryName ??
                                'Select category (AI will suggest if skipped)',
                            style: TextStyle(
                              color: _selectedCategoryName != null
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // ── Road type (only for road-related categories) ──────────────
            if (_showRoadType) ...[
              DropdownButtonFormField<String>(
                value: _roadType == 'none' ? 'lane' : _roadType,
                decoration: const InputDecoration(labelText: 'Road type'),
                items: _roadTypes
                    .map((r) => DropdownMenuItem(
                          value: r['value'],
                          child: Text(r['label']!),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roadType = v ?? 'lane'),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),

            // ── Submit ───────────────────────────────────────────────────
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Submit Report'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
