<div align="center">
<h1>gb-mesh</h1>
<p><strong>Procedural 3D Mesh Generation</strong></p>
<p>Pure Haskell — no GPU, no asset pipeline, no IO. Just math.</p>
<p><a href="#modules">Modules</a> · <a href="#quick-start">Quick Start</a> · <a href="#design">Design</a> · <a href="#building">Building</a></p>
<p>

[![CI](https://github.com/Gondola-Bros-Entertainment/gb-mesh/actions/workflows/ci.yml/badge.svg)](https://github.com/Gondola-Bros-Entertainment/gb-mesh/actions/workflows/ci.yml)
[![Hackage](https://img.shields.io/hackage/v/gb-mesh.svg)](https://hackage.haskell.org/package/gb-mesh)
![Haskell](https://img.shields.io/badge/haskell-GHC%209.8-purple)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)

</p>
</div>

---

Pure functions that produce 3D geometry from parametric descriptions. 34 modules covering primitives, curves, surfaces, SDFs, noise, terrain, subdivision, deformation, skeletal animation, inverse kinematics, skinning, morph targets, GPU buffer packing, and import/export.

## Quick Start

```haskell
import GBMesh

-- Generate a sphere, subdivide it, export to glTF
main :: IO ()
main = case sphere 1.0 32 16 of
  Nothing -> pure ()
  Just mesh ->
    let smoothed = subdivide 1 mesh
        gltf = meshToGLTF smoothed
     in writeFile "sphere.gltf" gltf

-- SDF-based terrain with marching cubes
proceduralRock :: Mesh
proceduralRock =
  let cfg = mkNoiseConfig 42
      sdf = smoothIntersection 0.3
              (sdfSphere 2.0)
              (sdfBox (V3 2.5 1.5 2.0))
   in marchingCubes sdf 40 40 40 (V3 (-3) (-3) (-3)) (V3 3 3 3)

-- Skeletal animation pipeline
animatedCharacter :: Float -> Maybe Mesh
animatedCharacter time = do
  skel <- humanoid 1.8
  let pose = oscillate 0 (V3 0 1 0) (pi / 4) 1.0 time
      binding = buildSkinBinding skel mesh 2 0.5
  baseMesh <- cylinder 0.2 1.0 8 4
  pure (applySkin skel pose binding baseMesh)
```

## Modules

### Geometry

| Module | Description |
|--------|-------------|
| `Primitives` | Sphere, capsule, cylinder, cone, torus, box, plane, tapered cylinder |
| `Curve` | Bezier, B-spline, NURBS curves with arc-length parameterization |
| `Surface` | Bezier patches, B-spline surfaces, NURBS surfaces |
| `Loft` | Revolve, loft, extrude, sweep with Bishop frames |
| `Isosurface` | Marching cubes with SDF grid caching |
| `DualContour` | Dual contouring with QEF solving for sharp features |
| `Hull` | Incremental 3D convex hull |
| `Icosphere` | Geodesic sphere from icosahedron subdivision |
| `Terrain` | Heightmap terrain with thermal and hydraulic erosion |

### Procedural

| Module | Description |
|--------|-------------|
| `SDF` | Signed distance fields, CSG, smooth blending, twist, bend, taper, repetition |
| `Noise` | Perlin 2D/3D, simplex 2D/3D/4D, Worley 2D/3D, FBM, ridged, turbulence |
| `Boolean` | Mesh-level CSG union, intersection, difference |
| `Scatter` | Uniform, Poisson disk, and weighted point distribution |
| `UV` | Planar, cylindrical, spherical, box UV projection |

### Processing

| Module | Description |
|--------|-------------|
| `Combine` | Translate, rotate, scale, merge, recompute normals and tangents |
| `Deform` | Twist, bend (Barr 1984), taper, FFD, displacement mapping |
| `Subdivision` | Catmull-Clark (quads), Loop (triangles) |
| `Smooth` | Laplacian smoothing, Taubin volume-preserving smoothing |
| `Simplify` | Quadric error metric decimation (Garland-Heckbert) |
| `Weld` | Spatial-hash vertex welding, degenerate triangle removal |
| `Symmetry` | Mirror (X/Y/Z/arbitrary plane), radial symmetry |
| `LOD` | Level-of-detail chain generation with screen-size selection |
| `Remesh` | Isotropic remeshing (split, collapse, flip, relax) |
| `Raycast` | Ray-triangle intersection, BVH-accelerated raycasting |

### Animation

| Module | Description |
|--------|-------------|
| `Skeleton` | Joint trees with humanoid and quadruped builders |
| `Pose` | Forward kinematics, pose interpolation |
| `Animate` | Procedural oscillators, keyframes, easing functions |
| `IK` | CCD and FABRIK solvers with hinge and cone constraints |
| `Skin` | Linear blend skinning, dual quaternion skinning, auto-weights |
| `Morph` | Mesh morphing, additive blend shapes |

### Foundation

| Module | Description |
|--------|-------------|
| `Types` | `V2`, `V3`, `V4`, `Quaternion`, `Vertex`, `Mesh`, vector math |
| `Buffer` | GPU-ready vertex/index packing (interleaved and separate layouts) |
| `Export` | Wavefront OBJ, glTF 2.0 (embedded base64) |
| `Import` | OBJ and glTF 2.0 parsing (single and multi-mesh) |

## Design

- **Pure.** Every function is `params -> Mesh`. No IO, no GPU, no mutable state.
- **Minimal deps.** `base` + `containers` + `array`. Nothing else.
- **Composable.** Chain generators, deformations, SDFs, and animations freely.
- **Parametric.** Tessellation density, blend radii, joint limits — everything is a parameter.
- **Total.** No partial functions. Invalid inputs return `Nothing`, not crashes.

## Coordinate System

Right-handed, Y-up. Counter-clockwise front faces. All angles in radians.

```
    Y (up)
    |
    |
    +------ X (right)
   /
  Z (toward camera)
```

## Building

```bash
cabal build all --ghc-options="-Werror"
cabal test
```

## Stats

34 modules | 255 tests | GHC 9.8.4

---

<div align="center">

Gondola Bros Entertainment

</div>
