import 'package:cloud_firestore/cloud_firestore.dart';

class BattleEvent {
  final String id;
  final String attackerId;
  final String defenderId;
  final int rpStolen;
  final double areaSqm;
  final DateTime timestamp;
  final String locationName;
  final List<List<double>>? capturedCoordinates;

  BattleEvent({
    required this.id,
    required this.attackerId,
    required this.defenderId,
    required this.rpStolen,
    required this.areaSqm,
    required this.timestamp,
    required this.locationName,
    this.capturedCoordinates,
  });

  factory BattleEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    List<List<double>>? coords;
    if (data['capturedCoordinates'] != null) {
      coords = (data['capturedCoordinates'] as List).map((point) {
        if (point is GeoPoint) {
          return [point.latitude, point.longitude];
        } else if (point is Map) {
          // If stored as map somehow
          return [(point['latitude'] ?? 0.0) as double, (point['longitude'] ?? 0.0) as double];
        }
        return [0.0, 0.0];
      }).toList();
    }
    
    return BattleEvent(
      id: doc.id,
      attackerId: data['attackerId'] ?? '',
      defenderId: data['defenderId'] ?? '',
      rpStolen: data['rpStolen'] ?? 0,
      areaSqm: (data['areaSqm'] ?? 0.0).toDouble(),
      timestamp: data['timestamp'] != null 
          ? (data['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      locationName: data['locationName'] ?? 'Unknown Area',
      capturedCoordinates: coords,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'attackerId': attackerId,
      'defenderId': defenderId,
      'rpStolen': rpStolen,
      'timestamp': FieldValue.serverTimestamp(),
      'locationName': locationName,
      if (capturedCoordinates != null)
        'capturedCoordinates': capturedCoordinates!.map((c) => GeoPoint(c[0], c[1])).toList(),
    };
  }
}
