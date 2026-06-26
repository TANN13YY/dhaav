import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/run_history_service.dart';
import '../services/run_tracker.dart';
import '../theme/app_colors.dart';

void showNotificationsFullscreen(BuildContext context) {
  showDialog(
    context: context,
    useSafeArea: false,
    builder: (ctx) {
      return Dialog.fullscreen(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
            title: Text(
              'NOTIFICATIONS',
              style: GoogleFonts.orbitron(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: const _NotificationsList(),
        ),
      );
    },
  );
}

class _NotificationsList extends StatefulWidget {
  const _NotificationsList();

  @override
  State<_NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends State<_NotificationsList> {
  bool _isLoading = true;
  bool _hasWelcomeBonus = false;
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final bool hasClaimed = data['welcomeRPClaimed'] ?? false;
        if (mounted) {
          setState(() {
            _hasWelcomeBonus = !hasClaimed;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _claimWelcomeBonus() async {
    setState(() => _isClaiming = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final db = FirebaseFirestore.instance;
      
      // Update user document
      await db.collection('Users').doc(uid).set({
        'rpBalance': FieldValue.increment(100),
        'welcomeRPClaimed': true,
      }, SetOptions(merge: true));

      // Add to RunHistory
      final dummyRun = RunResult(
        id: db.collection('RunHistory').doc().id,
        timestamp: DateTime.now(),
        pathCoordinates: [],
        totalDistanceKm: 0.0,
        totalDuration: Duration.zero,
        totalRP: 100,
        averagePaceMinPerKm: 0.0,
        isBusted: false,
        isClosedLoop: false,
        areaM2: 0.0,
      );
      await RunHistoryService().saveRunResult(uid, dummyRun);

      HapticFeedback.heavyImpact();

      if (mounted) {
        setState(() => _hasWelcomeBonus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('100 RP Claimed! Welcome to Dhaav.', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.successGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error claiming bonus: \$e");
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    if (!_hasWelcomeBonus) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined, color: Theme.of(context).hintColor, size: 24),
            const SizedBox(height: 16),
            Text(
              'No new notifications',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars, color: AppColors.gold),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome to Dhaav!',
                      style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "You've been granted a welcome bonus of 100 RP to kickstart your journey.",
                      style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isClaiming ? null : _claimWelcomeBonus,
                child: _isClaiming
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : Text('CLAIM', style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
