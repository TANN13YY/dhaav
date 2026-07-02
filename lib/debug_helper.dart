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
        
        if (owner == 'mock_user_alpha') {
          deleted++; // just counting now, no longer deleting
        }
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Map Debug: Found $deleted Alpha territories (Not deleted)')));
      }
      
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
