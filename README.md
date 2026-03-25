<div align="center">

# gb-mesh

**Procedural 3D mesh generation in Haskell**

[![Haskell](https://img.shields.io/badge/Haskell-GHC%209.8.4-5e5086)](https://www.haskell.org)
[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue)](LICENSE)

</div>

---

The 3D equivalent of [gb-sprite](https://hackage.haskell.org/package/gb-sprite). Pure functions that produce vertex and index data from parametric descriptions. No GPU dependency — plug into any renderer.

## Planned Modules

| Module | Purpose |
|--------|---------|
| `Mesh.Primitives` | Sphere, capsule, cylinder, cone, tapered cylinder |
| `Mesh.Loft` | Revolve/loft Bezier profiles into meshes |
| `Mesh.Humanoid` | Proportions → skeleton → procedural character mesh |
| `Mesh.Equipment` | Bone-attached procedural equipment meshes |

## Design

- **Pure.** All generation functions are `a -> ([Vertex], [Word32])` — no IO, no GPU.
- **Minimal deps.** Only `base` + `linear`.
- **Parametric.** Every shape is controlled by named parameters, not magic numbers.
- **Composable.** Combine primitives to build complex geometry.

## Part of the GB Ecosystem

```
gb-vector    math foundations
gb-sprite    2D procedural generation (sprites, noise, filters)
gb-synth     audio procedural generation (waveforms, instruments)
gb-mesh      3D procedural generation (meshes, skeletons, characters)  ← this
gb-engine    Vulkan rendering (consumes all of the above)
```

## Building

```bash
cabal build all --ghc-options="-Werror"
```

---

<div align="center">

Gondola Bros Entertainment

</div>
