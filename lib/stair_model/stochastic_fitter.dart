import 'dart:math';

/// Result from [StochasticFitter.fit].
class StochasticFitResult {
  const StochasticFitResult({
    required this.ganglinjeMm,
    required this.stepCounts,
    required this.totalSteps,
    required this.idealTreadMm,
    required this.riserMm,
    required this.feasible,
  });

  /// Gangelinje per section. Even indices = adjusted segment walks (≤ input max).
  /// Odd indices = fixed node arcs (unchanged from input).
  final List<double> ganglinjeMm;

  /// Steps per section (same indexing as [ganglinjeMm]).
  final List<int> stepCounts;

  final int    totalSteps;
  final double idealTreadMm;
  final double riserMm;

  /// True when every non-zero section satisfies the min-depth constraint.
  final bool feasible;

  // ── Named accessors for the stair model ────────────────────────────────────

  int get nSegments => (ganglinjeMm.length + 1) ~/ 2;
  int get nNodes    => ganglinjeMm.length ~/ 2;

  /// Adjusted straight-walk for segment [i] (0 … nSegments-1).
  double segmentGangelinje(int i) => ganglinjeMm[i * 2];

  /// Fixed arc length for node [j] (0 … nNodes-1).
  double nodeGangelinje(int j) => ganglinjeMm[j * 2 + 1];

  /// Step count for segment [i].
  int segmentSteps(int i) => stepCounts[i * 2];

  /// Step count for node [j].
  int nodeSteps(int j) => stepCounts[j * 2 + 1];
}

/// Stochastic stair-step optimizer.
///
/// Input: flat, odd-length list alternating segment / node / segment.
/// Each entry: `[gangelinjeMm, innerMm]`.
///
///   Straight segment: `[straightMax, straightMax]`
///     The optimizer may shorten the segment (0 … straightMax). Shortening
///     a segment moves the adjacent node — longer landings, fewer steps on
///     the straight. Inner = gangelinje for straight sections (uniform tread).
///
///   Corner node: `[arcMm, innerMm]`
///     Arc and inner are FIXED. The node's walking arc is determined by its
///     corner geometry; only the adjacent segments are adjusted.
///
/// Adaptive weights are maintained per segment.  Each iteration samples a
/// fraction (0–1) of each segment's max gangelinje.  Feasibility feedback
/// (every non-zero section satisfies `inner/steps ≥ minDepthMm`) updates the
/// per-segment weight vectors.  The best feasible Blondel solution is returned.
class StochasticFitter {
  static const _eps         = 1e-6;
  static const _kIterations = 800;
  static const _kCandidates = 3;
  static const _alpha       = 0.12;

  // Fractions of the max segment gangelinje that the optimizer may choose.
  static const _fractions = <double>[0.0, 0.15, 0.30, 0.45, 0.60, 0.75, 1.0];

  static StochasticFitResult fit(
    List<List<double>> sections,
    double totalHeightMm,
    double minDepthMm, {
    Random? rng,
  }) {
    assert(sections.isNotEmpty && sections.length.isOdd,
        'sections must alternate segment/node/segment (odd length)');
    assert(sections.every((s) => s.length == 2),
        'each entry must be [gangelinjeMm, innerMm]');

    final random    = rng ?? Random();
    final nSect     = sections.length;
    final nSegments = (nSect + 1) ~/ 2;

    // Reference total gangelinje (all sections at their input value) for Blondel.
    final refL = sections.fold(0.0, (s, e) => s + e[0]);
    if (refL < _eps) return _empty(nSect);

    final nCands = _blondelN(totalHeightMm, refL, k: _kCandidates);

    List<double>? bestG;
    List<int>?    bestSteps;
    int    bestN        = nCands.first;
    double bestScore    = double.infinity;
    bool   bestFeasible = false;

    for (final N in nCands) {
      // One weight vector per SEGMENT over the fraction candidates.
      final weights = List.generate(
        nSegments,
        (_) => List.filled(_fractions.length, 1.0 / _fractions.length),
      );

      for (var iter = 0; iter < _kIterations; iter++) {
        final chosen = List<int>.generate(
          nSegments, (si) => _sample(weights[si], random),
        );

        // Build gangelinje vector.
        // Even index (segment): fraction × max.   Odd index (node): fixed.
        final g = List<double>.generate(nSect, (i) {
          if (i.isEven) {
            final si = i ~/ 2;
            return (sections[i][0] * _fractions[chosen[si]])
                .clamp(0.0, sections[i][0]);
          }
          return sections[i][0]; // node arc — not adjusted
        });

        final totalG = g.fold(0.0, (s, v) => s + v);
        if (totalG < _eps) continue;

        final steps = _distribute(g, nSect, N);
        final ok    = _feasible(g, sections, steps, minDepthMm);
        final score = ok ? _score(g, steps, N) : double.infinity;

        // Update per-segment weights from feasibility feedback.
        for (var si = 0; si < nSegments; si++) {
          if (ok) {
            weights[si][chosen[si]] += _alpha;
          } else {
            weights[si][chosen[si]] =
                (weights[si][chosen[si]] - _alpha * 0.4)
                    .clamp(_eps, double.infinity);
          }
          _normalise(weights[si]);
        }

        if ((!bestFeasible && ok) || (bestFeasible == ok && score < bestScore)) {
          bestScore    = score;
          bestN        = N;
          bestG        = List.of(g);
          bestSteps    = List.of(steps);
          bestFeasible = ok;
        }
      }
    }

    final g      = bestG    ?? [for (final s in sections) s[0]];
    final steps  = bestSteps ?? _distribute(g, nSect, bestN);
    final totalG = g.fold(0.0, (s, v) => s + v);

    return StochasticFitResult(
      ganglinjeMm:  g,
      stepCounts:   steps,
      totalSteps:   bestN,
      idealTreadMm: totalG > _eps ? totalG / bestN : 0,
      riserMm:      totalHeightMm > _eps ? totalHeightMm / bestN : 0,
      feasible:     bestFeasible,
    );
  }

