-- | Core data types shared across all modules.
--
-- Vector types, vertex and mesh representations, mesh combination
-- with index offset arithmetic, and validation predicates.
module GBMesh.Types
  ( -- * Vector types
    V2 (..),
    V3 (..),
    V4 (..),
    Quaternion (..),

    -- * Vector space abstraction
    VecSpace (..),

    -- * V2 operations
    dot2,
    vlength2,
    normalize2,
    vlerp2,

    -- * V3 operations
    dot,
    cross,
    vlength,
    normalize,
    vlerp,

    -- * Quaternion operations
    axisAngle,
    mulQuat,
    inverseQuat,
    slerpQuat,
    rotateV3,

    -- * Scalar operations
    vlengthSq,
    vlengthSq2,
    distanceSq,

    -- * Re-exports
    Word32,

    -- * Core mesh types
    Vertex (..),
    Mesh (..),
    mkMesh,

    -- * Mesh validation
    validateMesh,
    validIndices,
    validTriangleCount,
    validNormals,

    -- * Shared helpers
    lerp,
    lerpFloat,
    pairwiseLerp,
    safeIndex,
    safeLast,
    safeNormalize,
    identityQuat,
    rootParent,
    clampF,
    nearZeroLength,
    groupTriangles,
    fastFloor,
    pickPerpendicular,
    applyIterations,
  )
where

