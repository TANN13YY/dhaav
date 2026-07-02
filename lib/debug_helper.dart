import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DebugHelper {
  static Future<void> analyzeTerritories(BuildContext context) async {
    try {
      final db = FirebaseFirestore.instance;
      
      // 1. Check for orphaned 'Anonymous' users and delete them
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      String? currentDhaavId;
      if (currentUid != null) {
        final userQuery = await db.collection('Users').where('authUid', isEqualTo: currentUid).limit(1).get();
        if (userQuery.docs.isNotEmpty) currentDhaavId = userQuery.docs.first.id;
      }

      final usersSnapshot = await db.collection('Users').get();
      int deletedUsers = 0;
      for (var doc in usersSnapshot.docs) {
        final id = doc.id;
        final data = doc.data();
        if (id == 'mock_user_alpha') continue; // keep alpha
        if (id == currentDhaavId) continue; // keep current user
        
        // If it's a mock user or doesn't have a name, delete it to keep leaderboard clean
        final fName = (data['firstName'] ?? '').toString().trim();
        final uName = (data['username'] ?? '').toString().trim();
        if (fName.isEmpty && uName.isEmpty) {
          await doc.reference.delete();
          deletedUsers++;
        }
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Database Cleanup: Removed $deletedUsers orphaned/anonymous users.')));
      }
      
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
