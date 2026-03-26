import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/issues_provider.dart';
import '../issue_detail/issue_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  static const _defaultCenter = LatLng(17.3850, 78.4867);
  static const _pinZoomThreshold = 14.0;
  double _currentZoom = 12.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPins());
  }

  void _loadPins() {
    try {
      final bounds = _mapController.camera.visibleBounds;
      context.read<IssuesProvider>().loadMapPins(
            minLng: bounds.west,
            minLat: bounds.south,
            maxLng: bounds.east,
            maxLat: bounds.north,
          );
    } catch (_) {}
  }

  Color _pinColor(String severity, String status) {
    if (status == 'resolved') return AppColors.resolved;
    return AppColors.severityColor(severity);
  }

  // Convert pins to heatmap data points
  List<WeightedLatLng> _toHeatPoints(List<dynamic> pins) {
    return pins.map((pin) {
      final lat = (pin['latitude'] as num).toDouble();
      final lng = (pin['longitude'] as num).toDouble();

      final severityWeight = {
            'critical': 1.0,
            'high': 0.75,
            'moderate': 0.5,
            'low': 0.25,
          }[pin['severity']] ??
          0.3;

      final reportBoost =
          ((pin['report_count'] as num?)?.toInt() ?? 1).clamp(1, 5) / 5.0;

      final weight = severityWeight * (0.6 + 0.4 * reportBoost);

      return WeightedLatLng(
        LatLng(lat, lng),
        weight,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IssuesProvider>();
    final isPinMode = _currentZoom >= _pinZoomThreshold;

    return Scaffold(
      appBar: AppBar(
        title: Text(isPinMode ? '📍 Issue Pins' : '🔥 Issue Heatmap'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPins)
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Text(
                'Show:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              ...[
                {'label': 'All', 'value': 'all'},
                {'label': 'Active', 'value': 'active'},
                {'label': 'Resolved', 'value': 'resolved'},
              ].map(
                (f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f['label']!),
                    selected: provider.mapFilter == f['value'],
                    onSelected: (_) {
                      provider.setMapFilter(f['value']!);
                      _loadPins();
                    },
                    selectedColor: AppColors.primaryLight,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: provider.mapFilter == f['value']
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                isPinMode ? 'Zoom out for heatmap' : 'Zoom in for pins',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ]),
          ),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: _currentZoom,
                onMapReady: () => Future.delayed(
                  const Duration(milliseconds: 500),
                  _loadPins,
                ),
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture) {
                    final newZoom = pos.zoom ?? _currentZoom;
                    final crossed = (_currentZoom < _pinZoomThreshold) !=
                        (newZoom < _pinZoomThreshold);
                    setState(() => _currentZoom = newZoom);
                    if (crossed || hasGesture) _loadPins();
                  }
                },
              ),
              children: [
                // Dark map tiles (like Snapchat)
                TileLayer(
                  urlTemplate:
                      'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.civicpulse.app',
                ),

                // Heatmap layer (visible when zoomed out)
                if (!isPinMode && provider.mapPins.isNotEmpty)
                  HeatMapLayer(
                    heatMapDataSource: InMemoryHeatMapDataSource(
                      data: _toHeatPoints(provider.mapPins),
                    ),
                    heatMapOptions: HeatMapOptions(
                      radius: 60,
                      layerOpacity: 0.85,
                      gradient: {
                        0.15: Colors.blue,
                        0.35: Colors.cyan,
                        0.55: Colors.lime,
                        0.72: Colors.yellow,
                        0.88: Colors.orange,
                        1.0: Colors.red,
                      },
                    ),
                  ),

                // Pin markers (visible when zoomed in)
                if (isPinMode)
                  MarkerLayer(
                    markers: provider.mapPins.map((pin) {
                      final lat = (pin['latitude'] as num).toDouble();
                      final lng = (pin['longitude'] as num).toDouble();
                      final severity = pin['severity'] ?? 'low';
                      final status = pin['status'] ?? 'pending';
                      final isCritical =
                          severity == 'critical' && status != 'resolved';
                      final color = _pinColor(severity, status);

                      return Marker(
                        point: LatLng(lat, lng),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => _showPinDetail(context, pin),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isCritical)
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.25),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    status == 'resolved' ? '✓' : '!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPinDetail(BuildContext context, Map<String, dynamic> pin) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _pinColor(
                    pin['severity'] ?? 'low',
                    pin['status'] ?? 'pending',
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pin['title'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ]),
            if (pin['category_name'] != null) ...[
              const SizedBox(height: 6),
              Text(
                pin['category_name'],
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              _StatChip(Icons.thumb_up_outlined, '${pin['upvote_count'] ?? 0}'),
              const SizedBox(width: 12),
              _StatChip(
                Icons.people_outline,
                '${pin['report_count'] ?? 1} reports',
              ),
              const SizedBox(width: 12),
              _StatChip(Icons.schedule, '${pin['days_open'] ?? 0}d open'),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IssueDetailScreen(issueId: pin['id']),
                    ),
                  );
                },
                child: const Text('View Full Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
}
