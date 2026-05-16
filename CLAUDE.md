# the_stair_app — Claude Notes

## Project overview
Dedicated Flutter staircase design app. Separate from `homesim` (the floor plan editor).
Working directory: `~/Projects/widdinghome/FlutterProjects/the_stair_app`

## Two staircase models

### 1. Classic `Staircase` model (`lib/models/staircase.dart`)
- Persisted in SQLite via `StaircaseRepository`
- Types: straight, lShaped, uShaped, straightWithLanding, zShaped, sShaped, sShapedMirror
- One `widths` list (one width per flight); alignment: left/center/right
- Supports winding corners, comfortable winding, chamfer, vanger, landing nodes
- Rendered by `staircase_layer_painter.dart` and `staircase_painter_helper.dart`
- UI: `StaircaseBottomPanel` slides up from bottom when selected — tabbed cards (Steps, Vanger, Width, Corner, Cut list)
- DB: `staircases`, `staircase_points`, `staircase_landings`, `staircase_flight_widths` tables

### 2. Chain `StairChain` model (`lib/stair_model/chain.dart`)
- **In-memory only — not persisted to DB**
- A polyline of `ChainNode` waypoints connected by `ChainEdge` flight segments
- Invariant: `nodes.length == edges.length + 1`
- `ChainEdge`: widthMm, heightMm (floor height per segment), **stepCount** (nullable int, null = auto)
- `ChainNode`: gx/gy grid position, landingMm (0 = pure miter), landingOffset (0–1)
- Geometry computed by `ChainGeometry.compute()` in `chain_geometry.dart`
  - Returns `ChainPolygons` with `List<EdgeData>` and `List<NodeData>`
  - Edge polygon: 4 pts `[startLeft, endLeft, endRight, startRight]`
  - Node polygon: up to 6 pts `[endOuter, omc, startOuter, startInner, imc, endInner]`
- Rendered by `ChainPainter` in `chain_painter.dart`
- UI: Chain inspector panel on LEFT when chain selected; node panel on RIGHT when node tapped
- Draw mode toggled via the polyline icon in the AppBar

## Editor screen (`lib/screens/editor_screen.dart`)
- Manages both models simultaneously
- `_selectedStaircaseId` → shows `StaircaseBottomPanel`
- `_selectedChainId` + `_selectedChainNodeIdx` → shows chain inspector (left) + node panel (right)
- `showPanel = _selectedStaircase != null` — bottom panel only for classic model
- Chain inspector in `_buildEdgeCard` / `_buildNodeCard` — reads `ChainGeometry.compute(chain, 10.0)`

## Key conventions
- Grid: 1 unit = 10 mm
- Blondel formula: `2R + T = 620 mm`; `StaircaseCalculator.findOptimalN(heightMm, treadMm)`
- Step dividers drawn with `strokeWidth 0.5`, same color as stroke
- Edge step dividers: interpolate left and right sides of edge polygon at equal t parameters
- Chain `heightMm` is per edge (each segment can have different floor height)

## What's been built
- Chain model: `ChainEdge.stepCount` (nullable int) — null = auto from heightMm; step dividers drawn in `ChainPainter._drawChain`; step count slider added to `_buildEdgeCard` in editor
- Classic model: `segmentSteps` (List<int?>) added to Staircase model and persisted in DB (see homesim for reference implementation — needs porting here too)
