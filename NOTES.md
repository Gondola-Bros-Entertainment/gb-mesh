# gb-mesh — Design Notes

## Thesis

The mathematical foundations of AI-driven content generation — noise fields, basis functions, signed distance fields, spectral methods, interpolation in continuous spaces — are the same foundations procedural generation has used for decades. Diffusion models don't invent new math. They learn parameters for existing math by optimizing over data.

gb-mesh uses that same mathematical toolkit directly. Instead of learning parameters from training data (stochastic, GPU-heavy, opaque), we specify parameters explicitly (deterministic, real-time, composable, type-safe). Same engine, different steering wheel.

This isn't a limitation — it's a deliberate trade:

- **Determinism** — same input, same output, always
- **Real-time performance** — no inference cost, just math
- **Composability** — functions compose, operations chain, meshes merge
- **Type safety** — the compiler catches errors before runtime
- **No training data** — no dataset curation, no bias, no licensing
- **Introspection** — you can read the code and understand exactly what it does

## The Shared Mathematical Core

| Domain | AI / Neural | Procedural / gb-mesh |
|--------|-------------|----------------------|
| Noise | Gaussian noise schedules (diffusion) | Perlin, simplex, Worley, FBM |
| Basis functions | Learned conv filters, attention heads | B-spline basis, spherical harmonics |
| Interpolation | Latent space traversal | Lofting, morphing, parameter blending |
| Implicit surfaces | NeRFs, neural SDFs | Analytical SDFs, CSG combinators |
| Spectral methods | Positional encoding (Fourier features) | Fourier synthesis, spectral analysis |
| Gradient fields | Backpropagation | Surface normals (gradient of implicit fn) |
| Deformation | Learned warping fields | FFD, twist, bend, taper, displacement |

The math is identical. The control mechanism differs.

## Why

Paradise was a 2.5D isometric MMO. The client had a fully procedural character system built on gb-sprite — 16-joint humanoid skeletons, Bezier body contours, 8-directional facing projection with ellipse cross-section math, procedural pose generators (sine-based walk/idle/attack/cast), delta-based keyframe animation, depth-sorted layered rendering, joint-attached equipment with per-material shading. All pure Haskell, all procedural — no pre-rendered sprites.

We're pivoting Paradise to full 3D via gb-engine (our Vulkan renderer). gb-engine handles the GPU side — pipelines, PBR shading, skeletal animation playback, terrain, scene management. But it doesn't generate geometry. It loads meshes from glTF files or uses hardcoded builtins (cube, quad).

gb-mesh fills the gap: procedural 3D mesh generation. The same role gb-sprite plays for 2D — pure functions that produce geometry from parametric descriptions. No Blender, no asset pipeline, just code. But unlike a style-locked generator, gb-mesh is not limited to a single fidelity level. The mathematical toolkit scales from 500-triangle low-poly characters to arbitrarily detailed geometry.

## The GB Ecosystem

```
gb-vector    SVG generation, vector math
gb-sprite    2D procedural generation (sprites, noise, filters, isometric)
gb-synth     audio procedural generation (waveforms, instruments, SFX)
gb-mesh      3D procedural generation (meshes, surfaces, characters)  <-- this
gb-engine    Vulkan rendering engine (consumes all of the above)
```

All published or to-be-published on Hackage. BSD-3-Clause. Minimal dependencies.

## Paradise 2D → 3D Translation

The 2D character system in Paradise (client/Skeleton.hs, ~1200 lines) already solves the hard design problems. gb-mesh translates those solutions to 3D:

