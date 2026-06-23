import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/territory_service.dart';
import '../theme/app_colors.dart';
import 'territory_map_screen.dart';

class MyTerritoriesScreen extends StatefulWidget {
  const MyTerritoriesScreen({Key? key}) : super(key: key);

  @override
  State<MyTerritoriesScreen> createState() => _MyTerritoriesScreenState();
}

class _MyTerritoriesScreenState extends State<MyTerritoriesScreen> {
  bool _isLoading = true;
  List<PolygonTerritory> _territories = [];

  @override
  void initState() {
    super.initState();
    _loadTerritories();
  }

  Future<void> _loadTerritories() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final territories = await TerritoryService().getUserTerritories(uid);
      if (mounted) {
        setState(() {
          _territories = territories;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading territories: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        title: Text(
          'MY AREAS',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.radarCyan))
          : _territories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.map, color: AppColors.textMuted, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'No areas captured yet',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete runs to capture areas in your city.',
                        style: GoogleFonts.inter(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _territories.length,
                  itemBuilder: (context, index) {
                    final territory = _territories[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TerritoryMapScreen(territory: territory),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCardSolid,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.radarCyan.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Area #${index + 1}',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.stars, color: AppColors.amber, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${territory.rp} RP Value',
                                      style: GoogleFonts.orbitron(
                                        color: AppColors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.radarCyan),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
