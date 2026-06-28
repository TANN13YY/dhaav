import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/login_sheet.dart';
import '../widgets/home_map_overlay.dart';
import '../theme/theme_manager.dart';
import '../theme/app_colors.dart';
import '../services/territory_service.dart';

/// Global notifier to trigger map refresh from other parts of the app
final ValueNotifier<int> mapRefreshNotifier = ValueNotifier(0);

/// ┌────────────────────────────────────────────────────────┐
/// Full-screen dark Mapbox map with the floating HomeMapOverlay.
/// When [showLoginOnLaunch] is true, the login bottom-sheet is triggered
/// automatically after the first frame.
class MapRadarScreen extends StatefulWidget {
  const MapRadarScreen({
    super.key,
    this.showLoginOnLaunch = false,
    required this.onNavigateToMe,
  });

  /// If true, auto-show the login sheet on first build.
  final bool showLoginOnLaunch;
  final VoidCallback onNavigateToMe;

  @override
  State<MapRadarScreen> createState() => _MapRadarScreenState();
}

class _MapRadarScreenState extends State<MapRadarScreen> {
  MapboxMap? _mapboxMap;
  PolygonAnnotationManager? _polygonManager;
  PointAnnotationManager? _pointManager;
  bool _loginSheetShown = false;

  @override
  void initState() {
    super.initState();
    ThemeManager().isDarkMode.addListener(_onThemeChanged);
    mapRefreshNotifier.addListener(_locateMe);
    if (widget.showLoginOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_loginSheetShown && mounted) {
          _loginSheetShown = true;
          showLoginSheet(context);
        }
      });
    }
  }

  void _onThemeChanged() {
    _mapboxMap?.loadStyleURI(
        ThemeManager().isDarkMode.value ? MapboxStyles.DARK : MapboxStyles.LIGHT);
  }

  @override
  void dispose() {
    ThemeManager().isDarkMode.removeListener(_onThemeChanged);
    mapRefreshNotifier.removeListener(_locateMe);
    super.dispose();
  }

  void _onMapCreated(MapboxMap map) {
    _mapboxMap = map;

    // Hide default UI chrome for a clean, immersive look
    _mapboxMap!.compass.updateSettings(CompassSettings(enabled: false));
    _mapboxMap!.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _mapboxMap!.logo.updateSettings(LogoSettings(
      position: OrnamentPosition.BOTTOM_LEFT,
      marginLeft: 8,
      marginBottom: 8,
    ));
    _mapboxMap!.attribution.updateSettings(
      AttributionSettings(
        position: OrnamentPosition.BOTTOM_LEFT,
        marginLeft: 40,
        marginBottom: 8,
      ),
    );

    // Enable the pulsing location puck (radar blip)
    _mapboxMap!.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: 0xFF00F0FF, // radar cyan
        pulsingMaxRadius: 40.0,
      ),
    );

    _initPolygonManager();
  }

  Future<void> _initPolygonManager() async {
    final annotationPlugin = _mapboxMap!.annotations;
    _polygonManager = await annotationPlugin.createPolygonAnnotationManager();
    _pointManager = await annotationPlugin.createPointAnnotationManager();
    _locateMe(); // Load initial polygons once ready
  }

  Future<void> _loadNearbyTerritories(double lat, double lng) async {
    if (_polygonManager == null) return;
    try {
      final territories = await TerritoryService().getNearbyTerritories(lat, lng);
      
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      
      _polygonManager?.deleteAll();
      _pointManager?.deleteAll();
      if (territories.isEmpty) return;

      List<PolygonAnnotationOptions> polygons = [];
      List<PointAnnotationOptions> points = [];

      for (var t in territories) {
        final isMine = t.ownerId == currentUid;
        final coords = t.coordinates.map((p) => Position(p[1], p[0])).toList();
        
        polygons.add(PolygonAnnotationOptions(
          geometry: Polygon(coordinates: [coords]),
          fillColor: (isMine ? AppColors.territoryOwn : AppColors.territoryOther).value,
          fillOpacity: 0.3,
          fillOutlineColor: (isMine ? AppColors.territoryOwn : AppColors.territoryOther).value,
        ));

        // Calculate simple center for the label
        // Only show labels for OTHER players to avoid clustering the map with "ME"
        if (coords.isNotEmpty && !isMine) {
          double sumLat = 0;
          double sumLng = 0;
          for (var c in coords) {
            sumLat += c.lat.toDouble();
            sumLng += c.lng.toDouble();
          }
          final centerLat = sumLat / coords.length;
          final centerLng = sumLng / coords.length;

          String initials = t.ownerId.substring(0, 2).toUpperCase();
          if (t.ownerId == 'mock_user_alpha') initials = 'A';
          if (t.ownerId == 'mock_user_beta') initials = 'B';

          points.add(PointAnnotationOptions(
            geometry: Point(coordinates: Position(centerLng, centerLat)),
            textField: initials,
            textSize: 14.0,
            textColor: Colors.white.value,
            textHaloColor: Colors.black.value,
            textHaloWidth: 1.5,
          ));
        }
      }
      
      await _polygonManager?.createMulti(polygons);
      await _pointManager?.createMulti(points);
    } catch (e) {
      debugPrint('Error loading nearby territories: $e');
    }
  }

  Future<void> _locateMe() async {
    if (_mapboxMap == null) return;
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16.0,
          pitch: 45.0,
        ),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );
      _loadNearbyTerritories(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("Error locating user: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Ã¢â€â‚¬Ã¢â€â‚¬ Full-screen map Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          MapWidget(
            styleUri: Theme.of(context).brightness == Brightness.dark ? MapboxStyles.DARK : MapboxStyles.LIGHT,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(77.2090, 28.6139), // New Delhi
              ),
              zoom: 15.0,
              pitch: 45.0, // slight tilt for depth
            ),
            onMapCreated: _onMapCreated,
          ),

          // Ã¢â€â‚¬Ã¢â€â‚¬ Home Map UI Overlay Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          HomeMapOverlay(
            onLocateMe: _locateMe,
            onNavigateToMe: widget.onNavigateToMe,
          ),
        ],
      ),
    );
  }
}
