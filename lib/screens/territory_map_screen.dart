import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/territory_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_manager.dart';

class TerritoryMapScreen extends StatefulWidget {
  final PolygonTerritory territory;

  const TerritoryMapScreen({super.key, required this.territory});

  @override
  State<TerritoryMapScreen> createState() => _TerritoryMapScreenState();
}

class _TerritoryMapScreenState extends State<TerritoryMapScreen> {
  PolygonAnnotationManager? _polygonManager;
  MapboxMap? _mapboxMap;

  @override
  void initState() {
    super.initState();
    ThemeManager().isDarkMode.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    _mapboxMap?.loadStyleURI(
        ThemeManager().isDarkMode.value ? MapboxStyles.DARK : MapboxStyles.LIGHT);
  }

  @override
  void dispose() {
    ThemeManager().isDarkMode.removeListener(_onThemeChanged);
    super.dispose();
  }

  _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    
    // Add polygon
    _polygonManager = await mapboxMap.annotations.createPolygonAnnotationManager();

    final coords = widget.territory.coordinates.map((c) => Position(c[1], c[0])).toList();
    if (coords.isNotEmpty) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      String? dhaavId;
      if (currentUid != null) {
        dhaavId = await UserService().fetchDhaavId(currentUid);
      }
      final isMine = widget.territory.ownerId == dhaavId;
      final colorValue = isMine ? AppColors.territoryOwn.value : AppColors.territoryOther.value;

      await _polygonManager!.create(PolygonAnnotationOptions(
        geometry: Polygon(coordinates: [coords]),
        fillColor: colorValue,
        fillOpacity: 0.4,
        fillOutlineColor: colorValue,
      ));

      // Calculate bounding box to fit camera
      double minLat = coords.first.lat.toDouble();
      double maxLat = coords.first.lat.toDouble();
      double minLng = coords.first.lng.toDouble();
      double maxLng = coords.first.lng.toDouble();

      for (var c in coords) {
        if (c.lat < minLat) minLat = c.lat.toDouble();
        if (c.lat > maxLat) maxLat = c.lat.toDouble();
        if (c.lng < minLng) minLng = c.lng.toDouble();
        if (c.lng > maxLng) maxLng = c.lng.toDouble();
      }

      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      await mapboxMap.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(centerLng, centerLat)),
          zoom: 15.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'AREA DETAILS',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            styleUri: Theme.of(context).brightness == Brightness.dark ? MapboxStyles.DARK : MapboxStyles.LIGHT,
            cameraOptions: CameraOptions(
              zoom: 2.0, // Default zoom before flyTo
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Captured Area',
                        style: GoogleFonts.inter(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${widget.territory.coordinates.length} points mapped',
                        style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 14),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${widget.territory.rp}',
                          style: GoogleFonts.orbitron(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.stars, color: AppColors.gold, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
