import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../stair_model/chain.dart';
import '../stair_model/chain_painter.dart';
import 'grid_painter.dart';

const _kDefaultCellSize = 8.0;
const _kMinCellSize     = 0.3;
const _kMaxCellSize     = 100.0;
const _kNodeHitRadius   = 22.0;
const _kChainHitWidth   = 28.0;

typedef ChainEdgeDrawCallback    = void Function(double gx1, double gy1, double gx2, double gy2);
typedef ChainNodeDragEndCallback = void Function(String chainId, int nodeIdx, double gx, double gy);
typedef ChainNodeTapCallback     = void Function(String chainId, int nodeIdx);
typedef ChainTapCallback         = void Function(String chainId);

/// Canvas with pan/zoom, chain draw (primary drag on empty space),
/// and secondary-button (right-click) pan.
///
/// No explicit "draw mode" — dragging on empty space always draws a chain
/// edge. Right-click drag or two-finger gesture pans the view.
class StairCanvas extends StatefulWidget {
  const StairCanvas({
    super.key,
    this.chains             = const [],
    this.draftChain,
    this.selectedChainId,
    this.onChainEdgeDraw,
    this.onChainNodeDragEnd,
    this.onChainNodeTap,
    this.onChainTap,
    this.onTapEmpty,
    this.initialCellSize    = _kDefaultCellSize,
    this.initialOrigin      = const Offset(200, 200),
  });

  final List<StairChain>          chains;
  final StairChain?               draftChain;
  final String?                   selectedChainId;
  final ChainEdgeDrawCallback?    onChainEdgeDraw;
  final ChainNodeDragEndCallback? onChainNodeDragEnd;
  final ChainNodeTapCallback?     onChainNodeTap;
  final ChainTapCallback?         onChainTap;
  final VoidCallback?             onTapEmpty;
  final double                    initialCellSize;
  final Offset                    initialOrigin;

  @override
  State<StairCanvas> createState() => _StairCanvasState();
}

class _StairCanvasState extends State<StairCanvas> {
  late Offset _origin;
  late double _cellSize;

  // ── Secondary-button (right-click) pan ───────────────────────────────────
  Offset? _secPanStart;
  Offset? _secPanOrigin;

  // ── Pinch state ───────────────────────────────────────────────────────────
  double? _pinchStartCellSize;
  Offset? _pinchStartFocal;
  Offset? _pinchStartOrigin;

  // ── Chain node drag state ─────────────────────────────────────────────────
  String? _dragChainId;
  int?    _dragChainNodeIdx;
  double? _dragChainGx;
  double? _dragChainGy;
  bool    _suppressTap = false;

  // ── Primary-button pan (when no draw is possible) ────────────────────────
  Offset? _primaryPanStart;
  Offset? _primaryPanOrigin;

  // ── Chain edge-draw drag state ────────────────────────────────────────────
  bool    _isChainDrawingDrag = false;
  (double, double)? _chainDrawStart;
  Offset? _chainDragStartPx;
  Offset? _chainDragLastPx;
  Offset? _chainDraftScreenPos;

  @override
  void initState() {
    super.initState();
    _cellSize = widget.initialCellSize;
    _origin   = widget.initialOrigin;
  }

  // ── Grid snap ─────────────────────────────────────────────────────────────

  int get _snapStep {
    if (_cellSize >= 1.6)  return 5;
    if (_cellSize >= 0.16) return 50;
    return 100;
  }

  (double, double) _pixelToGridDouble(Offset local) {
    final step = _snapStep;
    final cx = (local.dx - _origin.dx) / _cellSize;
    final cy = (local.dy - _origin.dy) / _cellSize;
    return (
      ((cx / step).round() * step).toDouble(),
      ((cy / step).round() * step).toDouble(),
    );
  }

  // ── Hit-testing ───────────────────────────────────────────────────────────

  ({String chainId, int nodeIdx})? _hitTestChainNode(Offset local) {
    for (final chain in widget.chains) {
      for (var i = 0; i < chain.nodes.length; i++) {
        final nd = chain.nodes[i];
        final px = Offset(
          _origin.dx + nd.gx * _cellSize,
          _origin.dy + nd.gy * _cellSize,
        );
        if ((local - px).distance <= _kNodeHitRadius) {
          return (chainId: chain.id, nodeIdx: i);
        }
      }
    }
    return null;
  }

