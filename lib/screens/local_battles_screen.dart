import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/battle_event.dart';
import '../theme/app_colors.dart';

class LocalBattlesScreen extends StatefulWidget {
  const LocalBattlesScreen({super.key});

  @override
  State<LocalBattlesScreen> createState() => _LocalBattlesScreenState();
}

class _LocalBattlesScreenState extends State<LocalBattlesScreen> {
  bool _isLoading = true;
  List<BattleEvent> _battles = [];

  @override
  void initState() {
    super.initState();
    _loadBattles();
  }

  Future<void> _loadBattles() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('BattleHistory')
          .where('participants', arrayContains: uid)
          .orderBy('timestamp', descending: true)
          .get();

      final battles = snapshot.docs.map((doc) => BattleEvent.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _battles = battles;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading battles: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'LOCAL BATTLES',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : _battles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_fire_department, color: Theme.of(context).hintColor, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'No local battles yet',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          "Once you capture an area that overlaps with another runner, it will show up here.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: Theme.of(context).hintColor),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _battles.length,
                  itemBuilder: (context, index) {
                    final battle = _battles[index];
                    final isAttacker = battle.attackerId == uid;
                    
                    final dateStr = '${battle.timestamp.day}/${battle.timestamp.month}/${battle.timestamp.year}';
                    
                    final title = isAttacker ? 'You captured territory!' : 'Territory stolen!';
                    final color = isAttacker ? Theme.of(context).colorScheme.primary : AppColors.errorRed;
                    final icon = isAttacker ? Icons.arrow_upward : Icons.arrow_downward;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$dateStr  •  ${battle.locationName}',
                                style: GoogleFonts.inter(
                                  color: Theme.of(context).hintColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, color: color, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${battle.rpStolen} RP',
                                    style: GoogleFonts.orbitron(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
