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
  final int totalSteps;
  final double idealTreadMm;
  final double riserMm;
}

/// Ganglinje-position fitter.
///
/// Receives a pre-computed [Ganglinje] and grid-searches over each edge's
/// straight-walk length (independently, no fixed-sum constraint) plus the top
/// [_kCandidates] Blondel N values.  The ganglinje length L = Σstraight + Σarc
/// varies per grid combo; T = L/N is recomputed each time.
class ChainFitter {
  static const _eps         = 1e-6;
  static const _kCandidates = 3;
  static const _kGrid       = 7;

  static ChainFitResult fit(
    StairChain chain,
    Ganglinje ganglinje, {
    double minInnerMm = 100.0,
  }) {
    if (!chain.isValid || chain.edgeCount == 0) {
      return ChainFitResult(
          chain: chain, totalSteps: 0, idealTreadMm: 250.0, riserMm: 0);
    }

    final nEdges    = ganglinje.nEdges;
    final nInterior = ganglinje.nInterior;
    final rawL      = ganglinje.rawEdgeMm;
    final arcLen    = ganglinje.arcMm;
    final isCorner  = ganglinje.isCorner;
    final tBack     = ganglinje.tBackMm;
    final tFwd      = ganglinje.tFwdMm;
    final totalArc  = ganglinje.totalArcMm;
    final straightMax = ganglinje.straightMaxMm;

    // ── Reference L = actual ganglinje at minimum landings ───────────────────
    // sum(rawL) overstates L because landings consume part of each edge.
    // The correct reference is sum(straightMax) + totalArc.
    final refL = straightMax.fold(0.0, (s, v) => s + v) + totalArc;
    if (refL < _eps) {
      return ChainFitResult(
          chain: chain, totalSteps: 0, idealTreadMm: 250.0, riserMm: 0);
    }
    final nCandidates = _blondelCandidates(ganglinje.totalHeightMm, refL);

    // ── Grid search ──────────────────────────────────────────────────────────
    // Each edge i has a free straight-walk si ∈ [0, straightMax[i]].
    // These are INDEPENDENT — no sum constraint.
    // Score is measured against tRef = refL/N (fixed Blondel target for this N),
    // NOT against comboL/N — this prevents degenerate all-eaten solutions from
    // scoring perfectly just because every remaining section has equal treads.
    final totalCombos = _pow(_kGrid, nEdges);

    var bestN         = nCandidates.first;
    var bestStraights = List<double>.of(straightMax); // default: minimum landings
    var bestEdgeSteps = List<int>.filled(nEdges, 1);
    var bestNodeSteps = List<int?>.filled(nInterior, null);
    var bestScore     = double.infinity;

    for (final N in nCandidates) {
      final tRef = refL / N; // fixed Blondel-optimal tread for this N

      for (var combo = 0; combo < totalCombos; combo++) {
        var rem = combo;
        final straights = List<double>.filled(nEdges, 0.0);
        for (var i = 0; i < nEdges; i++) {
          final idx  = rem % _kGrid;
          rem ~/= _kGrid;
          final frac = _kGrid > 1 ? idx / (_kGrid - 1.0) : 0.0;
          straights[i] = frac * straightMax[i];
        }

        // Skip zero-length combos.
        var comboL = totalArc;
        for (final s in straights) { comboL += s; }
        if (comboL < _eps) continue;

        final edgeSteps = List<int>.filled(nEdges, 0);
        final nodeSteps = List<int?>.filled(nInterior, null);
        _distribute(straights, arcLen, N, nEdges, nInterior, isCorner,
            edgeSteps, nodeSteps);

        // Score against tRef (not comboL/N) so eating edges is penalised.
        final score = _score(straights, arcLen, edgeSteps, nodeSteps, isCorner, tRef);
        if (score < bestScore) {
          bestScore     = score;
          bestN         = N;
          bestStraights = List.of(straights);
          bestEdgeSteps = List.of(edgeSteps);
          bestNodeSteps = List.of(nodeSteps);
        }
      }
    }

    // ── Translate best straight lengths → physical landing sizes ─────────────
    // For each corner j (leftEdge = j, rightEdge = j+1):
    //   backL[j]: if edge j is shared with corner j-1, split equally beyond mins;
    //             otherwise entire consumed portion goes to this corner.
    //   fwdL[j]:  same rule for edge j+1 shared with corner j+1.
    final backL = List<double>.filled(nInterior, 0.0);
    final fwdL  = List<double>.filled(nInterior, 0.0);

    for (var j = 0; j < nInterior; j++) {
      if (!isCorner[j]) {
        backL[j] = tBack[j];
        fwdL[j]  = tFwd[j];
        continue;
      }
      // ── backL: from leftEdge = j ──────────────────────────────────────────
      final sharedLeft = j > 0 && isCorner[j - 1];
      if (sharedLeft) {
        // Edge j is shared between corner j-1 (its fwdL) and corner j (backL).
        final extra = (rawL[j] - bestStraights[j] - tFwd[j - 1] - tBack[j])
            .clamp(0.0, double.infinity);
        backL[j] = tBack[j] + extra / 2;
      } else {
        backL[j] = (rawL[j] - bestStraights[j]).clamp(tBack[j], rawL[j]);
      }

      // ── fwdL: from rightEdge = j+1 ───────────────────────────────────────
      final sharedRight = j < nInterior - 1 && isCorner[j + 1];
      if (sharedRight) {
        final extra = (rawL[j + 1] - bestStraights[j + 1] - tFwd[j] - tBack[j + 1])
            .clamp(0.0, double.infinity);
        fwdL[j] = tFwd[j] + extra / 2;
      } else {
        fwdL[j] = (rawL[j + 1] - bestStraights[j + 1]).clamp(tFwd[j], rawL[j + 1]);
      }
    }

    // ── Min inner constraint — grow landings if inner tread too narrow ────────
    if (minInnerMm > _eps) {
      final tempChain = _buildChainForGeo(chain, backL, fwdL, nInterior);
      final tempPolys = ChainGeometry.compute(tempChain, 10.0);
      for (var j = 0; j < nInterior; j++) {
        if (!isCorner[j]) continue;
        final nd = tempPolys.nodes[j];
        if (nd.poly.length != 6) continue;
        final innerPath = _innerPath(nd.poly);
        final m         = (bestNodeSteps[j] ?? 2).clamp(2, 24);
        if (innerPath < m * minInnerMm - _eps && innerPath > _eps) {
          final scale = m * minInnerMm / innerPath;
          backL[j] = (backL[j] * scale).clamp(backL[j], rawL[j]);
          fwdL[j]  = (fwdL[j]  * scale).clamp(fwdL[j],  rawL[j + 1]);
        }
      }
    }

    // ── Exact final geometry ─────────────────────────────────────────────────
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
      if (isCorner[j]) { finalL += finalArcLen[j]; }
    }

