import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/location_service.dart';

/// ── RadarHud ────────────────────────────────────────────────────────────────
/// Floating heads-up display overlay pinned on top of the map.
/// Shows Current RP, Pace, and Wanted Level as glassmorphic stat panels.
class RadarHud extends StatelessWidget {
  const RadarHud({super.key});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 12,
      left: 12,
      right: 12,
      child: Row(
        children: [
          Expanded(child: _RpPanel()),
          SizedBox(width: 8),
          Expanded(child: _PacePanel()),
          SizedBox(width: 8),
          Expanded(child: _WantedPanel()),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STAT PANELS
// ═══════════════════════════════════════════════════════════════════════════════

/// ── RP Panel ────────────────────────────────────────────────────────────────
class _RpPanel extends StatefulWidget {
  const _RpPanel();
  @override
  State<_RpPanel> createState() => _RpPanelState();
}

class _RpPanelState extends State<_RpPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HudCard(
      label: 'CURRENT RP',
      suffix: Text(' RP', style: _suffixStyle(context),),
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmer, LocationService().runTracker]),
        builder: (context, child) {
          final currentRP = LocationService().runTracker.currentRP;
          return ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(colors: [Colors.transparent, Colors.white24, Colors.transparent])
                  .createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Text(
              currentRP.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},'),
              style: _valueStyle(context),
            ),
          );
        },
      ),
    );
  }
}

/// ── Pace Panel ──────────────────────────────────────────────────────────────
class _PacePanel extends StatefulWidget {
  const _PacePanel();
  @override
  State<_PacePanel> createState() => _PacePanelState();
}

class _PacePanelState extends State<_PacePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HudCard(
      label: 'PACE',
      suffix: Text(' /km', style: _suffixStyle(context),),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, LocationService().runTracker]),
        builder: (context, child) {
          final glowOpacity = 0.3 + 0.7 * _pulse.value;
          final pace = LocationService().runTracker.currentPaceMinPerKm;
          
          String paceStr = "0'00\"";
          if (pace > 0) {
            final mins = pace.floor();
            final secs = ((pace - mins) * 60).round();
            paceStr = "$mins'${secs.toString().padLeft(2, '0')}\"";
          }

          return Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: glowOpacity * 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(paceStr, style: _valueStyle(context),),
          );
        },
      ),
    );
  }
}

/// ── Wanted Level Panel ──────────────────────────────────────────────────────
class _WantedPanel extends StatefulWidget {
  const _WantedPanel();
  @override
  State<_WantedPanel> createState() => _WantedPanelState();
}

class _WantedPanelState extends State<_WantedPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _starPulse;
  static const int _wantedLevel = 3;
  static const int _maxLevel = 5;

  @override
  void initState() {
    super.initState();
    _starPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _starPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HudCard(
      label: 'WANTED',
      child: AnimatedBuilder(
        animation: _starPulse,
        builder: (context, _) {
          final scale =
              _wantedLevel >= 3 ? 1.0 + 0.08 * _starPulse.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_maxLevel, (i) {
                final filled = i < _wantedLevel;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: filled
                      ? ShaderMask(
                          shaderCallback: (bounds) =>
                              LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary]).createShader(bounds),
                          child: Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        )
                      : Icon(
                          Icons.star_outline_rounded,
                          size: 16,
                          color: Theme.of(context).hintColor.withValues(alpha: 0.4),
                        ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SHARED HUD CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _HudCard extends StatelessWidget {
  const _HudCard({
    required this.label,
    required this.child,
    this.suffix,
  });

  final String label;
  final Widget child;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CircuitBorderPainter(Theme.of(context).colorScheme.primary),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Label row
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).hintColor,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: 4),
                // Value row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(child: child),
                    if (suffix != null) suffix!,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CIRCUIT-BOARD BORDER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Draws faint grid lines and corner tick marks for a sci-fi cockpit feel.
class _CircuitBorderPainter extends CustomPainter {
  final Color primaryColor;
  _CircuitBorderPainter(this.primaryColor);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor.withValues(alpha: 0.07)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final tickPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.25)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // ── Faint internal grid lines ──────────────────────────────────────────
    const gridSpacing = 12.0;
    // Horizontal lines
    for (double y = gridSpacing; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vertical lines
    for (double x = gridSpacing; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // ── Corner tick marks ──────────────────────────────────────────────────
    const tickLen = 8.0;
    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(tickLen, 0), tickPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, tickLen), tickPaint);
    // Top-right
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - tickLen, 0), tickPaint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, tickLen), tickPaint);
    // Bottom-left
    canvas.drawLine(
        Offset(0, size.height), Offset(tickLen, size.height), tickPaint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - tickLen), tickPaint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - tickLen, size.height), tickPaint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - tickLen), tickPaint);

    // ── Small crosshair dots at grid intersections (sparse) ────────────────
    final dotPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    for (double x = gridSpacing * 3; x < size.width; x += gridSpacing * 3) {
      for (double y = gridSpacing * 3; y < size.height; y += gridSpacing * 3) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TEXT STYLES
// ═══════════════════════════════════════════════════════════════════════════════

TextStyle _valueStyle(BuildContext context) => TextStyle(
  fontFamily: 'Orbitron',
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: Theme.of(context).colorScheme.onSurface,
  shadows: [
    Shadow(color: Theme.of(context).colorScheme.primary, blurRadius: 6),
  ],
);

TextStyle _suffixStyle(BuildContext context) => TextStyle(
  fontFamily: 'Orbitron',
  fontSize: 10,
  fontWeight: FontWeight.w500,
  color: Theme.of(context).hintColor,
);

