import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/user_service.dart';
import '../theme/theme_manager.dart';
import '../models/battle_event.dart';
import '../theme/app_colors.dart';
import '../services/territory_service.dart';
import 'territory_map_screen.dart';

class LocalBattlesScreen extends StatefulWidget {
  const LocalBattlesScreen({super.key});

  @override
  State<LocalBattlesScreen> createState() => _LocalBattlesScreenState();
}

class _LocalBattlesScreenState extends State<LocalBattlesScreen> {
  bool _isLoading = true;
  List<BattleEvent> _battles = [];
  Map<String, String> _userNames = {};
  String? _currentDhaavId;

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
      final dhaavId = await UserService().fetchDhaavId(uid);
      if (dhaavId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      
      _currentDhaavId = dhaavId;
      
      final snapshot = await FirebaseFirestore.instance
          .collection('BattleHistory')
          .where('participants', arrayContains: dhaavId)
          .get();

      final allBattles = snapshot.docs.map((doc) => BattleEvent.fromFirestore(doc)).toList();
      
      // Sort locally to avoid needing a Firestore composite index
      allBattles.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      final battles = allBattles;

      // Fetch opponent usernames
      Set<String> uidsToFetch = {};
      for (var b in battles) {
        if (b.attackerId != dhaavId) uidsToFetch.add(b.attackerId);
        if (b.defenderId != dhaavId) uidsToFetch.add(b.defenderId);
      }

      Map<String, String> fetchedNames = {};
      for (var id in uidsToFetch) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('Users').doc(id).get();
          if (userDoc.exists) {
            fetchedNames[id] = userDoc.data()?['username'] ?? 'Unknown Runner';
          }
        } catch (e) {}
      }
      if (mounted) {
        setState(() {
          _battles = battles;
          _userNames = fetchedNames;
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
            color: Theme.of(context).colorScheme.onSurface,
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
                      SizedBox(height: 16),
                      Text(
                        'No local battles yet',
                        style: GoogleFonts.inter(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
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
                    final isAttacker = battle.attackerId == _currentDhaavId;
                    
                    final dateStr = '${battle.timestamp.day}/${battle.timestamp.month}/${battle.timestamp.year}';
                    
                    final opponentId = isAttacker ? battle.defenderId : battle.attackerId;
                    final opponentName = _userNames[opponentId] ?? 'Unknown Runner';

                    final title = isAttacker ? 'You captured territory from $opponentName!' : '$opponentName stole territory!';
                    final color = isAttacker ? Theme.of(context).colorScheme.primary : AppColors.errorRed;
                    final icon = isAttacker ? Icons.arrow_upward : Icons.arrow_downward;

                    return GestureDetector(
                      onTap: () {
                        if (battle.capturedCoordinates != null && battle.capturedCoordinates!.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TerritoryMapScreen(
                                territory: PolygonTerritory(
                                  id: battle.id,
                                  ownerId: battle.attackerId,
                                  rp: battle.rpStolen,
                                  areaSqm: battle.areaSqm,
                                  coordinates: battle.capturedCoordinates!,
                                ),
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('No map data available for this older battle.')),
                          );
                        }
                      },
                      child: Container(
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$dateStr  •  ${battle.locationName}',
                                  style: GoogleFonts.inter(
                                    color: Theme.of(context).hintColor,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  title,
                                  style: GoogleFonts.inter(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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
                              if (battle.areaSqm > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${(battle.areaSqm).toStringAsFixed(1)} m²',
                                    style: GoogleFonts.inter(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ));
                  },
                ),
    );
  }
}