  // Distance from point p to line segment a→b.
  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 < 1e-9) return (p - a).distance;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    return (p - (a + ab * t.clamp(0.0, 1.0))).distance;
  }

  String? _hitTestChainBody(Offset local) {
    for (final chain in widget.chains) {
      for (var i = 0; i < chain.nodes.length - 1; i++) {
        final a = Offset(
          _origin.dx + chain.nodes[i].gx * _cellSize,
          _origin.dy + chain.nodes[i].gy * _cellSize,
        );
        final b = Offset(
          _origin.dx + chain.nodes[i + 1].gx * _cellSize,
          _origin.dy + chain.nodes[i + 1].gy * _cellSize,
        );
        if (_distToSegment(local, a, b) <= _kChainHitWidth) return chain.id;
      }
    }
    return null;
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    // Pinch zoom / two-finger pan
    if (d.pointerCount >= 2) {
      _pinchStartCellSize = _cellSize;
      _pinchStartFocal    = d.localFocalPoint;
      _pinchStartOrigin   = _origin;
      return;
    }

    // Chain node drag
    final chainHit = _hitTestChainNode(d.localFocalPoint);
    if (chainHit != null) {
      final chain = widget.chains.where((c) => c.id == chainHit.chainId).firstOrNull;
      if (chain != null) {
        final nd = chain.nodes[chainHit.nodeIdx];
        setState(() {
          _dragChainId      = chainHit.chainId;
          _dragChainNodeIdx = chainHit.nodeIdx;
          _dragChainGx      = nd.gx;
          _dragChainGy      = nd.gy;
          _suppressTap      = false;
        });
        return;
      }
    }

    // Committed chain exists and no draft active → pan instead of draw.
    if (widget.chains.isNotEmpty && widget.draftChain == null) {
      setState(() {
        _primaryPanStart  = d.localFocalPoint;
        _primaryPanOrigin = _origin;
      });
      return;
    }

    // Primary drag on empty space → draw a new chain edge.
    // If a draft chain exists start from its last node; otherwise from drag origin.
    double startGx, startGy;
    final draft = widget.draftChain;
    if (draft != null && draft.isValid) {
      startGx = draft.nodes.last.gx;
      startGy = draft.nodes.last.gy;
    } else {
      final (gx, gy) = _pixelToGridDouble(d.localFocalPoint);
      startGx = gx;
      startGy = gy;
    }
    setState(() {
      _isChainDrawingDrag  = true;
      _chainDrawStart      = (startGx, startGy);
      _chainDragStartPx    = d.localFocalPoint;
      _chainDragLastPx     = d.localFocalPoint;
      _chainDraftScreenPos = d.localFocalPoint;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_primaryPanStart != null) {
      setState(() => _origin = _primaryPanOrigin! + d.localFocalPoint - _primaryPanStart!);
      return;
    }

    // Two-finger: zoom + pan together
    if (d.pointerCount >= 2) {
      if (_pinchStartCellSize == null) return;
      final newCs = (_pinchStartCellSize! * d.scale).clamp(_kMinCellSize, _kMaxCellSize);
      setState(() {
        _cellSize = newCs;
        _origin   = d.localFocalPoint -
            (_pinchStartFocal! - _pinchStartOrigin!) * (newCs / _pinchStartCellSize!);
      });
      return;
    }

    if (_isChainDrawingDrag) {
      setState(() {
        _chainDraftScreenPos = d.localFocalPoint;
        _chainDragLastPx     = d.localFocalPoint;
      });
      return;
    }

    if (_dragChainId != null) {
      final (gx, gy) = _pixelToGridDouble(d.localFocalPoint);
      setState(() {
        _dragChainGx = gx;
        _dragChainGy = gy;
        _suppressTap = true;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_primaryPanStart != null) {
      setState(() { _primaryPanStart = null; _primaryPanOrigin = null; });
      return;
    }

    if (_isChainDrawingDrag) {
      final startPx = _chainDragStartPx;
      final endPx   = _chainDragLastPx;
      final moved   = startPx != null &&
          endPx != null &&
          (endPx - startPx).distance > _snapStep * _cellSize * 0.4;
      if (moved && _chainDrawStart != null) {
        final (endGx, endGy) = _pixelToGridDouble(endPx);
        final s = _chainDrawStart!;
        if (endGx != s.$1 || endGy != s.$2) {
          widget.onChainEdgeDraw?.call(s.$1, s.$2, endGx, endGy);
        }
      }
      setState(() {
        _isChainDrawingDrag  = false;
        _chainDrawStart      = null;
        _chainDragStartPx    = null;
        _chainDragLastPx     = null;
        _chainDraftScreenPos = null;
      });
      return;
    }

    if (_dragChainId != null && _dragChainNodeIdx != null &&
        _dragChainGx != null && _dragChainGy != null) {
      widget.onChainNodeDragEnd?.call(
          _dragChainId!, _dragChainNodeIdx!, _dragChainGx!, _dragChainGy!);
    }

    setState(() {
      _dragChainId        = null;
      _dragChainNodeIdx   = null;
      _dragChainGx        = null;
      _dragChainGy        = null;
      _pinchStartCellSize = null;
      _pinchStartFocal    = null;
      _pinchStartOrigin   = null;
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (_suppressTap) { _suppressTap = false; return; }

    final nodeHit = _hitTestChainNode(d.localPosition);
    if (nodeHit != null) {
      widget.onChainNodeTap?.call(nodeHit.chainId, nodeHit.nodeIdx);
      return;
    }

    final bodyHit = _hitTestChainBody(d.localPosition);
    if (bodyHit != null) {
      widget.onChainTap?.call(bodyHit);
      return;
    }

    widget.onTapEmpty?.call();
  }

  void _onMouseScroll(PointerScrollEvent e) {
    const zoomFactor = 1.1;
    final factor     = e.scrollDelta.dy < 0 ? zoomFactor : 1 / zoomFactor;
    final newCs      = (_cellSize * factor).clamp(_kMinCellSize, _kMaxCellSize);
    final local      = e.localPosition;
    setState(() {
      _origin   = local - (local - _origin) * (newCs / _cellSize);
      _cellSize = newCs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final edgeFill     = Paint()..color = cs.primary.withValues(alpha: 0.30)    ..style = PaintingStyle.fill;
    final nodeFill     = Paint()..color = cs.secondary.withValues(alpha: 0.40)  ..style = PaintingStyle.fill;
    final selectedFill = Paint()..color = cs.primary.withValues(alpha: 0.50)    ..style = PaintingStyle.fill;
    final stroke       = Paint()..color = cs.primary ..style = PaintingStyle.stroke ..strokeWidth = 1.5;
    final ghostStroke  = Paint()..color = cs.primary.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke ..strokeWidth = 1.5 ..strokeCap = StrokeCap.round;

    final displayChains = _dragChainId != null
        ? [
            for (final c in widget.chains)
              c.id == _dragChainId
                  ? c.withNodeMoved(_dragChainNodeIdx!, _dragChainGx!, _dragChainGy!)
                  : c,
          ]
        : widget.chains;

    final chainCursorLocal = _chainDraftScreenPos != null
        ? _chainDraftScreenPos! - _origin
        : null;
    final chainGhostStart = (_isChainDrawingDrag &&
            _chainDrawStart != null &&
            widget.draftChain == null)
        ? Offset(_chainDrawStart!.$1 * _cellSize, _chainDrawStart!.$2 * _cellSize)
        : null;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _onMouseScroll(e);
      },
      // Right-click drag = pan
      onPointerDown: (e) {
        if (e.buttons == kSecondaryMouseButton) {
          _secPanStart  = e.localPosition;
          _secPanOrigin = _origin;
        }
      },
      onPointerMove: (e) {
        if (_secPanStart != null) {
          setState(() => _origin = _secPanOrigin! + e.localPosition - _secPanStart!);
        }
      },
      onPointerUp: (_) {
        _secPanStart  = null;
        _secPanOrigin = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: GridPainter(origin: _origin, cellSize: _cellSize),
                child: const SizedBox.expand(),
              ),
            ),
            Transform.translate(
              offset: _origin,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ChainPainter(
                    chains:          displayChains,
                    draftChain:      widget.draftChain,
                    draftCursor:     chainCursorLocal,
                    dragGhostStart:  chainGhostStart,
                    selectedChainId: widget.selectedChainId,
                    cellSize:        _cellSize,
                    edgeFill:        edgeFill,
                    nodeFill:        nodeFill,
                    selectedFill:    selectedFill,
                    stroke:          stroke,
                    ghostStroke:     ghostStroke,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