  // ── Step distribution ──────────────────────────────────────────────────────

  static List<int> _distribute(List<double> g, int n, int N) {
    final mins = List<int>.generate(n, (i) {
      if (g[i] < _eps) return 0;
      return i.isOdd ? 2 : 1; // corner nodes ≥ 2; segments ≥ 1
    });

    final minTotal = mins.fold(0, (s, m) => s + m);
    if (N < minTotal) return _distributeProp(g, n, N);

    final extra  = N - minTotal;
    final total  = g.fold(0.0, (s, v) => s + v);
    final floors = List<int>.of(mins);
    final rems   = <double>[];

    for (var i = 0; i < n; i++) {
      final share = (total > _eps && extra > 0) ? extra * g[i] / total : 0.0;
      floors[i] += share.floor();
      rems.add(share - share.floor());
    }

    var shortfall = N - floors.fold(0, (s, v) => s + v);
    final order = List.generate(n, (i) => i)
      ..sort((a, b) => rems[b].compareTo(rems[a]));
    if (shortfall > 0) {
      for (var k = 0; k < shortfall && k < order.length; k++) {
        floors[order[k]]++;
      }
    } else if (shortfall < 0) {
      for (var k = order.length - 1; k >= 0 && shortfall < 0; k--) {
        if (floors[order[k]] > mins[order[k]]) {
          floors[order[k]]--;
          shortfall++;
        }
      }
    }
    return floors;
  }

  static List<int> _distributeProp(List<double> g, int n, int N) {
    final total  = g.fold(0.0, (s, v) => s + v);
    final floors = List<int>.filled(n, 0);
    final rems   = <double>[];
    for (var i = 0; i < n; i++) {
      final share = total > _eps ? N * g[i] / total : 0.0;
      floors[i] = share.floor();
      rems.add(share - share.floor());
    }
    var shortfall = N - floors.fold(0, (s, v) => s + v);
    final order = List.generate(n, (i) => i)
      ..sort((a, b) => rems[b].compareTo(rems[a]));
    for (var k = 0; k < shortfall && k < order.length; k++) {
      floors[order[k]]++;
    }
    return floors;
  }

  // ── Feasibility ────────────────────────────────────────────────────────────

  // Segments (even): tread = g[i]/steps — use the adjusted g[i] as narrowest.
  // Nodes (odd): narrowest is the fixed inner path from the input.
  static bool _feasible(
      List<double> g, List<List<double>> sects, List<int> steps, double minD) {
    if (minD <= _eps) return true;
    for (var i = 0; i < sects.length; i++) {
      final s = steps[i];
      if (s == 0) continue;
      final narrowest = i.isEven ? g[i] : sects[i][1];
      if (narrowest / s < minD - _eps) return false;
    }
    return true;
  }

  // ── Score ──────────────────────────────────────────────────────────────────

  static double _score(List<double> g, List<int> steps, int N) {
    final totalG = g.fold(0.0, (s, v) => s + v);
    if (totalG < _eps || N == 0) return double.infinity;
    final T = totalG / N;
    var sumSq = 0.0;
    var count = 0;
    for (var i = 0; i < g.length; i++) {
      final s = steps[i];
      if (s == 0) continue;
      final d = g[i] / s - T;
      sumSq += d * d;
      count++;
    }
    return count > 0 ? sumSq / count : 0.0;
  }

  // ── Blondel N candidates ──────────────────────────────────────────────────

  static List<int> _blondelN(double h, double l, {required int k}) {
    final scores = <int, double>{};
    for (var n = 3; n <= 25; n++) {
      scores[n] = (2 * h / n / 10 + l / n / 10 - 62).abs();
    }
    return (scores.keys.toList()
          ..sort((a, b) => scores[a]!.compareTo(scores[b]!)))
        .take(k)
        .toList();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static int _sample(List<double> w, Random rng) {
    var r = rng.nextDouble();
    for (var i = 0; i < w.length; i++) {
      r -= w[i];
      if (r <= 0) return i;
    }
    return w.length - 1;
  }

  static void _normalise(List<double> w) {
    final sum = w.fold(0.0, (s, v) => s + v);
    if (sum > _eps) {
      for (var i = 0; i < w.length; i++) { w[i] /= sum; }
    }
  }

  static StochasticFitResult _empty(int n) => StochasticFitResult(
        ganglinjeMm:  List.filled(n, 0.0),
        stepCounts:   List.filled(n, 0),
        totalSteps:   0,
        idealTreadMm: 0,
        riserMm:      0,
        feasible:     true,
      );
}
