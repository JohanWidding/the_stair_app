import 'dart:math' show Random;
import 'package:flutter/painting.dart';

import 'chain.dart';
import 'chain_geometry.dart';
import 'ganglinje.dart';

class ChainFitResult {
  const ChainFitResult({
    required this.chain,
    required this.totalSteps,
    required this.idealTreadMm,
    required this.riserMm,
  });

  final StairChain chain;
  final int        totalSteps;
  final double     idealTreadMm;
  final double     riserMm;
}

/// Exhaustive integer step-count optimizer.
///
/// For each candidate N (Blondel top-3) and each valid integer assignment
/// of steps to segments, exactly one [ChainGeometry.compute] call is made
/// to get the actual arc lengths.  The node steps are then split analytically
/// (all valid splits tried) against a FIXED reference tread T = refL / N.
///
/// Segment treads are **exactly** T by construction (walk = k × T).
/// Only node treads can deviate; the optimizer minimises that deviation.
/// A small landing-size penalty prefers compact nodes when scores are equal.
class ChainFitter {
  static const _eps            = 1e-6;
  static const _kCandidates    = 3;
  static const _landingPenalty = 1e-8;

  static ChainFitResult fit(
    StairChain chain,
    Ganglinje  ganglinje, {
    double  minInnerMm = 100.0,
    Random? rng, // kept for API compatibility, unused
  }) {
    if (!chain.isValid || chain.edgeCount == 0) {
      return ChainFitResult(
          chain: chain, totalSteps: 0, idealTreadMm: 250.0, riserMm: 0);
    }

    final nEdges      = ganglinje.nEdges;
    final nInterior   = ganglinje.nInterior;
    final isCorner    = ganglinje.isCorner;
    final tBack       = ganglinje.tBackMm;
    final tFwd        = ganglinje.tFwdMm;
    final rawL        = ganglinje.rawEdgeMm;
    final straightMax = ganglinje.straightMaxMm;
    final nCorners    = isCorner.where((b) => b).length;

    // Reference walk (max straights + zero-landing arcs) for Blondel N.
    final refL = straightMax.fold(0.0, (s, v) => s + v) +
        ganglinje.arcMm.fold(0.0, (s, v) => s + v);
    if (refL < _eps) {
      return ChainFitResult(
          chain: chain, totalSteps: 0, idealTreadMm: 250.0, riserMm: 0);
    }

    final nCands = _blondelCandidates(ganglinje.totalHeightMm, refL);

    List<double>? bestStraights;
    List<int>?    bestEdgeSteps;
    List<int?>?   bestNodeSteps;
    int    bestN     = nCands.first;
    double bestScore = double.infinity;

    // ── Main search ───────────────────────────────────────────────────────────
    for (final N in nCands) {
      final T      = refL / N;
      final kSegs  = List<int>.filled(nEdges, 0);
      final minForNodes = 2 * nCorners; // minimum total steps reserved for nodes

      // Evaluate one segment step-count combo: one geometry call, all node splits.
      void evalCombo() {
        final kSum = kSegs.fold(0, (s, k) => s + k);
        final kRem = N - kSum;
        if (kRem < minForNodes) return;

        // Segment straight walks = exact multiples of T.
        final s = List<double>.generate(nEdges, (i) => kSegs[i] * T);

        // Landing sizes from segment walks.
        final bL = List<double>.filled(nInterior, 0.0);
        final fL = List<double>.filled(nInterior, 0.0);
        _landings(nInterior, rawL, s, tBack, tFwd, isCorner, bL, fL);

        // One geometry call per segment combo.
        final tempChain = _buildChainForGeo(chain, bL, fL, nInterior);
        final tempPolys = ChainGeometry.compute(tempChain, 10.0);

        final actualArc   = List<double>.generate(nInterior, (j) =>
            isCorner[j]
                ? Ganglinje.nodeMm(tempPolys.nodes[j], ganglinje.mode)
                : 0.0);
        final actualInner = List<double>.generate(nInterior, (j) {
          if (!isCorner[j] || tempPolys.nodes[j].poly.length != 6) return 0.0;
          return _innerPath(tempPolys.nodes[j].poly);
        });

        final cornerIdxs = [
          for (var j = 0; j < nInterior; j) if (isCorner[j]) j,
        ];

        // Landing sum penalty (prefer compact nodes).
        var landingSum = 0.0;
        for (final j in cornerIdxs) { landingSum += bL[j] + fL[j]; }

        // Try ALL valid node step distributions (no geometry, just scoring).
        final nodeSteps = List<int?>.filled(nInterior, null);

        void enumNodeSplits(int ci, int remaining) {
          if (ci == cornerIdxs.length) {
            // All corners assigned — check feasibility and score.
            if (remaining != 0) return;

            if (minInnerMm > _eps) {
              for (final j in cornerIdxs) {
                final k = nodeSteps[j] ?? 2;
                if (actualInner[j] / k < minInnerMm - _eps) return;
              }
            }

            // Score: Σ(arc/k - T)² + max(arc/k - T)² + landing penalty.
            // Segments are exactly T by construction — no contribution.
            var sumSq = 0.0;
            var maxSq = 0.0;
            for (final j in cornerIdxs) {
              final k = nodeSteps[j] ?? 2;
              final d = actualArc[j] / k - T;
              final dsq = d * d;
              sumSq += dsq;
              if (dsq > maxSq) maxSq = dsq;
            }
            final score = sumSq + maxSq + _landingPenalty * landingSum;

            if (score < bestScore) {
              bestScore     = score;
              bestN         = N;
              bestStraights = List.of(s);
              bestEdgeSteps = List.of(kSegs);
              bestNodeSteps = List.of(nodeSteps);
            }
            return;
          }

          final j           = cornerIdxs[ci];
          final minForRest  = 2 * (cornerIdxs.length - ci - 1);
          final maxK        = remaining - minForRest;
          for (var k = 2; k <= maxK; k++) {
            nodeSteps[j] = k;
            enumNodeSplits(ci + 1, remaining - k);
          }
        }

        enumNodeSplits(0, kRem);
      }

      // Enumerate segment step counts recursively (one level per edge).
      void enumSegs(int edge) {
        if (edge == nEdges) {
          evalCombo();
          return;
        }
        final kSumSoFar = kSegs.sublist(0, edge).fold(0, (s, k) => s + k);
        final maxK = (straightMax[edge] / T)
            .floor()
            .clamp(0, N - kSumSoFar - minForNodes);
        for (var k = 0; k <= maxK; k++) {
          kSegs[edge] = k;
          enumSegs(edge + 1);
        }
      }

      enumSegs(0);
    }

    // ── Build result from best ────────────────────────────────────────────────
    final bS        = bestStraights ?? List.of(straightMax);
    final edgeSteps = bestEdgeSteps ?? List.filled(nEdges, 1);
    final nodeSteps = bestNodeSteps ?? List<int?>.filled(nInterior, null);

    final backL = List<double>.filled(nInterior, 0.0);
    final fwdL  = List<double>.filled(nInterior, 0.0);
    _landings(nInterior, rawL, bS, tBack, tFwd, isCorner, backL, fwdL);

    // Min-inner post-processing: grow landing if inner tread still too narrow.
    if (minInnerMm > _eps) {
      final tempChain = _buildChainForGeo(chain, backL, fwdL, nInterior);
      final tempPolys = ChainGeometry.compute(tempChain, 10.0);
      for (var j = 0; j < nInterior; j++) {
        if (!isCorner[j]) continue;
        final nd = tempPolys.nodes[j];
        if (nd.poly.length != 6) continue;
        final innerPath = _innerPath(nd.poly);
        final m         = (nodeSteps[j] ?? 2).clamp(2, 24);
        if (innerPath < m * minInnerMm - _eps && innerPath > _eps) {
          final scale = m * minInnerMm / innerPath;
          backL[j] = (backL[j] * scale).clamp(backL[j], rawL[j]);
          fwdL[j]  = (fwdL[j]  * scale).clamp(fwdL[j],  rawL[j + 1]);
        }
      }
    }

    // Exact final geometry.
    final bestR      = ganglinje.totalHeightMm / bestN;
    final exactChain = _buildChainForGeo(chain, backL, fwdL, nInterior);
    final exactPolys = ChainGeometry.compute(exactChain, 10.0);

    final finalEdgeWalk = List<double>.generate(nEdges, (i) {
      final lH = i == 0          ? 0.0 : fwdL[i - 1];
      final rH = i == nEdges - 1 ? 0.0 : backL[i];
      return (rawL[i] - lH - rH).clamp(0.0, double.infinity);
    });
    final finalArcLen = List<double>.generate(nInterior, (j) =>
        isCorner[j]
            ? Ganglinje.nodeMm(exactPolys.nodes[j], ganglinje.mode)
            : 0.0);

    var finalL = finalEdgeWalk.fold(0.0, (s, v) => s + v);
    for (var j = 0; j < nInterior; j++) {
      if (isCorner[j]) finalL += finalArcLen[j];
    }
    final bestT = finalL > _eps ? finalL / bestN : 0.0;

    // Build result chain.
    final newEdges = [
      for (var i = 0; i < nEdges; i++)
        chain.edges[i].copyWith(
            stepCount: edgeSteps[i],
            heightMm:  edgeSteps[i] * bestR),
    ];
    final newNodes = <ChainNode>[chain.nodes.first];
    for (var j = 0; j < nInterior; j++) {
      final lm     = backL[j] + fwdL[j];
      final offset = lm > _eps ? backL[j] / lm : 0.5;
      newNodes.add(chain.nodes[j + 1].copyWith(
        landingMm:     lm,
        landingOffset: offset,
        stepCount:     isCorner[j] ? (nodeSteps[j] ?? 2).clamp(2, 24) : null,
      ));
    }
    newNodes.add(chain.nodes.last);
    final resultChain = chain.copyWith(edges: newEdges, nodes: newNodes);

    _log(nEdges, nInterior, finalEdgeWalk, finalArcLen,
        edgeSteps, nodeSteps, backL, fwdL, isCorner,
        bestN, bestT, bestR, ganglinje.totalHeightMm, finalL);

    return ChainFitResult(
        chain: resultChain, totalSteps: bestN, idealTreadMm: bestT, riserMm: bestR);
  }

