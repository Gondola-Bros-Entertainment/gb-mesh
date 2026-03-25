-- | Skeletal mesh skinning with linear blend skinning.
--
-- Computes per-vertex bone weights (by proximity or manually) and
-- deforms a mesh according to a posed skeleton. Each vertex is
-- influenced by up to 'maxInfluences' bones.
module GBMesh.Skin
  ( -- * Types
    BoneWeight (..),
    SkinVertex (..),
    SkinBinding (..),

    -- * Constants
    maxInfluences,

    -- * Weight manipulation
    normalizeWeights,

    -- * Automatic binding
    buildSkinBinding,

    -- * Skinning
    applySkin,
  )
where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (foldl', sortBy)
import Data.Ord (comparing)
import GBMesh.Pose (Pose)
import GBMesh.Skeleton (Joint (..), Skeleton, skelBones, skelChildren, skelJoints, skelRestPositions, skelRoot)
import GBMesh.Types
  ( Mesh (..),
    Quaternion (..),
    V3 (..),
    VecSpace (..),
    Vertex (..),
    mkMesh,
    mulQuat,
    normalize,
    rotateV3,
    vlength,
  )

-- ----------------------------------------------------------------
-- Types
-- ----------------------------------------------------------------

-- | A single bone influence: which joint and how much weight.
data BoneWeight = BoneWeight
  { bwBone :: !Int,
    bwWeight :: !Float
  }
  deriving (Show, Eq)

-- | Per-vertex bone influences, up to 'maxInfluences' entries.
newtype SkinVertex = SkinVertex
  { svWeights :: [BoneWeight]
  }
  deriving (Show, Eq)

-- | Binding that maps each mesh vertex to its bone influences.
-- The list has one 'SkinVertex' per mesh vertex, in order.
newtype SkinBinding = SkinBinding
  { skinWeights :: [SkinVertex]
  }
  deriving (Show, Eq)

-- ----------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------

-- | Maximum number of bone influences per vertex.
maxInfluences :: Int
maxInfluences = 4

-- ----------------------------------------------------------------
-- Weight manipulation
-- ----------------------------------------------------------------

-- | Normalize bone weights so they sum to 1.0. If the total weight
-- is near zero, all weights are set to zero to avoid division by
-- zero.
normalizeWeights :: SkinVertex -> SkinVertex
normalizeWeights (SkinVertex weights) =
  SkinVertex (map scaleWeight weights)
  where
    totalWeight = foldl' (\acc bw -> acc + bwWeight bw) 0 weights
    scaleWeight bw
      | totalWeight < nearZeroWeight = bw {bwWeight = 0}
      | otherwise = bw {bwWeight = bwWeight bw / totalWeight}

-- ----------------------------------------------------------------
-- Automatic binding
-- ----------------------------------------------------------------

-- | Compute skin weights automatically by proximity. For each mesh
-- vertex, find the closest bones (using bone midpoint distance),
-- assign weights inversely proportional to distance, and normalize.
-- The 'Float' parameter is a falloff radius — bones farther than
-- this distance receive zero weight.
buildSkinBinding :: Skeleton -> Mesh -> Float -> SkinBinding
buildSkinBinding skel mesh falloffRadius =
  SkinBinding (map bindVertex (meshVertices mesh))
  where
    restPositions = skelRestPositions skel
    bones = skelBones skel

    -- Precompute bone midpoints: for each (parent, child) pair,
    -- store the joint ID and midpoint position.
    boneMidpoints :: [(Int, V3)]
    boneMidpoints =
      [ (childId, midpoint parentPos childPos)
      | (parentId, childId) <- bones,
        let parentPos = IntMap.findWithDefault vzero parentId restPositions,
        let childPos = IntMap.findWithDefault vzero childId restPositions
      ]

    -- Also include the root joint itself as a potential influence,
    -- since it has no parent bone.
    rootId = skelRoot skel
    rootPos = IntMap.findWithDefault vzero rootId restPositions
    allInfluenceSources :: [(Int, V3)]
    allInfluenceSources = (rootId, rootPos) : boneMidpoints

    bindVertex :: Vertex -> SkinVertex
    bindVertex vtx =
      let vertexPos = vPosition vtx
          -- Compute distance to each bone midpoint
          distances :: [(Int, Float)]
          distances =
            [ (boneId, vlength (vertexPos ^-^ bonePos))
            | (boneId, bonePos) <- allInfluenceSources
            ]
          -- Sort by distance and take the closest N
          sorted = take maxInfluences (sortBy (comparing snd) distances)
          -- Assign inverse-distance weights, respecting falloff
          rawWeights =
            [ BoneWeight boneId (inverseDistanceWeight dist)
            | (boneId, dist) <- sorted
            ]
       in normalizeWeights (SkinVertex rawWeights)

    inverseDistanceWeight :: Float -> Float
    inverseDistanceWeight dist
      | dist >= falloffRadius = 0
      | dist < nearZeroWeight = 1
      | otherwise = 1.0 / dist

-- ----------------------------------------------------------------
-- Skinning
-- ----------------------------------------------------------------

-- | Apply linear blend skinning. For each vertex:
--
-- 1. Look up the world-space transform (position + rotation) for
--    each influencing bone from the posed skeleton.
-- 2. Compute the rest-pose inverse transform for each bone.
-- 3. For each influence: @transform = worldTransform * inverseRestTransform@
-- 4. Blend: @finalPos = sum(weight_i * transform_i * restPos)@
-- 5. Transform normals with rotation only (no translation).
applySkin :: Skeleton -> Pose -> SkinBinding -> Mesh -> Mesh
applySkin skel pose binding mesh =
  mkMesh skinnedVertices (meshIndices mesh)
  where
    -- Posed world-space positions and rotations
    (posedPositions, posedRotations) = computePoseTransforms skel pose
    -- Rest-pose world-space positions and rotations (identity rotations)
    restPositions = skelRestPositions skel

    skinnedVertices :: [Vertex]
    skinnedVertices =
      zipWith skinVertex (meshVertices mesh) (skinWeights binding)

    skinVertex :: Vertex -> SkinVertex -> Vertex
    skinVertex vtx skinVtx =
      let restPos = vPosition vtx
          restNrm = vNormal vtx
          influences = svWeights skinVtx
          -- Accumulate blended position and normal
          (blendedPos, blendedNrm) =
            foldl' (blendInfluence restPos restNrm) (vzero, vzero) influences
          finalNrm = normalize blendedNrm
       in vtx {vPosition = blendedPos, vNormal = finalNrm}

    blendInfluence ::
      V3 ->
      V3 ->
      (V3, V3) ->
      BoneWeight ->
      (V3, V3)
    blendInfluence restPos restNrm (!accPos, !accNrm) bw =
      let boneId = bwBone bw
          weight = bwWeight bw
          -- Posed transform for this bone
          posePos = IntMap.findWithDefault vzero boneId posedPositions
          poseRot = IntMap.findWithDefault identityQuat boneId posedRotations
          -- Rest transform for this bone (identity rotation at rest)
          restBonePos = IntMap.findWithDefault vzero boneId restPositions
          -- Combined transform: worldTransform * inverseRestTransform
          -- For a point p in rest pose:
          --   1. Remove rest transform: p_local = p - restBonePos
          --   2. Apply posed transform: p_posed = poseRot * p_local + posePos
          localPos = restPos ^-^ restBonePos
          transformedPos = rotateV3 poseRot localPos ^+^ posePos
          -- Normal: rotate only (no translation)
          transformedNrm = rotateV3 poseRot restNrm
       in (accPos ^+^ weight *^ transformedPos, accNrm ^+^ weight *^ transformedNrm)

-- ----------------------------------------------------------------
-- Internal: forward kinematics with rotations
-- ----------------------------------------------------------------

-- | Propagate pose rotations down the skeleton tree to produce
-- world-space positions and rotations for every joint. This is
-- equivalent to 'applyPose' but also returns the rotation map.
computePoseTransforms :: Skeleton -> Pose -> (IntMap V3, IntMap Quaternion)
computePoseTransforms skel pose = go (IntMap.empty, IntMap.empty) (skelRoot skel)
  where
    go (!posAcc, !rotAcc) jid =
      let joint = lookupJoint skel jid
          localRot = IntMap.findWithDefault identityQuat jid pose
          parentId = jointParent joint
          (parentPos, parentRot) =
            if parentId == rootParent
              then (vzero, identityQuat)
              else
                ( IntMap.findWithDefault vzero parentId posAcc,
                  IntMap.findWithDefault identityQuat parentId rotAcc
                )
          worldRot = mulQuat parentRot localRot
          worldPos = parentPos ^+^ rotateV3 parentRot (jointLocal joint)
          posAccUpdated = IntMap.insert jid worldPos posAcc
          rotAccUpdated = IntMap.insert jid worldRot rotAcc
       in foldl' go (posAccUpdated, rotAccUpdated) (skelChildren skel jid)

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Midpoint between two positions.
midpoint :: V3 -> V3 -> V3
midpoint pointA pointB = 0.5 *^ (pointA ^+^ pointB)

-- | Identity quaternion (no rotation).
identityQuat :: Quaternion
identityQuat = Quaternion 1 (V3 0 0 0)

-- | Sentinel value for "no parent" (root joint).
rootParent :: Int
rootParent = -1

-- | Look up a joint by ID, falling back to a default.
lookupJoint :: Skeleton -> Int -> Joint
lookupJoint skel jid =
  IntMap.findWithDefault (Joint jid rootParent vzero) jid (skelJoints skel)

-- | Threshold below which a weight sum is considered zero.
nearZeroWeight :: Float
nearZeroWeight = 1.0e-10
