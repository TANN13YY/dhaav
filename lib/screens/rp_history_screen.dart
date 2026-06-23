import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/run_history_service.dart';
import '../services/run_tracker.dart';
import '../theme/app_colors.dart';

class RPHistoryScreen extends StatefulWidget {
  const RPHistoryScreen({Key? key}) : super(key: key);

  @override
  State<RPHistoryScreen> createState() => _RPHistoryScreenState();
}

class _RPHistoryScreenState extends State<RPHistoryScreen> {
  bool _isLoading = true;
  List<RunResult> _rpRuns = [];

  @override
  void initState() {
    super.initState();
    _loadRPHistory();
  }

  Future<void> _loadRPHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final allRuns = await RunHistoryService().getUserRuns(uid);
      final rpRuns = allRuns.where((run) => run.totalRP > 0).toList();
      
      if (mounted) {
        setState(() {
          _rpRuns = rpRuns;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading RP history: $e');
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
          'RP HISTORY',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _rpRuns.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.stars, color: AppColors.textMuted, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'No RP earned yet',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete a run to start earning RP!',
                        style: GoogleFonts.inter(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rpRuns.length,
                  itemBuilder: (context, index) {
                    final run = _rpRuns[index];
                    final dateStr = '${run.timestamp.day}/${run.timestamp.month}/${run.timestamp.year}';
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCardSolid,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.amber.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                run.totalDistanceKm == 0 
                                  ? 'Welcome Bonus' 
                                  : '${run.totalDistanceKm.toStringAsFixed(2)} km Run',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                '+${run.totalRP}',
                                style: GoogleFonts.orbitron(
                                  color: AppColors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.stars, color: AppColors.amber, size: 16),
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