    final bestT = finalL > _eps ? finalL / bestN : 0.0;
    final bestR = ganglinje.totalHeightMm / bestN;

    // ── Build result chain ───────────────────────────────────────────────────
    final newEdges = [
      for (var i = 0; i < nEdges; i++)
        chain.edges[i].copyWith(
            stepCount: bestEdgeSteps[i],
            heightMm:  bestEdgeSteps[i] * bestR),
    ];
    final newNodes = <ChainNode>[chain.nodes.first];
    for (var j = 0; j < nInterior; j++) {
      final lm     = backL[j] + fwdL[j];
      final offset = lm > _eps ? backL[j] / lm : 0.5;
      newNodes.add(chain.nodes[j + 1].copyWith(
        landingMm:     lm,
        landingOffset: offset,
        stepCount:     isCorner[j] ? (bestNodeSteps[j] ?? 2).clamp(2, 24) : null,
      ));
    }
    newNodes.add(chain.nodes.last);
    final result = chain.copyWith(edges: newEdges, nodes: newNodes);

    // ── Log ───────────────────────────────────────────────────────────────────
    final finalPolys = ChainGeometry.compute(result, 10.0);
    final buf = StringBuffer(
        '[ChainFitter] refL=${refL.round()}mm  finalL=${finalL.round()}mm  '
        'H=${ganglinje.totalHeightMm.round()}mm  '
        'N=$bestN  T=${bestT.round()}mm  R=${bestR.round()}mm  '
        '2R+T=${(2 * bestR / 10 + bestT / 10).toStringAsFixed(1)}cm  '
        'combos=${nCandidates.length}×$totalCombos\n');
    var seg = 0;
    for (var i = 0; i < nEdges; i++) {
      final steps = bestEdgeSteps[i];
      if (steps == 0) {
        buf.write('  [$seg] Edge  $i: (eaten)  rawL=${rawL[i].round()}mm\n');
      } else {
        final walk  = finalEdgeWalk[i];
        final tread = steps > 0 ? walk / steps : 0.0;
        buf.write('  [$seg] Edge  $i: '
            '${steps}s  walk=${walk.round()}mm  '
            'tread=${tread.round()}mm  '
            'Δ=${(tread - bestT) >= 0 ? '+' : ''}${(tread - bestT).round()}mm\n');
      }
      seg++;
      if (i < nInterior) {
        final lm = backL[i] + fwdL[i];
        if (!isCorner[i]) {
          buf.write('  [$seg] Node  $i: (straight)  landing=${lm.round()}mm\n');
        } else {
          final nd     = finalPolys.nodes[i];
          final walk   = finalArcLen[i];
          final nSteps = (bestNodeSteps[i] ?? 2).clamp(2, 24);
          final tread  = nSteps > 0 ? walk / nSteps : 0.0;
          final inner  = nd.poly.length == 6
              ? '  inner/step=${(_innerPath(nd.poly) / nSteps).round()}mm' : '';
          buf.write('  [$seg] Node  $i: '
              '${nSteps}s  walk=${walk.round()}mm  '
              'tread=${tread.round()}mm  '
              'Δ=${(tread - bestT) >= 0 ? '+' : ''}${(tread - bestT).round()}mm  '
              'landing=${lm.round()}mm$inner\n');
        }
        seg++;
      }
    }
    // ignore: avoid_print
    print(buf);

