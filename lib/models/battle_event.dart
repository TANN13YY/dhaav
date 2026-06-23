import 'package:cloud_firestore/cloud_firestore.dart';

class BattleEvent {
  final String id;
  final String attackerId;
  final String defenderId;
  final int rpStolen;
  final DateTime timestamp;
  final String locationName;

  BattleEvent({
    required this.id,
    required this.attackerId,
    required this.defenderId,
    required this.rpStolen,
    required this.timestamp,
    required this.locationName,
  });

  factory BattleEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BattleEvent(
      id: doc.id,
      attackerId: data['attackerId'] ?? '',
      defenderId: data['defenderId'] ?? '',
      rpStolen: data['rpStolen'] ?? 0,
      timestamp: data['timestamp'] != null 
          ? (data['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      locationName: data['locationName'] ?? 'Unknown Area',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'attackerId': attackerId,
      'defenderId': defenderId,
      'rpStolen': rpStolen,
      'timestamp': FieldValue.serverTimestamp(),
      'locationName': locationName,
    };
  }
}
