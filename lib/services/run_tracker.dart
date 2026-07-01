import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RunResult {
  final String id;
  final double totalDistanceKm;
  final int totalRP;
  final double averagePaceMinPerKm;
  final bool isBusted;
  final Duration totalDuration;
  final List<List<double>> pathCoordinates; // [[lat, lng], ...]
  final DateTime timestamp;
  final bool isClosedLoop;
  final double areaM2;

  RunResult({
    required this.id,
    required this.totalDistanceKm,
    required this.totalRP,
    required this.averagePaceMinPerKm,
    required this.isBusted,
    required this.totalDuration,
    required this.pathCoordinates,
    required this.isClosedLoop,
    required this.areaM2,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'RunResult(Distance: ${totalDistanceKm.toStringAsFixed(2)} km, RP: $totalRP, Pace: ${averagePaceMinPerKm.toStringAsFixed(2)} min/km, Closed: $isClosedLoop, Area: ${areaM2.toStringAsFixed(0)} m²)';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'totalDistanceKm': totalDistanceKm,
      'totalRP': totalRP,
      'averagePaceMinPerKm': averagePaceMinPerKm,
      'isBusted': isBusted,
      'totalDurationMs': totalDuration.inMilliseconds,
      'pathCoordinates': pathCoordinates.map((c) => GeoPoint(c[0], c[1])).toList(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isClosedLoop': isClosedLoop,
      'areaM2': areaM2,
    };
  }

  factory RunResult.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedTimestamp = DateTime.now();
    if (map['timestamp'] != null) {
      if (map['timestamp'] is int) {
        parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(map['timestamp']);
      } else if (map['timestamp'] is Timestamp) {
        parsedTimestamp = (map['timestamp'] as Timestamp).toDate();
      }
    }

    return RunResult(
      id: docId,
      totalDistanceKm: (map['totalDistanceKm'] ?? 0.0).toDouble(),
      totalRP: map['totalRP'] ?? 0,
      averagePaceMinPerKm: (map['averagePaceMinPerKm'] ?? 0.0).toDouble(),
      isBusted: map['isBusted'] ?? false,
      totalDuration: Duration(milliseconds: map['totalDurationMs'] ?? 0),
      pathCoordinates: (map['pathCoordinates'] as List<dynamic>?)
              ?.map<List<double>>((e) {
                if (e is GeoPoint) return [e.latitude, e.longitude];
                return (e as List<dynamic>).map<double>((v) => (v as num).toDouble()).toList();
              })
              .toList() ?? <List<double>>[],
      isClosedLoop: map['isClosedLoop'] ?? false,
      areaM2: (map['areaM2'] ?? 0.0).toDouble(),
      timestamp: parsedTimestamp,
    );
  }
}

class RunTracker extends ChangeNotifier {
  Position? _lastPosition;
  double _totalDistanceMeters = 0.0;
  bool _isBusted = false;
  DateTime? _startTime;
  bool _isPaused = false;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartTime;
  final List<List<double>> _pathCoordinates = [];

  List<List<double>> get pathCoordinates => List.unmodifiable(_pathCoordinates);

  bool get isTracking => _startTime != null;
  bool get isBusted => _isBusted;
  bool get isPaused => _isPaused;
  
  double get totalDistanceKm => _totalDistanceMeters / 1000.0;

  /// Approximates if the current path forms a closed loop.
  bool get isCurrentlyClosedLoop {
    if (_pathCoordinates.length < 5) return false;
    final start = _pathCoordinates.first;
    final end = _pathCoordinates.last;
    final dist = Geolocator.distanceBetween(start[0], start[1], end[0], end[1]);
    return dist < 50.0; // 50 meters threshold
  }

  /// Get captured area in square meters using Shoelace + spherical approx
  double get capturedAreaM2 {
    if (!isCurrentlyClosedLoop || _pathCoordinates.length < 3) return 0.0;
    
    // Create a closed copy of coordinates
    final coords = List<List<double>>.from(_pathCoordinates);
    if (coords.first[0] != coords.last[0] || coords.first[1] != coords.last[1]) {
      coords.add(coords.first);
    }
    
    double area = 0.0;
    for (int i = 0; i < coords.length - 1; i++) {
      final p1 = coords[i];
      final p2 = coords[i + 1];
      // shoelace on spherical projection (approx)
      area += _toRadians(p2[1] - p1[1]) * 
              (2 + math.sin(_toRadians(p1[0])) + math.sin(_toRadians(p2[0])));
    }
    area = area * 6378137.0 * 6378137.0 / 2.0;
    return area.abs();
  }

