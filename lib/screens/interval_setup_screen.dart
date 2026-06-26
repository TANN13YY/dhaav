import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/interval_config.dart';

// Global singleton for now to easily pass the config to the map
final ValueNotifier<IntervalConfig> currentIntervalConfig = 
    ValueNotifier(IntervalConfig.defaultConfig());

class IntervalSetupScreen extends StatefulWidget {
  const IntervalSetupScreen({super.key});

  @override
  State<IntervalSetupScreen> createState() => _IntervalSetupScreenState();
}

class _IntervalSetupScreenState extends State<IntervalSetupScreen> {
  late IntervalConfig _config;

  @override
  void initState() {
    super.initState();
    _config = currentIntervalConfig.value;
  }

  void _updateConfig(IntervalConfig newConfig) {
    HapticFeedback.selectionClick();
    setState(() {
      _config = newConfig;
    });
    currentIntervalConfig.value = newConfig;
  }

  Widget _buildDial(String label, int valueInSeconds, Function(int) onChanged, {bool isSets = false, Color? accentColor}) {
    accentColor ??= Theme.of(context).colorScheme.primary;
    final displayValue = isSets ? valueInSeconds.toString() : '${(valueInSeconds / 60).floor()}:${(valueInSeconds % 60).toString().padLeft(2, '0')}';
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.orbitron(
              color: Theme.of(context).hintColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => onChanged(valueInSeconds - (isSets ? 1 : 15)),
                icon: Icon(Icons.remove_circle_outline, color: accentColor),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  displayValue,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(valueInSeconds + (isSets ? 1 : 15)),
                icon: Icon(Icons.add_circle_outline, color: accentColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'INTERVAL SETUP',
          style: GoogleFonts.orbitron(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildDial(
              'WARMUP',
              _config.warmupSeconds,
              (v) {
                if (v >= 0) _updateConfig(IntervalConfig(warmupSeconds: v, workSeconds: _config.workSeconds, restSeconds: _config.restSeconds, sets: _config.sets));
              },
            ),
            _buildDial(
              'WORK',
              _config.workSeconds,
              (v) {
                if (v >= 15) _updateConfig(IntervalConfig(warmupSeconds: _config.warmupSeconds, workSeconds: v, restSeconds: _config.restSeconds, sets: _config.sets));
              },
              accentColor: Theme.of(context).colorScheme.error,
            ),
            _buildDial(
              'REST',
              _config.restSeconds,
              (v) {
                if (v >= 0) _updateConfig(IntervalConfig(warmupSeconds: _config.warmupSeconds, workSeconds: _config.workSeconds, restSeconds: v, sets: _config.sets));
              },
              accentColor: Theme.of(context).dividerColor,
            ),
            _buildDial(
              'SETS',
              _config.sets,
              (v) {
                if (v >= 1) _updateConfig(IntervalConfig(warmupSeconds: _config.warmupSeconds, workSeconds: _config.workSeconds, restSeconds: _config.restSeconds, sets: v));
              },
              isSets: true,
              accentColor: Colors.amber,
            ),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'YOUR WORKOUT IS SAVED AUTOMATICALLY.\nSWITCH TO THE MAP TO START YOUR RUN.',
                textAlign: TextAlign.center,
                style: GoogleFonts.orbitron(
                  color: Theme.of(context).hintColor.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
