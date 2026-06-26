import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../theme/theme_manager.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/run_screen.dart';

/// Shows the profile settings bottom sheet when tapping the profile icon on the Home tab.
void showProfileSettingsSheet(BuildContext context, {required VoidCallback onNavigateToMe}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => _ProfileSettingsContent(
        scrollController: scrollCtrl,
        onNavigateToMe: onNavigateToMe,
      ),
    ),
  );
}

class _ProfileSettingsContent extends StatefulWidget {
  const _ProfileSettingsContent({required this.scrollController, required this.onNavigateToMe});
  final ScrollController scrollController;
  final VoidCallback onNavigateToMe;

  @override
  State<_ProfileSettingsContent> createState() => _ProfileSettingsContentState();
}

class _ProfileSettingsContentState extends State<_ProfileSettingsContent> {
  bool _appSettingsExpanded = false;
  bool _privacyExpanded = false;
  bool _isAnonymous = false;

  @override
  void initState() {
    super.initState();
    _loadAnonymousState();
  }

  Future<void> _loadAnonymousState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _isAnonymous = doc.data()?['isAnonymous'] ?? false;
        });
      }
    }
  }

  Future<void> _setAnonymousState(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('Users').doc(uid).set(
        {'isAnonymous': value}, SetOptions(merge: true)
      );
      if (mounted) {
        setState(() {
          _isAnonymous = value;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null ? FirebaseFirestore.instance.collection('Users').doc(user.uid).snapshots() : null,
      builder: (context, snapshot) {
        String displayUsername = user?.email?.split('@').first ?? 'Agent';
        String initials = displayUsername.isNotEmpty 
            ? displayUsername.substring(0, displayUsername.length >= 2 ? 2 : 1).toUpperCase() 
            : 'U';

        if (snapshot.hasData && snapshot.data!.data() != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          String firstName = data['firstName'] ?? '';
          String lastName = data['lastName'] ?? '';
          
          if (firstName.trim().isNotEmpty && lastName.trim().isNotEmpty) {
            initials = '${firstName.trim()[0]}${lastName.trim()[0]}'.toUpperCase();
          } else if (firstName.trim().isNotEmpty) {
            initials = firstName.trim()[0].toUpperCase();
          } else if (data['username'] != null && data['username'].toString().trim().isNotEmpty) {
            displayUsername = data['username'];
            initials = displayUsername.substring(0, displayUsername.length >= 2 ? 2 : 1).toUpperCase();
          }
        }
        final name = displayUsername;

        return ValueListenableBuilder<bool>(
          valueListenable: ThemeManager().isDarkMode,
          builder: (outerContext, isDark, child) {
            final activeTheme = isDark ? AppTheme.dark() : AppTheme.light();
            return Theme(
              data: activeTheme,
              child: Builder(
                builder: (context) {
                  return Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: ListView(
                      controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Profile header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).cardColor,
                      child: Text(
                        initials,
                        style: GoogleFonts.orbitron(fontSize: 14, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        name.toUpperCase(),
                        style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () {
                        // Close sheet, navigate to Me tab
                        Navigator.pop(context);
                        widget.onNavigateToMe();
                      },
                      child: Text('View profile', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),

              // ── Edit Profile ────────────────────────────────────────────────
              _buildNavigationTile(
                icon: Icons.edit,
                label: 'Edit profile',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                },
              ),
              Divider(color: Theme.of(context).dividerColor, height: 1),

              // ── App Settings (expandable) ───────────────────────────────────
              _buildExpandableTile(
                icon: Icons.settings,
                label: 'App settings',
                expanded: _appSettingsExpanded,
                onTap: () => setState(() => _appSettingsExpanded = !_appSettingsExpanded),
                children: [
                  _buildSubSection(
                    title: 'Notifications',
                    subtitle: 'Manage notifications',
                    onTap: () {
                      _showNotificationSettings(context);
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 1, indent: 16),
                  _buildSubSection(
                    title: 'Units & Measurement',
                    subtitle: 'Kilometres & metres',
                    onTap: () {
                      _showUnitSettings(context);
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 1, indent: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 56, right: 16),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: Theme.of(context).colorScheme.primary,
                      title: Text('App Theme', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(ThemeManager().isDarkMode.value ? 'Dark' : 'Light', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
                      value: ThemeManager().isDarkMode.value,
                      onChanged: (val) {
                        ThemeManager().toggleTheme();
                      },
                    ),
                  ),
                ],
              ),
              Divider(color: Theme.of(context).dividerColor, height: 1),

              // ── Privacy (expandable) ────────────────────────────────────────
              _buildExpandableTile(
                icon: Icons.public,
                label: 'Privacy',
                expanded: _privacyExpanded,
                onTap: () => setState(() => _privacyExpanded = !_privacyExpanded),
                children: [
                  _buildSubAction(
                    icon: Icons.delete_outline,
                    label: 'Remove all my account data',
                    onTap: () => _confirmDeleteData(context),
                  ),
                  Divider(color: Theme.of(context).dividerColor, height: 1, indent: 16),
                  _buildSubAction(
                    icon: _isAnonymous ? Icons.visibility : Icons.visibility_off,
                    label: _isAnonymous ? 'Make my account visible' : 'Make my account anonymous',
                    onTap: () => _toggleAnonymous(context),
                  ),
                ],
              ),
              Divider(color: Theme.of(context).dividerColor, height: 1),

              // ── Contact Support ─────────────────────────────────────────────
              _buildNavigationTile(
                icon: Icons.headset_mic,
                label: 'Contact support',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Support: contact@dhaav.app')),
                  );
                },
              ),
              Divider(color: Theme.of(context).dividerColor, height: 1),

              SizedBox(height: 24),

              // ── Sign Out ────────────────────────────────────────────────────
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      FirebaseAuth.instance.signOut();
                    },
                    icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.onSurface),
                    label: Text('Sign out', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              SizedBox(height: 12),

              // ── Delete Account ──────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: () => _confirmDeleteAccount(context),
                  child: Text(
                    'Delete account',
                    style: GoogleFonts.inter(
                      color: AppColors.errorRed,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.errorRed,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32),
            ],
          ),
                  );
                },
              ),
            );
          },
        );
      }
    );
  }

  // ─── Tile Builders ────────────────────────────────────────────────────

  Widget _buildNavigationTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        leading: Icon(icon, color: Theme.of(context).hintColor),
        title: Text(label, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
        trailing: Icon(Icons.chevron_right, color: Theme.of(context).hintColor),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      ),
    );
  }

  Widget _buildExpandableTile({
    required IconData icon,
    required String label,
    required bool expanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: Icon(icon, color: expanded ? Colors.white : Theme.of(context).hintColor),
            title: Text(label, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: expanded ? FontWeight.bold : FontWeight.normal, fontSize: 15)),
            trailing: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).hintColor),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(left: 16, bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: children),
          ),
          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  Widget _buildSubSection({required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        title: Text(title, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSubAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).hintColor, size: 20),
        title: Text(label, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
        trailing: Icon(Icons.chevron_right, color: Theme.of(context).hintColor, size: 18),
        onTap: onTap,
      ),
    );
  }

  // ─── Action Handlers ──────────────────────────────────────────────────

  void _showNotificationSettings(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.primary)),
        title: Text('Manage Notifications', style: GoogleFonts.orbitron(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
        content: Material(color: Colors.transparent, child: _NotificationSettingsBody()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Done', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _showUnitSettings(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.primary)),
        title: Text('Units & Measurement', style: GoogleFonts.orbitron(color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
        content: Material(color: Colors.transparent, child: _UnitSettingsBody()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('Done', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteData(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.errorRed)),
        title: Text('Delete Account Data', style: GoogleFonts.orbitron(color: AppColors.errorRed, fontSize: 16)),
        content: Text(
          'This will permanently remove all your run history, territories, and stats. This action cannot be undone.',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(context).hintColor))),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              debugPrint('Deleting all account data from backend...');
              try {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  final db = FirebaseFirestore.instance;
                  final batch = db.batch();
                  
                  // 1. Find all physical runs to delete and calculate RP to deduct
                  int rpToRemove = 0;
                  final runsSnapshot = await db.collection('RunHistory').where('owner_id', isEqualTo: uid).get();
                  for (var doc in runsSnapshot.docs) {
                    final data = doc.data();
                    final distance = (data['totalDistanceKm'] ?? 0.0).toDouble();
                    
                    if (distance > 0) { // Keep the 0.0km Welcome Bonus!
                      batch.delete(doc.reference);
                      rpToRemove += (data['totalRP'] as num?)?.toInt() ?? 0;
                    }
                  }
                  
                  // 2. Delete all territories owned by user
                  final territorySnapshot = await db.collection('PolygonTerritories').where('owner_id', isEqualTo: uid).get();
                  for (var doc in territorySnapshot.docs) {
                    batch.delete(doc.reference);
                  }
                  
                  // 3. Deduct RP from user balance (and clean up old fields)
                  batch.update(db.collection('Users').doc(uid), {
                    if (rpToRemove > 0) 'rpBalance': FieldValue.increment(-rpToRemove),
                    'stats': FieldValue.delete(),
                    'runHistory': FieldValue.delete(),
                    'territories': FieldValue.delete(),
                  });
                  
                  await batch.commit();
                }
                
                // Clear local run history
                RunScreen.runHistory.clear();
                RunScreen.historyNotifier.value++;

                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Account data deleted.')));
                }
              } catch (e) {
                debugPrint('Failed to delete user data: $e');
              }
            },
            child: Text('Delete', style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _toggleAnonymous(BuildContext ctx) {
    final bool newAnonymousState = !_isAnonymous;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.secondary)),
        title: Text(newAnonymousState ? 'Go Anonymous' : 'Become Visible', style: GoogleFonts.orbitron(color: Theme.of(context).colorScheme.secondary, fontSize: 16)),
        content: Text(
          newAnonymousState 
              ? 'Your profile will be hidden from all leaderboards. Other players will not be able to see you. You can undo this anytime.'
              : 'Your profile will become visible on the leaderboards again.',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(context).hintColor))),
          TextButton(
            onPressed: () {
              _setAnonymousState(newAnonymousState);
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(newAnonymousState ? 'You are now anonymous.' : 'You are now visible.')
              ));
            },
            child: Text(newAnonymousState ? 'Go Anonymous' : 'Become Visible', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.errorRed)),
        title: Text('DELETE ACCOUNT', style: GoogleFonts.orbitron(color: AppColors.errorRed, fontSize: 16)),
        content: Text(
          'This will permanently delete your account, including all data, runs, territories, and stats. This cannot be reversed.',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: Text('Cancel', style: TextStyle(color: Theme.of(context).hintColor))),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              Navigator.pop(ctx); // Close the bottom sheet as well
              try {
                await FirebaseAuth.instance.currentUser?.delete();
              } catch (e) {
                // If it fails (usually requires recent login), sign out instead.
                debugPrint('Delete failed: $e');
                await FirebaseAuth.instance.signOut();
              }
            },
            child: Text('Delete Forever', style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─── Notification Settings Widget ─────────────────────────────────────────

class _NotificationSettingsBody extends StatefulWidget {
  @override
  State<_NotificationSettingsBody> createState() => _NotificationSettingsBodyState();
}

class _NotificationSettingsBodyState extends State<_NotificationSettingsBody> {
  bool _territoryAlerts = true;
  bool _runReminders = true;
  bool _leaderboardUpdates = false;
  bool _socialNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final settings = doc.data()?['settings'] ?? {};
      if (mounted) {
        setState(() {
          _territoryAlerts = settings['territoryAlerts'] ?? true;
          _runReminders = settings['runReminders'] ?? true;
          _leaderboardUpdates = settings['leaderboardUpdates'] ?? false;
          _socialNotifications = settings['socialNotifications'] ?? true;
        });
      }
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('Users').doc(uid).set({
      'settings': {key: value}
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSwitch('Territory alerts', 'Get notified when someone captures your territory', _territoryAlerts, (v) {
          setState(() => _territoryAlerts = v);
          _saveSetting('territoryAlerts', v);
        }),
        _buildSwitch('Run reminders', 'Daily motivation to keep running', _runReminders, (v) {
          setState(() => _runReminders = v);
          _saveSetting('runReminders', v);
        }),
        _buildSwitch('Leaderboard updates', 'Weekly ranking changes', _leaderboardUpdates, (v) {
          setState(() => _leaderboardUpdates = v);
          _saveSetting('leaderboardUpdates', v);
        }),
        _buildSwitch('Social', 'Friend requests and squad invites', _socialNotifications, (v) {
          setState(() => _socialNotifications = v);
          _saveSetting('socialNotifications', v);
        }),
      ],
    );
  }

  Widget _buildSwitch(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: Theme.of(context).colorScheme.primary,
      title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
      value: value,
      onChanged: onChanged,
    );
  }
}

