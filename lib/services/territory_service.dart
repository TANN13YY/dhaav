import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
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
          battleLocationName = place.name ?? place.street ?? 'Unknown Area';
        }
      }
    } catch (e) {
      // Fallback on error or no connectivity
      battleLocationName = 'Lat: ${centerPoint[0].toStringAsFixed(4)}, Lng: ${centerPoint[1].toStringAsFixed(4)}';
    }

    await _firestore.runTransaction((transaction) async {
      int selfOverlapRP = 0;
      int totalStolenRP = 0;
      final newDocRef = _firestore.collection('PolygonTerritories').doc();

      // Handle Boolean Operations (Option B)
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
          final double newRatio = intersectionArea / newClipperPath.area.abs();
          
          int rpToDeduct = (earnedRP * newRatio).round();
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
            transaction.delete(oldDocRef);

            if (!isSelfOverlap) {
              // Log battle history
              final battleDocRef = _firestore.collection('BattleHistory').doc();
              transaction.set(battleDocRef, {
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
              transaction.set(battleDocRef, {
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

            transaction.update(oldDocRef, {
              'rp': oldPoly.rp - rpToDeduct,
              'area_sqm': oldPoly.areaSqm - (oldPoly.areaSqm * oldRatio),
              'coordinates': updatedCoords.map((c) => GeoPoint(c[0], c[1])).toList(),
            });
          }

          if (isSelfOverlap) {
            selfOverlapRP += rpToDeduct;
          } else {
            // Deduct RP from old owner (the enemy lost it)
            _updateUserRP(transaction, oldPoly.ownerId, -rpToDeduct);
            // Add stolen RP to the attacker's total
            totalStolenRP += rpToDeduct;
          }
        }
      }

      int finalTerritoryRP = earnedRP + totalStolenRP;
      int netEarnedRP = finalTerritoryRP - selfOverlapRP;

      // Create new territory document after knowing final RP
      transaction.set(newDocRef, {
        'owner_id': userId,
        'rp': finalTerritoryRP,
        'coordinates': pathCoordinates.map((c) => GeoPoint(c[0], c[1])).toList(),
      });

      // Add the net new territory RP to the user's balance
      _updateUserRP(transaction, userId, netEarnedRP);
    });

    log('ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ Successfully submitted Polygon territory and handled overlaps.');
  }

  Future<void> creditRunRP(String uid, int rpChange) async {
    final userRef = _firestore.collection('Users').doc(uid);
    final weekId = _getWeekId();
    
    // Read the current doc to check if we need to reset weekly counters
    final userDoc = await userRef.get();
    final userData = userDoc.data() ?? {};
    final storedWeekId = userData['currentWeekId'] ?? '';
    
    final Map<String, dynamic> updates = {
      'rpBalance': FieldValue.increment(rpChange),
    };

    if (rpChange > 0) {
      updates['rpGained'] = FieldValue.increment(rpChange);
      if (storedWeekId == weekId) {
        updates['weeklyRpGained'] = FieldValue.increment(rpChange);
      } else {
        // New week ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ reset weekly counters
        updates['currentWeekId'] = weekId;
        updates['weeklyRpGained'] = rpChange;
        updates['weeklyRpLost'] = 0;
      }
    } else if (rpChange < 0) {
      updates['rpLost'] = FieldValue.increment(-rpChange); // Store as positive
      if (storedWeekId == weekId) {
        updates['weeklyRpLost'] = FieldValue.increment(-rpChange);
      } else {
        updates['currentWeekId'] = weekId;
        updates['weeklyRpGained'] = 0;
        updates['weeklyRpLost'] = -rpChange;
      }
    }

    try {
      await userRef.update(updates);
    } catch (e) {
      log('Error crediting RP: $e');
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

  void _updateUserRP(Transaction transaction, String userId, int rpChange) {
    if (rpChange == 0) return;
    
    final userRef = _firestore.collection('Users').doc(userId);
    final weekId = _getWeekId();
    
    // Note: We cannot easily read before write in a batch-style transaction without
    // restructuring the whole transaction to read all users first.
    // For simplicity in this demo, we'll use FieldValue.increment and just update
    // the weekly counter blindly. A production app would read the user doc first.
    final Map<String, dynamic> updates = {
      'rpBalance': FieldValue.increment(rpChange),
    };

    if (rpChange > 0) {
      updates['rpGained'] = FieldValue.increment(rpChange);
      updates['weeklyRpGained'] = FieldValue.increment(rpChange);
      updates['currentWeekId'] = weekId; // might overwrite incorrectly if week changed, but ok for MVP
    } else {
      updates['rpLost'] = FieldValue.increment(-rpChange);
      updates['weeklyRpLost'] = FieldValue.increment(-rpChange);
      updates['currentWeekId'] = weekId;
    }
    
    transaction.set(userRef, updates, SetOptions(merge: true));
  }
}

