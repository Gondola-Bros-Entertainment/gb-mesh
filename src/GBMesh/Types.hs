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
    rotateV3,

    -- * Core mesh types
    Vertex (..),
    Mesh (..),

    -- * Mesh validation
    validIndices,
    validTriangleCount,
    validNormals,
  )
where

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
    meshIndices :: ![Word32]
  }
  deriving (Show, Eq)

instance Semigroup Mesh where
  Mesh verticesA indicesA <> Mesh verticesB indicesB =
    Mesh
      (verticesA ++ verticesB)
      (indicesA ++ map (+ offset) indicesB)
    where
      offset = fromIntegral (length verticesA)

instance Monoid Mesh where
  mempty = Mesh [] []

-- ----------------------------------------------------------------
-- Mesh validation
-- ----------------------------------------------------------------

-- | Check that all indices reference valid vertex positions.
validIndices :: Mesh -> Bool
validIndices (Mesh vertices indices) =
  all (\idx -> fromIntegral idx < vertexCount) indices
  where
    vertexCount = length vertices

-- | Check that the index count is divisible by 3 (complete triangles).
validTriangleCount :: Mesh -> Bool
validTriangleCount (Mesh _ indices) = length indices `mod` 3 == 0

-- | Check that all vertex normals are approximately unit length.
-- The tolerance specifies the maximum deviation from 1.
validNormals :: Float -> Mesh -> Bool
validNormals tolerance (Mesh vertices _) =
  all isUnitNormal vertices
  where
    isUnitNormal v = abs (vlength (vNormal v) - 1.0) < tolerance

-- ----------------------------------------------------------------
-- Internal constants
-- ----------------------------------------------------------------

-- | Threshold below which a vector is considered zero-length.
nearZeroLength :: Float
nearZeroLength = 1.0e-10
