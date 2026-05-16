class StairMath {
  static double _blondelScore(double floorHeightMm, int n, double treadMm) {
    final riserCm = floorHeightMm / n / 10.0;
    final treadCm = treadMm / 10.0;
    return (2 * riserCm + treadCm - 62).abs();
  }

  /// Optimal step count for a given floor height and tread depth (Blondel).
  static int findOptimalN(double floorHeightMm, double treadMm) {
    var bestN = 15;
    var bestScore = double.infinity;
    for (var n = 3; n <= 25; n++) {
      final s = _blondelScore(floorHeightMm, n, treadMm);
      if (s < bestScore) {
        bestScore = s;
        bestN = n;
      }
    }
    return bestN;
  }

  /// Optimal step count given total height and total horizontal run.
  static int findOptimalNForRun(double heightMm, double activeRunMm) {
    final ideal = (2 * heightMm + activeRunMm) / 620;
    var bestN = ideal.round().clamp(3, 25);
    var bestScore = double.infinity;
    for (var n = (ideal - 1).floor().clamp(3, 25);
        n <= (ideal + 1).ceil().clamp(3, 25);
        n++) {
      final score =
          (2 * heightMm / n / 10 + activeRunMm / n / 10 - 62).abs();
      if (score < bestScore) {
        bestScore = score;
        bestN = n;
      }
    }
    return bestN;
  }
}
