import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/main_layout.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the Mapbox access token from build args (--dart-define=ACCESS_TOKEN=pk.xxx)
  const mapboxToken = String.fromEnvironment('ACCESS_TOKEN');
  if (mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxToken);
  }

  // Initialize Firebase
  await Firebase.initializeApp();

  // Immersive system UI — edge-to-edge dark chrome
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surfaceDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const DhaavApp());
}

/// ── Root App Widget ─────────────────────────────────────────────────────────
class DhaavApp extends StatelessWidget {
  const DhaavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dhaav - GTA Turf War Fitness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.radarCyan,
          secondary: AppColors.crimson,
          surface: AppColors.surfaceDark,
          error: AppColors.errorRed,
          onPrimary: AppColors.surfaceDark,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimary,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.surfaceDark,
        textTheme: GoogleFonts.orbitronTextTheme(
          ThemeData.dark().textTheme,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// ── AuthGate ────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: AppColors.radarCyan,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final bool isLoggedIn = snapshot.hasData;
        return MainLayout(
          key: ValueKey<bool>(isLoggedIn),
          showLoginOnLaunch: !isLoggedIn,
        );
      },
    );
  }
}
