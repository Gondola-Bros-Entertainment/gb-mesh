# gb-mesh — Design Notes

## Why

Paradise was a 2.5D isometric MMO. The client had a fully procedural character system built on gb-sprite — 16-joint humanoid skeletons, Bezier body contours, 8-directional facing projection with ellipse cross-section math, procedural pose generators (sine-based walk/idle/attack/cast), delta-based keyframe animation, depth-sorted layered rendering, joint-attached equipment with per-material shading. All pure Haskell, all procedural — no pre-rendered sprites.

We're pivoting Paradise to full 3D via gb-engine (our Vulkan renderer). gb-engine handles the GPU side — pipelines, PBR shading, skeletal animation playback, terrain, scene management. But it doesn't generate geometry. It loads meshes from glTF files or uses hardcoded builtins (cube, quad).

gb-mesh fills the gap: procedural 3D mesh generation. The same role gb-sprite plays for 2D — pure functions that produce geometry from parametric descriptions. No Blender, no asset pipeline, just code.

## The GB Ecosystem

```
gb-vector    SVG generation, vector math
gb-sprite    2D procedural generation (sprites, noise, filters, isometric)
gb-synth     audio procedural generation (waveforms, instruments, SFX)
gb-mesh      3D procedural generation (meshes, skeletons, characters)  <-- this
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

## Art Direction

Valheim-style: low-poly geometry + modern PBR lighting = commercially viable aesthetic without HD assets. A character at that fidelity is 500-2000 triangles — well within parametric mesh generation territory. Capsules, tapered cylinders, extruded shapes. No sculpting needed.

The key insight: if the geometry is simple enough, you don't need a 3D artist. You need good math and good lighting. gb-engine already has the lighting (Cook-Torrance BRDF, normal mapping, ACES tonemapping). gb-mesh provides the geometry.

## Planned Modules

### Mesh.Primitives
Parametric shapes with analytical normals and UVs:
- `sphere` — UV sphere from radius + segment counts
- `capsule` — hemisphere caps + cylinder body
- `cylinder` — top/bottom radius, height, segments
- `cone` — cylinder with zero top radius
- `taper` — cylinder with different top/bottom radii (limbs)
- `torus` — ring with tube radius

### Mesh.Loft
Surface generation from profiles:
- `revolve` — rotate a 2D profile around an axis (lathe)
- `loft` — interpolate between cross-section profiles along a spine
- `extrude` — push a 2D shape along a direction
- Bezier profile evaluation for smooth organic shapes

### Mesh.Humanoid
Full procedural character generation:
- `HumanoidSpec` — body proportions (head ratio, shoulder width, hip width, limb lengths)
- `BodyType` — male/female contour profiles
- `CharacterClass` — class-specific adjustments (stocky guardian, lean corsair, slim tempest)
- `buildSkeleton` — proportions → joint positions → skeleton
- `buildCharacterMesh` — skeleton + contours → full body mesh
- `buildLimbMesh` — tapered cylinder between two joints

### Mesh.Equipment
Bone-attached procedural gear:
- Armor plates, weapons, shields from parametric descriptions
- Attach points on skeleton joints
- Scale/orient to match character proportions

## Design Principles

1. **Pure functions only.** Every generator is `params -> ([Vertex], [Word32])`. No IO, no GPU, no state.
2. **Minimal dependencies.** `base` + `linear`. Nothing else.
3. **Parametric everything.** Named parameters, not magic numbers. Every shape is a function call.
4. **Composable.** Combine primitives freely. Merge vertex/index lists with offset arithmetic.
5. **Skeleton-agnostic animation.** Same approach as Paradise — delta keyframes work across body types.

## The Vision

The GB ecosystem + Claude = procedural content generation without neural networks. gb-sprite proved it for 2D (Defenders is fully procedural). gb-mesh extends it to 3D. Deterministic, reproducible, type-safe, real-time. The libraries are the tools, the games are the product.
