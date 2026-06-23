import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';

/// ── AuthService ─────────────────────────────────────────────────────────────
/// Encapsulates Firebase Email/Password and Google Sign-In logic.
/// Firebase automatically persists session state on native platforms,
/// so returning users are never asked to log in again.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  bool _googleInitialized = false;

  /// The currently signed-in user, or null.
  fb_auth.User? get currentUser => _auth.currentUser;

  /// Stream of auth-state changes for the AuthGate.
  Stream<fb_auth.User?> get authStateChanges => _auth.authStateChanges();

  // ── Email / Password ───────────────────────────────────────────────────

  /// Create a new account with email & password.
  Future<fb_auth.UserCredential> signUpWithEmail(String email, String password) async {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sign in with existing email & password.
  Future<fb_auth.UserCredential> signInWithEmail(String email, String password) async {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────

  /// Full Google Sign-In flow → Firebase credential.
  Future<fb_auth.UserCredential> signInWithGoogle() async {
    // Initialize once (google_sign_in v7+ requirement)
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;

    final fb_auth.OAuthCredential credential = fb_auth.GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
  }

  // ── Anonymous Sign-In ──────────────────────────────────────────────────

  /// Sign in anonymously.
  Future<fb_auth.UserCredential> signInAnonymously() async {
    return _auth.signInAnonymously();
  }

  // ── Sign Out ───────────────────────────────────────────────────────────

  /// Sign out of both Firebase and Google.
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}

/// Custom exception for auth-specific errors with a user-friendly message.
class AuthException implements Exception {
  final String code;
  final String message;
  const AuthException({required this.code, required this.message});

  @override
  String toString() => 'AuthException($code): $message';
}

class AuthExceptionHandler {
  /// Convert a Firebase error into a human-readable message suitable for display in the UI.
  static String friendlyMessage(dynamic error) {
    if (error is AuthException) {
      return error.message;
    }
    
    final errorString = error.toString();
    if (errorString.contains('ApiException: 10') || errorString.contains('DEVELOPER_ERROR')) {
      return 'Google Sign-In failed. Please ensure your SHA-1 fingerprint is registered in the Firebase Console.';
    }

    if (error is fb_auth.FirebaseAuthException) {
      return switch (error.code) {
        'email-already-in-use' => 'This email is already registered. Try logging in.',
        'invalid-email' => 'Please enter a valid email address.',
        'weak-password' => 'Password must be at least 6 characters.',
        'user-not-found' => 'No account found with this email.',
        'wrong-password' => 'Incorrect password. Please try again.',
        'too-many-requests' => 'Too many attempts. Please wait a moment.',
        _ => error.message ?? 'Authentication failed.',
      };
    }
    
    return 'Something went wrong. Please try again.';
  }
}
