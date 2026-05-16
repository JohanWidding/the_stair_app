import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../services/stair_math.dart';
import 'chain.dart';
import 'chain_fitter.dart';
import 'chain_geometry.dart';
import 'ganglinje.dart';

// ── Public value types ────────────────────────────────────────────────────────

/// Geometric and dimensional data for one step.
class StepInfo {
  const StepInfo({
    required this.number,
    required this.parent,
    required this.riserMm,
    required this.treadMm,
    required this.poly,
    this.innerTreadMm,
    this.outerTreadMm,
    this.stepAngleDeg = 0.0,
    this.inclAngleDeg = 0.0,
  });

  final int          number;
  final String       parent;
  final double       riserMm;
  final double       treadMm;
  final List<Offset> poly;

  /// Non-null for winding corner steps; the tread depth measured at the inner wall.
  final double? innerTreadMm;

  /// Non-null for winding corner steps; the tread depth measured at the outer wall.
  final double? outerTreadMm;

  /// Rotation per step within a corner node (degrees).
  final double stepAngleDeg;

  /// Stair inclination angle (degrees from horizontal).
  final double inclAngleDeg;

  bool get isCornerStep => innerTreadMm != null;
}

// ── Model ─────────────────────────────────────────────────────────────────────

/// Single point of access for all chain-staircase operations.
///
/// Owns the active [StairChain] and any in-progress draft, and exposes every
/// operation the UI needs: drawing, editing, geometry, step list, and fitting.
/// Fires [ChangeNotifier] on every mutation so screens can `watch` or `listen`.
class StaircaseModel extends ChangeNotifier {
  StaircaseModel({double minInnerMm = 100.0}) : _minInnerMm = minInnerMm;

  StaircaseModel.fromChain(StairChain chain, {double minInnerMm = 100.0})
      : _chain      = chain,
        _minInnerMm = minInnerMm;

  // ── Internal state ────────────────────────────────────────────────────────

  static var _idCounter = 0;
  static String _newId() => 'c${++_idCounter}';

  StairChain?    _chain;
  StairChain?    _draft;
  ChainFitResult? _lastFit;
  double         _minInnerMm;

  // ── Read-only getters ─────────────────────────────────────────────────────

  StairChain?     get chain      => _chain;
  StairChain?     get draft      => _draft;
  ChainFitResult? get lastFit    => _lastFit;
  double          get minInnerMm => _minInnerMm;

  bool get hasChain => _chain != null;
  bool get hasDraft => _draft != null;

  /// Total number of steps summed across all segments (auto-computed where not set).
  int get totalSteps {
    final c = _chain;
    if (c == null || !c.isValid) return 0;
    final polys = computeGeometry();
    var n = 0;
    for (var i = 0; i < c.edgeCount; i++) {
      n += c.edges[i].stepCount ??
          StairMath.findOptimalN(c.edges[i].heightMm, 250);
    }
    for (var j = 0; j < polys.nodes.length; j++) {
      final nd = polys.nodes[j];
      if (nd.turnAngleDeg > 1.0 && nd.poly.length == 6) {
        n += c.nodes[j + 1].stepCount ??
            (nd.turnAngleDeg / 30.0).round().clamp(2, 24);
      }
    }
    return n;
  }

  /// Rise per step = totalHeightMm / [totalSteps].
  double get riserMm {
    final n = totalSteps;
    final c = _chain;
    if (n == 0 || c == null) return 0;
    return c.totalHeightMm / n;
  }

  // ── Computation ───────────────────────────────────────────────────────────

  /// 2D polygon geometry for the active chain (empty result when no chain).
  /// Pass a [cellSize] other than 10 only for screen-space rendering.
  ChainPolygons computeGeometry({double cellSize = 10.0}) {
    final c = _chain;
    if (c == null) return const ChainPolygons(edges: [], nodes: []);
    return ChainGeometry.compute(c, cellSize);
  }

  /// Per-step data for every edge and corner node.
  /// [polys] must have been computed from the active chain with the same cellSize.
  List<StepInfo> computeSteps(ChainPolygons polys) {
    final c = _chain;
    if (c == null || !c.isValid) return const [];
    return _buildStepList(c, polys);
  }