// ─── Unit Settings Widget ─────────────────────────────────────────────────

class _UnitSettingsBody extends StatefulWidget {
  @override
  State<_UnitSettingsBody> createState() => _UnitSettingsBodyState();
}

class _UnitSettingsBodyState extends State<_UnitSettingsBody> {
  String _selectedUnit = 'metric';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final settings = doc.data()?['settings'] ?? {};
      if (mounted) {
        setState(() {
          _selectedUnit = settings['units'] ?? 'metric';
        });
      }
    }
  }

  Future<void> _saveSetting(String value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('Users').doc(uid).set({
      'settings': {'units': value}
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          activeColor: Theme.of(context).colorScheme.primary,
          title: Text('Kilometres & metres', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          subtitle: Text('Metric system', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
          value: 'metric',
          groupValue: _selectedUnit,
          onChanged: (v) {
            setState(() => _selectedUnit = v!);
            _saveSetting(v!);
          },
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          activeColor: Theme.of(context).colorScheme.primary,
          title: Text('Miles & feet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          subtitle: Text('Imperial system', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
          value: 'imperial',
          groupValue: _selectedUnit,
          onChanged: (v) {
            setState(() => _selectedUnit = v!);
            _saveSetting(v!);
          },
        ),
      ],
    );
  }
}
