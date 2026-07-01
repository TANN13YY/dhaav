import 'dart:math' as math;
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'territory_service.dart';

class MockDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _getWeekId() {
    final now = DateTime.now();
    final jan4 = DateTime(now.year, 1, 4);
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final weekNumber = ((dayOfYear - now.weekday + jan4.weekday + 6) ~/ 7);
    return '${now.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  double _toRadians(double degree) => degree * math.pi / 180.0;

  double _calculateArea(List<List<double>> coords) {
    if (coords.length < 3) return 0.0;
    final closedCoords = List<List<double>>.from(coords);
    if (closedCoords.first[0] != closedCoords.last[0] || closedCoords.first[1] != closedCoords.last[1]) {
      closedCoords.add(closedCoords.first);
    }
    double area = 0.0;
    for (int i = 0; i < closedCoords.length - 1; i++) {
      final p1 = closedCoords[i];
      final p2 = closedCoords[i + 1];
      area += _toRadians(p2[1] - p1[1]) *
          (2 + math.sin(_toRadians(p1[0])) + math.sin(_toRadians(p2[0])));
    }
    area = area * 6378137.0 * 6378137.0 / 2.0;
    return area.abs();
  }

  Future<void> generateMockData(BuildContext context, String currentUserId) async {
    try {
      log('Generating mock data...');

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Step 1: Locating...')));

      // Get current location
      double startLat = 37.7749;
      double startLon = -122.4194;
      
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          Position? position = await Geolocator.getLastKnownPosition();
          position ??= await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));
          