  /// Blondel deviation |2R + T − 62 cm| for the current step distribution.
  /// Returns null when no chain or no steps.
  double? blondelScore() {
    final fit = _lastFit;
    if (fit != null && fit.totalSteps > 0) {
      final R = fit.riserMm / 10.0;
      final T = fit.idealTreadMm / 10.0;
      return (2 * R + T - 62).abs();
    }
    final n = totalSteps;
    final c = _chain;
    if (c == null || n == 0) return null;
    final polys = computeGeometry();
    var walkMm = 0.0;
    for (final ed in polys.edges) { walkMm += ed.lengthMm; }
    for (final nd in polys.nodes) {
      if (nd.ganglinjeStart != null && nd.ganglinjeEnd != null) {
        // cellSize=10 → 1 px = 1 mm
        walkMm += (nd.ganglinjeEnd! - nd.ganglinjeStart!).distance;
      }
    }
    final R = c.totalHeightMm / n / 10.0;
    final T = walkMm / n / 10.0;
    return (2 * R + T - 62).abs();
  }

  // ── Draft drawing ─────────────────────────────────────────────────────────

  /// Start a new draft with one edge from (gx1,gy1) to (gx2,gy2).
  /// No-op when the chain already exists (one chain per session).
  void onEdgeDraw(double gx1, double gy1, double gx2, double gy2) {
    if (hasChain) return;
    if (_draft == null) {
      _draft = StairChain(
        id: _newId(),
        nodes: [
          ChainNode(id: _newId(), gx: gx1, gy: gy1),
          ChainNode(id: _newId(), gx: gx2, gy: gy2),
        ],
        edges: [ChainEdge(id: _newId())],
      );
    } else {
      _draft = _draft!.extended(
        ChainNode(id: _newId(), gx: gx2, gy: gy2),
        ChainEdge(id: _newId()),
      );
    }
    _logGanglinje();
    notifyListeners();
  }

  /// Commit the current draft as the active chain.
  void commitDraft() {
    final d = _draft;
    if (d == null) return;
    _chain = d;
    _draft = null;
    _logGanglinje();
    notifyListeners();
  }

  /// Discard the current draft without committing.
  void cancelDraft() {
    if (_draft == null) return;
    _draft = null;
    notifyListeners();
  }

  // ── Node mutations ────────────────────────────────────────────────────────

  /// Drag node [idx] to a new grid position.
  void moveNode(int nodeIdx, double gx, double gy) {
    final c = _chain;
    if (c == null) return;
    _chain = c.withNodeMoved(nodeIdx, gx, gy);
    _logGanglinje();
    notifyListeners();
  }

  /// Replace node [nodeIdx] with [updated] (e.g. from a landing slider).
  void updateNode(int nodeIdx, ChainNode updated) {
    final c = _chain;
    if (c == null || nodeIdx < 0 || nodeIdx >= c.nodes.length) return;
    _chain = c.copyWith(nodes: [
      for (var i = 0; i < c.nodes.length; i++)
        i == nodeIdx ? updated : c.nodes[i],
    ]);
    notifyListeners();
  }

  // ── Edge mutations ────────────────────────────────────────────────────────

  /// Replace edge [edgeIdx] with [updated] (e.g. from a step-count slider).
  void updateEdge(int edgeIdx, ChainEdge updated) {
    final c = _chain;
    if (c == null || edgeIdx < 0 || edgeIdx >= c.edges.length) return;
    _chain = c.copyWith(edges: [
      for (var i = 0; i < c.edges.length; i++)
        i == edgeIdx ? updated : c.edges[i],
    ]);
    notifyListeners();
  }

  // ── Chain-level mutations ─────────────────────────────────────────────────

  /// Set the total floor-to-floor height of the staircase.
  void setHeight(double mm) {
    final c = _chain;
    if (c == null) return;
    _chain = c.copyWith(totalHeightMm: mm);
    notifyListeners();
  }

  /// Switch the walking-line routing mode (middlewalk / middlestrict / …).
  void setGanglinjeMode(GanglinjeMode mode) {
    final c = _chain;
    if (c == null) return;
    _chain = c.copyWith(ganglinjeMode: mode);
    _logGanglinje();
    notifyListeners();
  }

  /// Set the minimum inner-tread depth used by [fit].
  void setMinInner(double mm) {
    if (_minInnerMm == mm) return;
    _minInnerMm = mm;
    notifyListeners();
  }

  // ── Fit ───────────────────────────────────────────────────────────────────

  /// Compute the 1-D ganglinje model for the active chain (zero-landing geometry).
  /// Returns null when there is no valid chain.
  Ganglinje? computeGanglinje() {
    final c = _chain;
    return c == null ? null : Ganglinje.compute(c);
  }

