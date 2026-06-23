class IntervalConfig {
  final int warmupSeconds;
  final int workSeconds;
  final int restSeconds;
  final int sets;

  const IntervalConfig({
    required this.warmupSeconds,
    required this.workSeconds,
    required this.restSeconds,
    required this.sets,
  });

  /// Factory for a default interval setup (e.g. 5 min warmup, 1 min sprint, 1 min walk, 5 sets)
  factory IntervalConfig.defaultConfig() {
    return const IntervalConfig(
      warmupSeconds: 300,
      workSeconds: 60,
      restSeconds: 60,
      sets: 5,
    );
  }
}
