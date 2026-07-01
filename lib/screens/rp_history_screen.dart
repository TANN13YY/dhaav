import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/run_history_service.dart';
import '../services/run_tracker.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

class RPHistoryScreen extends StatefulWidget {
  const RPHistoryScreen({super.key});

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
      final dhaavId = await UserService().fetchDhaavId(uid);
      if (dhaavId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final allRuns = await RunHistoryService().getUserRuns(dhaavId);
      final rpRuns = allRuns.where((run) => run.totalRP > 0 && !run.isMock).toList();
      
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'RP HISTORY',
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _rpRuns.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stars, color: Theme.of(context).hintColor, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'No RP earned yet',
                        style: GoogleFonts.inter(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Complete a run to start earning RP!',
                        style: GoogleFonts.inter(color: Theme.of(context).hintColor),
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
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
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
                                  color: Theme.of(context).hintColor,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                run.totalDistanceKm == 0 
                                  ? 'Welcome Bonus' 
                                  : '${run.totalDistanceKm.toStringAsFixed(2)} km Run',
                                style: GoogleFonts.inter(
                                  color: Theme.of(context).colorScheme.onSurface,
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
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.stars, color: AppColors.gold, size: 16),
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
