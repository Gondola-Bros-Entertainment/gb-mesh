-- | Inverse kinematics solvers — CCD and FABRIK.
--
-- Two complementary IK solvers for articulated skeletons. CCD
-- (Cyclic Coordinate Descent) is simple and robust for real-time
-- use. FABRIK (Forward And Backward Reaching Inverse Kinematics)
-- produces natural-looking results by operating in position space.
module GBMesh.IK
  ( -- * IK solvers
    solveCCD,
    solveFABRIK,

    -- * Helpers
    lookAt,
  )
where

import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List (foldl')
import GBMesh.Pose
import GBMesh.Skeleton
import GBMesh.Types

-- ----------------------------------------------------------------
-- Named constants
-- ----------------------------------------------------------------

-- | Convergence threshold for CCD: squared distance from end
-- effector to target below which we consider the chain converged.
ccdConvergenceThresholdSq :: Float
ccdConvergenceThresholdSq = 1.0e-6

-- | Minimum axis length for cross-product rotation axis. Below
-- this the vectors are nearly parallel or anti-parallel.
minAxisLength :: Float
minAxisLength = 1.0e-7

-- | Dot product is clamped to this range before passing to 'acos'.
dotClampMin :: Float
dotClampMin = -1.0

-- | Upper bound for dot clamp.
dotClampMax :: Float
dotClampMax = 1.0

-- | Identity quaternion (no rotation).
identityQuat :: Quaternion
identityQuat = Quaternion 1 (V3 0 0 0)

-- | Sentinel value for root parent.
rootParent :: Int
rootParent = -1

-- | The +Y unit vector, used as the default forward direction
-- for 'lookAt'.
yAxis :: V3
yAxis = V3 0 1 0

-- ----------------------------------------------------------------
-- CCD solver
-- ----------------------------------------------------------------

-- | CCD (Cyclic Coordinate Descent) IK solver.
--
-- Given a skeleton, an initial pose, a chain of joint IDs (ordered
-- from root to end effector), a target position, and a maximum
-- iteration count, iteratively adjusts joint rotations so the end
-- effector approaches the target.
--
-- Each iteration sweeps from the end-effector's parent back to the
-- chain root. For each joint it computes the rotation that aligns
-- the vector from the joint to the current end-effector position
-- with the vector from the joint to the target, then composes that
-- rotation into the joint's local rotation.
--
-- Returns the modified pose. The chain must contain at least two
-- joints (one parent and the end effector).
solveCCD :: Skeleton -> Pose -> [Int] -> V3 -> Int -> Pose
solveCCD _ pose [] _ _ = pose
solveCCD _ pose [_] _ _ = pose
solveCCD skel pose chain target maxIter =
  ccdLoop pose 0
  where
    endEffectorId = lastInt chain

    ccdLoop !currentPose !iter
      | iter >= maxIter = currentPose
      | effectorCloseEnough currentPose = currentPose
      | otherwise =
          let updatedPose = sweepChain skel currentPose chain endEffectorId target
           in ccdLoop updatedPose (iter + 1)

    effectorCloseEnough currentPose =
      let worldPositions = applyPose skel currentPose
          effectorPos = IntMap.findWithDefault vzero endEffectorId worldPositions
          delta = target ^-^ effectorPos
       in vlengthSq delta < ccdConvergenceThresholdSq

-- | One CCD sweep: iterate from end-effector parent back to chain
-- root, adjusting each joint's rotation.
sweepChain :: Skeleton -> Pose -> [Int] -> Int -> V3 -> Pose
sweepChain skel pose chain endEffectorId target =
  foldl' (adjustJoint skel endEffectorId target) pose sweepOrder
  where
    -- Reverse the chain minus the end effector: sweep from
    -- end-effector parent back to chain root.
    sweepOrder = reverse (initSafe chain)

-- | Adjust a single joint's rotation so the end effector moves
-- toward the target.
adjustJoint :: Skeleton -> Int -> V3 -> Pose -> Int -> Pose
adjustJoint skel endEffectorId target pose jointId =
  let worldPositions = applyPose skel pose
      worldRotations = applyPoseRotations skel pose
      jointPos = IntMap.findWithDefault vzero jointId worldPositions
      effectorPos = IntMap.findWithDefault vzero endEffectorId worldPositions
      toEffector = normalize (effectorPos ^-^ jointPos)
      toTarget = normalize (target ^-^ jointPos)
      deltaRot = rotationBetween toEffector toTarget
      -- Transform the world-space delta rotation into the joint's
      -- local space: localDelta = inverse(worldRot) * deltaRot * worldRot
      worldRot = IntMap.findWithDefault identityQuat jointId worldRotations
      localDelta = mulQuat (inverseQuat worldRot) (mulQuat deltaRot worldRot)
      currentLocal = IntMap.findWithDefault identityQuat jointId pose
      newLocal = mulQuat currentLocal localDelta
   in IntMap.insert jointId newLocal pose

-- ----------------------------------------------------------------
-- FABRIK solver
-- ----------------------------------------------------------------

-- | FABRIK (Forward And Backward Reaching Inverse Kinematics) solver.
--
-- Operates in position space: alternately pulls the chain toward
-- the target (forward reaching) and anchors the root back to its
-- original position (backward reaching). After convergence, converts
-- the resulting world positions back to local rotations.
--
-- Parameters: skeleton, initial pose, chain joint IDs (root to end
-- effector), target position, distance tolerance, max iterations.
--
-- The chain must contain at least two joints.
solveFABRIK :: Skeleton -> Pose -> [Int] -> V3 -> Float -> Int -> Pose
solveFABRIK _ pose [] _ _ _ = pose
solveFABRIK _ pose [_] _ _ _ = pose
solveFABRIK skel pose chain target tolerance maxIter =
  let worldPositions = applyPose skel pose
      chainPositions = map (\jid -> IntMap.findWithDefault vzero jid worldPositions) chain
      boneLengths = zipWith (\posA posB -> vlength (posB ^-^ posA)) chainPositions (drop 1 chainPositions)
      rootPos = case chainPositions of
        (p : _) -> p
        [] -> vzero -- unreachable: chain has >= 2 elements
      finalPositions = fabrikLoop chainPositions boneLengths rootPos 0
   in positionsToLocalRotations skel pose chain finalPositions
  where
    fabrikLoop !positions !lengths !anchorPos !iter
      | iter >= maxIter = positions
      | converged positions = positions
      | otherwise =
          let forwardPositions = forwardReach positions lengths target
              backwardPositions = backwardReach forwardPositions lengths anchorPos
           in fabrikLoop backwardPositions lengths anchorPos (iter + 1)

    converged chainPos =
      let effectorPos = lastV3 chainPos
          delta = target ^-^ effectorPos
       in vlength delta < tolerance

-- | Forward reaching pass: set end effector to target, then walk
-- backward placing each joint at bone-length distance from the next.
forwardReach :: [V3] -> [Float] -> V3 -> [V3]
forwardReach positions lengths target =
  reverse (foldl' step [target] (zip (reverse (initSafe positions)) (reverse lengths)))
  where
    step :: [V3] -> (V3, Float) -> [V3]
    step [] _ = [] -- unreachable
    step acc@(nextPos : _) (currentPos, boneLen) =
      let direction = normalize (currentPos ^-^ nextPos)
          adjustedDir =
            if vlengthSq direction < minAxisLength
              then yAxis
              else direction
          newPos = nextPos ^+^ boneLen *^ adjustedDir
       in newPos : acc

-- | Backward reaching pass: set root to original position, then walk
-- forward placing each joint at bone-length distance from the previous.
backwardReach :: [V3] -> [Float] -> V3 -> [V3]
backwardReach positions lengths anchorPos =
  reverse (foldl' step [anchorPos] (zip (drop 1 positions) lengths))
  where
    step :: [V3] -> (V3, Float) -> [V3]
    step [] _ = [] -- unreachable
    step acc@(prevPos : _) (currentPos, boneLen) =
      let direction = normalize (currentPos ^-^ prevPos)
          adjustedDir =
            if vlengthSq direction < minAxisLength
              then yAxis
              else direction
          newPos = prevPos ^+^ boneLen *^ adjustedDir
       in newPos : acc

-- | Convert FABRIK's world-space chain positions back to local
-- rotations. For each consecutive pair of joints in the chain,
-- compute the rotation that maps the original bone direction to
-- the new bone direction in the parent's local frame.
positionsToLocalRotations :: Skeleton -> Pose -> [Int] -> [V3] -> Pose
positionsToLocalRotations skel pose chain newPositions =
  fst (foldl' stepJoint (pose, origWorldRotations) bonePairs)
  where
    origWorldPositions = applyPose skel pose
    origWorldRotations = applyPoseRotations skel pose
    -- Build (jointId, newPos) pairs for the chain
    chainPairs = zip chain newPositions
    -- Consecutive pairs represent bones from parent to child
    bonePairs = zip chainPairs (drop 1 chainPairs)

    stepJoint :: (Pose, IntMap Quaternion) -> ((Int, V3), (Int, V3)) -> (Pose, IntMap Quaternion)
    stepJoint (!currentPose, !accWorldRots) ((parentJid, parentNewPos), (childJid, childNewPos)) =
      let -- Original bone direction in world space
          origParentPos = IntMap.findWithDefault vzero parentJid origWorldPositions
          origChildPos = IntMap.findWithDefault vzero childJid origWorldPositions
          origDir = normalize (origChildPos ^-^ origParentPos)
          -- New bone direction in world space
          newDir = normalize (childNewPos ^-^ parentNewPos)
          -- World-space delta rotation from original to new direction
          worldDelta = rotationBetween origDir newDir
          -- Current accumulated world rotation for this joint
          currentWorldRot = IntMap.findWithDefault identityQuat parentJid accWorldRots
          -- Apply the delta in world space to get the new world rotation
          updatedWorldRot = mulQuat worldDelta currentWorldRot
          -- Convert to local: localRot = inverse(parentWorldRot) * updatedWorldRot
          joint = IntMap.findWithDefault (Joint parentJid rootParent vzero) parentJid (skelJoints skel)
          parentOfParentWorldRot =
            if jointParent joint == rootParent
              then identityQuat
              else IntMap.findWithDefault identityQuat (jointParent joint) accWorldRots
          newLocalRot = mulQuat (inverseQuat parentOfParentWorldRot) updatedWorldRot
          updatedPose = IntMap.insert parentJid newLocalRot currentPose
          updatedWorldRots = IntMap.insert parentJid updatedWorldRot accWorldRots
       in (updatedPose, updatedWorldRots)

-- ----------------------------------------------------------------
-- lookAt
-- ----------------------------------------------------------------

-- | Compute the quaternion that rotates the +Y direction to point
-- from @source@ toward @destination@.
--
-- If the two points coincide (distance below threshold), returns
-- the identity quaternion.
lookAt :: V3 -> V3 -> Quaternion
lookAt source destination =
  let direction = normalize (destination ^-^ source)
   in if vlengthSq direction < minAxisLength
        then identityQuat
        else rotationBetween yAxis direction

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Compute the quaternion that rotates unit vector @from@ to align
-- with unit vector @to@. Uses the cross product as rotation axis
-- and acos(dot) as the angle. Returns identity for near-parallel
-- vectors and a 180-degree rotation for near-antiparallel vectors.
rotationBetween :: V3 -> V3 -> Quaternion
rotationBetween from to =
  let d = clampF dotClampMin dotClampMax (dot from to)
      axis = cross from to
      axisLen = vlength axis
   in if axisLen < minAxisLength
        then
          if d > 0
            then identityQuat
            else -- Nearly opposite: pick an arbitrary perpendicular axis
              let perp = findPerpendicular from
               in axisAngle perp pi
        else
          let angle = acos d
           in axisAngle (normalize axis) angle

-- | Find a vector perpendicular to the given vector. Picks the
-- coordinate axis least aligned with the input to maximize
-- numerical stability.
findPerpendicular :: V3 -> V3
findPerpendicular (V3 x y z) =
  let absX = abs x
      absY = abs y
      absZ = abs z
   in if absX <= absY && absX <= absZ
        then normalize (cross (V3 x y z) (V3 1 0 0))
        else
          if absY <= absZ
            then normalize (cross (V3 x y z) (V3 0 1 0))
            else normalize (cross (V3 x y z) (V3 0 0 1))

-- | Clamp a float to the given range.
clampF :: Float -> Float -> Float -> Float
clampF lo hi val = max lo (min hi val)

-- | Compute world-space rotations for all joints via forward
-- kinematics. Mirrors 'applyPose' but returns the rotation map
-- instead of the position map.
applyPoseRotations :: Skeleton -> Pose -> IntMap Quaternion
applyPoseRotations skel pose = rotations
  where
    (_, rotations) = go (IntMap.empty, IntMap.empty) (skelRoot skel)

    go (!posAcc, !rotAcc) jid =
      let joint = IntMap.findWithDefault (Joint jid rootParent vzero) jid (skelJoints skel)
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
          posWithSelf = IntMap.insert jid worldPos posAcc
          rotWithSelf = IntMap.insert jid worldRot rotAcc
       in foldl' go (posWithSelf, rotWithSelf) (skelChildren skel jid)

-- | Safe last element for 'V3' lists. Returns 'vzero' for empty
-- lists. Only used for position lists that are guaranteed non-empty
-- by the caller guards.
lastV3 :: [V3] -> V3
lastV3 [] = vzero
lastV3 [x] = x
lastV3 (_ : xs) = lastV3 xs

-- | Safe last element for 'Int' lists. Returns @0@ for empty lists.
-- Only used for chain ID lists that are guaranteed non-empty by
-- the caller guards.
lastInt :: [Int] -> Int
lastInt [] = 0
lastInt [x] = x
lastInt (_ : xs) = lastInt xs

-- | Safe init: all elements except the last. Returns empty for
-- empty or singleton lists.
initSafe :: [a] -> [a]
initSafe [] = []
initSafe [_] = []
initSafe (x : xs) = x : initSafe xs
