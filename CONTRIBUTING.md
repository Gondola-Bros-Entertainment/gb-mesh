# Contributing

## Build

Requires GHC 9.8.4.

```bash
cabal build all --ghc-options="-Werror"
```

## Formatting

Run on every changed file before committing:

```bash
ormolu -m inplace <file>
hlint <file>
```

## Commits

- Only commit when explicitly instructed.
- Never amend commits.
- Never push unless explicitly asked.

## Haskell Style

### Purity

Everything is a pure function. No `IO`, no exceptions, no `unsafePerformIO`. If a function cannot be pure, it does not belong in this library.

### Totality

No partial functions. Banned: `head`, `tail`, `!!`, `fromJust`, `read`, `error`, `undefined`, `throw`. Use pattern matching, `maybe`, `either`, `fromMaybe`, `NonEmpty`, or return `Maybe` / `Either`.

### Strictness

`StrictData` is enabled project-wide — all data fields are strict by default. Use bang patterns on accumulators in folds and recursive functions. Prefer `foldl'` over `foldl`.

### Naming

- Descriptive names. No single-letter variables except short lambdas or established math conventions (`u`, `v` for surface parameters, `n` for normal, `t` for interpolation parameter).
- No prime-mark variables (`x'`, `acc'`). Use descriptive names.
- Modules: `GBMesh.<Topic>`.
- Types: `PascalCase`.
- Functions and constants: `camelCase`.

### Exports

Explicit export lists on all modules. Export types, constructors, and functions deliberately.

### Functions

- Small, composable. Each function does one thing.
- Named constants for all numeric values. No magic numbers.
- Prefer `where` clauses for local bindings.

### Types

- Use `newtype` for domain-specific wrappers when type safety matters.
- Derive via `GeneralizedNewtypeDeriving` or `DerivingVia` when appropriate.
- Records for anything with more than 2–3 fields.

## Domain Conventions

### Coordinate System

Right-handed, Y-up:
- **X** = right
- **Y** = up
- **Z** = toward camera (out of screen)

### Linear Types

Use `linear` types consistently:
- Positions: `V3 Float`
- Normals: `V3 Float` (unit length)
- UVs: `V2 Float` (in `[0, 1]`)
- Indices: `Word32`

### Winding Order

Counter-clockwise (CCW) front faces.

### Normals

Analytical where possible — computed from the parametric surface equation, not from cross products of triangle edges.

### UVs

- U wraps around the circumference `[0, 1]`.
- V runs along the height/axis `[0, 1]`.
- Seam at U=0 / U=1 requires duplicate vertices with different UVs.

### Tessellation

All parametric shapes take segment/ring count parameters to control triangle density. Higher values = smoother, more triangles.

### Mesh Output

All generators produce a vertex list and an index list. Index values are offsets into the vertex list. Mesh combination is offset arithmetic.

### Angles

All angles in radians.
