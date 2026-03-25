-- | Pure animation functions from time to pose.
--
-- Procedural generators for common motion patterns (walk, idle,
-- breathe) and combinators for blending, sequencing, and looping.
-- Same concept as gb-sprite's @fromProcedural@.
module GBMesh.Animate
  ( -- * Animation type
    Animation,

    -- * Procedural generators
    walkCycle,
    idleCycle,
    breatheCycle,

    -- * Composition
    blendAnimations,
    sequenceAnimations,
    loopAnimation,
    reverseAnimation,
    constantPose,
  )
where

import GBMesh.Pose
import GBMesh.Types

-- ----------------------------------------------------------------
-- Animation type
-- ----------------------------------------------------------------

-- | An animation is a pure function from time (in seconds) to
-- a 'Pose'. All procedural generators produce loopable cycles
-- parameterized by cycle duration.
type Animation = Float -> Pose

-- ----------------------------------------------------------------
-- Procedural generators
-- ----------------------------------------------------------------

-- | A walking cycle. Hip flexion drives stepping, with
-- counter-rotation in the spine and arms. Cycle duration is
-- the period of one full left-right step.
--
-- Joint ID conventions follow 'humanoid':
-- 0=hips, 1=spine, 2=chest, 3=neck, 4=head,
-- 5-7=L arm, 8-10=R arm, 11-13=L leg, 14-16=R leg.
walkCycle :: Float -> Animation
walkCycle cycleDuration time =
  fromList
    [ -- Hips: subtle lateral sway
      (0, axisAngle (V3 0 0 1) (hipSwayAmplitude * sinPhase)),
      -- Spine: counter-rotate against hips
      (1, axisAngle (V3 0 1 0) (spineRotateAmplitude * sinPhase)),
      -- Left leg: hip flexion
      (11, axisAngle (V3 1 0 0) (legSwingAmplitude * sinPhase)),
      -- Left knee: flex on forward swing
      (12, axisAngle (V3 1 0 0) (kneeFlexAmplitude * max 0 sinPhase)),
      -- Right leg: opposite phase
      (14, axisAngle (V3 1 0 0) (legSwingAmplitude * negate sinPhase)),
      -- Right knee
      (15, axisAngle (V3 1 0 0) (kneeFlexAmplitude * max 0 (negate sinPhase))),
      -- Left arm: counter-swing to legs
      (5, axisAngle (V3 1 0 0) (armSwingAmplitude * negate sinPhase)),
      -- Right arm
      (8, axisAngle (V3 1 0 0) (armSwingAmplitude * sinPhase))
    ]
  where
    phase = cyclePhase cycleDuration time
    sinPhase = sin (twoPi * phase)

-- | A gentle idle cycle. Subtle breathing sway and weight shift.
idleCycle :: Float -> Animation
idleCycle cycleDuration time =
  fromList
    [ -- Spine: gentle forward-back sway
      (1, axisAngle (V3 1 0 0) (idleSwayAmplitude * sinPhase)),
      -- Hips: subtle lateral weight shift at half frequency
      (0, axisAngle (V3 0 0 1) (idleHipAmplitude * sin (pi * phase))),
      -- Head: slight look variation
      (3, axisAngle (V3 0 1 0) (idleHeadAmplitude * sin (twoPi * phase * idleHeadFreqRatio)))
    ]
  where
    phase = cyclePhase cycleDuration time
    sinPhase = sin (twoPi * phase)

-- | A breathing cycle. Chest expands and contracts, shoulders
-- rise slightly.
breatheCycle :: Float -> Animation
breatheCycle cycleDuration time =
  fromList
    [ -- Chest: expand forward
      (2, axisAngle (V3 1 0 0) (breatheChestAmplitude * sinPhase)),
      -- Shoulders rise slightly
      (5, axisAngle (V3 0 0 1) (breatheShoulderAmplitude * sinPhase)),
      (8, axisAngle (V3 0 0 1) (negate (breatheShoulderAmplitude * sinPhase)))
    ]
  where
    phase = cyclePhase cycleDuration time
    sinPhase = sin (twoPi * phase)

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

-- | Play an animation in reverse.
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

-- ----------------------------------------------------------------
-- Animation amplitude constants
-- ----------------------------------------------------------------

-- Walk cycle

-- | Hip lateral sway amplitude (radians).
hipSwayAmplitude :: Float
hipSwayAmplitude = 0.04

-- | Spine counter-rotation amplitude (radians).
spineRotateAmplitude :: Float
spineRotateAmplitude = 0.06

-- | Leg swing amplitude at hip (radians).
legSwingAmplitude :: Float
legSwingAmplitude = 0.4

-- | Knee flexion amplitude (radians).
kneeFlexAmplitude :: Float
kneeFlexAmplitude = 0.6

-- | Arm counter-swing amplitude (radians).
armSwingAmplitude :: Float
armSwingAmplitude = 0.25

-- Idle cycle

-- | Idle spine sway amplitude (radians).
idleSwayAmplitude :: Float
idleSwayAmplitude = 0.02

-- | Idle hip weight-shift amplitude (radians).
idleHipAmplitude :: Float
idleHipAmplitude = 0.015

-- | Idle head look amplitude (radians).
idleHeadAmplitude :: Float
idleHeadAmplitude = 0.03

-- | Idle head frequency ratio relative to base cycle.
idleHeadFreqRatio :: Float
idleHeadFreqRatio = 0.7

-- Breathe cycle

-- | Breathe chest expansion amplitude (radians).
breatheChestAmplitude :: Float
breatheChestAmplitude = 0.03

-- | Breathe shoulder rise amplitude (radians).
breatheShoulderAmplitude :: Float
breatheShoulderAmplitude = 0.02
