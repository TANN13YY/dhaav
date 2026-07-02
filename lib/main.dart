import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/main_layout.dart';
import 'theme/app_colors.dart';
import 'theme/theme_manager.dart';
import 'services/settings_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SettingsManager.instance.initialize();

  // Set the Mapbox access token from build args (--dart-define=ACCESS_TOKEN=pk.xxx)
  const mapboxToken = String.fromEnvironment('ACCESS_TOKEN');
  if (mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxToken);
  }

  // Initialize Firebase
  await Firebase.initializeApp();

  runApp(const DhaavApp());
}

/// ── Root App Widget ────────────────────────────────────────────────────────
class DhaavApp extends StatelessWidget {
  const DhaavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeManager().isDarkMode,
      builder: (context, isDark, _) {
        // Update system UI to match the current theme
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark ? const Color(0xFF121212) : Colors.white,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp(
          title: 'Dhaav',
          debugShowCheckedModeBanner: false,
          theme: isDark ? AppTheme.dark() : AppTheme.light(),
          themeAnimationDuration: Duration.zero,
          home: const AuthGate(),
        );
      },
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
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
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
