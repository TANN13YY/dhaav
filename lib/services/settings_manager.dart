import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';

/// ── SettingsManager ───────────────────────────────────────────────────────
/// A global singleton that listens to the user's Firestore document
/// and instantly syncs App Settings (Units, Notifications) across the app.
class SettingsManager {
  SettingsManager._();
  static final SettingsManager instance = SettingsManager._();

  StreamSubscription? _authSub;
  StreamSubscription? _userDocSub;

  /// Emits 'metric' (default) or 'imperial'
  final ValueNotifier<String> unitNotifier = ValueNotifier<String>('metric');

  /// Emits the current notification preferences
  final ValueNotifier<Map<String, dynamic>> notificationNotifier = ValueNotifier<Map<String, dynamic>>({
    'territoryAlerts': true,
    'runReminders': true,
    'leaderboardUpdates': false,
    'socialNotifications': true,
  });

  bool get isMetric => unitNotifier.value == 'metric';
  String get unitSuffix => isMetric ? 'km' : 'mi';

  /// Initializes listeners to auth state and user settings.
  void initialize() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _userDocSub?.cancel();
      if (user != null) {
        final dhaavId = await UserService().fetchDhaavId(user.uid);
        if (dhaavId != null) {
          _userDocSub = FirebaseFirestore.instance
              .collection('Users')
              .doc(dhaavId)
              .snapshots()
              .listen((snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;
            final settings = data['settings'] as Map<String, dynamic>? ?? {};

            unitNotifier.value = settings['units'] ?? 'metric';

            final currentNotifs = Map<String, dynamic>.from(notificationNotifier.value);
            currentNotifs['territoryAlerts'] = settings['territoryAlerts'] ?? true;
            currentNotifs['runReminders'] = settings['runReminders'] ?? true;
            currentNotifs['leaderboardUpdates'] = settings['leaderboardUpdates'] ?? false;
            currentNotifs['socialNotifications'] = settings['socialNotifications'] ?? true;
            
            notificationNotifier.value = currentNotifs;
            }
          });
        }
      } else {
        // Reset to defaults on logout
        unitNotifier.value = 'metric';
        notificationNotifier.value = {
          'territoryAlerts': true,
          'runReminders': true,
          'leaderboardUpdates': false,
          'socialNotifications': true,
        };
      }
    });
  }

  // ── Helper Methods for Conversion ────────────────────────────────────────

  /// Converts kilometers to miles if imperial is selected.
  double convertDistance(double distanceKm) {
    if (isMetric) return distanceKm;
    return distanceKm * 0.621371; // km to miles
  }

  /// Converts pace from min/km to min/mi if imperial is selected.
  double convertPace(double paceMinPerKm) {
    if (isMetric) return paceMinPerKm;
    return paceMinPerKm / 0.621371; // min/km to min/mi
  }

  /// Format distance securely with the unit suffix
  String formatDistance(double distanceKm) {
    return '${convertDistance(distanceKm).toStringAsFixed(2)} $unitSuffix';
  }
  
  /// Format pace securely with the unit suffix
  String formatPace(double paceMinPerKm) {
    final pace = convertPace(paceMinPerKm);
    if (pace <= 0 || pace.isInfinite || pace.isNaN) return '--:-- /$unitSuffix';
    final mins = pace.floor();
    final secs = ((pace - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')} /$unitSuffix';
  }

  /// Format area securely with the unit suffix
  String formatArea(double areaSqm) {
    if (isMetric) {
      return '${areaSqm.toStringAsFixed(1)} sq m';
    } else {
      final areaSqFt = areaSqm * 10.7639;
      return '${areaSqFt.toStringAsFixed(1)} sq ft';
    }
  }

  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
  }
}
