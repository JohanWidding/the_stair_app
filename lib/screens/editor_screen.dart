
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/level_repository.dart';
import '../models/project.dart';
import '../services/stair_math.dart';
import '../stair_model/chain.dart';
import '../stair_model/chain_geometry.dart';
import '../stair_model/staircase_model.dart';
import '../widgets/stair_canvas.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
  });

  final Project project;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  bool _loading = true;

  final StaircaseModel _model = StaircaseModel();

  String? _selectedChainId;
  int?    _selectedChainNodeIdx;

  // ── Bottom panel state ────────────────────────────────────────────────────
  double _panelFraction    = 0.40;
  bool   _isDraggingPanel  = false;
  static const _panelMinFraction     = 0.08;
  static const _panelMaxFraction     = 0.72;
  static const _panelDefaultFraction = 0.40;

  // Computed once — stable across rebuilds.
  double? _initialCellSize;
  Offset? _initialOrigin;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModelChanged);
    _init();
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _model.dispose();
    super.dispose();
  }

  void _onModelChanged() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialCellSize == null) {
      final size = MediaQuery.of(context).size;
      _initialCellSize = size.height / 700.0;
      _initialOrigin   = Offset(size.width * 0.15, size.height * 0.08);
    }
  }

  Future<void> _init() async {
    final levelRepo = context.read<LevelRepository>();
    await levelRepo.ensureDefaultLevel(widget.project.id);
    if (mounted) setState(() => _loading = false);
  }

  // ── Canvas callbacks ──────────────────────────────────────────────────────

  void _onChainEdgeDraw(double gx1, double gy1, double gx2, double gy2) {
    _model.onEdgeDraw(gx1, gy1, gx2, gy2);
  }

  void _onChainNodeDragEnd(String chainId, int nodeIdx, double gx, double gy) {
    if (_model.chain?.id == chainId) {
      _model.moveNode(nodeIdx, gx, gy);
    }
  }

  void _onChainNodeTap(String chainId, int nodeIdx) {
    if (_model.hasDraft) return;
    setState(() {
      if (_selectedChainId == chainId && _selectedChainNodeIdx == nodeIdx) {
        _selectedChainNodeIdx = null;
      } else {
        _selectedChainId      = chainId;
        _selectedChainNodeIdx = nodeIdx;
        _panelFraction        = _panelDefaultFraction;
      }
    });
  }

  void _onChainTap(String chainId) {
    if (_model.hasDraft) return;
    setState(() {
      if (_selectedChainId == chainId) {
        _selectedChainId      = null;
        _selectedChainNodeIdx = null;
      } else {
        _selectedChainId      = chainId;
        _selectedChainNodeIdx = null;
        _panelFraction        = _panelDefaultFraction;
      }
    });
  }

  void _commitDraft() {
    final id = _model.draft?.id;
    _model.commitDraft();
    setState(() {
      _selectedChainId = id;
      _panelFraction   = _panelDefaultFraction;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight  = screenHeight * _panelFraction;
    final showPanel    = _selectedChainId != null && _model.hasChain;

    final displayChains = _model.chain != null ? [_model.chain!] : <StairChain>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: '3D View — coming soon',
            onPressed: null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                // ── Canvas ────────────────────────────────────────────────
                StairCanvas(
                  chains:             displayChains,
                  draftChain:         _model.draft,
                  selectedChainId:    _selectedChainId,
                  onChainEdgeDraw:    _onChainEdgeDraw,
                  onChainNodeDragEnd: _onChainNodeDragEnd,
                  onChainNodeTap:     _onChainNodeTap,
                  onChainTap:         _onChainTap,
                  onTapEmpty: () => setState(() {
                    _selectedChainId      = null;
                    _selectedChainNodeIdx = null;
                  }),
                  initialCellSize: _initialCellSize ?? 8.0,
                  initialOrigin:   _initialOrigin ?? const Offset(200, 200),
                ),

                // ── Empty-state hint ──────────────────────────────────────
                if (!_model.hasChain && !_model.hasDraft)
                  IgnorePointer(
                    child: Center(
                      child: Text(
                        'Drag to draw a staircase\nRight-click drag to pan  ·  Scroll to zoom',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.30),
                            ),
                      ),
                    ),
                  ),

                // ── Draft floating card ───────────────────────────────────
                if (_model.hasDraft)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, -0.60),
                      child: Card(
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _model.draft!.edgeCount == 1
                                    ? '1 segment — drag from the last node to add more'
                                    : '${_model.draft!.edgeCount} segments — drag from last node to add more',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    onPressed: _model.cancelDraft,
                                    child: const Text('Cancel'),
                                  ),
                                  const SizedBox(width: 16),
                                  FilledButton(
                                    onPressed: _commitDraft,
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // ── Node property panel — top right ───────────────────────
                if (_selectedChainId != null &&
                    _selectedChainNodeIdx != null &&
                    _model.chain?.id == _selectedChainId)
                  Builder(builder: (context) {
                    final chain = _model.chain!;
                    final ni = _selectedChainNodeIdx!;
                    if (ni >= chain.nodes.length) return const SizedBox.shrink();
                    final node       = chain.nodes[ni];
                    final isInterior = ni > 0 && ni < chain.nodes.length - 1;
                    return Positioned(
                      right: 16,
                      top: 72,
                      child: Card(
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                          child: SizedBox(
                            width: 260,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Node $ni',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => setState(
                                          () => _selectedChainNodeIdx = null),
                                    ),
                                  ],
                                ),
                                if (isInterior) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Landing: ${node.landingMm.round()} mm',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Slider(
                                    value: node.landingMm,
                                    min: 0,
                                    max: 2000,
                                    divisions: 40,
                                    onChanged: (v) => _model.updateNode(
                                        ni, node.copyWith(landingMm: v)),
                                  ),
                                  Text(
                                    'Position: ${(node.landingOffset * 100).round()}%',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Slider(
                                    value: node.landingOffset,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 20,
                                    onChanged: (v) => _model.updateNode(
                                        ni, node.copyWith(landingOffset: v)),
                                  ),
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text('Endpoint — no landing',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // ── Bottom sliding panel ──────────────────────────────────
                AnimatedPositioned(
                  duration: _isDraggingPanel
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  bottom: showPanel ? 0 : -panelHeight,
                  left: 0,
                  right: 0,
                  height: panelHeight,
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: !showPanel,
                      child: _buildChainPanel(context),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Chain inspector panel ─────────────────────────────────────────────────

  Widget _buildChainPanel(BuildContext context) {
    final chain = _model.chain;
    if (chain == null || !chain.isValid) return const SizedBox.shrink();

    final polys      = _model.computeGeometry();
    final originMm   = Offset(chain.nodes[0].gx * 10, chain.nodes[0].gy * 10);
    final totalItems = chain.edgeCount * 2 - 1;
    final cs         = Theme.of(context).colorScheme;
    final stepList   = _model.computeSteps(polys);

    return DefaultTabController(
      length: 2,
      child: Material(
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Drag handle ──────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) =>
                  setState(() => _isDraggingPanel = true),
              onVerticalDragUpdate: (d) {
                final sh = MediaQuery.of(context).size.height;
                setState(() {
                  _panelFraction =
                      (_panelFraction - d.delta.dy / sh)
                          .clamp(_panelMinFraction, _panelMaxFraction);
                });
              },
              onVerticalDragEnd: (d) {
                final vy = d.velocity.pixelsPerSecond.dy;
                setState(() {
                  _isDraggingPanel = false;
                  if (vy < -600) {
                    _panelFraction = _panelMaxFraction;
                  } else if (vy > 600) {
                    _panelFraction = _panelMinFraction;
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${chain.edgeCount} segment${chain.edgeCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _selectedChainId      = null;
                      _selectedChainNodeIdx = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Controls row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Height slider
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Height: ${chain.totalHeightMm.round()} mm',
                            style: Theme.of(context).textTheme.bodySmall),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10),
                          ),
                          child: Slider(
                            min: 1500,
                            max: 6000,
                            divisions: 90,
                            value: chain.totalHeightMm,
                            onChanged: (v) => _model.setHeight(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Min-inner slider
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Min inner: ${_model.minInnerMm.round()} mm',
                            style: Theme.of(context).textTheme.bodySmall),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10),
                          ),
                          child: Slider(
                            min: 0,
                            max: 300,
                            divisions: 60,
                            value: _model.minInnerMm,
                            onChanged: (v) => _model.setMinInner(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _model.fit,
                      child: const Text('Fit'),
                    ),
                  ),
                ],
              ),
            ),

            // ── Ganglinje mode toggle ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: SegmentedButton<GanglinjeMode>(
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: GanglinjeMode.middlewalk,   label: Text('Mid')),
                  ButtonSegment(value: GanglinjeMode.middlestrict, label: Text('Mid+')),
                  ButtonSegment(value: GanglinjeMode.innerstrict,  label: Text('Inner')),
                  ButtonSegment(value: GanglinjeMode.outerstrict,  label: Text('Outer')),
                ],
                selected: {chain.ganglinjeMode},
                onSelectionChanged: (s) => _model.setGanglinjeMode(s.first),
              ),
            ),

            const Divider(height: 1),

            // ── Tab bar ──────────────────────────────────────────────────
            TabBar(
              labelStyle: Theme.of(context).textTheme.labelSmall,
              tabs: [
                Tab(text: 'Segments (${chain.edgeCount})'),
                Tab(text: 'Steps (${stepList.length})'),
              ],
            ),

            const Divider(height: 1),

            // ── Tab content ──────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                children: [
                  // Segments list
                  ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    itemCount: totalItems,
                    separatorBuilder: (context, i) => const SizedBox(width: 12),
                    itemBuilder: (context, idx) {
                      if (idx.isEven) {
                        final ei = idx ~/ 2;
                        return SizedBox(
                          width: 220,
                          child: _buildEdgeCard(context, ei,
                              polys.edges[ei], originMm, chain.edges[ei]),
                        );
                      } else {
                        final ni = idx ~/ 2;
                        return SizedBox(
                          width: 220,
                          child: _buildNodeCard(context, ni + 1,
                              polys.nodes[ni], originMm, chain.nodes[ni + 1]),
                        );
                      }
                    },
                  ),
                  // Steps list
                  ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: stepList.length,
                    separatorBuilder: (context, i) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, idx) =>
                        _buildStepCard(context, stepList[idx], originMm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edge card ─────────────────────────────────────────────────────────────

  Widget _buildEdgeCard(BuildContext context, int idx, EdgeData ed,
      Offset originMm, ChainEdge chainEdge) {
    final cs       = Theme.of(context).colorScheme;
    final ts       = Theme.of(context).textTheme;
    final relPoly  = [for (final p in ed.poly) p - originMm];
    final autoSteps = StairMath.findOptimalN(chainEdge.heightMm, 250.0);
    final isEaten   = chainEdge.stepCount == 0;
    final currentSteps = isEaten ? 0 : (chainEdge.stepCount ?? autoSteps);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _TypeBadge(label: 'EDGE', color: cs.primary),
              const SizedBox(width: 6),
              Text('Segment ${idx + 1}', style: ts.labelMedium),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 72,
              child: CustomPaint(
                painter: _PolyPreviewPainter(
                  points: relPoly,
                  strokeColor: cs.outline,
                  labels: const ['SL', 'EL', 'ER', 'SR'],
                  vertexColors: const {0: Colors.white, 3: Colors.white,
                                       1: Colors.black, 2: Colors.black},
                  ganglinjeStart: ed.ganglinjeStart - originMm,
                  ganglinjeEnd:   ed.ganglinjeEnd   - originMm,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            Text('W ${ed.widthMm.round()} mm  ·  L ${ed.lengthMm.round()} mm',
                style: ts.bodySmall),
            if (!isEaten && chainEdge.stepCount != null && chainEdge.heightMm > 0)
              Text(
                'H ${chainEdge.heightMm.round()} mm  ·  '
                'R ${(chainEdge.heightMm / chainEdge.stepCount!).round()} mm/step',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
            const SizedBox(height: 4),
            if (isEaten) ...[
              Text('Steps: 0 — eaten by adjacent landings',
                  style: ts.bodySmall?.copyWith(color: cs.outline)),
            ] else ...[
              Row(children: [
                Text('Steps: $currentSteps', style: ts.bodySmall),
                if (chainEdge.stepCount == null)
                  Text(' (auto)',
                      style: ts.bodySmall?.copyWith(color: cs.outline)),
              ]),
              Flexible(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    min: 3,
                    max: 25,
                    divisions: 22,
                    value: currentSteps.clamp(3, 25).toDouble(),
                    onChanged: (v) => _model.updateEdge(
                        idx, chainEdge.copyWith(stepCount: v.round())),
                    onChangeEnd: (v) {
                      if (v.round() == autoSteps) {
                        _model.updateEdge(idx, chainEdge.copyWith(stepCount: null));
                      }
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Node card ─────────────────────────────────────────────────────────────

  Widget _buildNodeCard(BuildContext context, int idx, NodeData nd,
      Offset originMm, ChainNode chainNode) {
    final cs       = Theme.of(context).colorScheme;
    final ts       = Theme.of(context).textTheme;
    final relPoly  = nd.poly.isEmpty
        ? <Offset>[]
        : [for (final p in nd.poly) p - originMm];
    final isCorner    = nd.poly.length == 6;
    final autoSteps   = (nd.turnAngleDeg / 30.0).round().clamp(2, 24);
    final currentSteps = (chainNode.stepCount ?? autoSteps).clamp(2, 24);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _TypeBadge(label: 'NODE', color: cs.secondary),
              const SizedBox(width: 6),
              Text('Node $idx', style: ts.labelMedium),
            ]),
            const SizedBox(height: 4),
            Text(
              nd.turnAngleDeg < 0.5
                  ? 'Straight'
                  : 'Turn ${nd.turnAngleDeg.round()}°'
                    ' ${nd.isRightTurn ? "Right" : "Left"}',
              style: ts.bodySmall,
            ),
            if (nd.landingMm > 0)
              Text('Landing ${nd.landingMm.round()} mm', style: ts.bodySmall),
            if (relPoly.isNotEmpty) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 72,
                child: CustomPaint(
                  painter: _PolyPreviewPainter(
                    points: relPoly,
                    strokeColor: cs.outline,
                    labels: const ['EO', 'OMC', 'SO', 'SI', 'IMC', 'EI'],
                    highlightIndex: relPoly.length == 6 ? 4 : null,
                    ganglinjeStart: nd.ganglinjeStart != null
                        ? nd.ganglinjeStart! - originMm : null,
                    ganglinjeEnd: nd.ganglinjeEnd != null
                        ? nd.ganglinjeEnd! - originMm : null,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('No corner geometry',
                    style: ts.bodySmall?.copyWith(color: cs.outline)),
              ),
            if (isCorner) ...[
              const SizedBox(height: 4),
              Row(children: [
                Text('Steps: $currentSteps', style: ts.bodySmall),
                if (chainNode.stepCount == null)
                  Text(' (auto)',
                      style: ts.bodySmall?.copyWith(color: cs.outline)),
              ]),
              Flexible(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    min: 2,
                    max: 24,
                    divisions: 22,
                    value: currentSteps.toDouble(),
                    onChanged: (v) => _model.updateNode(
                        idx, chainNode.copyWith(stepCount: v.round())),
                    onChangeEnd: (v) {
                      if (v.round() == autoSteps) {
                        _model.updateNode(idx, chainNode.copyWith(stepCount: null));
                      }
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Step card ─────────────────────────────────────────────────────────────

  Widget _buildStepCard(BuildContext context, StepInfo info, Offset originMm) {
    final cs       = Theme.of(context).colorScheme;
    final ts       = Theme.of(context).textTheme;
    final rel      = [for (final p in info.poly) p - originMm];

    final lTread = info.isCornerStep ? (info.outerTreadMm ?? info.treadMm) : info.treadMm;
    final cTread = info.treadMm;
    final rTread = info.isCornerStep ? (info.innerTreadMm ?? info.treadMm) : info.treadMm;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 56,
              child: CustomPaint(
                painter: _PolyPreviewPainter(
                  points: rel,
                  strokeColor: cs.outline,
                  labels: const ['', '', '', ''],
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    _TypeBadge(label: 'STEP', color: cs.tertiary),
                    const SizedBox(width: 6),
                    Text('#${info.number}', style: ts.labelMedium),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(info.parent,
                          style: ts.bodySmall?.copyWith(color: cs.outline),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  IntrinsicHeight(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _TreadCell(label: 'L', valueMm: lTread, cs: cs, ts: ts),
                        VerticalDivider(width: 1, color: cs.outlineVariant),
                        _TreadCell(label: 'C', valueMm: cTread, cs: cs, ts: ts),
                        VerticalDivider(width: 1, color: cs.outlineVariant),
                        _TreadCell(label: 'R', valueMm: rTread, cs: cs, ts: ts),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'R ${info.riserMm.round()} mm'
                    '  ·  α ${info.inclAngleDeg.toStringAsFixed(1)}°'
                    '${info.stepAngleDeg > 0.1 ? "  ·  ${info.stepAngleDeg.toStringAsFixed(1)}°/step" : ""}',
                    style: ts.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _TreadCell extends StatelessWidget {
  const _TreadCell({
    required this.label,
    required this.valueMm,
    required this.cs,
    required this.ts,
  });

  final String      label;
  final double      valueMm;
  final ColorScheme cs;
  final TextTheme   ts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: ts.labelSmall?.copyWith(
                  color: cs.outline, fontSize: 9)),
          Text('${valueMm.round()}',
              style: ts.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          Text('mm',
              style: ts.labelSmall?.copyWith(
                  color: cs.outline, fontSize: 8)),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PolyPreviewPainter extends CustomPainter {
  const _PolyPreviewPainter({
    required this.points,
    required this.strokeColor,
    required this.labels,
    this.vertexColors    = const {},
    this.highlightIndex,
    this.ganglinjeStart,
    this.ganglinjeEnd,
  });

  final List<Offset>    points;
  final Color           strokeColor;
  final List<String>    labels;
  final Map<int, Color> vertexColors;
  final int?            highlightIndex;
  final Offset?         ganglinjeStart;
  final Offset?         ganglinjeEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;

    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    const pad   = 8.0;
    final bw    = maxX - minX;
    final bh    = maxY - minY;
    final availW = size.width  - pad * 2;
    final availH = size.height - pad * 2;
    final scale  = (bw > 1e-6 && bh > 1e-6)
        ? (availW / bw < availH / bh ? availW / bw : availH / bh)
        : (bw > 1e-6 ? availW / bw : (bh > 1e-6 ? availH / bh : 1.0));

    Offset tx(Offset p) => Offset(
      pad + (p.dx - minX) * scale + (availW - bw * scale) / 2,
      pad + (p.dy - minY) * scale + (availH - bh * scale) / 2,
    );

    final fill = Paint()
      ..color = strokeColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()..moveTo(tx(points.first).dx, tx(points.first).dy);
    for (final p in points.skip(1)) { path.lineTo(tx(p).dx, tx(p).dy); }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    if (ganglinjeStart != null && ganglinjeEnd != null) {
      canvas.drawLine(
        tx(ganglinjeStart!), tx(ganglinjeEnd!),
        Paint()
          ..color = strokeColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < points.length && i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      final isHL = i == highlightIndex;
      tp.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          fontSize: 7,
          fontWeight: isHL ? FontWeight.w700 : FontWeight.normal,
          color: vertexColors[i] ??
              (isHL ? strokeColor : strokeColor.withValues(alpha: 0.7)),
        ),
      );
      tp.layout();
      final pos = tx(points[i]);
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PolyPreviewPainter old) =>
      old.points != points || old.strokeColor != strokeColor;
}
