<div align="center">

# gb-mesh

**Procedural 3D mesh generation in Haskell**

[![Haskell](https://img.shields.io/badge/Haskell-GHC%209.8.4-5e5086)](https://www.haskell.org)
[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue)](LICENSE)

</div>

---

Pure functions that produce 3D geometry from parametric descriptions. Primitives, curves, surfaces, signed distance fields, subdivision, deformation — the full mathematical toolkit for procedural mesh generation. The 3D equivalent of [gb-sprite](https://hackage.haskell.org/package/gb-sprite).

## Modules

| Module | Purpose |
|--------|---------|
| `GBMesh.Types` | Core types — `Vertex`, `Mesh`, index arithmetic |
| `GBMesh.Primitives` | Sphere, capsule, cylinder, cone, torus, box |
| `GBMesh.Curve` | Bezier, B-spline, NURBS curves |
| `GBMesh.Surface` | Bezier patches, B-spline, NURBS surfaces |
| `GBMesh.Loft` | Revolve, loft, extrude, sweep |
| `GBMesh.SDF` | Signed distance fields + CSG combinators |
| `GBMesh.Isosurface` | Marching cubes, dual contouring |
| `GBMesh.Subdivision` | Catmull-Clark, Loop subdivision |
| `GBMesh.Deform` | Twist, bend, taper, FFD, displacement |
| `GBMesh.Noise` | Perlin, simplex, Worley, FBM |
| `GBMesh.Combine` | Merge, transform, recompute normals/tangents |

## Design

- **Pure.** All generators are `params -> Mesh` — no IO, no GPU, no state.
- **Minimal deps.** Only `base` + `containers`.
- **Parametric.** Every shape is controlled by named parameters.
- **Composable.** Combine primitives, chain deformations, nest SDFs.
- **Fidelity-agnostic.** 500 triangles or 50,000 — tessellation is a parameter.

## Part of the GB Ecosystem

```
gb-vector    math foundations
gb-sprite    2D procedural generation (sprites, noise, filters)
gb-synth     audio procedural generation (waveforms, instruments)
gb-mesh      3D procedural generation (meshes, surfaces, characters)  ← this
```

## Building

```bash
cabal build all --ghc-options="-Werror"
```

---

<div align="center">

Gondola Bros Entertainment

</div>
