import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_settings_sheet.dart';
import 'notifications_dialog.dart';

class HomeMapOverlay extends StatelessWidget {
  const HomeMapOverlay({super.key, required this.onLocateMe, required this.onNavigateToMe});

  final VoidCallback onLocateMe;
  final VoidCallback onNavigateToMe;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 16;
    final user = FirebaseAuth.instance.currentUser;
    
    return StreamBuilder<QuerySnapshot>(
      stream: user != null ? FirebaseFirestore.instance.collection('Users').where('authUid', isEqualTo: user.uid).limit(1).snapshots() : null,
      builder: (context, snapshot) {
        String displayUsername = user?.email?.split('@').first ?? 'U';
        String initials = displayUsername.isNotEmpty 
            ? displayUsername.substring(0, displayUsername.length >= 2 ? 2 : 1).toUpperCase() 
            : 'U';

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
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
        
        // Determine if we need to show notification dot
        bool showNotificationDot = false;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          showNotificationDot = !(data['welcomeRPClaimed'] ?? false);
        }

        return Stack(
          children: [
            // Top Left: Notification Bell
            Positioned(
              top: topPadding,
              left: 16,
              child: Stack(
                children: [
                  _buildIconButton(context, 
                    icon: Icons.notifications_none,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showNotificationsFullscreen(context);
                    },
                  ),
                  if (showNotificationDot)
                    Positioned(
                      top: 4,
                      right: 4,
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
            ),

            // Top Right: Profile Picture → opens settings sheet
            Positioned(
              top: topPadding,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showProfileSettingsSheet(context, onNavigateToMe: onNavigateToMe);
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), width: 2),
                    color: Theme.of(context).cardColor,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.orbitron(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Middle Right: Locate Me
            Positioned(
              right: 16,
              bottom: 24, // Sit just above the bottom nav bar
              child: _buildIconButton(context, 
                icon: Icons.my_location,
                onTap: onLocateMe,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildIconButton(context, {required IconData icon, required VoidCallback onTap, Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: color ?? Theme.of(context).colorScheme.onSurface, size: 24),
      ),
    );
  }


}
