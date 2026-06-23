import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFriends = false; // false = Worldwide, true = Friends

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildCategoryTabs(),
            const SizedBox(height: 12),
            _buildScopeToggle(),
            const SizedBox(height: 12),
            Expanded(child: _buildLeaderboardList()),
          ],
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        'LEADERBOARD',
        style: GoogleFonts.orbitron(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 1.5,
          shadows: [
            const Shadow(color: AppColors.radarCyan, blurRadius: 8),
          ],
        ),
      ),
    );
  }

  // ─── Top Category Tabs ──────────────────────────────────────────────────

  Widget _buildCategoryTabs() {
    final labels = ['OVERALL', 'TOP GAINERS', 'TOP STEALERS'];
    final icons = [Icons.bar_chart, Icons.trending_up, Icons.flash_on];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(3, (i) {
          final selected = _tabController.index == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _tabController.animateTo(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.surfaceCardSolid
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? AppColors.radarCyan.withOpacity(0.5)
                        : Colors.white12,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[i],
                      color: selected ? AppColors.radarCyan : AppColors.textMuted,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: selected ? Colors.white : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Friends / Worldwide Toggle ─────────────────────────────────────────

  Widget _buildScopeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceCardSolid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            _buildScopeButton('Friends', _isFriends, () {
              HapticFeedback.selectionClick();
              setState(() => _isFriends = true);
            }),
            _buildScopeButton('Worldwide', !_isFriends, () {
              HapticFeedback.selectionClick();
              setState(() => _isFriends = false);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeButton(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: active ? AppColors.purpleToViolet : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: active ? Colors.white : AppColors.textMuted,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Leaderboard List ───────────────────────────────────────────────────

  Widget _buildLeaderboardList() {
    if (_isFriends) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'No friends added yet',
        subtitle: 'Add friends to see how you stack up against them.',
      );
    }

    // Determine Firestore field based on selected tab
    String orderByField;
    switch (_tabController.index) {
      case 0:
        orderByField = 'total_rp'; // Overall = net balance
        break;
      case 1:
        orderByField = 'total_rp'; // Top Gainers = most territory gained
        break;
      case 2:
        orderByField = 'total_rp'; // Top Stealers = most territory stolen
        break;
      default:
        orderByField = 'total_rp';
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Users')
          .orderBy(orderByField, descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child:
                CircularProgressIndicator(color: AppColors.radarCyan, strokeWidth: 2),
          );
        }

        if (snapshot.hasError) {
          return _buildEmptyState(
            icon: Icons.cloud_off,
            title: 'Connection Error',
            subtitle: 'Could not reach the server. Try again later.',
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'No rankings yet',
            subtitle: 'Start running to claim territory and appear here!',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final name = data['name'] ?? data['username'] ?? 'Anonymous';
            final rp = data['total_rp'] ?? 0;
            return _buildRankCard(index + 1, name.toString(), rp as int);
          },
        );
      },
    );
  }

  // ─── Rank Card ──────────────────────────────────────────────────────────

  Widget _buildRankCard(int rank, String name, int rp) {
    final isTop3 = rank <= 3;
    final Color rankColor = rank == 1
        ? AppColors.amber
        : rank == 2
            ? Colors.grey.shade300
            : rank == 3
                ? const Color(0xFFCD7F32)
                : AppColors.textMuted;

    final Color badgeBg = rank == 1
        ? AppColors.amber.withOpacity(0.15)
        : rank == 2
            ? Colors.grey.withOpacity(0.15)
            : rank == 3
                ? const Color(0xFFCD7F32).withOpacity(0.15)
                : AppColors.surfaceCardSolid;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isTop3
                    ? rankColor.withOpacity(0.4)
                    : Colors.white10,
                width: isTop3 ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Rank badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    shape: BoxShape.circle,
                    border: isTop3
                        ? Border.all(color: rankColor.withOpacity(0.6))
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: GoogleFonts.orbitron(
                      color: rankColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Avatar placeholder
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surfaceCardSolid,
                  child: Text(
                    name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppColors.radarCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name
                Expanded(
                  child: Text(
                    name.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // RP count
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCardSolid,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$rp',
                        style: GoogleFonts.orbitron(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'm²',
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Empty State ────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
