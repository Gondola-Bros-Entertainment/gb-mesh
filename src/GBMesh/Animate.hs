-- | Pure animation functions from time to pose.
--
-- Generic building blocks for procedural animation on any skeleton
-- topology. Compose single-joint oscillators into complex motions.
-- Same concept as gb-sprite's @fromProcedural@.
module GBMesh.Animate
  ( -- * Animation type
    Animation,

    -- * Building blocks
    oscillate,
    oscillatePositive,
    combine,
    delay,
    timeScale,

    -- * Composition
    blendAnimations,
    sequenceAnimations,
    loopAnimation,
    reverseAnimation,
    constantPose,
  )
where

import Data.IntMap.Strict qualified as IntMap
import Data.List (foldl')
import GBMesh.Pose
import GBMesh.Types

-- ----------------------------------------------------------------
-- Animation type
-- ----------------------------------------------------------------

-- | An animation is a pure function from time (in seconds) to
-- a 'Pose'. Compose with 'combine' to build multi-joint
-- animations from single-joint building blocks.
type Animation = Float -> Pose

-- ----------------------------------------------------------------
-- Building blocks
-- ----------------------------------------------------------------

-- | Oscillate a single joint sinusoidally around an axis.
--
-- @oscillate jointId axis amplitude cycleDuration@ produces a
-- rotation of @amplitude * sin(2π * t / cycleDuration)@ radians
-- around @axis@ for joint @jointId@.
--
-- Negate the amplitude for opposite phase. This is the
-- fundamental animation primitive — all procedural motion is
-- built from compositions of oscillators.
oscillate :: Int -> V3 -> Float -> Float -> Animation
oscillate jointId axis amplitude cycleDuration time =
  singleJoint jointId (axisAngle axis (amplitude * sinPhase))
  where
    sinPhase = sin (twoPi * cyclePhase cycleDuration time)

-- | Like 'oscillate' but only the positive half of the sine
-- wave. Useful for joints that only bend one direction (knees,
-- elbows, jaw).
--
-- @oscillatePositive jointId axis amplitude cycleDuration@
oscillatePositive :: Int -> V3 -> Float -> Float -> Animation
oscillatePositive jointId axis amplitude cycleDuration time =
  singleJoint jointId (axisAngle axis (amplitude * max 0 sinPhase))
  where
    sinPhase = sin (twoPi * cyclePhase cycleDuration time)

-- | Merge multiple animations into one. Each animation typically
-- affects different joints. If two animations affect the same
-- joint, the earlier entry in the list takes priority.
--
-- This is the primary way to build multi-joint animations:
--
-- @
-- myWalk duration = combine
--   [ oscillate hipJoint    (V3 0 0 1) 0.04 duration
--   , oscillate spineJoint  (V3 0 1 0) 0.06 duration
--   , oscillate leftLeg     (V3 1 0 0) 0.4  duration
--   , oscillate rightLeg    (V3 1 0 0) (-0.4) duration
--   ]
-- @
combine :: [Animation] -> Animation
combine animations time =
  foldl' IntMap.union IntMap.empty (map (\anim -> anim time) animations)

-- | Shift an animation forward in time by a fixed offset.
--
-- @delay offset anim@ evaluates @anim@ at @time - offset@.
-- Useful for phase-offsetting symmetric joints (e.g., delay a
-- leg swing by half the cycle for the opposite leg).
delay :: Float -> Animation -> Animation
delay offset anim time = anim (time - offset)

-- | Scale the playback speed of an animation.
--
-- @timeScale factor anim@ evaluates @anim@ at @time * factor@.
-- Factor > 1 speeds up, < 1 slows down, negative reverses.
timeScale :: Float -> Animation -> Animation
timeScale factor anim time = anim (time * factor)

-- ----------------------------------------------------------------
-- Composition
-- ----------------------------------------------------------------

-- | Blend two animations by interpolating their poses at each
-- time step. @t = 0@ is fully the first animation, @t = 1@ is
-- fully the second.
blendAnimations :: Float -> Animation -> Animation -> Animation
blendAnimations blendFactor animA animB time =
  lerpPose blendFactor (animA time) (animB time)

-- | Sequence animations end-to-end. Each entry is
-- @(duration, animation)@. Time wraps around the total duration.
-- Returns 'restPose' if the list is empty.
sequenceAnimations :: [(Float, Animation)] -> Animation
sequenceAnimations [] _ = restPose
sequenceAnimations segments time =
  let totalDuration = sum (map fst segments)
      wrappedTime =
        if totalDuration <= 0
          then 0
          else modFloat time totalDuration
   in findSegment wrappedTime segments

-- | Loop an animation over a fixed duration. Time is taken
-- modulo the duration.
loopAnimation :: Float -> Animation -> Animation
loopAnimation duration anim time
  | duration <= 0 = anim 0
  | otherwise = anim (modFloat time duration)

-- | Play an animation in reverse over a fixed duration.
reverseAnimation :: Float -> Animation -> Animation
reverseAnimation duration anim time =
  anim (duration - modFloat time duration)

-- | An animation that always returns the same pose.
constantPose :: Pose -> Animation
constantPose pose _ = pose

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Compute the normalized phase [0, 1) for a cycle.
cyclePhase :: Float -> Float -> Float
cyclePhase duration time
  | duration <= 0 = 0
  | otherwise = modFloat time duration / duration

-- | Floating-point modulo that always returns a non-negative
-- result.
modFloat :: Float -> Float -> Float
modFloat x y = x - y * fromIntegral (floor (x / y) :: Int)

-- | Find which segment contains the given time and evaluate it.
findSegment :: Float -> [(Float, Animation)] -> Pose
findSegment _ [] = restPose
findSegment time ((dur, anim) : rest)
  | time < dur || null rest = anim time
  | otherwise = findSegment (time - dur) rest

-- | Two times pi.
twoPi :: Float
twoPi = 2.0 * pi