import Data.List (foldl')
import Data.Word (Word32)

-- ----------------------------------------------------------------
-- Vector types
-- ----------------------------------------------------------------

-- | 2D vector. Used for UV coordinates.
data V2 = V2 !Float !Float
  deriving (Show, Eq)

-- | 3D vector. Used for positions and normals.
data V3 = V3 !Float !Float !Float
  deriving (Show, Eq)

-- | 4D vector. Used for tangents with bitangent handedness in w.
data V4 = V4 !Float !Float !Float !Float
  deriving (Show, Eq)

-- | Quaternion for rotations. Scalar part followed by vector part.
data Quaternion = Quaternion !Float !V3
  deriving (Show, Eq)

-- ----------------------------------------------------------------
-- Vector space abstraction
-- ----------------------------------------------------------------

-- | Types supporting addition, subtraction, and scalar multiplication.
-- Allows curve and surface algorithms to work over both 'V2' and 'V3'.
class VecSpace a where
  vzero :: a
  (^+^) :: a -> a -> a
  (^-^) :: a -> a -> a
  (*^) :: Float -> a -> a
  negateV :: a -> a
  negateV a = vzero ^-^ a

infixl 6 ^+^

infixl 6 ^-^

infixl 7 *^

instance VecSpace V2 where
  vzero = V2 0 0
  V2 x1 y1 ^+^ V2 x2 y2 = V2 (x1 + x2) (y1 + y2)
  V2 x1 y1 ^-^ V2 x2 y2 = V2 (x1 - x2) (y1 - y2)
  s *^ V2 x y = V2 (s * x) (s * y)

instance VecSpace V3 where
  vzero = V3 0 0 0
  V3 x1 y1 z1 ^+^ V3 x2 y2 z2 = V3 (x1 + x2) (y1 + y2) (z1 + z2)
  V3 x1 y1 z1 ^-^ V3 x2 y2 z2 = V3 (x1 - x2) (y1 - y2) (z1 - z2)
  s *^ V3 x y z = V3 (s * x) (s * y) (s * z)

instance VecSpace V4 where
  vzero = V4 0 0 0 0
  V4 x1 y1 z1 w1 ^+^ V4 x2 y2 z2 w2 = V4 (x1 + x2) (y1 + y2) (z1 + z2) (w1 + w2)
  V4 x1 y1 z1 w1 ^-^ V4 x2 y2 z2 w2 = V4 (x1 - x2) (y1 - y2) (z1 - z2) (w1 - w2)
  s *^ V4 x y z w = V4 (s * x) (s * y) (s * z) (s * w)

-- ----------------------------------------------------------------
-- V2 operations
-- ----------------------------------------------------------------

-- | Dot product of two 'V2' vectors.
dot2 :: V2 -> V2 -> Float
dot2 (V2 x1 y1) (V2 x2 y2) = x1 * x2 + y1 * y2

-- | Length of a 'V2' vector.
vlength2 :: V2 -> Float
vlength2 v = sqrt (dot2 v v)

-- | Normalize a 'V2' to unit length. Returns zero vector if input
-- length is below 'nearZeroLength'.
normalize2 :: V2 -> V2
normalize2 v
  | len < nearZeroLength = vzero
  | otherwise = (1.0 / len) *^ v
  where
    len = vlength2 v

-- | Linear interpolation between two 'V2' values.
vlerp2 :: Float -> V2 -> V2 -> V2
vlerp2 t from to = (1.0 - t) *^ from ^+^ t *^ to

-- ----------------------------------------------------------------
-- V3 operations
-- ----------------------------------------------------------------

-- | Dot product of two 'V3' vectors.
dot :: V3 -> V3 -> Float
dot (V3 x1 y1 z1) (V3 x2 y2 z2) = x1 * x2 + y1 * y2 + z1 * z2

-- | Cross product of two 'V3' vectors.
cross :: V3 -> V3 -> V3
cross (V3 x1 y1 z1) (V3 x2 y2 z2) =
  V3
    (y1 * z2 - z1 * y2)
    (z1 * x2 - x1 * z2)
    (x1 * y2 - y1 * x2)

-- | Length of a 'V3' vector.
vlength :: V3 -> Float
vlength v = sqrt (dot v v)

-- | Normalize a 'V3' to unit length. Returns zero vector if input
-- length is below 'nearZeroLength'.
normalize :: V3 -> V3
normalize v
  | len < nearZeroLength = vzero
  | otherwise = (1.0 / len) *^ v
  where
    len = vlength v

-- | Linear interpolation between two 'V3' values.
vlerp :: Float -> V3 -> V3 -> V3
vlerp t from to = (1.0 - t) *^ from ^+^ t *^ to

-- ----------------------------------------------------------------
-- Quaternion operations
-- ----------------------------------------------------------------

-- | Construct a quaternion from a unit axis and angle in radians.
axisAngle :: V3 -> Float -> Quaternion
axisAngle axis angle = Quaternion (cos halfAngle) (sin halfAngle *^ axis)
  where
    halfAngle = angle * 0.5

-- | Rotate a 'V3' by a quaternion using the optimized Rodrigues
-- formula: @p + 2w(v × p) + 2(v × (v × p))@.
rotateV3 :: Quaternion -> V3 -> V3
rotateV3 (Quaternion w v) p =
  p ^+^ (2.0 * w) *^ vCrossP ^+^ 2.0 *^ cross v vCrossP
  where
    vCrossP = cross v p

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

-- | Conjugate of a unit quaternion, which is also its inverse.
inverseQuat :: Quaternion -> Quaternion
inverseQuat (Quaternion w (V3 x y z)) =
  Quaternion w (V3 (negate x) (negate y) (negate z))

-- | Spherical linear interpolation between two quaternions.
-- Takes the shortest path (negates if dot product is negative).
slerpQuat :: Float -> Quaternion -> Quaternion -> Quaternion
slerpQuat t (Quaternion w1 (V3 x1 y1 z1)) (Quaternion w2 (V3 x2 y2 z2)) =
  let rawDot = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
      -- Take shortest path
      (cosTheta, w2a, x2a, y2a, z2a) =
        if rawDot < 0
          then (negate rawDot, negate w2, negate x2, negate y2, negate z2)
          else (rawDot, w2, x2, y2, z2)
   in if cosTheta > slerpThreshold
        then -- Near-parallel: use normalized lerp to avoid division by zero
          let w = w1 + t * (w2a - w1)
              x = x1 + t * (x2a - x1)
              y = y1 + t * (y2a - y1)
              z = z1 + t * (z2a - z1)
              invLen = 1.0 / sqrt (w * w + x * x + y * y + z * z)
           in Quaternion (w * invLen) (V3 (x * invLen) (y * invLen) (z * invLen))
        else
          let theta = acos (min 1.0 (max (-1.0) cosTheta))
              sinTheta = sin theta
              scaleA = sin ((1 - t) * theta) / sinTheta
              scaleB = sin (t * theta) / sinTheta
              w = scaleA * w1 + scaleB * w2a
              x = scaleA * x1 + scaleB * x2a
              y = scaleA * y1 + scaleB * y2a
              z = scaleA * z1 + scaleB * z2a
           in Quaternion w (V3 x y z)

-- | Threshold above which slerp falls back to normalized lerp.
slerpThreshold :: Float
slerpThreshold = 0.9995

-- ----------------------------------------------------------------
-- Scalar operations
-- ----------------------------------------------------------------

-- | Squared length of a 'V3' vector. Avoids the sqrt in 'vlength',
-- useful for distance comparisons.
vlengthSq :: V3 -> Float
vlengthSq v = dot v v

-- | Squared length of a 'V2' vector.
vlengthSq2 :: V2 -> Float
vlengthSq2 v = dot2 v v

-- | Squared Euclidean distance between two 'V3' vectors.
-- Avoids the @sqrt@ in a full distance computation, useful for
-- proximity comparisons.
distanceSq :: V3 -> V3 -> Float
distanceSq a b = vlengthSq (a ^-^ b)

-- ----------------------------------------------------------------
-- VecSpace Float instance
-- ----------------------------------------------------------------

instance VecSpace Float where
  vzero = 0
  (^+^) = (+)
  (^-^) = (-)
  s *^ x = s * x

-- ----------------------------------------------------------------
-- Core mesh types
-- ----------------------------------------------------------------

-- | A vertex with position, normal, UV coordinates, and tangent.
--
-- Tangent w stores bitangent handedness (+1 or −1). The engine
-- reconstructs the bitangent as @cross(normal, tangent.xyz) * tangent.w@.
data Vertex = Vertex
  { vPosition :: !V3,
    vNormal :: !V3,
    vUV :: !V2,
    vTangent :: !V4
  }
  deriving (Show, Eq)

-- | An indexed triangle mesh. Every three indices form one triangle.
-- Index values are offsets into the vertex list.
--
-- 'Mesh' is a 'Monoid': 'mempty' is the empty mesh, and '<>' merges
-- meshes with index offset arithmetic.
data Mesh = Mesh
  { meshVertices :: ![Vertex],
    meshIndices :: ![Word32],
    meshVertexCount :: !Int
  }
  deriving (Show, Eq)

-- | Construct a 'Mesh' from vertices and indices, computing the
-- vertex count automatically.
mkMesh :: [Vertex] -> [Word32] -> Mesh
mkMesh vs is = Mesh vs is (length vs)

instance Semigroup Mesh where
  Mesh verticesA indicesA countA <> Mesh verticesB indicesB countB =
    Mesh
      (verticesA ++ verticesB)
      (indicesA ++ map (+ offset) indicesB)
      (countA + countB)
    where
      offset = fromIntegral countA

instance Monoid Mesh where
  mempty = Mesh [] [] 0

-- ----------------------------------------------------------------
-- Mesh validation
-- ----------------------------------------------------------------

-- | Check that a mesh is well-formed: all indices are valid, the
-- index count is divisible by 3, and all normals are approximately
-- unit length (within a tolerance of 0.01).
validateMesh :: Mesh -> Bool
validateMesh mesh =
  validIndices mesh
    && validTriangleCount mesh
    && validNormals validateNormalTolerance mesh

-- | Normal tolerance used by 'validateMesh'.
validateNormalTolerance :: Float
validateNormalTolerance = 0.01

-- | Check that all indices reference valid vertex positions.
validIndices :: Mesh -> Bool
validIndices (Mesh _ indices vertexCount) =
  all (\idx -> fromIntegral idx < vertexCount) indices

-- | Check that the index count is divisible by 3 (complete triangles).
validTriangleCount :: Mesh -> Bool
validTriangleCount (Mesh _ indices _) = length indices `mod` 3 == 0

-- | Check that all vertex normals are approximately unit length.
-- The tolerance specifies the maximum deviation from 1.
validNormals :: Float -> Mesh -> Bool
validNormals tolerance (Mesh vertices _ _) =
  all isUnitNormal vertices
  where
    isUnitNormal v = abs (vlength (vNormal v) - 1.0) < tolerance

-- ----------------------------------------------------------------
-- Shared helpers
-- ----------------------------------------------------------------

-- | Generic linear interpolation for any 'VecSpace'.
lerp :: (VecSpace a) => Float -> a -> a -> a
lerp t from to = (1.0 - t) *^ from ^+^ t *^ to

-- | Linear interpolation between two 'Float' values.
lerpFloat :: Float -> Float -> Float -> Float
lerpFloat t from to = from + t * (to - from)

-- | Pairwise lerp across adjacent list elements.
-- Used by De Casteljau and other subdivision algorithms.
pairwiseLerp :: (VecSpace a) => Float -> [a] -> [a]
pairwiseLerp t pts = zipWith (lerp t) pts (drop 1 pts)

-- | Total safe list indexing. Returns 'Nothing' for out-of-bounds.
safeIndex :: [a] -> Int -> Maybe a
safeIndex [] _ = Nothing
safeIndex (x : _) 0 = Just x
safeIndex (_ : rest) n
  | n < 0 = Nothing
  | otherwise = safeIndex rest (n - 1)

-- | Total safe extraction of the last element.
safeLast :: [a] -> Maybe a
safeLast [] = Nothing
safeLast [x] = Just x
safeLast (_ : rest) = safeLast rest

-- | Normalize a 'V3' to unit length with an explicit fallback vector
-- for near-zero inputs. Uses 'nearZeroLength' as the threshold.
safeNormalize :: V3 -> V3 -> V3
safeNormalize fallback v
  | len < nearZeroLength = fallback
  | otherwise = (1.0 / len) *^ v
  where
    len = vlength v

-- | Identity quaternion (no rotation).
identityQuat :: Quaternion
identityQuat = Quaternion 1 (V3 0 0 0)

-- | Sentinel value for joints with no parent.
rootParent :: Int
rootParent = -1

-- | Clamp a value to a range.
clampF :: Float -> Float -> Float -> Float
clampF lo hi x = max lo (min hi x)

-- | Threshold below which a vector is considered zero-length.
-- Set to @1e-6@, above the 'Float' precision floor (~1.2e-7),
-- to avoid false negatives from accumulated rounding error.
nearZeroLength :: Float
nearZeroLength = 1.0e-6

-- | Group a flat index list into triples representing triangles.
groupTriangles :: [Word32] -> [(Word32, Word32, Word32)]
groupTriangles (a : b : c : rest) = (a, b, c) : groupTriangles rest
groupTriangles _ = []

-- | Fast floor: convert a 'Float' to the nearest 'Int' below it.
-- Uses truncation with correction for negative numbers.
fastFloor :: Float -> Int
fastFloor x =
  let truncated = truncate x :: Int
   in if fromIntegral truncated > x
        then truncated - 1
        else truncated

-- | Choose a vector perpendicular to the input. The input must be
-- normalized. Picks the cardinal axis least aligned with the input
-- to maximize numerical stability.
pickPerpendicular :: V3 -> V3
pickPerpendicular v@(V3 vx vy vz)
  | abs vx <= abs vy && abs vx <= abs vz = normalize (cross v (V3 1 0 0))
  | abs vy <= abs vz = normalize (cross v (V3 0 1 0))
  | otherwise = normalize (cross v (V3 0 0 1))

-- | Apply a transformation @n@ times.
applyIterations :: Int -> (a -> a) -> a -> a
applyIterations n step x = foldl' (\acc _ -> step acc) x [1 .. n]