| Paradise 2D | gb-mesh 3D |
|-------------|------------|
| `BodyContour` — cubic Bezier curves (shoulder→chest→waist→hip) | Loft/lathe — revolve the Bezier profile around the skeleton axis |
| `widthAtY` — linear interpolation between 4 stations | Radial profile function — height → cross-section radius |
| `ellipseWidth` — perspective-correct width at facing angle | Handled by actual 3D camera/projection |
| `drawEllipse` at joint positions | Generate capsule/sphere mesh at joints |
| Tapered limb lines between joints | Tapered cylinders between joints |
| `HumanoidSpec` — head-ratio proportions system | Same — drives joint positions and mesh radii |
| `BodyType` Male/Female contour differences | Different loft profiles per body type |
| `BodyProportions` — pixel-derived render values | World-space proportions (meters) |
| `projectPose` — 8-directional facing projection | Not needed — real 3D handles all angles |
| Delta-based keyframes (`JointDelta`) | Already in gb-engine (`BonePose`, `AnimationClip`) |
| `fromProcedural` — sine waves → animation clip | Same — construct `AnimationClip` from parametric functions |
| `AttachedVisual` — joint-attached equipment with depth | Bone-parented equipment meshes |
| `ShadedDraw` — per-material shading (skin, metal, cloth) | PBR materials in gb-engine |
| Per-class noise textures (FBM, simplex) | Procedural textures → Vulkan upload |

## Planned Modules

### Core

**GBMesh.Types** — Core data types shared across all modules. `Vertex` (position, normal, UV, tangent), `Mesh` (vertex list + index list), mesh combination with index offset arithmetic.

**GBMesh.Combine** — Mesh merging and transformation. Merge multiple meshes with correct index offsets. Transform vertices (translate, rotate, scale). Flip normals, reverse winding.

### Primitives

**GBMesh.Primitives** — Parametric shapes with analytical normals and UVs. Sphere, capsule, cylinder, cone, taper, torus, box, plane. Every shape takes segment/ring parameters for tessellation control.

### Curves & Surfaces

**GBMesh.Curve** — Parametric curves. Bezier (quadratic, cubic, arbitrary degree), B-spline, NURBS. Evaluation, splitting, arc-length parameterization.

**GBMesh.Surface** — Parametric surfaces. Bezier patches, B-spline surfaces, NURBS surfaces. Surface evaluation, normals from partial derivatives.

**GBMesh.Loft** — Surface generation from profiles. Revolve (lathe), loft (interpolate between cross-sections along a spine), extrude (push a shape along a direction), sweep (move a profile along a curve).

### Implicit & Constructive

**GBMesh.SDF** — Signed distance field primitives and combinators. Primitive SDFs (sphere, box, cylinder, torus, capsule). Boolean operations (union, intersection, difference). Smooth blending. Domain operations (repetition, twist, bend).

**GBMesh.Isosurface** — Implicit surface to mesh conversion. Marching cubes, dual contouring (sharp feature preservation), adaptive resolution.

### Modification

**GBMesh.Subdivision** — Subdivision surfaces. Catmull-Clark (quads), Loop (triangles). Arbitrary subdivision levels — the bridge from low-poly to smooth.

**GBMesh.Deform** — Mesh deformation. Twist, bend, taper along an axis. Free-form deformation (FFD lattice). Displacement from noise or arbitrary function.

**GBMesh.Noise** — Noise functions for displacement, detail, and procedural textures. Perlin (2D, 3D), simplex (2D, 3D, 4D), Worley/cellular. FBM composition. Ridged, turbulent, billowed variants.

### Application

**GBMesh.Humanoid** — Full procedural character generation. `HumanoidSpec` (body proportions), `BodyType` (contour profiles), `CharacterClass` (class-specific adjustments). Proportions → joint positions → skeleton → full body mesh.

**GBMesh.Equipment** — Bone-attached procedural gear. Armor, weapons, shields from parametric descriptions. Attach points on skeleton joints. Scale and orient to match character proportions.

## Design Principles

1. **Pure functions only.** Every generator is `params -> Mesh`. No IO, no GPU, no state.
2. **Minimal dependencies.** `base` + `linear`. Nothing else.
3. **Parametric everything.** Named parameters, not magic numbers. Every shape is a function call.
4. **Composable.** All operations compose. Combine meshes, chain deformations, nest SDFs.
5. **Fidelity-agnostic.** The same math works at 500 triangles or 50,000. Tessellation is a parameter, not a constraint.
6. **Mathematically grounded.** Analytical normals over numerical approximation. Exact evaluation over sampling. Use the right mathematical tool for each problem.

## The Vision

The GB ecosystem + deterministic math = procedural content generation that rivals AI output without AI costs. gb-sprite proved it for 2D — Defenders is fully procedural. gb-mesh extends it to 3D. The same mathematical foundations, applied directly. The libraries are the tools, the games are the product.
