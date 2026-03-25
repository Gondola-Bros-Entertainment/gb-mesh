<div align="center">
<h1>gb-mesh</h1>
<p><strong>Procedural 3D Mesh Generation</strong></p>
<p>Pure Haskell — no GPU, no asset pipeline, no IO. Just math.</p>
<p><a href="#modules">Modules</a> · <a href="#design">Design</a> · <a href="#building">Building</a></p>
<p>

[![CI](https://github.com/Gondola-Bros-Entertainment/gb-mesh/actions/workflows/ci.yml/badge.svg)](https://github.com/Gondola-Bros-Entertainment/gb-mesh/actions/workflows/ci.yml)
[![Hackage](https://img.shields.io/hackage/v/gb-mesh.svg)](https://hackage.haskell.org/package/gb-mesh)
![Haskell](https://img.shields.io/badge/haskell-GHC%209.8-purple)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)

</p>
</div>

---

Pure functions that produce 3D geometry from parametric descriptions. 33 modules covering primitives, curves, surfaces, SDFs, noise, terrain, subdivision, deformation, skeletal animation, inverse kinematics, skinning, morph targets, and import/export. The 3D equivalent of [gb-sprite](https://hackage.haskell.org/package/gb-sprite).

## Modules

### Geometry Generation

| Module | Purpose |
|--------|---------|
| `GBMesh.Primitives` | Sphere, capsule, cylinder, cone, torus, box, plane, tapered cylinder |
| `GBMesh.Curve` | Bezier, B-spline, NURBS curves with arc-length parameterization |
| `GBMesh.Surface` | Bezier patches, B-spline surfaces, NURBS surfaces |
| `GBMesh.Loft` | Revolve, loft, extrude, sweep (with Bishop frames) |
| `GBMesh.Isosurface` | Marching cubes with SDF grid caching |
| `GBMesh.DualContour` | Dual contouring with QEF solving for sharp features |
| `GBMesh.Hull` | Incremental 3D convex hull |
| `GBMesh.Icosphere` | Geodesic sphere from icosahedron subdivision |
| `GBMesh.Terrain` | Heightmap terrain with thermal/hydraulic erosion |

### Procedural Tools

| Module | Purpose |
|--------|---------|
| `GBMesh.SDF` | Signed distance fields, CSG booleans, smooth blending, domain warps |
| `GBMesh.Noise` | Perlin 2D/3D, simplex 2D/3D/4D, Worley 2D/3D, FBM, ridged, turbulence |
| `GBMesh.Boolean` | Mesh-level CSG union, intersection, difference |
| `GBMesh.Scatter` | Uniform, Poisson disk, and weighted point scattering |
| `GBMesh.UV` | Planar, cylindrical, spherical, box UV projection |

### Mesh Processing

| Module | Purpose |
|--------|---------|
| `GBMesh.Combine` | Translate, rotate, scale, merge, recompute normals/tangents |
| `GBMesh.Deform` | Twist, bend, taper, free-form deformation (FFD), displacement |
| `GBMesh.Subdivision` | Catmull-Clark (quads), Loop (triangles) |
| `GBMesh.Smooth` | Laplacian smoothing, Taubin volume-preserving smoothing |
| `GBMesh.Simplify` | Quadric error metric decimation with priority queue |
| `GBMesh.Weld` | Spatial-hash vertex welding, degenerate triangle removal |
| `GBMesh.Symmetry` | Mirror (X/Y/Z/arbitrary plane), radial symmetry |
| `GBMesh.LOD` | Level-of-detail chain generation with screen-size selection |
| `GBMesh.Remesh` | Isotropic remeshing (edge split/collapse/flip/relax) |
| `GBMesh.Raycast` | Ray-triangle intersection, BVH-accelerated mesh raycasting |

### Rigging and Animation

| Module | Purpose |
|--------|---------|
| `GBMesh.Skeleton` | Generic joint trees with humanoid/quadruped builders |
| `GBMesh.Pose` | Forward kinematics, pose interpolation, additive composition |
| `GBMesh.Animate` | Procedural oscillators, keyframe animation, easing functions |
| `GBMesh.IK` | CCD and FABRIK solvers with joint constraints (hinge, cone) |
| `GBMesh.Skin` | Linear blend skinning, dual quaternion skinning, automatic weights |
| `GBMesh.Morph` | Mesh morphing, blend shapes |

### Foundation and Export

| Module | Purpose |
|--------|---------|
| `GBMesh.Types` | Core types (`V2`, `V3`, `V4`, `Quaternion`, `Vertex`, `Mesh`), shared helpers |
| `GBMesh.Export` | Wavefront OBJ (text), glTF 2.0 (embedded base64) |
| `GBMesh.Import` | Wavefront OBJ and glTF 2.0 parsing (single and multi-mesh) |

## Design

- **Pure.** All generators are `params -> Mesh`. No IO, no GPU, no state.
- **Minimal deps.** `base` + `containers` + `array`. Nothing else.
- **Parametric.** Every shape is controlled by explicit parameters.
- **Composable.** Chain primitives, deformations, SDFs, and animations freely.
- **Style-agnostic.** Low-poly, high-poly, stylized, realistic — tessellation is a parameter.

## Part of the GB Ecosystem

```
gb-vector    math foundations
gb-sprite    2D procedural generation (sprites, noise, filters)
gb-synth     audio procedural generation (waveforms, instruments)
gb-mesh      3D procedural generation (meshes, surfaces, characters)  <- this
```

## Building

```bash
cabal build all --ghc-options="-Werror"
cabal test
```

## Stats

33 modules | 255 tests | GHC 9.8.4

---

<div align="center">

Gondola Bros Entertainment

</div>
