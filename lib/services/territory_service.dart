import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jts/dart_jts.dart' as jts;

class PolygonTerritory {
  final String id;
  final String ownerId;
  final int rp;
  final List<List<double>> coordinates;

  PolygonTerritory({
    required this.id,
    required this.ownerId,
    required this.rp,
    required this.coordinates,
  });

  factory PolygonTerritory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final coordsList = data['coordinates'] as List<dynamic>;
    final coords = coordsList.map((e) {
      final point = e as List<dynamic>;
      return [(point[0] as num).toDouble(), (point[1] as num).toDouble()];
    }).toList();

    return PolygonTerritory(
      id: doc.id,
      ownerId: data['owner_id'],
      rp: data['rp'],
      coordinates: coords,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'owner_id': ownerId,
      'rp': rp,
      'coordinates': coordinates,
    };
  }

  jts.Polygon toJTSPolygon(jts.GeometryFactory gf) {
    if (coordinates.isEmpty) return gf.createPolygonFromCoords([]);
    final coords = coordinates.map((p) => jts.Coordinate(p[1], p[0])).toList();
    if (!coords.first.equals2D(coords.last)) {
      coords.add(coords.first);
    }
    return gf.createPolygonFromCoords(coords);
  }
}

class TerritoryService {
  static final TerritoryService _instance = TerritoryService._internal();
  factory TerritoryService() => _instance;
  TerritoryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final jts.GeometryFactory _gf = jts.GeometryFactory.defaultPrecision();
  
  // Cache fetched polygons to avoid redundant reads
  final Map<String, PolygonTerritory> _polygonCache = {};

  Future<List<PolygonTerritory>> getNearbyTerritories(double lat, double lng) async {
    // For MVP, fetch all territories. In production, we'd use geohash or GeoFlutterFire.
    List<PolygonTerritory> results = [];
    try {
      final snapshot = await _firestore.collection('PolygonTerritories').get();

      for (var doc in snapshot.docs) {
        final territory = PolygonTerritory.fromFirestore(doc);
        _polygonCache[territory.id] = territory;
        results.add(territory);
      }
    } catch (e) {
      log('Error fetching nearby territories: $e');
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
        final territory = PolygonTerritory.fromFirestore(doc);
        _polygonCache[territory.id] = territory;
        results.add(territory);
      }
    } catch (e) {
      log('Error fetching user territories: $e');
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
    
    // Create the new JTS polygon
    final newCoords = pathCoordinates.map((p) => jts.Coordinate(p[1], p[0])).toList();
    if (!newCoords.first.equals2D(newCoords.last)) {
      newCoords.add(newCoords.first);
    }
    final newJtsPoly = _gf.createPolygonFromCoords(newCoords);

    // Fetch nearby polygons to check for overlaps
    final centerPoint = pathCoordinates.first;
    final nearby = await getNearbyTerritories(centerPoint[0], centerPoint[1]);

    await _firestore.runTransaction((transaction) async {
      // Add the new territory to the user's balance
      _updateUserRP(transaction, userId, earnedRP);

      // Create new territory document
      final newDocRef = _firestore.collection('PolygonTerritories').doc();
      transaction.set(newDocRef, {
        'owner_id': userId,
        'rp': earnedRP,
        'coordinates': pathCoordinates,
      });

      // Handle Boolean Operations (Option B)
      for (var oldPoly in nearby) {
        if (oldPoly.ownerId == userId) continue; // Don't deduct from self

        final oldJtsPoly = oldPoly.toJTSPolygon(_gf);
        
        // Skip if geometries are invalid
        if (!oldJtsPoly.isValid() || !newJtsPoly.isValid()) continue;

        if (oldJtsPoly.intersects(newJtsPoly)) {
          final intersection = oldJtsPoly.intersection(newJtsPoly);
          if (!intersection.isEmpty()) {
            // Roughly estimate the ratio of area stolen
            final oldArea = oldJtsPoly.getArea();
            final intersectArea = intersection.getArea();
            final ratio = intersectArea / oldArea;
            
            final rpToDeduct = (oldPoly.rp * ratio).round();

            if (rpToDeduct > 0) {
              // Deduct RP from old owner
              _updateUserRP(transaction, oldPoly.ownerId, -rpToDeduct);

              // Calculate the difference shape
              final difference = oldJtsPoly.difference(newJtsPoly);

              final oldDocRef = _firestore.collection('PolygonTerritories').doc(oldPoly.id);
              
              // Record Battle Event
              final battleDocRef = _firestore.collection('BattleHistory').doc();
              transaction.set(battleDocRef, {
                'attackerId': userId,
                'defenderId': oldPoly.ownerId,
                'participants': [userId, oldPoly.ownerId],
                'rpStolen': rpToDeduct,
                'timestamp': FieldValue.serverTimestamp(),
                'locationName': 'Local Area',
              });
              
              if (difference.isEmpty()) {
                // Completely engulfed
                transaction.delete(oldDocRef);
              } else {
                // Update shape and RP
                List<List<double>> updatedCoords = [];
                // Handle MultiPolygon vs Polygon
                if (difference is jts.Polygon) {
                  final coords = difference.getCoordinates();
                  updatedCoords = coords.map((c) => [c.y, c.x]).toList();
                } else if (difference is jts.MultiPolygon && difference.getNumGeometries() > 0) {
                  // If difference splits polygon into multiple pieces, take the largest piece
                  // (Simplification for Firestore storage to avoid complex MultiPolygon schema)
                  jts.Polygon largest = difference.getGeometryN(0) as jts.Polygon;
                  for (int i = 1; i < difference.getNumGeometries(); i++) {
                    final poly = difference.getGeometryN(i) as jts.Polygon;
                    if (poly.getArea() > largest.getArea()) largest = poly;
                  }
                  final coords = largest.getCoordinates();
                  updatedCoords = coords.map((c) => [c.y, c.x]).toList();
                }

                transaction.update(oldDocRef, {
                  'rp': oldPoly.rp - rpToDeduct,
                  'coordinates': updatedCoords,
                });
              }
            }
          }
        }
      }
    });

    log('✅ Successfully submitted Polygon territory and handled overlaps.');
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
        // New week — reset weekly counters
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

    await userRef.set(updates, SetOptions(merge: true));
    log('✅ Credited $rpChange RP to User: $uid for unclosed loop.');
  }

  void _updateUserRP(Transaction transaction, String uid, int rpChange) {
    final userRef = _firestore.collection('Users').doc(uid);
    final weekId = _getWeekId();
    
    final Map<String, dynamic> updates = {
      'rpBalance': FieldValue.increment(rpChange),
    };

    if (rpChange > 0) {
      updates['rpGained'] = FieldValue.increment(rpChange);
      updates['weeklyRpGained'] = FieldValue.increment(rpChange);
      updates['currentWeekId'] = weekId;
    } else if (rpChange < 0) {
      updates['rpLost'] = FieldValue.increment(-rpChange);
      updates['weeklyRpLost'] = FieldValue.increment(-rpChange);
      updates['currentWeekId'] = weekId;
    }

    transaction.update(userRef, updates);
  }

  /// Returns the current ISO week identifier, e.g. "2026-W26"
  String _getWeekId() {
    final now = DateTime.now();
    // ISO week calculation: week 1 contains Jan 4
    final jan4 = DateTime(now.year, 1, 4);
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final weekNumber = ((dayOfYear - now.weekday + jan4.weekday + 6) ~/ 7);
    return '${now.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }
}
