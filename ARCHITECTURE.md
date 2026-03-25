# gb-mesh — Architecture

## Core Design Decisions

### Vertex Type — Fixed Record

```haskell
data Vertex = Vertex
  { vPosition :: !(V3 Float)
  , vNormal   :: !(V3 Float)
  , vUV       :: !(V2 Float)
  , vTangent  :: !(V4 Float)  -- w = bitangent handedness (+1 or -1)
  }
```

No typeclass polymorphism, no parametric vertex type. Every generator produces
the same concrete type. This is the glTF/Unity/Unreal standard vertex layout.

Tangent w stores bitangent handedness. The engine reconstructs
`bitangent = cross(normal, tangent.xyz) * tangent.w`.

StrictData handles bang patterns via the project-wide extension.

### Mesh Type — Flat, with Monoid

```haskell
data Mesh = Mesh
  { meshVertices :: ![Vertex]
  , meshIndices  :: ![Word32]
  }
```

- Indexed triangle list only (every 3 indices = one triangle)
- Word32 indices only (no Word16 parameterization)
- No submesh/material metadata — multi-material objects are `[Mesh]`
- `Monoid` instance: `mempty` is empty mesh, `mappend` does vertex
  concatenation + index offset arithmetic
- No `Storable`, no `Vector` — plain lists, gb-engine handles GPU packing

### Error Handling — Make Invalid States Unrepresentable

