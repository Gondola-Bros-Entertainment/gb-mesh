-- | Laplacian and Taubin mesh smoothing.
--
-- Iteratively relax vertex positions toward the average of their
-- edge-connected neighbors. Laplacian smoothing shrinks the mesh;
-- Taubin smoothing alternates positive and negative steps to
-- preserve volume.
module GBMesh.Smooth
  ( -- * Laplacian smoothing
    smooth,

    -- * Taubin smoothing
    smoothTaubin,
  )
where

import Data.IntMap.Strict qualified as IntMap
import Data.IntSet qualified as IntSet
import Data.List (foldl')
import Data.Word (Word32)
import GBMesh.Combine (recomputeNormals, recomputeTangents)
import GBMesh.Types (Mesh (..), V3, VecSpace (..), Vertex (..))

-- ----------------------------------------------------------------
-- Laplacian smoothing
-- ----------------------------------------------------------------

-- | Apply @n@ iterations of Laplacian smoothing with the given
-- blend factor.
--
-- Each iteration computes, for every vertex, the average position
-- of all edge-connected neighbors and blends between the original
-- position and that average by @factor@. Iterations are clamped to
-- @>= 0@ and the factor is clamped to @[0, 1]@. Normals and
-- tangents are recomputed after all iterations.
smooth :: Int -> Float -> Mesh -> Mesh
smooth iterations factor =
  recomputeTangents
    . recomputeNormals
    . applyIterations clampedIterations (smoothStep clampedFactor)
  where
    clampedIterations = max 0 iterations
    clampedFactor = clamp01 factor

-- ----------------------------------------------------------------
-- Taubin smoothing
-- ----------------------------------------------------------------

-- | Apply @n@ iterations of Taubin (shrink-free) smoothing.
--
-- Each iteration performs two smoothing steps: one with @lambda@
-- (positive, smoothing) followed by one with @mu@ (negative,
-- inflation). This prevents the mesh from shrinking. Typical
-- values are @lambda = 0.5@, @mu = -0.53@.
--
-- Iterations are clamped to @>= 0@. Lambda and mu are used as
-- given (not clamped) since mu must be negative.
smoothTaubin :: Int -> Float -> Float -> Mesh -> Mesh
smoothTaubin iterations lambda mu =
  recomputeTangents
    . recomputeNormals
    . applyIterations clampedIterations taubinStep
  where
    clampedIterations = max 0 iterations
    taubinStep = smoothStep mu . smoothStep lambda

-- ----------------------------------------------------------------
-- Internal: smoothing step
-- ----------------------------------------------------------------

-- | Perform one smoothing step: blend each vertex position toward
-- the average of its neighbors by the given factor.
smoothStep :: Float -> Mesh -> Mesh
smoothStep factor (Mesh vertices indices count) =
  Mesh smoothedVertices indices count
  where
    adjacency = buildAdjacency indices
    positionMap = IntMap.fromList (zip [0 ..] (map vPosition vertices))
    smoothedVertices = zipWith (smoothVertex adjacency positionMap factor) [0 ..] vertices

-- | Blend a single vertex position toward its neighbor average.
smoothVertex :: IntMap.IntMap IntSet.IntSet -> IntMap.IntMap V3 -> Float -> Int -> Vertex -> Vertex
smoothVertex adjacency positionMap factor vertexIndex vertex =
  case IntMap.lookup vertexIndex adjacency of
    Nothing -> vertex
    Just neighborSet
      | IntSet.null neighborSet -> vertex
      | otherwise ->
          let neighborPositions = IntSet.foldl' gatherPositions [] neighborSet
              neighborCount = fromIntegral (IntSet.size neighborSet) :: Float
              inverseCount = 1.0 / neighborCount
              averagePosition = inverseCount *^ foldl' (^+^) vzero neighborPositions
              originalPosition = vPosition vertex
              blendedPosition = (1.0 - factor) *^ originalPosition ^+^ factor *^ averagePosition
           in vertex {vPosition = blendedPosition}
  where
    gatherPositions !acc neighborIndex =
      case IntMap.lookup neighborIndex positionMap of
        Just pos -> pos : acc
        Nothing -> acc

-- ----------------------------------------------------------------
-- Internal: adjacency
-- ----------------------------------------------------------------

-- | Build a map from each vertex index to the set of its
-- edge-connected neighbor indices by scanning all triangles.
buildAdjacency :: [Word32] -> IntMap.IntMap IntSet.IntSet
buildAdjacency = foldl' insertTriangle IntMap.empty . groupTriangles

-- | Insert the three edges of a triangle into the adjacency map.
-- Each edge connects two vertices bidirectionally.
insertTriangle :: IntMap.IntMap IntSet.IntSet -> (Word32, Word32, Word32) -> IntMap.IntMap IntSet.IntSet
insertTriangle !acc (idx0, idx1, idx2) =
  addEdge i0 i1
    . addEdge i1 i0
    . addEdge i0 i2
    . addEdge i2 i0
    . addEdge i1 i2
    . addEdge i2 i1
    $ acc
  where
    i0 = fromIntegral idx0
    i1 = fromIntegral idx1
    i2 = fromIntegral idx2
    addEdge from to =
      IntMap.insertWith IntSet.union from (IntSet.singleton to)

-- ----------------------------------------------------------------
-- Internal: helpers
-- ----------------------------------------------------------------

-- | Group a flat index list into triples representing triangles.
groupTriangles :: [Word32] -> [(Word32, Word32, Word32)]
groupTriangles (a : b : c : rest) = (a, b, c) : groupTriangles rest
groupTriangles _ = []

-- | Apply a mesh transformation @n@ times.
applyIterations :: Int -> (Mesh -> Mesh) -> Mesh -> Mesh
applyIterations n step mesh = foldl' (\acc _ -> step acc) mesh [1 .. n]

-- | Clamp a value to the @[0, 1]@ range.
clamp01 :: Float -> Float
clamp01 x = max 0.0 (min 1.0 x)
