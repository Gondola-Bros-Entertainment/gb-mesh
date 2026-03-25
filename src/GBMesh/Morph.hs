-- | Mesh morphing and blend shape deformation.
--
-- Linear interpolation between meshes, multi-target blend shapes,
-- and position-only morphing. All operations renormalize normals
-- after interpolation.
module GBMesh.Morph
  ( -- * Full mesh morphing
    morphMesh,

    -- * Blend shapes
    blendShapes,

    -- * Position-only morphing
    morphPositions,
  )
where

import Data.List (foldl')
import Data.Word (Word32)
import GBMesh.Types
  ( Mesh (..),
    V2,
    V3,
    V4,
    VecSpace (..),
    Vertex (..),
    mkMesh,
    vlength,
  )

-- ----------------------------------------------------------------
-- Full mesh morphing
-- ----------------------------------------------------------------

-- | Linearly interpolate between two meshes.
--
-- @t = 0@ gives the first mesh, @t = 1@ gives the second.
-- Interpolates positions, normals, UVs, and tangents.
-- If vertex counts differ, the shorter count is used and
-- indices are truncated to remain valid. Normals are
-- renormalized after interpolation.
morphMesh :: Float -> Mesh -> Mesh -> Mesh
morphMesh t meshA meshB =
  let verticesA = meshVertices meshA
      verticesB = meshVertices meshB
      blendedVertices = zipWith (lerpVertex t) verticesA verticesB
      vertexCount = length blendedVertices
      indices = truncateIndices vertexCount (meshIndices meshA)
   in mkMesh blendedVertices indices

-- | Interpolate all vertex attributes between two vertices.
-- Renormalizes the interpolated normal.
lerpVertex :: Float -> Vertex -> Vertex -> Vertex
lerpVertex t vertA vertB =
  Vertex
    { vPosition = lerpV3 t (vPosition vertA) (vPosition vertB),
      vNormal = safeNormalize (lerpV3 t (vNormal vertA) (vNormal vertB)),
      vUV = lerpV2 t (vUV vertA) (vUV vertB),
      vTangent = lerpV4 t (vTangent vertA) (vTangent vertB)
    }

-- ----------------------------------------------------------------
-- Blend shapes
-- ----------------------------------------------------------------

-- | Apply multiple weighted morph targets to a base mesh.
--
-- Each target is a @(weight, mesh)@ pair. The blended value for
-- each attribute is:
--
-- @blended = base + sum(weight_i * (target_i - base))@
--
-- If any target has fewer vertices than the base, only the
-- overlapping vertices are blended. Normals are renormalized
-- after blending.
blendShapes :: Mesh -> [(Float, Mesh)] -> Mesh
blendShapes baseMesh targets =
  let baseVertices = meshVertices baseMesh
      blendedVertices = zipWithIndex baseVertices 0
      indices = truncateIndices (length blendedVertices) (meshIndices baseMesh)
   in mkMesh blendedVertices indices
  where
    zipWithIndex [] _ = []
    zipWithIndex (baseVtx : restBase) !idx =
      let deltas = collectDeltas baseVtx idx targets
          blendedVtx = applyDeltas baseVtx deltas
       in blendedVtx : zipWithIndex restBase (idx + 1)

-- | Collect weighted deltas from all targets for a given vertex index.
-- Returns the accumulated (position, normal, uv, tangent) delta.
collectDeltas :: Vertex -> Int -> [(Float, Mesh)] -> (V3, V3, V2, V4)
collectDeltas baseVtx idx =
  foldl' accumDelta (vzero, vzero, vzero, vzero)
  where
    basePos = vPosition baseVtx
    baseNrm = vNormal baseVtx
    baseUv = vUV baseVtx
    baseTan = vTangent baseVtx

    accumDelta (!accPos, !accNrm, !accUv, !accTan) (weight, targetMesh) =
      case safeIndex (meshVertices targetMesh) idx of
        Nothing -> (accPos, accNrm, accUv, accTan)
        Just targetVtx ->
          let deltaPos = vPosition targetVtx ^-^ basePos
              deltaNrm = vNormal targetVtx ^-^ baseNrm
              deltaUv = vUV targetVtx ^-^ baseUv
              deltaTan = vTangent targetVtx ^-^ baseTan
           in ( accPos ^+^ weight *^ deltaPos,
                accNrm ^+^ weight *^ deltaNrm,
                accUv ^+^ weight *^ deltaUv,
                accTan ^+^ weight *^ deltaTan
              )

-- | Apply accumulated deltas to a base vertex and renormalize the normal.
applyDeltas :: Vertex -> (V3, V3, V2, V4) -> Vertex
applyDeltas baseVtx (deltaPos, deltaNrm, deltaUv, deltaTan) =
  Vertex
    { vPosition = vPosition baseVtx ^+^ deltaPos,
      vNormal = safeNormalize (vNormal baseVtx ^+^ deltaNrm),
      vUV = vUV baseVtx ^+^ deltaUv,
      vTangent = vTangent baseVtx ^+^ deltaTan
    }

-- ----------------------------------------------------------------
-- Position-only morphing
-- ----------------------------------------------------------------

-- | Like 'morphMesh' but only interpolates positions.
--
-- Normals, UVs, and tangents are kept from the first mesh.
-- If vertex counts differ, the shorter count is used and
-- indices are truncated.
morphPositions :: Float -> Mesh -> Mesh -> Mesh
morphPositions t meshA meshB =
  let verticesA = meshVertices meshA
      verticesB = meshVertices meshB
      blendedVertices = zipWith (lerpPositionOnly t) verticesA verticesB
      vertexCount = length blendedVertices
      indices = truncateIndices vertexCount (meshIndices meshA)
   in mkMesh blendedVertices indices

-- | Interpolate only the position, keeping other attributes from
-- the first vertex.
lerpPositionOnly :: Float -> Vertex -> Vertex -> Vertex
lerpPositionOnly t vertA vertB =
  vertA {vPosition = lerpV3 t (vPosition vertA) (vPosition vertB)}

-- ----------------------------------------------------------------
-- Interpolation helpers
-- ----------------------------------------------------------------

-- | Linear interpolation between two 'V3' values.
lerpV3 :: Float -> V3 -> V3 -> V3
lerpV3 t from to = (1.0 - t) *^ from ^+^ t *^ to

-- | Linear interpolation between two 'V2' values.
lerpV2 :: Float -> V2 -> V2 -> V2
lerpV2 t from to = (1.0 - t) *^ from ^+^ t *^ to

-- | Linear interpolation between two 'V4' values.
lerpV4 :: Float -> V4 -> V4 -> V4
lerpV4 t from to = (1.0 - t) *^ from ^+^ t *^ to

-- ----------------------------------------------------------------
-- Utility helpers
-- ----------------------------------------------------------------

-- | Normalize a vector, returning the zero vector if the input
-- length is below the near-zero threshold.
safeNormalize :: V3 -> V3
safeNormalize v
  | len < nearZeroLength = vzero
  | otherwise = (1.0 / len) *^ v
  where
    len = vlength v

-- | Threshold below which a vector is considered zero-length.
nearZeroLength :: Float
nearZeroLength = 1.0e-10

-- | Truncate an index list so that all indices are valid for
-- the given vertex count. Indices referencing beyond the count
-- cause the enclosing triangle to be dropped.
truncateIndices :: Int -> [Word32] -> [Word32]
truncateIndices vertexCount = go
  where
    maxIndex = fromIntegral vertexCount

    go (idxA : idxB : idxC : rest)
      | idxA < maxIndex && idxB < maxIndex && idxC < maxIndex =
          idxA : idxB : idxC : go rest
      | otherwise = go rest
    go _ = []

-- | Safely index into a list, returning 'Nothing' for
-- out-of-bounds access.
safeIndex :: [a] -> Int -> Maybe a
safeIndex [] _ = Nothing
safeIndex (x : _) 0 = Just x
safeIndex (_ : rest) n
  | n < 0 = Nothing
  | otherwise = safeIndex rest (n - 1)
