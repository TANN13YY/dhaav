import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../widgets/login_sheet.dart';
import '../widgets/home_map_overlay.dart';

/// ── MapRadarScreen ──────────────────────────────────────────────────────────
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
  bool _loginSheetShown = false;

  @override
  void initState() {
    super.initState();
    if (widget.showLoginOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_loginSheetShown && mounted) {
          _loginSheetShown = true;
          showLoginSheet(context);
        }
      });
    }
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
          // ── Full-screen map ──────────────────────────────────────────────
          MapWidget(
            styleUri: MapboxStyles.DARK,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(77.2090, 28.6139), // New Delhi
              ),
              zoom: 15.0,
              pitch: 45.0, // slight tilt for depth
            ),
            onMapCreated: _onMapCreated,
          ),

          // ── Home Map UI Overlay ─────────────────────────────────────────
          HomeMapOverlay(
            onLocateMe: _locateMe,
            onNavigateToMe: widget.onNavigateToMe,
          ),
        ],
      ),
    );
  }
}