  // ── Landing sizes ─────────────────────────────────────────────────────────

  static void _landings(
    int nInterior,
    List<double> rawL,
    List<double> straights,
    List<double> tBack,
    List<double> tFwd,
    List<bool>   isCorner,
    List<double> backL,
    List<double> fwdL,
  ) {
    for (var j = 0; j < nInterior; j++) {
      if (!isCorner[j]) {
        backL[j] = tBack[j];
        fwdL[j]  = tFwd[j];
        continue;
      }

      final sharedLeft  = j > 0 && isCorner[j - 1];
      final sharedRight = j < nInterior - 1 && isCorner[j + 1];

      if (sharedLeft) {
        final extra = (rawL[j] - straights[j] - tFwd[j - 1] - tBack[j])
            .clamp(0.0, double.infinity);
        backL[j] = tBack[j] + extra / 2;
      } else {
        backL[j] = (rawL[j] - straights[j]).clamp(tBack[j], rawL[j]);
      }

      if (sharedRight) {
        final extra = (rawL[j + 1] - straights[j + 1] - tFwd[j] - tBack[j + 1])
            .clamp(0.0, double.infinity);
        fwdL[j] = tFwd[j] + extra / 2;
      } else {
        fwdL[j] =
            (rawL[j + 1] - straights[j + 1]).clamp(tFwd[j], rawL[j + 1]);
      }
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static List<int> _blondelCandidates(double h, double l,
      {int k = _kCandidates}) {
    final scores = <int, double>{};
    for (var n = 3; n <= 25; n++) {
      scores[n] = (2 * h / n / 10 + l / n / 10 - 62).abs();
    }
    return (scores.keys.toList()
          ..sort((a, b) => scores[a]!.compareTo(scores[b]!)))
        .take(k)
        .toList();
  }

  static double _innerPath(List<Offset> poly) =>
      (poly[4] - poly[5]).distance + (poly[3] - poly[4]).distance;

  static StairChain _buildChainForGeo(
      StairChain chain, List<double> backL, List<double> fwdL, int nInterior) {
    final newNodes = <ChainNode>[chain.nodes.first];
    for (var j = 0; j < nInterior; j++) {
      final lm  = backL[j] + fwdL[j];
      final off = lm > _eps ? backL[j] / lm : 0.5;
      newNodes.add(
          chain.nodes[j + 1].copyWith(landingMm: lm, landingOffset: off));
    }
    newNodes.add(chain.nodes.last);
    return chain.copyWith(nodes: newNodes);
  }

  // ── Log ───────────────────────────────────────────────────────────────────

  static void _log(
    int nEdges, int nInterior,
    List<double> edgeWalk, List<double> arcLen,
    List<int> edgeSteps, List<int?> nodeSteps,
    List<double> backL, List<double> fwdL,
    List<bool> isCorner,
    int N, double T, double R, double H, double finalL,
  ) {
    final buf = StringBuffer(
        '[ChainFitter] H=${H.round()}mm  finalL=${finalL.round()}mm  '
        'N=$N  T=${T.round()}mm  R=${R.round()}mm  '
        '2R+T=${(2 * R / 10 + T / 10).toStringAsFixed(1)}cm\n');
    var seg = 0;
    for (var i = 0; i < nEdges; i++) {
      final s = edgeSteps[i];
      if (s == 0) {
        buf.write('  [$seg] Seg  $i: (eaten)  walk=${edgeWalk[i].round()}mm\n');
      } else {
        final tread = edgeWalk[i] / s;
        buf.write('  [$seg] Seg  $i: ${s}s  walk=${edgeWalk[i].round()}mm  '
            'tread=${tread.round()}mm  '
            'Δ=${tread - T >= 0 ? '+' : ''}${(tread - T).round()}mm\n');
      }
      seg++;
      if (i < nInterior) {
        final lm = backL[i] + fwdL[i];
        if (!isCorner[i]) {
          buf.write('  [$seg] Node $i: (straight)  landing=${lm.round()}mm\n');
        } else {
          final nSt   = (nodeSteps[i] ?? 2).clamp(2, 24);
          final tread = nSt > 0 ? arcLen[i] / nSt : 0.0;
          buf.write('  [$seg] Node $i: ${nSt}s  arc=${arcLen[i].round()}mm  '
              'tread=${tread.round()}mm  '
              'Δ=${tread - T >= 0 ? '+' : ''}${(tread - T).round()}mm  '
              'landing=${lm.round()}mm\n');
        }
        seg++;
      }
    }
    // ignore: avoid_print
    print(buf);
  }
}
