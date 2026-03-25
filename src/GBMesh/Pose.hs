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
