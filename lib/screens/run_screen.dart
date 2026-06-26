import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/location_service.dart';
import '../services/territory_service.dart';
import '../services/run_tracker.dart';
import '../services/run_history_service.dart';

/// Run states for the state machine
enum RunState { idle, running, paused }

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  // Run history (in-memory)
  static final List<RunResult> runHistory = [];
  static final ValueNotifier<int> historyNotifier = ValueNotifier(0);

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> with WidgetsBindingObserver {
  MapboxMap? _mapboxMap;
  RunState _runState = RunState.idle;
  Timer? _durationTimer;
  final _tracker = LocationService().runTracker;

  // Hold-to-action state
  bool _isHolding = false;
  double _holdProgress = 0.0;
  Timer? _holdTimer;
  String? _holdAction; // 'pause', 'finish'

  // Polyline annotation for history view
  PolylineAnnotationManager? _polylineManager;
  PolygonAnnotationManager? _polygonManager;
  StreamSubscription<geo.ServiceStatus>? _gpsSubscription;

  bool _isGpsEnabled = false;
  geo.LocationPermission _locationPermission = geo.LocationPermission.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _checkGpsStatus();
    _loadRunHistory();
    _tracker.addListener(_onTrackerUpdate);
    _gpsSubscription = geo.Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        setState(() => _isGpsEnabled = status == geo.ServiceStatus.enabled);
      }
    });
  }

  Future<void> _loadRunHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && RunScreen.runHistory.isEmpty) {
      try {
        final runs = await RunHistoryService().getUserRuns(uid);
        if (mounted) {
          RunScreen.runHistory.clear();
          RunScreen.runHistory.addAll(runs.where((r) => r.totalDistanceKm > 0));
          RunScreen.historyNotifier.value++;
        }
      } catch (e) {
        debugPrint('Error loading history: $e');
      }
    }
  }

  void _checkGpsStatus() async {
    final enabled = await geo.Geolocator.isLocationServiceEnabled();
    if (mounted) setState(() => _isGpsEnabled = enabled);
  }

  Future<void> _checkPermissions() async {
    final permission = await geo.Geolocator.checkPermission();
    if (mounted) setState(() => _locationPermission = permission);
  }

  Future<void> _handleGpsIconTap() async {
    if (_locationPermission == geo.LocationPermission.denied || 
        _locationPermission == geo.LocationPermission.deniedForever) {
      final permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.deniedForever) {
        await geo.Geolocator.openAppSettings();
      }
      if (mounted) setState(() => _locationPermission = permission);
    } else if (!_isGpsEnabled) {
      await geo.Geolocator.openLocationSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _holdTimer?.cancel();
    _gpsSubscription?.cancel();
    _tracker.removeListener(_onTrackerUpdate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _checkGpsStatus();
    }
  }

  void _onTrackerUpdate() {
    if (mounted) setState(() {});
  }

  void _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;
    map.compass.updateSettings(CompassSettings(enabled: false));
    map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    map.logo.updateSettings(LogoSettings(
      position: OrnamentPosition.BOTTOM_LEFT, marginLeft: 8, marginBottom: 8,
    ));
    map.attribution.updateSettings(AttributionSettings(
      position: OrnamentPosition.BOTTOM_LEFT, marginLeft: 40, marginBottom: 8,
    ));
    map.location.updateSettings(LocationComponentSettings(
      enabled: true, pulsingEnabled: true,
      pulsingColor: 0xFF00F0FF, pulsingMaxRadius: 40.0,
    ));
    _polylineManager = await map.annotations.createPolylineAnnotationManager();
    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    
    // Load initial territories based on current location
    try {
      final pos = await geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.high);
      _loadNearbyTerritories(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  Future<void> _loadNearbyTerritories(double lat, double lng) async {
    if (_polygonManager == null) return;
    final territories = await TerritoryService().getNearbyTerritories(lat, lng);
    
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    
    final polygons = territories.map((t) {
      final isMine = t.ownerId == currentUid;
      final coords = t.coordinates.map((p) => Position(p[1], p[0])).toList();
      return PolygonAnnotationOptions(
        geometry: Polygon(coordinates: [coords]),
        fillColor: (isMine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error).toARGB32(),
        fillOpacity: 0.3,
        fillOutlineColor: (isMine ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error).toARGB32(),
      );
    }).toList();

    await _polygonManager!.deleteAll();
    if (polygons.isNotEmpty) {
      await _polygonManager!.createMulti(polygons);
    }
  }

  Future<void> _locateMe() async {
    if (_mapboxMap == null) return;
    try {
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 16.0, pitch: 45.0,
        ),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );
      _loadNearbyTerritories(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint("Error locating: $e");
    }
  }

  // ─── Run State Actions ──────────────────────────────────────────────────

  void _startRun() {
    HapticFeedback.heavyImpact();
    _tracker.startRun();
    LocationService().startTracking();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() => _runState = RunState.running);
  }

  void _pauseRun() {
    HapticFeedback.heavyImpact();
    _tracker.pauseRun();
    _durationTimer?.cancel();
    setState(() => _runState = RunState.paused);
  }

  void _resumeRun() {
    HapticFeedback.lightImpact();
    _tracker.resumeRun();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() => _runState = RunState.running);
  }

  Future<void> _finishRun() async {
    HapticFeedback.heavyImpact();
    _durationTimer?.cancel();
    final result = _tracker.stopRun();
    LocationService().stopTracking();

    // Save to history
    RunScreen.runHistory.insert(0, result);
    RunScreen.historyNotifier.value++;

    // Submit territory or RP
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        // Always save history to the DB
        await RunHistoryService().saveRunResult(uid, result);

        if (!result.isBusted && result.totalRP > 0) {
          if (result.isClosedLoop) {
          await TerritoryService().submitCustomTerritory(
            pathCoordinates: result.pathCoordinates,
            areaM2: result.areaM2,
            userId: uid,
            earnedRP: result.totalRP,
          );
        } else {
          // Unclosed loop, just credit RP
          await TerritoryService().creditRunRP(uid, result.totalRP);
        }
        }
        
        // Refresh territories
        final pos = await geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.high);
        _loadNearbyTerritories(pos.latitude, pos.longitude);
        
      } catch (e) {
        debugPrint('Error submitting run: $e');
      }
    }
    setState(() => _runState = RunState.idle);
  }

  void _discardRun() {
    HapticFeedback.heavyImpact();
    _durationTimer?.cancel();
    _tracker.discardRun();
    LocationService().stopTracking();
    setState(() => _runState = RunState.idle);
  }

  // ─── Hold-to-action mechanics ───────────────────────────────────────────

  void _startHold(String action) {
    _holdAction = action;
    _isHolding = true;
    _holdProgress = 0.0;
    HapticFeedback.lightImpact();
    
    const int tickMs = 50;
    const int totalMs = 2000;
    _holdTimer = Timer.periodic(Duration(milliseconds: tickMs), (timer) {
      if (!_isHolding) {
        timer.cancel();
        return;
      }
      setState(() {
        _holdProgress += tickMs / totalMs;
      });
      if (_holdProgress >= 1.0) {
        timer.cancel();
        _isHolding = false;
        _holdProgress = 0.0;
        HapticFeedback.heavyImpact();
        if (action == 'pause') {
          _pauseRun();
        } else if (action == 'finish') {
          _showFinishDialog();
        }
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    setState(() {
      _isHolding = false;
      _holdProgress = 0.0;
      _holdAction = null;
    });
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E212A), Color(0xFF161820)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Icon(Icons.close, color: Theme.of(context).hintColor, size: 28),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "I'M FINISHED\nRUNNING",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Great job! Well done on finishing your run. Let's just confirm you're done so we don't end it early.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _finishRun();
                  },
                  child: Text(
                    'Finish my run',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _discardRun();
                },
                child: Text(
                  'Discard run',
                  style: GoogleFonts.inter(
                    color: Theme.of(context).hintColor,
                    decoration: TextDecoration.underline,
                    decorationColor: Theme.of(context).hintColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Formatting Helpers ─────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _formatPace(double pace) {
    if (pace <= 0) return '0:00';
    final mins = pace.floor();
    final secs = ((pace - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  // ─── History ────────────────────────────────────────────────────────────

  void _showHistory() {
    _clearMapPolyline();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'RUN HISTORY',
                    style: GoogleFonts.orbitron(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: RunScreen.historyNotifier,
                builder: (context, _, __) {
                  if (RunScreen.runHistory.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_run, color: Theme.of(context).hintColor, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'No runs yet',
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Complete a run to see it here.',
                            style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: RunScreen.runHistory.length,
                    itemBuilder: (_, i) => _buildHistoryCard(RunScreen.runHistory[i], i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(RunResult run, int index) {
    final date = run.timestamp;
    final dateStr = '${date.day}/${date.month}/${date.year}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final durationStr = _formatDuration(run.totalDuration);

    return Dismissible(
      key: Key(run.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.errorRed,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).cardColor,
            title: Text('Delete Run', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text('Are you sure you want to delete this run? This will also remove the RP earned.', style: GoogleFonts.inter(color: Theme.of(context).hintColor)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete', style: TextStyle(color: AppColors.errorRed)),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        // Remove from memory
        RunScreen.runHistory.remove(run);
        RunScreen.historyNotifier.value++;

        // Remove from DB
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          try {
            await RunHistoryService().deleteRunResult(uid, run);
          } catch (e) {
            debugPrint('Error deleting run: $e');
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
      child: Row(
        children: [
          // Run number badge
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '#${index + 1}',
              style: GoogleFonts.orbitron(
                color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Run details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dateStr  •  $timeStr',
                  style: GoogleFonts.inter(
                    color: Theme.of(context).hintColor, fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${run.totalDistanceKm.toStringAsFixed(2)} km',
                      style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      durationStr,
                      style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_formatPace(run.averagePaceMinPerKm)} /km',
                      style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // View on map button
          if (run.pathCoordinates.length >= 2)
            GestureDetector(
              onTap: () {
                Navigator.pop(context); // close sheet
                _showRunOnMap(run);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, color: Theme.of(context).colorScheme.primary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'View',
                      style: GoogleFonts.inter(
                        color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  void _showRunOnMap(RunResult run) async {
    if (_mapboxMap == null || _polylineManager == null) return;
    _clearMapPolyline();

    // Build polyline coordinates
    final coords = run.pathCoordinates
        .map((c) => Position(c[1], c[0])) // [lat,lng] -> Position(lng, lat)
        .toList();

    if (coords.length < 2) return;

    await _polylineManager!.create(PolylineAnnotationOptions(
      geometry: LineString(coordinates: coords),
      lineColor: AppColors.territoryOwn.toARGB32(),
      lineWidth: 4.0,
      lineOpacity: 0.9,
    ));

    // Fly to the center of the run path
    final midIdx = coords.length ~/ 2;
    _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: coords[midIdx]),
        zoom: 15.0,
        pitch: 30.0,
      ),
      MapAnimationOptions(duration: 1200, startDelay: 0),
    );
  }

  void _clearMapPolyline() {
    _polylineManager?.deleteAll();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Full-screen map
          MapWidget(
            styleUri: MapboxStyles.DARK,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(77.2090, 28.6139)),
              zoom: 15.0, pitch: 45.0,
            ),
            onMapCreated: _onMapCreated,
          ),

          // Top-left: History button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: _showHistory,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).cardColor.withValues(alpha: 0.9),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.history, color: Colors.white, size: 22),
                    ValueListenableBuilder<int>(
                      valueListenable: RunScreen.historyNotifier,
                      builder: (context, _, __) {
                        if (RunScreen.runHistory.isEmpty) return const SizedBox.shrink();
                        return Positioned(
                          top: 6, right: 6,
                          child: Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${RunScreen.runHistory.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Top-right: locate me button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: _locateMe,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 22),
              ),
            ),
          ),

          // GPS / Permission indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 68,
            child: GestureDetector(
              onTap: _handleGpsIconTap,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Icon(
                  (_locationPermission == geo.LocationPermission.denied || _locationPermission == geo.LocationPermission.deniedForever)
                      ? Icons.location_off
                      : (!_isGpsEnabled ? Icons.location_off : Icons.location_on),
                  color: (_locationPermission == geo.LocationPermission.denied || _locationPermission == geo.LocationPermission.deniedForever || !_isGpsEnabled) 
                      ? AppColors.errorRed 
                      : Colors.green,
                  size: 22,
                ),
              ),
            ),
          ),

          // Bottom stats panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final distance = _tracker.totalDistanceKm;
    final duration = _tracker.activeDuration;
    final pace = _tracker.currentPaceMinPerKm;
    final capturedM2 = (distance * 1000).round(); // Rough m² approximation

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Capture area
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$capturedM2',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'm²',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Area covered',
                    style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 12),
                  ),
                ],
              ),
          const SizedBox(height: 12),
          Text(
            _runState == RunState.idle 
                ? 'Standby' 
                : (_runState == RunState.paused ? 'Capture Paused' : 'Capture in Progress'),
            style: GoogleFonts.inter(
              color: _runState == RunState.idle 
                  ? Theme.of(context).hintColor 
                  : (_runState == RunState.paused ? Colors.orangeAccent : Theme.of(context).colorScheme.primary), 
              fontSize: 14, 
              fontWeight: FontWeight.bold
            ),
          ),
          const SizedBox(height: 20),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(distance.toStringAsFixed(2), 'km', 'Distance'),
              _buildStat(_formatDuration(duration), '', 'Duration'),
              _buildStat(_formatPace(pace), '', 'Average pace'),
            ],
          ),
          const SizedBox(height: 20),

          // Action buttons
          _buildActionButtons(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String unit, String label) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            if (unit.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit, style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 12)),
      ],
    );
  }

  Widget _buildActionButtons() {
    switch (_runState) {
      case RunState.idle:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            onPressed: _startRun,
            child: Text(
              'Start Run',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        );

      case RunState.running:
        // Hold to pause button
        return GestureDetector(
          onLongPressStart: (_) => _startHold('pause'),
          onLongPressEnd: (_) => _cancelHold(),
          onLongPressCancel: _cancelHold,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _isHolding && _holdAction == 'pause'
                      ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                ),
                child: Center(
                  child: Text(
                    _isHolding && _holdAction == 'pause'
                        ? 'Hold to pause... ${(2 - _holdProgress * 2).ceil()}s'
                        : 'Hold to Pause',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );

      case RunState.paused:
        return Row(
          children: [
            // Resume Run
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: _resumeRun,
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: Text(
                  'Resume Run',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Hold to Finish
            Expanded(
              child: GestureDetector(
                onLongPressStart: (_) => _startHold('finish'),
                onLongPressEnd: (_) => _cancelHold(),
                onLongPressCancel: _cancelHold,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _isHolding && _holdAction == 'finish'
                            ? Theme.of(context).colorScheme.error
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.stop, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _isHolding && _holdAction == 'finish'
                                ? '${(2 - _holdProgress * 2).ceil()}s'
                                : 'Hold to Finish',
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }
}
