import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// ── LoginSheet ──────────────────────────────────────────────────────────────
/// Premium glassmorphic bottom-sheet with Email sign-up/login + Google sign-in.
/// Call [showLoginSheet] to present it over the map.
Future<void> showLoginSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LoginSheetBody(),
  );
}

class _LoginSheetBody extends StatefulWidget {
  const _LoginSheetBody();
  @override
  State<_LoginSheetBody> createState() => _LoginSheetBodyState();
}

class _LoginSheetBodyState extends State<_LoginSheetBody> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = false; // false = Sign Up mode, true = Login mode
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await AuthService.instance
            .signInWithEmail(_emailCtrl.text, _passwordCtrl.text);
      } else {
        await AuthService.instance
            .signUpWithEmail(_emailCtrl.text, _passwordCtrl.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = AuthExceptionHandler.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = AuthExceptionHandler.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.72,
        child: CustomPaint(
          painter: _SheetCircuitPainter(Theme.of(context).colorScheme.primary),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
                    left: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
                    right:
                        BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(),
                          SizedBox(height: 28),
                          _buildEmailField(),
                          SizedBox(height: 14),
                          _buildPasswordField(),
                          if (_error != null) ...[
                            SizedBox(height: 10),
                            _buildError(),
                          ],
                          SizedBox(height: 22),
                          _buildSubmitButton(),
                          SizedBox(height: 18),
                          _buildDivider(),
                          const SizedBox(height: 18),
                          _buildGoogleButton(),
                          const SizedBox(height: 20),
                          _buildToggle(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        // Decorative top handle
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(height: 20),
        // Glowing title
        Text(
          'DHAAV',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 6,
          ),
        ),
        SizedBox(height: 6),
        Text(
          _isLogin ? 'Welcome back, runner.' : 'Claim your territory.',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 11,
            color: Theme.of(context).hintColor,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      style: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: _inputDecoration('EMAIL ADDRESS'),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (!v.contains('@')) return 'Enter a valid email';
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      obscureText: true,
      style: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: _inputDecoration('PASSWORD'),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (v.length < 6) return 'Min 6 characters';
        return null;
      },
    );
  }

  Widget _buildError() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -8.0, end: 0.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.elasticOut,
      builder: (context, offset, child) {
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 14, color: Theme.of(context).colorScheme.error),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontSize: 10,
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        onPressed: _loading ? null : _submitEmail,
        child: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : Text(
                _isLogin ? 'LOG IN' : 'CREATE ACCOUNT',
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 0.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 10,
              color: Theme.of(context).hintColor,
              letterSpacing: 2,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 0.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _submitGoogle,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Theme.of(context).cardColor.withValues(alpha: 0.5),
        ),
        icon: Image.network(
          'https://developers.google.com/identity/images/g-logo.png',
          height: 24,
          width: 24,
        ),
        label: Text(
          'SIGN IN WITH GOOGLE',
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildToggle() {
    return GestureDetector(
      onTap: () => setState(() {
        _isLogin = !_isLogin;
        _error = null;
      }),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 10,
            color: Theme.of(context).hintColor,
          ),
          children: [
            TextSpan(
              text:
                  _isLogin ? "Don't have an account? " : 'Already have an account? ',
            ),
            TextSpan(
              text: _isLogin ? 'Sign up' : 'Log in',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 10,
        color: Theme.of(context).hintColor,
        letterSpacing: 1.5,
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
      ),
      errorStyle: TextStyle(
        fontFamily: 'Orbitron',
        fontSize: 9,
        color: Theme.of(context).colorScheme.error,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CIRCUIT BACKGROUND PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Subtle circuit-board pattern behind the login sheet.
class _SheetCircuitPainter extends CustomPainter {
  final Color primaryColor;
  _SheetCircuitPainter(this.primaryColor);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor.withValues(alpha: 0.04)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 20.0;
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Corner accents
    final accentPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const len = 30.0;
    // Top-left corner
    canvas.drawLine(const Offset(0, 0), const Offset(len, 0), accentPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, len), accentPaint);
    // Top-right corner
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - len, 0), accentPaint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, len), accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