  void _logGanglinje() {
    final chain = _chain ?? _draft;
    if (chain == null) return;
    final g = Ganglinje.compute(chain);
    if (g == null) return;
    final buf = StringBuffer('[Ganglinje] mode=${g.mode.name}  '
        'L=${g.totalMm.round()}mm  '
        'straight=${g.totalStraightMm.round()}mm  '
        'arc=${g.totalArcMm.round()}mm  '
        'H=${g.totalHeightMm.round()}mm  '
        'nEdges=${g.nEdges}\n');
    for (var i = 0; i < g.nEdges; i++) {
      buf.write('  [E$i] raw=${g.rawEdgeMm[i].round()}mm  '
          'sMax=${g.straightMaxMm[i].round()}mm');
      if (i < g.nInterior) {
        buf.write('\n  [N$i] corner=${g.isCorner[i]}  '
            'arc=${g.arcMm[i].round()}mm  '
            'tBack=${g.tBackMm[i].round()}mm  '
            'tFwd=${g.tFwdMm[i].round()}mm');
      }
      buf.write('\n');
    }
    // ignore: avoid_print
    print(buf);
  }

  /// Run the multi-N optimizer and replace the active chain with the result.
  /// Returns the [ChainFitResult] (also stored in [lastFit]), or null when
  /// there is no valid chain.
  ChainFitResult? fit() {
    final c = _chain;
    if (c == null || !c.isValid) return null;
    final g = Ganglinje.compute(c);
    if (g == null) return null;
    final result = ChainFitter.fit(c, g, minInnerMm: _minInnerMm);
    _lastFit = result;
    _chain   = result.chain;
    _logFitSteps(result);
    notifyListeners();
    return result;
  }

  void _logFitSteps(ChainFitResult result) {
    final polys = ChainGeometry.compute(result.chain, 10.0);
    final steps = _buildStepList(result.chain, polys);
    final buf   = StringBuffer('[Fit steps]\n{\n');
    buf.write('  "totalSteps": ${result.totalSteps},\n');
    buf.write('  "riserMm": ${result.riserMm.toStringAsFixed(1)},\n');
    buf.write('  "idealTreadMm": ${result.idealTreadMm.toStringAsFixed(1)},\n');
    buf.write('  "steps": [\n');
    for (var i = 0; i < steps.length; i++) {
      final s  = steps[i];
      final sb = StringBuffer('    {');
      sb.write('"number": ${s.number}, ');
      sb.write('"parent": "${s.parent}", ');
      sb.write('"riserMm": ${s.riserMm.toStringAsFixed(1)}, ');
      sb.write('"treadMm": ${s.treadMm.toStringAsFixed(1)}, ');
      if (s.isCornerStep) {
        sb.write('"innerTreadMm": ${s.innerTreadMm!.toStringAsFixed(1)}, ');
        sb.write('"outerTreadMm": ${s.outerTreadMm!.toStringAsFixed(1)}, ');
        sb.write('"stepAngleDeg": ${s.stepAngleDeg.toStringAsFixed(1)}, ');
      }
      sb.write('"inclAngleDeg": ${s.inclAngleDeg.toStringAsFixed(1)}');
      sb.write('}');
      if (i < steps.length - 1) sb.write(',');
      buf.write('$sb\n');
    }
    buf.write('  ]\n}');
    // ignore: avoid_print
    print(buf);
  }

  // ── Step list ─────────────────────────────────────────────────────────────

