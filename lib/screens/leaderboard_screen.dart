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
  bool _isWeekly = false; // false = All Time, true = Weekly

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

  /// Returns the current ISO week identifier, e.g. "2026-W26"
  String _getWeekId() {
    final now = DateTime.now();
    final jan4 = DateTime(now.year, 1, 4);
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final weekNumber = ((dayOfYear - now.weekday + jan4.weekday + 6) ~/ 7);
    return '${now.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            SizedBox(height: 8),
            _buildCategoryTabs(),
            SizedBox(height: 12),
            _buildTimeToggle(),
            SizedBox(height: 12),
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
          color: Theme.of(context).colorScheme.onSurface,
          letterSpacing: 1.5,
          shadows: [
            Shadow(color: Theme.of(context).colorScheme.primary, blurRadius: 8),
          ],
        ),
      ),
    );
  }

  // ─── Top Category Tabs ──────────────────────────────────────────────────

  Widget _buildCategoryTabs() {
    final labels = ['OVERALL', 'TOP GAINERS', 'TOP LOSERS'];
    final icons = [Icons.bar_chart, Icons.trending_up, Icons.trending_down];

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
                      ? Theme.of(context).cardColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                        : Colors.white10,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      icons[i],
                      color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
                      size: 20,
                    ),
                    SizedBox(height: 6),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: selected ? Colors.white : Theme.of(context).hintColor,
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

  // ─── Weekly / All Time Toggle ───────────────────────────────────────────

  Widget _buildTimeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            _buildTimeButton('All Time', !_isWeekly, () {
              HapticFeedback.selectionClick();
              setState(() => _isWeekly = false);
            }),
            _buildTimeButton('Weekly', _isWeekly, () {
              HapticFeedback.selectionClick();
              setState(() => _isWeekly = true);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeButton(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active ? Theme.of(context).colorScheme.secondary : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: active ? Colors.white : Theme.of(context).hintColor,
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
    // Determine the field to order by and display label
    String orderByField;
    String metricLabel;

    switch (_tabController.index) {
      case 0: // Overall — net RP (rpGained)
        orderByField = _isWeekly ? 'weeklyRpGained' : 'rpGained';
        metricLabel = 'RP';
        break;
      case 1: // Top Gainers
        orderByField = _isWeekly ? 'weeklyRpGained' : 'rpGained';
        metricLabel = 'RP';
        break;
      case 2: // Top Losers
        orderByField = _isWeekly ? 'weeklyRpLost' : 'rpLost';
        metricLabel = 'RP';
        break;
      default:
        orderByField = 'rpGained';
        metricLabel = 'RP';
    }

    // Build the Firestore query
    Query query = FirebaseFirestore.instance.collection('Users');

    if (_isWeekly) {
      final weekId = _getWeekId();
      query = query.where('currentWeekId', isEqualTo: weekId);
    }

    query = query.orderBy(orderByField, descending: true).limit(50);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
          );
        }

        if (snapshot.hasError) {
          // Common: missing composite index — show a helpful message
          final errorMsg = snapshot.error.toString();
          if (errorMsg.contains('FAILED_PRECONDITION') || errorMsg.contains('index')) {
            return _buildEmptyState(
              icon: Icons.build_circle_outlined,
              title: 'Index Required',
              subtitle:
                  'A Firestore composite index is needed for this query. Check the debug console for the index creation link.',
            );
          }
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
            subtitle: _isWeekly
                ? 'No one has earned RP this week yet. Start running!'
                : 'Start running to earn RP and appear here!',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final firstName = data['firstName'] ?? '';
            final lastName = data['lastName'] ?? '';
            final username = data['username'] ?? '';
            
            // Build display name
            String name;
            if (firstName.toString().trim().isNotEmpty) {
              name = lastName.toString().trim().isNotEmpty
                  ? '${firstName.toString().trim()} ${lastName.toString().trim()}'
                  : firstName.toString().trim();
            } else if (username.toString().trim().isNotEmpty) {
              name = username.toString().trim();
            } else {
              name = 'Anonymous';
            }

            // Get the metric value based on current tab
            int metricValue;
            switch (_tabController.index) {
              case 0: // Overall — show net: rpGained - rpLost
                final gained = (data[_isWeekly ? 'weeklyRpGained' : 'rpGained'] ?? 0) as num;
                final lost = (data[_isWeekly ? 'weeklyRpLost' : 'rpLost'] ?? 0) as num;
                metricValue = (gained - lost).toInt();
                break;
              case 1: // Top Gainers
                metricValue = (data[orderByField] ?? 0) as int;
                break;
              case 2: // Top Losers
                metricValue = (data[orderByField] ?? 0) as int;
                break;
              default:
                metricValue = 0;
            }

            return _buildRankCard(
              index + 1,
              name,
              metricValue,
              metricLabel,
              isLoss: _tabController.index == 2,
            );
          },
        );
      },
    );
  }

  // ─── Rank Card ──────────────────────────────────────────────────────────

  Widget _buildRankCard(int rank, String name, int value, String label,
      {bool isLoss = false}) {
    final isTop3 = rank <= 3;
    final Color rankColor = rank == 1
        ? AppColors.gold
        : rank == 2
            ? Colors.grey.shade300
            : rank == 3
                ? const Color(0xFFCD7F32)
                : Theme.of(context).hintColor;

    final Color badgeBg = rank == 1
        ? AppColors.gold.withValues(alpha: 0.15)
        : rank == 2
            ? Colors.grey.withValues(alpha: 0.15)
            : rank == 3
                ? const Color(0xFFCD7F32).withValues(alpha: 0.15)
                : Theme.of(context).cardColor;

    // Color for the RP value — red for losers tab, green/white otherwise
    final Color valueColor = isLoss ? const Color(0xFFFF6B6B) : Colors.white;
    final String prefix = isLoss ? '-' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isTop3
                    ? rankColor.withValues(alpha: 0.4)
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
                        ? Border.all(color: rankColor.withValues(alpha: 0.6))
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
                SizedBox(width: 14),

                // Avatar placeholder
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).cardColor,
                  child: Text(
                    name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),

                // Name
                Expanded(
                  child: Text(
                    name.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Theme.of(context).colorScheme.onSurface,
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
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$prefix$value',
                        style: GoogleFonts.orbitron(
                          color: valueColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).hintColor,
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
          Icon(icon, color: Theme.of(context).hintColor, size: 48),
          SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Theme.of(context).hintColor,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
