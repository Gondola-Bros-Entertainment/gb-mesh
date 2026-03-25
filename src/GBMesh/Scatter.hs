-- | Point distribution on mesh surfaces.
--
-- Scatter points uniformly, with Poisson disk spacing, or weighted
-- by a per-vertex function. Useful for object placement such as
-- foliage, rocks, or decals on terrain.
module GBMesh.Scatter
  ( -- * Placement
    Placement (..),

    -- * Distribution strategies
    scatterUniform,
    scatterPoisson,
    scatterWeighted,

    -- * Utilities
    triangleArea,
  )
where

import Data.Array (listArray, (!))
import Data.Bits ((.&.))
import Data.List (foldl')
import GBMesh.Types

-- ----------------------------------------------------------------
-- Placement
-- ----------------------------------------------------------------

-- | A point placed on a mesh surface, recording the world-space
-- position, interpolated normal, and the index of the source
-- triangle.
data Placement = Placement
  { plPosition :: !V3,
    plNormal :: !V3,
    plTriangleIndex :: !Int
  }
  deriving (Show, Eq)

-- ----------------------------------------------------------------
-- Triangle helpers
-- ----------------------------------------------------------------

-- | Area of a triangle defined by three vertices.
triangleArea :: V3 -> V3 -> V3 -> Float
triangleArea a b c = 0.5 * vlength (cross (b ^-^ a) (c ^-^ a))

-- ----------------------------------------------------------------
-- Deterministic PRNG
-- ----------------------------------------------------------------

-- | Linear congruential generator step. Returns a non-negative
-- 31-bit integer derived from the seed.
lcgNext :: Int -> Int
lcgNext s = (s * 1103515245 + 12345) .&. 0x7FFFFFFF

-- | Map a seed to a float in @[0, 1)@.
seedToFloat :: Int -> Float
seedToFloat s = fromIntegral (s .&. 0xFFFFFF) / fromIntegral (0xFFFFFF :: Int)

-- ----------------------------------------------------------------
-- Barycentric sampling
-- ----------------------------------------------------------------

-- | Sample a point inside a triangle using two uniform random
-- values. Returns the interpolated position and normal.
sampleTriangle :: Vertex -> Vertex -> Vertex -> Float -> Float -> (V3, V3)
sampleTriangle v0 v1 v2 r1 r2 =
  let u = sqrt r1
      a = 1 - u
      b = u * (1 - r2)
      c = u * r2
      pos = a *^ vPosition v0 ^+^ b *^ vPosition v1 ^+^ c *^ vPosition v2
      nrm = normalize (a *^ vNormal v0 ^+^ b *^ vNormal v1 ^+^ c *^ vNormal v2)
   in (pos, nrm)

-- ----------------------------------------------------------------
-- CDF construction
-- ----------------------------------------------------------------

-- | Build a cumulative distribution function from per-triangle
-- weights. Returns a list of @(cumulativeWeight, triangleIndex)@
-- pairs and the total weight.
buildCDF :: [Float] -> ([(Float, Int)], Float)
buildCDF weights =
  let indexed = zip weights [0 :: Int ..]
      (cdf, total) = foldl' step ([], 0) indexed
   in (reverse cdf, total)
  where
    step (!acc, !running) (w, i) =
      let runningNext = running + max 0 w
       in ((runningNext, i) : acc, runningNext)

-- | Binary search a CDF for the triangle corresponding to a
-- uniform random value in @[0, totalWeight)@.
searchCDF :: [(Float, Int)] -> Float -> Int
searchCDF [] _ = 0
searchCDF cdf val = go 0 (len - 1)
  where
    arr = listArray (0, max 0 (len - 1)) cdf
    len = length cdf
    go lo hi
      | lo >= hi = snd (arr ! hi)
      | otherwise =
          let mid = lo + (hi - lo) `div` 2
           in if fst (arr ! mid) < val
                then go (mid + 1) hi
                else go lo mid

-- ----------------------------------------------------------------
-- Scatter: uniform
-- ----------------------------------------------------------------

-- | Scatter points uniformly across the mesh surface.
--
-- Each triangle is selected with probability proportional to its
-- area. The @seed@ makes the distribution deterministic; different
-- seeds yield different distributions.
scatterUniform :: Int -> Int -> Mesh -> [Placement]
scatterUniform seed count mesh
  | count <= 0 = []
  | null tris = []
  | totalArea <= 0 = []
  | otherwise = go seed count []
  where
    verts = meshVertices mesh
    tris = groupTriangles (meshIndices mesh)
    areas = map (triArea verts) tris
    (cdf, totalArea) = buildCDF areas

    go _ 0 acc = reverse acc
    go s n acc =
      let s1 = lcgNext s
          s2 = lcgNext s1
          s3 = lcgNext s2
          triIdx = searchCDF cdf (seedToFloat s1 * totalArea)
          r1 = seedToFloat s2
          r2 = seedToFloat s3
          placement = makePlacement verts tris triIdx r1 r2
       in go s3 (n - 1) (placement : acc)

-- ----------------------------------------------------------------
-- Scatter: Poisson disk
-- ----------------------------------------------------------------

-- | Scatter points with Poisson disk spacing via dart throwing.
--
-- Generates candidate points uniformly and accepts them only if
-- they are at least @minDistance@ from every previously accepted
-- point. Stops after @maxAttempts@ total candidates have been
-- tried.
--
-- Complexity is @O(attempts * accepted)@, suitable for moderate
-- point counts.
scatterPoisson :: Int -> Float -> Int -> Mesh -> [Placement]
scatterPoisson seed minDistance maxAttempts mesh
  | maxAttempts <= 0 = []
  | null tris = []
  | totalArea <= 0 = []
  | otherwise = go seed maxAttempts []
  where
    verts = meshVertices mesh
    tris = groupTriangles (meshIndices mesh)
    areas = map (triArea verts) tris
    (cdf, totalArea) = buildCDF areas
    minDistSq = minDistance * minDistance

    go _ 0 acc = reverse acc
    go s remaining acc =
      let s1 = lcgNext s
          s2 = lcgNext s1
          s3 = lcgNext s2
          triIdx = searchCDF cdf (seedToFloat s1 * totalArea)
          r1 = seedToFloat s2
          r2 = seedToFloat s3
          placement = makePlacement verts tris triIdx r1 r2
       in if tooClose (plPosition placement) acc
            then go s3 (remaining - 1) acc
            else go s3 (remaining - 1) (placement : acc)

    tooClose _ [] = False
    tooClose p (pl : rest) =
      distanceSq p (plPosition pl) < minDistSq || tooClose p rest

-- ----------------------------------------------------------------
-- Scatter: weighted
-- ----------------------------------------------------------------

-- | Scatter points with per-vertex weight control.
--
-- Triangle selection probability is proportional to
-- @triangleArea * averageVertexWeight@. The weight function maps
-- each vertex to a non-negative weight (e.g. based on height,
-- slope, curvature).
scatterWeighted :: Int -> Int -> (Vertex -> Float) -> Mesh -> [Placement]
scatterWeighted seed count weightFn mesh
  | count <= 0 = []
  | null tris = []
  | totalWeight <= 0 = []
  | otherwise = go seed count []
  where
    verts = meshVertices mesh
    tris = groupTriangles (meshIndices mesh)
    weights = map (weightedTriArea verts weightFn) tris
    (cdf, totalWeight) = buildCDF weights

    go _ 0 acc = reverse acc
    go s n acc =
      let s1 = lcgNext s
          s2 = lcgNext s1
          s3 = lcgNext s2
          triIdx = searchCDF cdf (seedToFloat s1 * totalWeight)
          r1 = seedToFloat s2
          r2 = seedToFloat s3
          placement = makePlacement verts tris triIdx r1 r2
       in go s3 (n - 1) (placement : acc)

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Compute the area of a triangle given the vertex list and an
-- index triple.
triArea :: [Vertex] -> (Word32, Word32, Word32) -> Float
triArea verts (i0, i1, i2) =
  case (safeIndex verts (fromIntegral i0), safeIndex verts (fromIntegral i1), safeIndex verts (fromIntegral i2)) of
    (Just v0, Just v1, Just v2) ->
      triangleArea (vPosition v0) (vPosition v1) (vPosition v2)
    _ -> 0

-- | Compute weighted area: @triangleArea * averageVertexWeight@.
weightedTriArea :: [Vertex] -> (Vertex -> Float) -> (Word32, Word32, Word32) -> Float
weightedTriArea verts weightFn (i0, i1, i2) =
  case (safeIndex verts (fromIntegral i0), safeIndex verts (fromIntegral i1), safeIndex verts (fromIntegral i2)) of
    (Just v0, Just v1, Just v2) ->
      let area = triangleArea (vPosition v0) (vPosition v1) (vPosition v2)
          avgW = (weightFn v0 + weightFn v1 + weightFn v2) / 3.0
       in area * max 0 avgW
    _ -> 0

-- | Construct a 'Placement' by sampling inside the triangle at
-- the given index.
makePlacement :: [Vertex] -> [(Word32, Word32, Word32)] -> Int -> Float -> Float -> Placement
makePlacement verts tris triIdx r1 r2 =
  case safeIndex tris triIdx of
    Nothing -> Placement vzero (V3 0 1 0) 0
    Just (i0, i1, i2) ->
      case (safeIndex verts (fromIntegral i0), safeIndex verts (fromIntegral i1), safeIndex verts (fromIntegral i2)) of
        (Just v0, Just v1, Just v2) ->
          let (pos, nrm) = sampleTriangle v0 v1 v2 r1 r2
           in Placement pos nrm triIdx
        _ -> Placement vzero (V3 0 1 0) triIdx
