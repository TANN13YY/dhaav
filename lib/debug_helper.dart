import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DebugHelper {
  static Future<void> analyzeTerritories(BuildContext context) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('PolygonTerritories').get();
      
      int deleted = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final owner = data['owner_id'];
        
        // Delete ALL mock_user_alpha territories to instantly restore the map
        if (owner == 'mock_user_alpha') {
          await doc.reference.delete();
          deleted++;
        }
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Map Fix: Deleted $deleted Alpha territories!')));
      }
      
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
