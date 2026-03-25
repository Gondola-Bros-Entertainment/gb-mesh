# Contributing

## Build

Requires GHC 9.8.4.

```bash
cabal build all --ghc-options="-Werror"
ormolu -m inplace <changed files>
hlint <changed files>
```

## Rules

- **`-Wall -Wcompat` clean.** Warnings are errors.
- **ALWAYS run `ormolu -m inplace` AND `hlint` on changed files before committing.**
- Only commit and push when explicitly instructed. Never amend commits.

## Haskell Style

- **Pure by default.** Everything is a pure function unless it fundamentally cannot be.
- **Total functions only.** No `head`, `tail`, `!!`, `fromJust`, `read`, or any partial function.
- **Strict by default.** Bang patterns on all data fields and accumulators.
- **No prime-mark variables.** Use descriptive names.
- **Named constants.** No magic numbers or hardcoded strings.
- **Small, composable functions.** Each function does one thing.
- **Explicit export lists on all modules.**