    return ChainFitResult(
        chain: result, totalSteps: bestN, idealTreadMm: bestT, riserMm: bestR);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<int> _blondelCandidates(double heightMm, double runMm,
      {int k = _kCandidates}) {
    final scores = <int, double>{};
    for (var n = 3; n <= 25; n++) {
      scores[n] = (2 * heightMm / n / 10 + runMm / n / 10 - 62).abs();
    }
    final sorted = scores.keys.toList()
      ..sort((a, b) => scores[a]!.compareTo(scores[b]!));
    return sorted.take(k).toList();
  }

  static void _distribute(
    List<double> straights,
    List<double> arcLens,
    int          N,
    int          nEdges,
    int          nInterior,
    List<bool>   isCorner,
    List<int>    edgeSteps,
    List<int?>   nodeSteps,
  ) {
    final walks = <double>[];
    final mins  = <int>[];
    final eIdx  = <int?>[];
    final nIdx  = <int?>[];

    for (var i = 0; i < nEdges; i++) {
      walks.add(straights[i]);
      mins.add(straights[i] > _eps ? 1 : 0);
      eIdx.add(i);
      nIdx.add(null);
      if (i < nInterior && isCorner[i]) {
        walks.add(arcLens[i]);
        mins.add(2);
        eIdx.add(null);
        nIdx.add(i);
      }
    }

    final steps = _distributeSteps(walks, N, mins);
    for (var s = 0; s < steps.length; s++) {
      if (eIdx[s] != null) { edgeSteps[eIdx[s]!] = steps[s]; }
      if (nIdx[s] != null) { nodeSteps[nIdx[s]!] = steps[s]; }
    }
  }

  static List<int> _distributeSteps(
      List<double> walks, int N, List<int> mins) {
    final total    = walks.fold(0.0, (s, w) => s + w);
    final minTotal = mins.fold(0, (s, m) => s + m);
    final extra    = N - minTotal;
    final floors   = List<int>.of(mins);
    final rems     = <double>[];

    for (var i = 0; i < walks.length; i++) {
      final share = (total > _eps && extra > 0)
          ? extra * walks[i] / total : 0.0;
      floors[i] += share.floor();
      rems.add(share - share.floor());
    }

    var shortfall = N - floors.fold(0, (s, v) => s + v);
    final order   = List.generate(floors.length, (i) => i)
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

  static double _score(
    List<double> straights,
    List<double> arcLens,
    List<int>    edgeSteps,
    List<int?>   nodeSteps,
    List<bool>   isCorner,
    double       T,
  ) {
    var sumSq = 0.0;
    var maxSq = 0.0;
    var count = 0;
    for (var i = 0; i < straights.length; i++) {
      final s = edgeSteps[i];
      if (s == 0) continue;
      final d = _sq(straights[i] / s - T);
      sumSq += d; if (d > maxSq) maxSq = d; count++;
    }
    for (var j = 0; j < arcLens.length; j++) {
      if (!isCorner[j]) continue;
      final s = nodeSteps[j] ?? 2;
      final d = _sq((s > 0 ? arcLens[j] / s : 0.0) - T);
      sumSq += d; if (d > maxSq) maxSq = d; count++;
    }
    return count > 0 ? sumSq / count + maxSq : 0.0;
  }

  static double _sq(double x) => x * x;

  static int _pow(int base, int exp) {
    var r = 1;
    for (var i = 0; i < exp; i++) { r *= base; }
    return r;
  }

  static StairChain _buildChainForGeo(
      StairChain chain, List<double> backL, List<double> fwdL, int nInterior) {
    final newNodes = <ChainNode>[chain.nodes.first];
    for (var j = 0; j < nInterior; j++) {
      final lm  = backL[j] + fwdL[j];
      final off = lm > _eps ? backL[j] / lm : 0.5;
      newNodes.add(chain.nodes[j + 1].copyWith(landingMm: lm, landingOffset: off));
    }
    newNodes.add(chain.nodes.last);
    return chain.copyWith(nodes: newNodes);
  }

  static double _innerPath(List<Offset> poly) =>
      (poly[4] - poly[5]).distance + (poly[3] - poly[4]).distance;
}