          startLat = position.latitude - 0.02;
          startLon = position.longitude - 0.02;
        }
      } catch (e) {
        log('Could not get location: $e');
      }
      
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Step 2: Location resolved. Generating polygons...')));

      final double step = 0.005; // Roughly 500m

      // 3. Generate grid of territories ALL for the current user
      for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
          final lat = startLat + (i * step);
          final lon = startLon + (j * step);

          // Define points in counter-clockwise order (GeoJSON standard)
          // East, North, West, South
          final coords = [
            [lat, lon],
            [lat, lon + step],
            [lat + step, lon + step],
            [lat + step, lon],
            [lat, lon],
          ];

          final area = _calculateArea(coords);
          final perimeter = 4 * math.sqrt(area);
          final rp = (perimeter / 100.0).round();
          final owner = currentUserId;

          // Save territory
          await _firestore.collection('PolygonTerritories').add({
            'owner_id': owner,
            'rp': rp,
            'area_sqm': area,
            'coordinates': coords.map((c) => GeoPoint(c[0], c[1])).toList(),
          });

          // Credit RP using Admin Cloud Function
          try {
            await FirebaseFunctions.instance.httpsCallable('adminCreditRP').call({
              'targetUid': owner,
              'amount': rp,
            });
          } catch (e) {
            log('Error crediting mock RP via cloud function: $e');
          }
        }
      }

      log('Mock data generation complete!');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SUCCESS: Mock Data Generated!')));
      }
    } catch (e, stack) {
      log('CRASH in generateMockData: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CRASH: $e')));
      }
    }
  }

  Future<void> clearMockData(BuildContext context, String currentUserId) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clearing mock data...')));
      }

      // 1. Delete all territories
      final snapshot = await _firestore.collection('PolygonTerritories').get();
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Delete all RunHistory to prevent duplicate welcome bonuses and ghost runs
      final runHistorySnapshot = await _firestore.collection('RunHistory').get();
      for (var doc in runHistorySnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete mock battles
      final battleSnapshot = await _firestore.collection('BattleHistory').get();
      for (var doc in battleSnapshot.docs) {
        await doc.reference.delete();
      }

      // 2. Reset user RP stats and initialize Alpha Bot
      final userIds = [currentUserId, 'mock_user_alpha', 'mock_user_beta'];
      for (var uid in userIds) {
        if (uid == 'mock_user_alpha') {
          await _firestore.collection('Users').doc(uid).set({
            'firstName': 'Alpha Bot',
            'rpBalance': 0,
            'rpGained': 0,
            'rpLost': 0,
            'weeklyRpGained': 0,
            'weeklyRpLost': 0,
            'totalRpEarned': 0,
            'currentWeekId': _getWeekId(),
            'welcomeRPClaimed': false,
          }, SetOptions(merge: true));
        } else {
          await _firestore.collection('Users').doc(uid).update({
            'rpBalance': 0,
            'rpGained': 0,
            'rpLost': 0,
            'weeklyRpGained': 0,
            'weeklyRpLost': 0,
            'totalRpEarned': 0,
            'currentWeekId': _getWeekId(),
            'welcomeRPClaimed': false,
          }).catchError((_) {}); // Ignore if user doc doesn't exist
        }
      }

      log('Mock data cleared!');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SUCCESS: Mock Data Cleared!')));
      }
    } catch (e, stack) {
      log('CRASH in clearMockData: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
      }
    }
  }

  Future<void> simulateTerritoryLoss(BuildContext context, String currentUserId) async {
    try {
      final query = await _firestore.collection('PolygonTerritories')
          .where('owner_id', isEqualTo: currentUserId)
          .get();
          
      if (query.docs.isNotEmpty) {
        final docs = query.docs;
        final doc = docs[math.Random().nextInt(docs.length)];
        
        // 1. Give territory to enemy
        await doc.reference.update({
          'owner_id': 'mock_user_alpha',
        });
        
        // 2. Deduct RP from user and give to alpha
        final userRef = _firestore.collection('Users').doc(currentUserId);
        final alphaRef = _firestore.collection('Users').doc('mock_user_alpha');
        
        await _firestore.runTransaction((tx) async {
          // MUST DO ALL READS BEFORE ANY WRITES
          final userSnap = await tx.get(userRef);
          final alphaSnap = await tx.get(alphaRef);
          
          if (userSnap.exists) {
            final data = userSnap.data()!;
            final currentRp = data['rpBalance'] ?? 0;
            final currentRpLost = data['rpLost'] ?? 0;
            final currentWeeklyRpLost = data['weeklyRpLost'] ?? 0;
            
            tx.update(userRef, {
              'rpBalance': math.max(0, (currentRp as num) - 21),
              'rpLost': (currentRpLost as num) + 21,
              'weeklyRpLost': (currentWeeklyRpLost as num) + 21,
            });
          }
          
          if (alphaSnap.exists) {
            final alphaData = alphaSnap.data()!;
            final alphaRp = alphaData['rpBalance'] ?? 0;
            final alphaGained = alphaData['rpGained'] ?? 0;
            final alphaWeeklyGained = alphaData['weeklyRpGained'] ?? 0;
            
            tx.update(alphaRef, {
              'rpBalance': (alphaRp as num) + 21,
              'rpGained': (alphaGained as num) + 21,
              'weeklyRpGained': (alphaWeeklyGained as num) + 21,
              'currentWeekId': _getWeekId(),
            });
          } else {
             // Create it if it doesn't exist
             tx.set(alphaRef, {
                'firstName': 'Alpha Bot',
                'rpBalance': 21,
                'rpGained': 21,
                'rpLost': 0,
                'weeklyRpGained': 21,
                'weeklyRpLost': 0,
                'totalRpEarned': 21,
                'currentWeekId': _getWeekId(),
                'welcomeRPClaimed': false,
             });
          }
        });
        
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulated SPECIFIC territory loss of 21 RP!')));
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No matching territory found to lose!')));
      }
    } catch (e) {
      log('Error simulating loss: $e');
    }
  }

  Future<void> simulateAlphaAttack(BuildContext context, String currentUserId, {String shape = 'circle'}) async {
    try {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulating Alpha attack...')));
      
      final query = await _firestore.collection('PolygonTerritories')
          .where('owner_id', isEqualTo: currentUserId)
          .get();
          
      if (query.docs.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no territories to attack!')));
        return;
      }
      
      final docs = query.docs;
      final doc = docs[math.Random().nextInt(docs.length)];
      final coords = (doc.data())['coordinates'] as List<dynamic>;
      if (coords.isEmpty) return;
      
      // Center the attack on a random CORNER of the territory rather than the dead center.
      // This ensures the attack intersects the border and doesn't create a "donut hole" 
      // inside the polygon (which our simple flat-array Firestore schema currently can't render).
      final centerPoint = coords[math.Random().nextInt(coords.length)] as GeoPoint;
      
      // Generate the requested shape around this point
      final double lat = centerPoint.latitude;
      final double lon = centerPoint.longitude;
      final double radiusDeg = 0.0025;
      List<List<double>> attackPoints = [];

      if (shape == 'figure8') {
        // Generate a peanut/dumbbell shape that looks like an 8 but doesn't self-intersect
        for (int i = 0; i < 30; i++) {
          final double t = i * (math.pi * 2 / 30);
          // Lemniscate of Gerono (peanut shape)
          // To make it fatter so it doesn't cross itself, we adjust the math
          final double dLat = math.cos(t) * radiusDeg * 1.5;
          final double dLon = math.sin(t) * math.cos(t).abs() * radiusDeg * 1.5 + math.sin(t) * 0.0005; 
          attackPoints.add([lat + dLat, lon + dLon]);
        }
      } else if (shape == 'star') {
        // Generate a 5-point star
        for (int i = 0; i < 10; i++) {
          final double angle = i * (math.pi * 2 / 10);
          final double currentRadius = (i % 2 == 0) ? radiusDeg : radiusDeg * 0.4;
          final double dLat = math.cos(angle) * currentRadius;
          final double dLon = math.sin(angle) * currentRadius;
          attackPoints.add([lat + dLat, lon + dLon]);
        }
      } else {
        // Default circle
        for (int i = 0; i < 12; i++) {
          final double angle = i * (math.pi * 2 / 12);
          final double dLat = math.cos(angle) * radiusDeg;
          final double dLon = math.sin(angle) * radiusDeg;
          attackPoints.add([lat + dLat, lon + dLon]);
        }
      }
      
      // Mapbox requires GeoJSON outer rings to be COUNTER-CLOCKWISE!
      // Our math generated a clockwise shape, so we MUST reverse it before closing it!
      attackPoints = attackPoints.reversed.toList();
      
      // close the polygon
      if (attackPoints.isNotEmpty) {
        attackPoints.add([attackPoints[0][0], attackPoints[0][1]]);
      }
      
      await TerritoryService().submitCustomTerritory(
        pathCoordinates: attackPoints,
        areaM2: 196349, // ~pi * 250^2
        userId: 'mock_user_alpha',
        earnedRP: 15,
      );
      
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alpha successfully attacked your territory!')));
      
    } catch (e, stack) {
      log('Error simulating Alpha attack: $e\n$stack');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}



