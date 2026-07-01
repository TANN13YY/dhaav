import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:clipper2/clipper2.dart';
import 'package:geocoding/geocoding.dart';

const double clipperScale = 1e7;

class PolygonTerritory {
  final String id;
  final String ownerId;
  final int rp;
  final double areaSqm;
  final List<List<double>> coordinates;

  PolygonTerritory({
    required this.id,
    required this.ownerId,
    required this.rp,
    this.areaSqm = 0.0,
    required this.coordinates,
  });

  factory PolygonTerritory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Safely parse coordinates
    List<List<double>> coords = [];
    if (data['coordinates'] is List) {
      final coordsList = data['coordinates'] as List<dynamic>;
      coords = coordsList.map((e) {
        if (e is GeoPoint) return [e.latitude, e.longitude];
        if (e is List) return [(e[0] as num).toDouble(), (e[1] as num).toDouble()];
        return [0.0, 0.0];
      }).toList();
    }

    return PolygonTerritory(
      id: doc.id,
      ownerId: data['owner_id']?.toString() ?? 'unknown',
      rp: (data['rp'] as num?)?.toInt() ?? 0,
      areaSqm: (data['area_sqm'] as num?)?.toDouble() ?? 0.0,
      coordinates: coords,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'owner_id': ownerId,
      'rp': rp,
      'area_sqm': areaSqm,
      'coordinates': coordinates.map((c) => GeoPoint(c[0], c[1])).toList(),
    };
  }

  Path64 toClipperPath() {
    final path = <Point64>[];
    if (coordinates.isEmpty) return path;
    
    // We don't want the last coordinate if it's identical to the first, 
    // Clipper assumes closed paths natively, but we can just feed it the points.
    for (var i = 0; i < coordinates.length; i++) {
      final p = coordinates[i];
      // Skip the last point if it closes the loop (Clipper handles closure)
      if (i == coordinates.length - 1 && p[0] == coordinates.first[0] && p[1] == coordinates.first[1]) {
        continue;
      }
      path.add(Point64((p[1] * clipperScale).round(), (p[0] * clipperScale).round())); // x = lon, y = lat
    }
    return path;
  }
}

class TerritoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache fetched polygons to avoid redundant reads
  final Map<String, PolygonTerritory> _polygonCache = {};

  Future<List<PolygonTerritory>> getNearbyTerritories(double lat, double lng) async {
    // For MVP, fetch all territories. In production, we'd use geohash or GeoFlutterFire.
    List<PolygonTerritory> results = [];
    try {
      final snapshot = await _firestore.collection('PolygonTerritories').get();

      for (var doc in snapshot.docs) {
        try {
          final territory = PolygonTerritory.fromFirestore(doc);
          _polygonCache[territory.id] = territory;
          results.add(territory);
        } catch (e) {
          log('Skipping corrupted territory \${doc.id}\: $e');
        }
      }
    } catch (e) {
      log('Error getting territories: $e');
    }
    return results;
  }

  Future<List<PolygonTerritory>> getUserTerritories(String userId) async {
    List<PolygonTerritory> results = [];
    try {
      final snapshot = await _firestore
          .collection('PolygonTerritories')
          .where('owner_id', isEqualTo: userId)
          .get();

      for (var doc in snapshot.docs) {
        try {
          final territory = PolygonTerritory.fromFirestore(doc);
          _polygonCache[territory.id] = territory;
          results.add(territory);
        } catch (e) {
          log('Skipping corrupted territory \${doc.id}\: $e');
        }
      }
    } catch (e) {
      log('Error getting user territories: $e');
    }
    return results;
  }

  void clearCache() {
    _polygonCache.clear();
  }

  Future<void> submitCustomTerritory({
    required List<List<double>> pathCoordinates,
    required double areaM2,
    required String userId,
    required int earnedRP,
  }) async {
    if (pathCoordinates.isEmpty) return;
    
    // Create the new Clipper path
    final newClipperPath = <Point64>[];
    for (var i = 0; i < pathCoordinates.length; i++) {
      final p = pathCoordinates[i];
      if (i == pathCoordinates.length - 1 && p[0] == pathCoordinates.first[0] && p[1] == pathCoordinates.first[1]) {
        continue; // skip closing coordinate
      }
      newClipperPath.add(Point64((p[1] * clipperScale).round(), (p[0] * clipperScale).round()));
    }

    // Fetch nearby polygons to check for overlaps
    final centerPoint = pathCoordinates.first;
    final nearby = await getNearbyTerritories(centerPoint[0], centerPoint[1]);

    String battleLocationName = 'Unknown Area';
    try {
      final placemarks = await placemarkFromCoordinates(centerPoint[0], centerPoint[1]);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = [place.subLocality, place.locality].where((s) => s != null && s.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          battleLocationName = parts.join(', ');
        } else {
          battleLocationName = place.name ?? 'Unknown Area';
        }
      }
    } catch (e) {
      log('Error reverse geocoding: $e');
    }

    final batch = _firestore.batch();
    int selfOverlapRP = 0;
    int totalStolenRP = 0;
    List<Map<String, dynamic>> enemyDeductions = [];
    final newDocRef = _firestore.collection('PolygonTerritories').doc();

    for (var oldPoly in nearby) {
      final oldClipperPath = oldPoly.toClipperPath();
      
      // Calculate intersection area
      final intersectionPaths = Clipper.intersect(
        subject: [oldClipperPath], 
        clip: [newClipperPath], 
        fillRule: FillRule.nonZero
      );
      
      final double intersectionArea = intersectionPaths.area.abs();

      if (intersectionArea > 0) {
        // Calculate RP to deduct based on the NEW shape's proportion
        final double oldRatio = intersectionArea / oldClipperPath.area.abs();
        
        int rpToDeduct = (earnedRP * (intersectionArea / newClipperPath.area.abs())).round();
        if (rpToDeduct > oldPoly.rp) rpToDeduct = oldPoly.rp;

        // Calculate the remaining geometry for the old owner
        final differencePaths = Clipper.difference(
          subject: [oldClipperPath], 
          clip: [newClipperPath], 
          fillRule: FillRule.nonZero
        );
        
        final oldDocRef = _firestore.collection('PolygonTerritories').doc(oldPoly.id);
        final bool isSelfOverlap = (oldPoly.ownerId == userId);

        if (differencePaths.isEmpty) {
          // The territory was completely engulfed, so we MUST deduct its full value since it gets deleted
          rpToDeduct = oldPoly.rp;
          batch.delete(oldDocRef);

          if (!isSelfOverlap) {
            // Log battle history
            final battleDocRef = _firestore.collection('BattleHistory').doc();
            batch.set(battleDocRef, {
              'attackerId': userId,
              'defenderId': oldPoly.ownerId,
              'rpStolen': oldPoly.rp,
              'areaSqm': oldPoly.areaSqm,
              'timestamp': FieldValue.serverTimestamp(),
              'locationName': battleLocationName,
              'type': 'engulfed',
              'participants': [userId, oldPoly.ownerId],
              'capturedCoordinates': oldPoly.coordinates.map((c) => GeoPoint(c[0], c[1])).toList(),
            });
          }
        } else {
          if (!isSelfOverlap) {
            // Log battle history
            final battleDocRef = _firestore.collection('BattleHistory').doc();
            List<GeoPoint> intersectionGeoPoints = [];
            if (intersectionPaths.isNotEmpty) {
              final path = intersectionPaths.first;
              for (final pt in path) {
                intersectionGeoPoints.add(GeoPoint(pt.y / clipperScale, pt.x / clipperScale));
              }
            }
            batch.set(battleDocRef, {
              'attackerId': userId,
              'defenderId': oldPoly.ownerId,
              'rpStolen': rpToDeduct,
              'areaSqm': oldPoly.areaSqm * oldRatio,
              'timestamp': FieldValue.serverTimestamp(),
              'locationName': battleLocationName,
              'type': 'partial',
              'participants': [userId, oldPoly.ownerId],
              'capturedCoordinates': intersectionGeoPoints,
            });
          }

          // Take the largest piece if it split into multiples
          Path64 largestPiece = differencePaths.first;
          double maxArea = largestPiece.area.abs();
          for (var i = 1; i < differencePaths.length; i++) {
            final area = differencePaths[i].area.abs();
            if (area > maxArea) {
              maxArea = area;
              largestPiece = differencePaths[i];
            }
          }
          
          List<List<double>> updatedCoords = [];
          for (final pt in largestPiece) {
            updatedCoords.add([pt.y / clipperScale, pt.x / clipperScale]);
          }
          // Close the loop for GeoJSON/Mapbox
          if (updatedCoords.isNotEmpty) {
            updatedCoords.add(updatedCoords.first);
          }

          batch.update(oldDocRef, {
            'rp': oldPoly.rp - rpToDeduct,
            'area_sqm': oldPoly.areaSqm - (oldPoly.areaSqm * oldRatio),
            'coordinates': updatedCoords.map((c) => GeoPoint(c[0], c[1])).toList(),
          });
        }

        if (isSelfOverlap) {
          selfOverlapRP += rpToDeduct;
        } else {
          // Track deduction for enemy
          enemyDeductions.add({
            'enemyId': oldPoly.ownerId,
            'rpStolen': rpToDeduct,
          });
          totalStolenRP += rpToDeduct;
        }
      }
    }

    int finalTerritoryRP = earnedRP + totalStolenRP;

    // Create pending claim to be processed by Cloud Function
    batch.set(_firestore.collection('PendingTerritoryClaims').doc(), {
      'userId': userId,
      'enemyDeductions': enemyDeductions,
      'selfOverlapRP': selfOverlapRP,
      'newDocRefId': newDocRef.id,
      'rp': finalTerritoryRP,
      'area_sqm': areaM2,
      'coordinates': pathCoordinates.map((c) => GeoPoint(c[0], c[1])).toList(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      // Fire and forget batch for offline support
      batch.commit();
      log('Successfully queued Polygon territory via Pending Claim for offline support.');
    } catch (e) {
      log('Error submitting territory batch: $e');
    }
  }

  /// Returns the current ISO week identifier, e.g. "2026-W26"
  String _getWeekId() {
    final now = DateTime.now();
    final jan4 = DateTime(now.year, 1, 4);
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final weekNumber = ((dayOfYear - now.weekday + jan4.weekday + 6) ~/ 7);
    return '${now.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }
}

