-- | GBMesh.Primitives
--
-- Parametric 3D mesh primitives: sphere, capsule, cylinder, cone, taper.
-- All functions are pure, producing vertex/index lists suitable for upload
-- to any GPU backend. Normals and UVs are computed analytically.
module GBMesh.Primitives () where