  double _toRadians(double degree) => degree * math.pi / 180.0;

  /// Get currently accumulated RP
  int get currentRP {
    final m = _totalDistanceMeters;
    if (isCurrentlyClosedLoop) {
      return (m / 100).round();
    } else {
      return (m / 110).round();
    }
  }

  /// Returns the active running duration (excluding paused time).
  Duration get activeDuration {
    if (_startTime == null) return Duration.zero;
    final now = DateTime.now();
    final totalElapsed = now.difference(_startTime!);
    final currentPauseDuration = _isPaused && _pauseStartTime != null
        ? now.difference(_pauseStartTime!)
        : Duration.zero;
    return totalElapsed - _pausedDuration - currentPauseDuration;
  }
  
  double get currentPaceMinPerKm {
    if (_startTime == null || totalDistanceKm == 0) return 0.0;
    final durationMinutes = activeDuration.inSeconds / 60.0;
    return durationMinutes / totalDistanceKm;
  }

  /// Starts or resets the run tracker.
  void startRun() {
    _lastPosition = null;
    _totalDistanceMeters = 0.0;
    _isBusted = false;
    _isPaused = false;
    _pausedDuration = Duration.zero;
    _pauseStartTime = null;
    _pathCoordinates.clear();
    _startTime = DateTime.now();
    log('🏃‍♂️ Run started');
    notifyListeners();
  }

  /// Pauses the run tracker. GPS positions received while paused are ignored.
  void pauseRun() {
    if (!isTracking || _isPaused) return;
    _isPaused = true;
    _pauseStartTime = DateTime.now();
    log('⏸️ Run paused');
    notifyListeners();
  }

  /// Resumes the run tracker from a paused state.
  void resumeRun() {
    if (!isTracking || !_isPaused) return;
    if (_pauseStartTime != null) {
      _pausedDuration += DateTime.now().difference(_pauseStartTime!);
    }
    _isPaused = false;
    _pauseStartTime = null;
    _lastPosition = null; // Reset last position to avoid a jump in distance
    log('▶️ Run resumed');
    notifyListeners();
  }

  /// Processes a new GPS coordinate from the location stream.
  void processNewPosition(Position currentPosition) {
    if (_startTime == null || _isBusted || _isPaused) return;

    if (_lastPosition != null) {
      final distanceMeters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      final timeDeltaMs = currentPosition.timestamp.difference(_lastPosition!.timestamp).inMilliseconds;

      if (timeDeltaMs > 0) {
        final speedMps = distanceMeters / (timeDeltaMs / 1000.0);
        final speedKmph = speedMps * 3.6;

        if (speedKmph > 25.0) {
          _isBusted = true;
          log('🚨 Anti-cheat triggered! Speed between points was ${speedKmph.toStringAsFixed(1)} km/h.');
          notifyListeners();
          return;
        }

        _totalDistanceMeters += distanceMeters;
      }
    }

    _lastPosition = currentPosition;
    _pathCoordinates.add([currentPosition.latitude, currentPosition.longitude]);
    notifyListeners();
  }

  /// Stops the run and returns the calculated statistics.
  RunResult stopRun() {
    final duration = activeDuration;
    final closed = isCurrentlyClosedLoop;
    final area = capturedAreaM2;

    final result = RunResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Temp ID, will be overwritten by Firebase doc ID
      totalDistanceKm: totalDistanceKm,
      totalRP: _isBusted ? 0 : currentRP,
      averagePaceMinPerKm: currentPaceMinPerKm,
      isBusted: _isBusted,
      totalDuration: duration,
      pathCoordinates: List.from(_pathCoordinates),
      isClosedLoop: closed,
      areaM2: area,
    );

    _startTime = null;
    _lastPosition = null;
    _isPaused = false;
    _pausedDuration = Duration.zero;
    _pauseStartTime = null;

    log('🛑 Run stopped. $result');
    notifyListeners();
    return result;
  }

  /// Discards the run without returning results.
  void discardRun() {
    _startTime = null;
    _lastPosition = null;
    _totalDistanceMeters = 0.0;
    _isBusted = false;
    _isPaused = false;
    _pausedDuration = Duration.zero;
    _pauseStartTime = null;
    _pathCoordinates.clear();
    log('🗑️ Run discarded');
    notifyListeners();
  }
}

