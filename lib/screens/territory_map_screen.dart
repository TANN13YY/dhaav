import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../services/territory_service.dart';
import '../theme/app_colors.dart';

class TerritoryMapScreen extends StatefulWidget {
  final PolygonTerritory territory;

  const TerritoryMapScreen({Key? key, required this.territory}) : super(key: key);

  @override
  State<TerritoryMapScreen> createState() => _TerritoryMapScreenState();
}

class _TerritoryMapScreenState extends State<TerritoryMapScreen> {
  PolygonAnnotationManager? _polygonManager;

  _onMapCreated(MapboxMap mapboxMap) async {
    
    // Add polygon
    _polygonManager = await mapboxMap.annotations.createPolygonAnnotationManager();

    final coords = widget.territory.coordinates.map((c) => Position(c[1], c[0])).toList();
    if (coords.isNotEmpty) {
      await _polygonManager!.create(PolygonAnnotationOptions(
        geometry: Polygon(coordinates: [coords]),
        fillColor: AppColors.radarCyan.value,
        fillOpacity: 0.4,
        fillOutlineColor: AppColors.radarCyan.value,
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
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        title: Text(
          'AREA DETAILS',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            styleUri: "mapbox://styles/mapbox/dark-v11",
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
                color: AppColors.surfaceCardSolid.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.radarCyan.withOpacity(0.5)),
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
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.territory.coordinates.length} points mapped',
                        style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${widget.territory.rp}',
                          style: GoogleFonts.orbitron(
                            color: AppColors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.stars, color: AppColors.amber, size: 16),
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