  static List<StepInfo> _buildStepList(StairChain chain, ChainPolygons polys) {
    final result  = <StepInfo>[];

    // Total step count determines riser height.
    var totalN = 0;
    for (var i = 0; i < chain.edgeCount; i++) {
      totalN += chain.edges[i].stepCount ??
          StairMath.findOptimalN(chain.edges[i].heightMm, 250);
    }
    for (var j = 0; j < polys.nodes.length; j++) {
      final nd = polys.nodes[j];
      if (nd.turnAngleDeg > 1.0 && nd.poly.length == 6) {
        totalN += chain.nodes[j + 1].stepCount ??
            (nd.turnAngleDeg / 30.0).round().clamp(2, 24);
      }
    }
    if (totalN == 0) return result;

    final riser  = chain.totalHeightMm / totalN;
    var stepNum  = 1;

    for (var ei = 0; ei < chain.edgeCount; ei++) {
      // ── Straight flight segment ────────────────────────────────────────
      final edge   = chain.edges[ei];
      final edData = polys.edges[ei];
      final n      = edge.stepCount ?? StairMath.findOptimalN(edge.heightMm, 250);
      if (n > 0) {
        final tread = edData.lengthMm / n;
        final incl  = tread > 0 && riser > 0
            ? math.atan(riser / tread) * 180.0 / math.pi : 0.0;
        final p = edData.poly; // [SL, EL, ER, SR]
        for (var s = 0; s < n; s++) {
          final t0 = s / n;
          final t1 = (s + 1) / n;
          result.add(StepInfo(
            number:       stepNum++,
            parent:       'Seg ${ei + 1}',
            riserMm:      riser,
            treadMm:      tread,
            inclAngleDeg: incl,
            poly: [
              _lerp(p[0], p[1], t0), _lerp(p[0], p[1], t1),
              _lerp(p[3], p[2], t1), _lerp(p[3], p[2], t0),
            ],
          ));
        }
      }

      // ── Winding corner node that follows ──────────────────────────────
      if (ei >= polys.nodes.length) continue;
      final nd = polys.nodes[ei];
      if (nd.turnAngleDeg < 1.0 || nd.poly.length != 6) continue;
      final nodeN = chain.nodes[ei + 1].stepCount ??
          (nd.turnAngleDeg / 30.0).round().clamp(2, 24);
      if (nodeN <= 0) continue;
      // poly = [EO(0), OMC(1), SO(2), SI(3), IMC(4), EI(5)]
      final outerPath     = [nd.poly[0], nd.poly[1], nd.poly[2]]; // EO → OMC → SO
      final innerBoundary = [nd.poly[5], nd.poly[4], nd.poly[3]]; // EI → IMC → SI
      final eiPt = nd.poly[5]; // EI — chord start for inner distribution
      final siPt = nd.poly[3]; // SI — chord end
      final gangLen   = nd.ganglinjeStart != null && nd.ganglinjeEnd != null
          ? (nd.ganglinjeEnd! - nd.ganglinjeStart!).distance : 0.0;
      final gangTread = gangLen / nodeN;
      final nodeIncl  = gangTread > 0 && riser > 0
          ? math.atan(riser / gangTread) * 180.0 / math.pi : 0.0;
      for (var s = 0; s < nodeN; s++) {
        final t0 = s / nodeN;
        final t1 = (s + 1) / nodeN;
        final o0 = _ptOnPath(outerPath, t0);
        final o1 = _ptOnPath(outerPath, t1);
        final i0 = _chordProjectOnPath(innerBoundary, eiPt, siPt, t0);
        final i1 = _chordProjectOnPath(innerBoundary, eiPt, siPt, t1);
        result.add(StepInfo(
          number:        stepNum++,
          parent:        'Corner ${ei + 1}',
          riserMm:       riser,
          treadMm:       gangTread,
          innerTreadMm:  (i1 - i0).distance,
          outerTreadMm:  (o1 - o0).distance,
          stepAngleDeg:  nd.turnAngleDeg / nodeN,
          inclAngleDeg:  nodeIncl,
          poly:          [o0, o1, i1, i0],
        ));
      }
    }
    return result;
  }

  // ── Path helpers ──────────────────────────────────────────────────────────

  static Offset _lerp(Offset a, Offset b, double t) => a + (b - a) * t;

  /// Returns the point on [pts] whose projection onto the chord [a→b]
  /// equals t·|b−a|.  Anchors land on the real boundary (e.g. EI→IMC→SI)
  /// while the t-spacing comes from the straight chord (even distribution).
  static Offset _chordProjectOnPath(
      List<Offset> pts, Offset a, Offset b, double t) {
    final chord = b - a;
    final len   = chord.distance;
    if (len < 1e-6) return a;
    final u          = chord / len;
    final targetProj = t * len;
    for (var seg = 0; seg < pts.length - 1; seg++) {
      final p0    = pts[seg];
      final p1    = pts[seg + 1];
      final proj0 = (p0 - a).dx * u.dx + (p0 - a).dy * u.dy;
      final proj1 = (p1 - a).dx * u.dx + (p1 - a).dy * u.dy;
      final span  = proj1 - proj0;
      if (span.abs() < 1e-6) continue;
      final localT = (targetProj - proj0) / span;
      if (localT >= -1e-6 && localT <= 1 + 1e-6) {
        return p0 + (p1 - p0) * localT.clamp(0.0, 1.0);
      }
    }
    return pts.last;
  }

  static Offset _ptOnPath(List<Offset> pts, double t) {
    double total = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    if (total < 1e-6) return pts.first;
    double target = t * total;
    double accum  = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      final seg = (pts[i + 1] - pts[i]).distance;
      if (accum + seg >= target - 1e-9) {
        return _lerp(pts[i], pts[i + 1],
            (seg < 1e-6 ? 0.0 : (target - accum) / seg).clamp(0.0, 1.0));
      }
      accum += seg;
    }
    return pts.last;
  }
}