- `NonEmpty` for profile lists in loft (can't loft zero profiles)
- Smart constructors returning `Maybe` for degenerate inputs (zero radius,
  zero segments)
- Minimum parameter clamping: segments >= 3, stacks >= 1
- No `error`, no `undefined`, no partial functions

### Transforms — Decomposed, Not Matrix

- `translate :: V3 Float -> Mesh -> Mesh`
- `rotate :: Quaternion Float -> Mesh -> Mesh`
- `uniformScale :: Float -> Mesh -> Mesh`
- Normals transformed by rotation only, re-normalized
- Tangent xyz same treatment, w preserved
- No M44 transform (avoids inverse-transpose for non-uniform scale)

### Engine Boundary

gb-mesh produces logical mesh descriptions (plain lists of records). gb-engine
consumes them and handles all GPU-facing concerns. No Storable, no Vector, no
Foreign.Ptr in gb-mesh. The engine extracts fields via record accessors and
packs into Vulkan buffers on its side.

---

## Module Dependency Graph

```
Types
  │
  ├── Combine
  │     │
  │     └── Primitives
  │
  ├── Curve ──────────────┐
  │     │                 │
  │     ├── Surface       │
  │     │     │           │
  │     │     └── Loft ───┘
  │     │           │
  │     │           ├── Humanoid
  │     │           │     │
  │     │           │     └── Equipment
  │     │           │
  │     └───────────┘
  │
  ├── SDF
  │     │
  │     └── Isosurface
  │
  ├── Noise
  │     │
  │     └── Deform
  │
  └── Subdivision
```

---

## Build Order

### Phase 1 — Foundation

#### GBMesh.Types

Core data types shared across all modules.

- `Vertex` — position, normal, UV, tangent (fixed record)
- `Mesh` — vertex list + index list
- `Monoid` instance for `Mesh` with index offset arithmetic
- Mesh validation predicates (all indices in bounds, index count divisible
  by 3, normals unit length)

#### GBMesh.Combine

Mesh merging and transformation.

- `translate` — offset all positions
- `rotate` — rotate positions and normals via quaternion
- `uniformScale` — scale positions, re-normalize normals
- `flipNormals` — negate all normals
- `reverseWinding` — swap second and third index in each triangle
- `merge` — combine a list of meshes (the `Monoid` fold)

### Phase 2 — Primitives

#### GBMesh.Primitives

Parametric shapes with analytical normals and UVs. Every shape takes
segment/ring count parameters for tessellation control.

**Sphere.** Parametric UV sphere.

- Parametric equations: `x = r sin θ cos φ`, `y = r cos θ`, `z = r sin θ sin φ`
- Analytical normals: `n = (x, y, z) / r` (gradient of implicit sphere)
- UV mapping: `u = φ / 2π`, `v = θ / π`
- Seam duplication: vertices at `j = slices` duplicate `j = 0` with `u = 1.0`
- Pole handling: per-triangle pole vertices with `u = (j + 0.5) / slices`,
  centered on each triangle's angular span
- Vertex count: `(stacks + 1) × (slices + 1)`
- Index count: `6 × stacks × slices`

**Capsule.** Two hemispheres + cylinder body.

- Shared vertices at hemisphere/body equator seams (no duplication — positions
  and normals match exactly at θ = π/2)
- Hemisphere normals: `n = normalize(p - hemisphereCenter)`
- Cylinder normals: `n = (cos φ, 0, sin φ)`
- C1-continuous normal transition (both formulas agree at the equator)
- Generated as a single sequence of rings from north pole to south pole:
  top hemisphere rings → cylinder body rings → bottom hemisphere rings

**Cylinder.** Open barrel + optional caps.

- Barrel normals: `n = (cos φ, 0, sin φ)` (radial in XZ)
- Cap normals: `n = (0, ±1, 0)` (flat)
- Hard edge at cap/barrel boundary requires duplicate vertices (barrel rim
  has radial normals, cap rim has flat normals — same position, different
  normals)
- Cap tessellation: fan from center vertex
- Barrel UV: `u = φ / 2π`, `v = t` (linear along height)
- Cap UV: `u = 0.5 + 0.5 cos φ`, `v = 0.5 + 0.5 sin φ` (planar projection)

**Cone.** Apex + tapered body + optional base cap.

- Analytical normals constant along height (ruled surface):
  `n = (h / slant × cos φ, r / slant, h / slant × sin φ)`
  where `slant = √(h² + r²)`
- Apex handling: duplicate apex vertices (one per triangle), each with normal
  centered on that slice's angular span
- Degenerates to a disc when height = 0

**Torus.** Major radius R, minor radius r.

- Parametric: `x = (R + r cos φ) cos θ`, `y = r sin φ`,
  `z = (R + r cos φ) sin θ`
- Analytical normal: `n = (cos φ cos θ, sin φ, cos φ sin θ)` (direction from
  tube center to surface point)
- Double seam duplication: both θ (around major axis) and φ (around tube)
  require seam vertices for UV continuity
- UV: `u = θ / 2π`, `v = φ / 2π`
- Vertex count: `(rings + 1) × (slices + 1)`
- Index count: `6 × rings × slices`

**Box.** Per-face construction.

- 24 vertices (4 per face × 6 faces), not 8
- Per-face flat normals: `(±1, 0, 0)`, `(0, ±1, 0)`, `(0, 0, ±1)`
- UV: each face gets full `[0, 1] × [0, 1]` range
- Optional subdivision grid per face for displacement:
  `(segsU + 1) × (segsV + 1)` vertices per face
- Without subdivision: 24 vertices, 36 indices

**Plane.** Subdivided XZ grid.

- Vertices row by row (Z outer loop, X inner loop)
- Constant normal: `n = (0, 1, 0)`
- UV: `u = j / segsX`, `v = i / segsZ`
- Vertex count: `(segsX + 1) × (segsZ + 1)`
- Index count: `6 × segsX × segsZ`

**Tapered Cylinder.** Different top and bottom radius.

- `radius(t) = lerp(topRadius, bottomRadius, t)`
- Normal tilt by taper angle:
  `nY = (bottomRadius - topRadius) / slant` where
  `slant = √(h² + (bottomRadius - topRadius)²)`
- Normal does not vary with height (ruled surface)
- Degenerates to cone when `topRadius = 0`, to cylinder when
  `topRadius = bottomRadius`

**Index generation pattern** (shared across all parametric shapes): for each
quad at grid position `(i, j)`:

```
a = i × (slices + 1) + j
b = a + 1
c = (i + 1) × (slices + 1) + j
d = c + 1

Triangle 1 (CCW from outside): a, c, b
Triangle 2 (CCW from outside): b, c, d
```

### Phase 3 — Curves

#### GBMesh.Curve

Parametric curves for profiles, paths, and surface construction.

**Bezier curves.**

- De Casteljau evaluation (numerically stable — only linear interpolation,
  intermediate values stay within convex hull):

  ```
  P_i^[0] = P_i
  P_i^[r] = (1 - t) × P_i^[r-1] + t × P_{i+1}^[r-1]
  C(t) = P_0^[n]
  ```

- Arbitrary degree support (quadratic and cubic as special cases)
- Curve splitting at parameter t: left subcurve = left edge of De Casteljau
  tableau, right subcurve = right edge
- Derivative via hodograph: `C'(t)` is a degree-(n-1) Bezier with control
  points `Q_i = n × (P_{i+1} - P_i)`
- Properties: endpoint interpolation, convex hull containment, variation
  diminishing

**B-spline curves.**

- De Boor's algorithm for evaluation (B-spline analogue of De Casteljau):
  1. Find knot span index k via binary search
  2. Operate on the p+1 relevant control points (local support)
  3. Iterative alpha-blending to a single point

- Cox-de Boor recursion for basis functions:

  ```
  N_{i,0}(u) = 1 if u_i ≤ u < u_{i+1}, else 0
  N_{i,p}(u) = [(u - u_i) / (u_{i+p} - u_i)] × N_{i,p-1}(u)
             + [(u_{i+p+1} - u) / (u_{i+p+1} - u_{i+1})] × N_{i+1,p-1}(u)
  ```

- 0/0 convention: when a knot span has zero length, the fraction is defined
  as 0

- Knot vector types:
  - Clamped/open: first and last knots repeated p+1 times (curve interpolates
    endpoints) — the standard for design
  - Uniform: equally spaced (curve does not interpolate endpoints)
  - Non-uniform: arbitrary spacing (used by NURBS)

- Local control: changing P_i only affects `[u_i, u_{i+p+1})`
- Derivative: degree-(p-1) B-spline with control points
  `Q_i = p × (P_{i+1} - P_i) / (u_{i+p+1} - u_{i+1})`

**NURBS curves.**

- Projective space trick (implementation strategy):
  1. Lift control points to weighted 4D:
     `P_i^w = (w_i × x_i, w_i × y_i, w_i × z_i, w_i)`
  2. Evaluate standard B-spline in 4D using De Boor:
     `Q(u) = (X, Y, Z, W)`
  3. Project back: `C(u) = (X/W, Y/W, Z/W)`

- Reuses entire B-spline machinery unchanged — only adds lift and project
- Can represent conic sections exactly (circles, ellipses) because rational
  functions of the parameter can express cos/sin via Weierstrass substitution
- Derivative uses quotient rule:
  `C'(u) = (A'(u) - C(u) × w'(u)) / w(u)`
- Weights must be positive; large weight ratios cause numerical issues

**Arc-length parameterization.**

- Problem: parameter t ≠ distance along curve (uniform t-sampling gives
  non-uniform spacing)
- Arc length integral: `s(a, b) = ∫|C'(t)| dt`
- Numerical integration: Gaussian quadrature (5-point per knot span is
  typically sufficient)
- Inverse mapping (the important direction — given arc length s, find t):
  1. Build lookup table: N uniformly-spaced parameter samples with cumulative
     arc lengths
  2. Binary search to find the interval containing target s
  3. Linear interpolation within the interval
  4. Optional Newton-Raphson refinement:
     `t_new = t - (s(0, t) - s) / |C'(t)|`
- Table size: 100–1000 entries typical
- Incremental sampling: for M uniform samples, walk the table incrementally
  — O(M + N) instead of O(M log N)

### Phase 4 — Surfaces & Lofting

#### GBMesh.Surface

Parametric surfaces via tensor product construction.

**Bezier patches.**

- Tensor product of two univariate Bezier bases:
  `S(u, v) = ΣΣ B_{i,m}(u) × B_{j,n}(v) × P_{i,j}`
- Evaluation via nested De Casteljau: apply De Casteljau in u across each
  row, then in v across the results
- Bicubic patch (degree 3×3, 4×4 = 16 control points) is the standard
  workhorse
- Normals from partial derivatives: `N = dS/du × dS/dv`
- `dS/du` is itself a Bezier patch of degree (m-1, n) with control points
  `m × (P_{i+1,j} - P_{i,j})`
- Tessellation: uniform sampling in (u, v) parameter space, connect into
  quads, split into triangles

**B-spline surfaces.**

- Tensor product of B-spline bases in u and v
- Evaluation via nested De Boor: find knot spans in both directions,
  evaluate inner direction first for each relevant row, then outer direction
- Only (p+1) × (q+1) control points contribute to any point (local support)
- Relationship to Bezier patches: knot insertion decomposes B-spline surface
  into a grid of Bezier patches — standard approach for tessellation

**NURBS surfaces.**

- Same projective space trick as NURBS curves, extended to surfaces
- Lift control points to weighted 4D, evaluate standard B-spline surface
  in 4D, project back to 3D
- Derivatives via quotient rule on the 4D evaluation

#### GBMesh.Loft

Surface generation from profiles.

**Revolve (lathe).**

- Rotate a 2D profile curve around an axis:
  `S(t, θ) = A + z(t) × a + r(t) × (cos θ × e1 + sin θ × e2)`
  where A is a point on the axis, a is the axis direction, e1/e2 are
  perpendicular basis vectors
- Analytical normals from partial derivatives:
  `N = r(t) × [z'(t) × (cos θ × e1 + sin θ × e2) - r'(t) × a]`
- Pole handling when profile touches axis (r = 0): generate triangle fan,
  pole normal = axis direction
- Partial revolution supported (not full 2π) — open edges may need caps

**Loft.**

- Interpolate between K cross-section profiles along a spine
- Linear interpolation between consecutive pairs (ruled surface) for
  simplest case
- B-spline interpolation in v-direction for smoother results
- All profiles must have same parameterization — resample to match via
  arc-length parameterization if needed
- Profile orientation: all profiles must be traversed in the same direction
  (all CCW when viewed from spine direction)
- Normals: `N = dS/dt × dS/dv` from profile and spine derivatives

**Extrude.**

- Push 2D profile along a direction vector:
  `S(t, v) = C(t) + v × d`
- Normal: `N = C'(t) × d` (constant along extrusion direction)
- Cap generation via ear-clipping triangulation of the profile polygon
- Bottom cap winding matches inward normal, top cap reversed

**Sweep.**

- Move profile along a 3D spine curve, oriented by a frame at each point
- **Bishop frame** (rotation-minimizing), NOT Frenet:
  - Frenet fails at inflection points (curvature = 0, normal undefined)
    and on straight segments
  - Bishop frame has no torsion component — the frame changes as little as
    possible around the tangent axis
- Double-reflection algorithm (Bloomenthal 1990) for frame propagation:
  1. Reflect previous U and T across plane perpendicular to chord vector
  2. Reflect again across plane perpendicular to tangent difference
  3. O(1) per step, no trigonometry, numerically stable
- Initial frame: choose U₀ perpendicular to T₀ via cross product with
  a reference axis
- Closed curves: measure accumulated twist after one traversal, distribute
  compensating twist uniformly
- Self-intersection warning: if profile radius exceeds spine's radius of
  curvature, the swept surface self-intersects on the inside of the bend

### Phase 5 — Implicit Geometry

#### GBMesh.SDF

Signed distance field primitives and combinators.

**Primitive SDFs.** Exact distance functions:

- Sphere: `f(p) = ‖p‖ - r`
- Box (sharp edges):
  `q = (|px| - bx, |py| - by, |pz| - bz)`
  `f(p) = ‖max(q, 0)‖ + min(max(qx, qy, qz), 0)`
- Cylinder (capped):
  `d = (√(px² + pz²) - r, |py| - h/2)`
  `f(p) = ‖max(d, 0)‖ + min(max(dx, dy), 0)`
- Torus: `f(p) = ‖(√(px² + pz²) - R, py)‖ - r`
- Capsule: `f(p) = ‖p - clampedProjection‖ - r`
- Cone: height-dependent radius check
- Plane: `f(p) = dot(p, n) - d`

**CSG Boolean operations:**

- Union: `min(a, b)`
- Intersection: `max(a, b)`
- Difference: `max(a, -b)`

**Smooth blending** (polynomial smooth min with blend radius k):

```
smoothUnion(a, b, k):
  h = clamp(0.5 + 0.5 × (b - a) / k, 0, 1)
  return lerp(b, a, h) - k × h × (1 - h)
```

Smooth intersection and difference follow the same pattern.

**Domain operations:**

- Repetition: `mod(p, period) - period / 2`
- Twist: rotate XZ cross-section by angle proportional to Y
- Bend: remap through cylindrical coordinate rotation
- Taper: scale cross-section as function of axial position
- Elongation: clamp coordinates to extend a shape

**SDF normals:** gradient via central differences:

```
n = normalize(
  f(p + (ε,0,0)) - f(p - (ε,0,0)),
  f(p + (0,ε,0)) - f(p - (0,ε,0)),
  f(p + (0,0,ε)) - f(p - (0,0,ε))
)
```

Typical ε = 0.001. Requires 6 extra SDF evaluations per normal. Analytical
gradients available for primitive SDFs but not for composed SDFs in general.

#### GBMesh.Isosurface

Implicit surface to mesh conversion.

**Marching Cubes.**

- Sample SDF on a regular 3D grid
- For each cube (8 corner samples), classify corners as inside (< 0) or
  outside (≥ 0) — gives an 8-bit index into a 256-entry lookup table
- 256 configurations reduce to 15 unique cases via rotation and reflection
  symmetry
- Lookup table maps each configuration to a list of triangles (edges to
  interpolate)
- Edge interpolation: place vertex on the edge where the SDF crosses zero,
  using linear interpolation between corner values:
  `v = p_a + (p_b - p_a) × (0 - f(p_a)) / (f(p_b) - f(p_a))`
- Ambiguous cases (cases 3, 6, 7, 10, 12, 13): faces where the sign pattern
  is ambiguous — resolve consistently (face diagonal test or asymptotic
  decider)
- Normals: compute SDF gradient at each interpolated vertex position

**Dual Contouring.**

- Vertices placed inside cells (not on edges like marching cubes)
- Hermite data: for each edge that crosses the surface, store the
  intersection point and surface normal
- QEF minimization: find the point inside each cell that minimizes the sum
  of squared distances to the tangent planes defined by the Hermite data:
  `minimize Σ (dot(n_i, x - p_i))²`
  This is a linear least-squares problem: `A^T A x = A^T b` where each row
  of A is a normal vector and b contains `dot(n_i, p_i)`
- Solution via SVD or pseudoinverse (SVD is more robust for
  near-degenerate cases)
- Sharp feature preservation: because the vertex position is the
  least-squares fit to the tangent planes, sharp edges and corners are
  naturally preserved (the tangent planes from different faces intersect at
  the edge/corner)
- Connect vertices of adjacent cells that share a sign-change edge

### Phase 6 — Mesh Modification

#### GBMesh.Subdivision

Subdivision surfaces.

**Catmull-Clark subdivision.**

- Produces quads from any input mesh topology
- Rules per subdivision step:
  - Face point: centroid of face vertices
  - Edge point: average of (edge midpoint, adjacent face points)
  - Vertex point: `(Q + 2R + (n-3)V) / n` where Q = average of adjacent
    face points, R = average of adjacent edge midpoints, V = original
    vertex, n = valence
- Converges to a limit surface (C2 everywhere except C1 at extraordinary
  vertices where valence ≠ 4)
- Boundary handling: boundary edges use the curve subdivision rule
  (midpoint averaging)
- Semi-sharp creases (Pixar's rules): crease sharpness value per edge,
  interpolate between smooth subdivision rule and sharp (linear) rule,
  sharpness decrements by 1 per subdivision level

**Loop subdivision.**

- Triangle meshes only (requires triangle input)
- Edge point: `3/8 × (v_a + v_b) + 1/8 × (v_c + v_d)` where v_a, v_b are
  edge endpoints, v_c, v_d are opposite vertices
- Vertex point: `(1 - n × β) × V + β × Σ(neighbors)` where n = valence,
  β = `1/n × (5/8 - (3/8 + 1/4 × cos(2π/n))²)` (Loop's weights)
- Each triangle becomes 4 triangles per subdivision level
- Boundary handling: boundary edges subdivide by midpoint, boundary vertices
  use 1/8, 3/4, 1/8 weights

#### GBMesh.Deform

Mesh deformation operators. All are `Mesh -> Mesh` transformations.

**Twist.** Rotate each vertex around an axis by angle proportional to its
position along that axis:

```
angle = twistRate × dot(position, axis)
position' = rotateAround(axis, angle, position)
normal' = rotateAround(axis, angle, normal)
```

**Bend.** Remap coordinates through cylindrical coordinate rotation. The
standard formulation bends geometry around a specified axis by converting to
cylindrical coordinates, applying an angular offset proportional to the axial
coordinate, and converting back.

**Taper.** Scale cross-section as a function of position along an axis:

```
scale = taperFunction(dot(position, axis))
position' = axialComponent + scale × radialComponent
```

Linear taper: `taperFunction(t) = lerp(1.0, endScale, t)`.

**Free-Form Deformation (FFD).** Sederberg & Parry's formulation:

1. Embed mesh in a parallelepiped lattice with (l+1) × (m+1) × (n+1)
   control points
2. For each vertex, compute its (s, t, u) coordinates in the lattice's
   local space
3. Evaluate trivariate Bernstein polynomial:
   `X(s,t,u) = ΣΣΣ B_{i,l}(s) × B_{j,m}(t) × B_{k,n}(u) × P_{i,j,k}`
4. Deformation = displacing lattice control points from their rest positions

Moving a single lattice point smoothly deforms all vertices in its influence
region. Low lattice resolution (3×3×3 or 4×4×4) for broad deformation, higher
for local control.

**Displacement.** Offset each vertex along its normal by a scalar function:

```
position' = position + displacementFunction(position) × normal
```

The displacement function is typically noise (Perlin, simplex, FBM) or any
`V3 Float -> Float` function. Normals should be recomputed after displacement
for accurate lighting — either analytically (using noise derivatives) or
numerically (from displaced triangle geometry).

Tessellation level must be high enough to capture the displacement detail —
displacement cannot add detail beyond the mesh resolution.

#### GBMesh.Noise

Pure noise functions for displacement, detail, and procedural textures.

**Improved Perlin noise (2002).**

- Seed-derived permutation table: 256-entry permutation generated via
  Fisher-Yates shuffle driven by splitmix PRNG, doubled to 512 for
  wrapping
- C2 fade curve: `fade(t) = 6t⁵ - 15t⁴ + 10t³`
  (the unique degree-5 polynomial with f(0)=0, f(1)=1, f'(0)=f'(1)=0,
  f''(0)=f''(1)=0 — C2 continuity eliminates visible creases at lattice
  boundaries in displacement)
- 12-edge gradient vectors: midpoints of cube edges
  `{(±1,±1,0), (±1,0,±1), (0,±1,±1)}`
  — breaks axis symmetry, each has one zero component (fast dot product)
- Algorithm (3D): floor to unit cube, fractional position, hash 8 corners
  via permutation table, gradient dot products at each corner, trilinear
  interpolation using faded fractional coordinates
- 2D and 3D variants
- Output range: approximately [-1, 1]
- Analytical derivatives computed alongside value: `d(noise)/dp` uses the
  chain rule through the fade curve and gradient dot products — 30-50%
  overhead vs 300% for finite differences, and exactly smooth

**Simplex noise.**

- Patent expired January 8, 2022 — freely available
- Skew/unskew transforms:
  - Skew factor: `F_N = (√(N+1) - 1) / N`
  - Unskew factor: `G_N = (1 - 1/√(N+1)) / N`
  - 2D: F₂ ≈ 0.366, G₂ ≈ 0.211
  - 3D: F₃ = 1/3, G₃ = 1/6
  - 4D: F₄ ≈ 0.309, G₄ ≈ 0.138
- Simplex traversal: determine which simplex the point is in by sorting
  offset coordinates (2D: 2 simplices per square, 3D: 6 per cube,
  4D: 24 per hypercube)
- Radial kernel instead of interpolation:
  `n_k = max(0, r² - |d_k|²)⁴ × dot(g_k, d_k)`
  (r² = 0.5 for 2D, 0.6 for 3D)
- Fewer evaluations than Perlin: N+1 gradient contributions instead of 2^N
  (4 vs 8 in 3D, 5 vs 16 in 4D)
- Better isotropy, no axis-aligned artifacts
- 2D, 3D, and 4D variants (4D useful for animated noise)
- Analytical derivatives:
  `d(n_k)/dp = -8 × t_k³ × dot(g_k, d_k) × d_k + t_k⁴ × g_k`

**Worley noise (cellular/Voronoi).**

- Feature points: one per integer-coordinate cell at deterministic random
  offset (jittered grid)
- F1 (nearest), F2 (second nearest), F2-F1 (cell borders)
- Distance metrics: Euclidean, Manhattan, Chebyshev, general Minkowski
  - Euclidean: organic rounded cells
  - Manhattan: diamond-shaped crystalline cells
  - Chebyshev: square/cubic cells
- Neighbor search: 3×3×3 = 27 cells in 3D (guaranteed sufficient for
  jittered grid with jitter ≤ 1)
- Hash function for feature point positions: integer hash from cell
  coordinates + seed, mapped to [0, 1)
- Visual character:
  - F1: soap bubbles, river stones
  - F2-F1: cracked mud, flagstone, reptile scales, stone walls

**Fractal Brownian Motion (FBM).**

- Octave layering at increasing frequencies and decreasing amplitudes:
  `fbm(p) = Σ persistence^i × noise(lacunarity^i × p)`
- Parameters:
  - Octaves: 4–8 typical (each doubles computation)
  - Lacunarity: frequency multiplier (standard: 2.0)
  - Persistence/gain: amplitude multiplier (standard: 0.5)
- Amplitude normalization: divide by geometric series sum
  `(1 - persistence^octaves) / (1 - persistence)`
- Derivative: `d(fbm)/dp = Σ amplitude_i × frequency_i × d(noise)/dp`
  (extra frequency factor from chain rule — higher octaves dominate the
  derivative)
- Visual character: terrain, clouds, rolling hills

**Ridged multifractal.**

- Base: `signal = offset - abs(noise(p))` then `signal = signal²` (squaring
  sharpens ridges, makes valleys smoother)
- Octave weighting: each octave's contribution weighted by previous octave's
  output — concentrates detail on ridges, suppresses it in valleys
- Parameters: offset (typically 1.0), gain (typically 2.0)
- Visual character: mountain ridges, canyon networks, veins, craggy terrain

**Turbulence.**

- FBM with absolute value per octave:
  `turbulence(p) = Σ amplitude_i × |noise(frequency_i × p)|`
- Always positive (unlike FBM which spans [-1, 1])
- Visual character: billowy clouds, fire, smoke, marble veining (via
  `sin(x + turbulence(p))`)

**Domain warping.**

- Use noise to distort input coordinates of another noise function:
  `f(p) = noise(p + amplitude × V(p))` where V(p) is a vector of
  decorrelated noise values
- Decorrelation offsets: use arbitrary constant offsets (e.g., 5.2, 1.3) to
  prevent correlation between displacement channels
- Nested warping for more complex distortion:
  `f(p) = fbm(p + a₁ × fbm(p + a₂ × fbm(p + offset)))`
- Visual character: geological strata, flowing lava, Jupiter's cloud bands

**Seeding and reproducibility.**

- Splitmix PRNG: ~15 lines of pure Haskell using Data.Bits and Data.Word
  - State update: `state' = state + 0x9E3779B97F4A7C15`
  - Mix function: three rounds of xor-shift + multiply
  - 64-bit output, excellent distribution, purely functional
- Generate permutation table from seed via Fisher-Yates shuffle driven by
  splitmix (using ST monad — pure, not IO)
- All noise functions take a `NoiseConfig` containing the immutable
  permutation table — no IO, no mutable state

**Surface normals from noise displacement.**

For a heightmap `h(x, z)` displaced surface:

```
normal = normalize(-dh/dx, 1, -dh/dz)
```

Using analytical noise derivatives gives smooth, exact normals without finite
differencing. This is a key advantage of procedural mesh generation over
post-hoc displacement.

### Phase 7 — Application

#### GBMesh.Humanoid

Parametric character generation.

- `HumanoidSpec` — body proportions (head ratio, shoulder width, hip width,
  limb lengths, joint radii)
- `BodyType` — contour profiles per body type (different Bezier profiles for
  torso shape: shoulder → chest → waist → hip)
- Pipeline: proportions → joint positions → skeleton → body mesh
  - Torso: revolve/loft Bezier body contours around skeleton axis
  - Limbs: tapered cylinders between joint positions, optional twist
    deformation for forearm
  - Head: sphere, optionally subdivided
  - Joints: capsules/spheres at joint positions for smooth connections
  - Assembly: merge all parts via Combine
- Direct translation of the 2D Paradise character system:
  - `BodyContour` Bezier curves → loft/revolve profiles
  - `widthAtY` → radial profile function (height → cross-section radius)
  - Tapered limb lines → tapered cylinders
  - `HumanoidSpec` head-ratio proportions → same, drives joint positions
    and mesh radii
  - `BodyType` contour differences → different loft profiles

#### GBMesh.Equipment

Bone-attached procedural gear.

- Parametric armor, weapons, shields from parametric descriptions
- Attach points on skeleton joints (bone-parented meshes)
- Scale and orient to match character proportions
- Hard-surface details via SDF boolean operations (armor plates via
  difference, beveled edges via smooth intersection)
- Assembly: each equipment piece is a separate Mesh, positioned relative
  to the attach joint

---

## Testing Strategy

### Property-Based Tests (Primary)

Invariants verified across randomized parameter ranges via QuickCheck or
Hedgehog:

**Structural invariants (all meshes):**
- All indices < vertex count (no out-of-bounds)
- Index count divisible by 3
- Vertex count > 0, index count > 0

**Geometric invariants (well-formed meshes):**
- All normals approximately unit length: `|‖n‖ - 1| < ε`
- All tangent xyz approximately unit length
- Tangent w is exactly +1 or -1
- No degenerate triangles (cross product of edges has non-zero length)

**Topological invariants (closed surfaces):**
- Watertightness: every edge shared by exactly 2 triangles
- Euler characteristic: V - E + F = 2 for genus-0 closed surfaces

**Generator-specific invariants:**
- Vertex count matches formula for given tessellation parameters
- Triangle count matches formula
- Bounding box matches expected dimensions
- Centroid approximately at origin for centered shapes

**Combination invariants:**
- Merged vertex count = sum of parts
- Merged index count = sum of parts
- Vertex data preserved (first |A| vertices of merge equal A's vertices)
- Monoid laws: associativity, identity

### Golden Tests (Thin Regression Layer)

- Simplest case of each generator (unit cube, unit sphere at low
  tessellation)
- Hash of vertex data rather than full vertex list (reduces brittleness)
- Catches unintended changes to UV mapping, normal direction, winding order

---

## Algorithm Choices

| Decision | Choice | Rationale |
|---|---|---|
| Bezier evaluation | De Casteljau | Numerically stable, splitting for free |
| B-spline evaluation | De Boor's algorithm | O(p²), local support, standard |
| NURBS evaluation | Projective space trick | Reuses B-spline machinery unchanged |
| Sweep frame | Bishop (double-reflection) | Frenet fails at inflection points and straight segments |
| SDF normals | Central differences | Composed SDFs lack closed-form gradients |
| Isosurface (v1) | Marching cubes | Straightforward, well-understood |
| Isosurface (v2) | Dual contouring | Sharp features, layers in after MC |
| Subdivision primary | Catmull-Clark | Handles any topology, quad output, crease support |
| Noise PRNG | Splitmix | ~15 lines pure Haskell, base-only, excellent quality |
| Perlin fade curve | 6t⁵ - 15t⁴ + 10t³ | C2 continuity (no displacement creases) |
| Index topology | Triangle list | Universal, modern GPUs prefer it, simplest |

---

## Not in v1

- Adaptive tessellation (octree marching cubes, T-junction crack patching)
- Poisson disk feature points for Worley
- Multi-resolution subdivision
- glTF export (gb-engine's concern)
- Animation data / bone weights (gb-engine's concern)
- Vertex colors (can be added to Vertex later if needed)
