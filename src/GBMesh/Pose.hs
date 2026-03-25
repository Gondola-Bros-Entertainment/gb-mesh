-- | Joint rotations and forward kinematics.
--
-- A 'Pose' maps joint IDs to local rotations. 'applyPose' propagates
-- those rotations down the skeleton tree to produce world-space
-- positions for every joint.
module GBMesh.Pose
  ( -- * Pose type
    Pose,

    -- * Construction
    restPose,
    singleJoint,
    fromList,

    -- * Forward kinematics
    applyPose,

    -- * Interpolation
    lerpPose,
    slerpQuat,
  )
where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (foldl')
import GBMesh.Skeleton
import GBMesh.Types

-- ----------------------------------------------------------------
-- Pose type
-- ----------------------------------------------------------------

-- | A pose is a rotation per joint. Joints absent from the map
-- use the identity quaternion (no rotation).
type Pose = IntMap Quaternion

-- ----------------------------------------------------------------
-- Construction
-- ----------------------------------------------------------------

-- | The rest pose: all joints at identity orientation.
restPose :: Pose
restPose = IntMap.empty

-- | Set a single joint's rotation.
singleJoint :: Int -> Quaternion -> Pose
singleJoint = IntMap.singleton

-- | Build a pose from a list of @(jointId, rotation)@ pairs.
fromList :: [(Int, Quaternion)] -> Pose
fromList = IntMap.fromList

-- ----------------------------------------------------------------
-- Forward kinematics
-- ----------------------------------------------------------------

-- | Propagate pose rotations down the skeleton tree to produce
-- world-space positions for every joint.
--
-- For the root joint:
--
-- @
-- worldPos(root)  = localPos(root)
-- worldRot(root)  = poseRot(root)
-- @
--
-- For all other joints:
--
-- @
-- worldRot(j)  = worldRot(parent(j)) * poseRot(j)
-- worldPos(j)  = worldPos(parent(j)) + rotate(worldRot(parent(j)), localPos(j))
-- @
--
-- Single O(n) pass over the joint tree.
applyPose :: Skeleton -> Pose -> IntMap V3
applyPose skel pose = positions
  where
    (positions, _) = go (IntMap.empty, IntMap.empty) (skelRoot skel)

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
          posAcc' = IntMap.insert jid worldPos posAcc
          rotAcc' = IntMap.insert jid worldRot rotAcc
       in foldl' go (posAcc', rotAcc') (skelChildren skel jid)

-- ----------------------------------------------------------------
-- Interpolation
-- ----------------------------------------------------------------

-- | Interpolate between two poses. Each joint is interpolated
-- independently via spherical linear interpolation (slerp).
-- Joints present in only one pose interpolate toward/from
-- identity.
lerpPose :: Float -> Pose -> Pose -> Pose
lerpPose t poseA poseB =
  IntMap.mapWithKey
    ( \jid _ ->
        let qa = IntMap.findWithDefault identityQuat jid poseA
            qb = IntMap.findWithDefault identityQuat jid poseB
         in slerpQuat t qa qb
    )
    allKeys
  where
    allKeys = IntMap.union poseA poseB

-- ----------------------------------------------------------------
-- Quaternion operations
-- ----------------------------------------------------------------

-- | Spherical linear interpolation between two quaternions.
-- Takes the shortest path (negates if dot product is negative).
slerpQuat :: Float -> Quaternion -> Quaternion -> Quaternion
slerpQuat t (Quaternion w1 (V3 x1 y1 z1)) (Quaternion w2 (V3 x2 y2 z2)) =
  let rawDot = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
      -- Take shortest path
      (cosTheta, w2', x2', y2', z2') =
        if rawDot < 0
          then (negate rawDot, negate w2, negate x2, negate y2, negate z2)
          else (rawDot, w2, x2, y2, z2)
   in if cosTheta > slerpThreshold
        then -- Near-parallel: use normalized lerp to avoid division by zero
          let w = w1 + t * (w2' - w1)
              x = x1 + t * (x2' - x1)
              y = y1 + t * (y2' - y1)
              z = z1 + t * (z2' - z1)
              invLen = 1.0 / sqrt (w * w + x * x + y * y + z * z)
           in Quaternion (w * invLen) (V3 (x * invLen) (y * invLen) (z * invLen))
        else
          let theta = acos (min 1.0 (max (-1.0) cosTheta))
              sinTheta = sin theta
              scaleA = sin ((1 - t) * theta) / sinTheta
              scaleB = sin (t * theta) / sinTheta
              w = scaleA * w1 + scaleB * w2'
              x = scaleA * x1 + scaleB * x2'
              y = scaleA * y1 + scaleB * y2'
              z = scaleA * z1 + scaleB * z2'
           in Quaternion w (V3 x y z)

-- | Multiply two quaternions (Hamilton product).
-- @mulQuat a b@ applies rotation @b@ first, then @a@
-- (right-to-left, like matrix multiplication).
mulQuat :: Quaternion -> Quaternion -> Quaternion
mulQuat (Quaternion w1 (V3 x1 y1 z1)) (Quaternion w2 (V3 x2 y2 z2)) =
  Quaternion
    (w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)
    ( V3
        (w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2)
        (w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2)
        (w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2)
    )

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Identity quaternion (no rotation).
identityQuat :: Quaternion
identityQuat = Quaternion 1 (V3 0 0 0)

-- | Sentinel value for root parent.
rootParent :: Int
rootParent = -1

-- | Look up a joint by ID, falling back to a default.
lookupJoint :: Skeleton -> Int -> Joint
lookupJoint skel jid =
  IntMap.findWithDefault (Joint jid rootParent vzero) jid (skelJoints skel)

-- | Threshold above which slerp falls back to normalized lerp.
slerpThreshold :: Float
slerpThreshold = 0.9995
