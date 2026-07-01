import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../widgets/notifications_dialog.dart';
import '../widgets/profile_settings_sheet.dart';
import 'local_battles_screen.dart';
import 'my_territories_screen.dart';
import 'rp_history_screen.dart';
import 'shop_screen.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return StreamBuilder<QuerySnapshot>(
      stream: user != null ? FirebaseFirestore.instance.collection('Users').where('authUid', isEqualTo: user.uid).limit(1).snapshots() : null,
      builder: (context, snapshot) {
        String displayUsername = user?.email?.split('@').first ?? 'AGENT_UNKNOWN';
        String initials = displayUsername.isNotEmpty 
            ? displayUsername.substring(0, displayUsername.length >= 2 ? 2 : 1).toUpperCase() 
            : 'U';

        Map<String, dynamic>? data;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          String firstName = data['firstName'] ?? '';
          String lastName = data['lastName'] ?? '';
          
          if (firstName.trim().isNotEmpty || lastName.trim().isNotEmpty) {
            displayUsername = '${firstName.trim()} ${lastName.trim()}'.trim();
          } else if (data['username'] != null && data['username'].toString().trim().isNotEmpty) {
            displayUsername = data['username'];
          }
          
          if (firstName.trim().isNotEmpty && lastName.trim().isNotEmpty) {
            initials = '${firstName.trim()[0]}${lastName.trim()[0]}'.toUpperCase();
          } else if (firstName.trim().isNotEmpty) {
            initials = firstName.trim()[0].toUpperCase();
          } else {
            initials = displayUsername.substring(0, displayUsername.length >= 2 ? 2 : 1).toUpperCase();
          }
        }
        
        bool showNotificationDot = false;
        if (data != null) {
          showNotificationDot = !(data['welcomeRPClaimed'] ?? false);
        }
        
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Stack(
                children: [
                  Icon(Icons.notifications_none, color: Theme.of(context).colorScheme.onSurface),
                  if (showNotificationDot)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                showNotificationsFullscreen(context);
              },
            ),
            title: Text(
              'ME',
              style: GoogleFonts.orbitron(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showProfileSettingsSheet(context, onNavigateToMe: () {});
                  },
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).cardColor,
                    child: Text(
                      initials,
                      style: GoogleFonts.orbitron(fontSize: 10, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileHeader(context, displayUsername, initials, data),
                SizedBox(height: 32),
                _buildSectionHeader(context, 'Dhaav Store', 'Gear up and customize', Icons.storefront),
                SizedBox(height: 16),
                _buildShopCard(context),
                SizedBox(height: 32),
                _buildSectionHeader(context, 'Local battles', 'Compete for local dominance', Icons.local_fire_department),
                SizedBox(height: 16),
                _buildLocalBattlesCard(context),
                SizedBox(height: 32),
                _buildSectionHeader(context, 'My Territories', 'Manage your area', Icons.map),
                const SizedBox(height: 16),
                _buildTerritoriesCard(context),
                const SizedBox(height: 48),
                Center(child: _buildLogoutButton()),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildProfileHeader(BuildContext context, String name, String initials, Map<String, dynamic>? data) {
    final rpBalance = data?['rpBalance'] ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).cardColor,
              child: Text(
                initials,
                style: GoogleFonts.orbitron(fontSize: 18, color: Theme.of(context).colorScheme.primary),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.toUpperCase(),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (data != null && data['dhaavId'] != null)
                    Text(
                      'DHAAV ID: ${data['dhaavId']}',
                      style: GoogleFonts.inter(
                        color: Theme.of(context).hintColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RPHistoryScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stars, color: AppColors.gold, size: 16),
                          SizedBox(width: 4),
                          Text(
                            '$rpBalance RP BALANCE',
                            style: GoogleFonts.orbitron(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: AppColors.gold, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).cardColor,
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.onSurface, size: 20),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: Theme.of(context).hintColor,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildShopCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spend your hard-earned RP on premium avatars, custom map trails, and exclusive gear.',
            style: GoogleFonts.inter(
              color: Theme.of(context).hintColor,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen()));
                },
                child: Text(
                  'ENTER SHOP',
                  style: GoogleFonts.orbitron(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalBattlesCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalBattlesScreen()));
      },
      child: Container(
        width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Local Battle History',
            style: GoogleFonts.inter(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Tap to view recent battles and territory clashes in your area.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Theme.of(context).hintColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTerritoriesCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTerritoriesScreen()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, color: Theme.of(context).hintColor, size: 32),
            const SizedBox(height: 16),
            Text(
              'My Territories',
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "View your captured areas and empires.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.errorRed,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      onPressed: () => FirebaseAuth.instance.signOut(),
      icon: const Icon(Icons.logout),
      label: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
    );
  }
}
