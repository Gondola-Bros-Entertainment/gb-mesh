{-# OPTIONS_GHC -fno-warn-orphans #-}

{- HLINT ignore "Monoid law, left identity" -}
{- HLINT ignore "Monoid law, right identity" -}

module Main (main) where

import GBMesh.Combine
import GBMesh.Types
import Test.Tasty
import Test.Tasty.QuickCheck as QC

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "gb-mesh"
    [ testGroup "Types" typesTests,
      testGroup "Combine" combineTests
    ]

-- ----------------------------------------------------------------
-- Arbitrary instances
-- ----------------------------------------------------------------

smallFloat :: Gen Float
smallFloat = choose (-100, 100)

instance Arbitrary V2 where
  arbitrary = V2 <$> smallFloat <*> smallFloat

instance Arbitrary V3 where
  arbitrary = V3 <$> smallFloat <*> smallFloat <*> smallFloat

instance Arbitrary V4 where
  arbitrary = V4 <$> smallFloat <*> smallFloat <*> smallFloat <*> smallFloat

arbitraryUnitV3 :: Gen V3
arbitraryUnitV3 = do
  x <- smallFloat
  y <- smallFloat
  z <- smallFloat
  let v = V3 x y z
      len = vlength v
  if len < 0.001
    then pure (V3 0 1 0)
    else pure (normalize v)

instance Arbitrary Quaternion where
  arbitrary = axisAngle <$> arbitraryUnitV3 <*> smallFloat

instance Arbitrary Vertex where
  arbitrary = do
    pos <- arbitrary
    normal <- arbitraryUnitV3
    uvU <- choose (0, 1)
    uvV <- choose (0, 1)
    tangentDir <- arbitraryUnitV3
    w <- elements [1.0, -1.0]
    let V3 tx ty tz = tangentDir
    pure (Vertex pos normal (V2 uvU uvV) (V4 tx ty tz w))

instance Arbitrary Mesh where
  arbitrary = do
    vertexCount <- choose (3, 30)
    vertices <- vectorOf vertexCount arbitrary
    triangleCount <- choose (1, 10)
    indices <-
      vectorOf
        (triangleCount * 3)
        (choose (0, fromIntegral vertexCount - 1))
    pure (Mesh vertices indices)

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------

approxEq :: Float -> Float -> Bool
approxEq a b = abs (a - b) < tolerance
  where
    tolerance = 1.0e-4

approxEqV3 :: V3 -> V3 -> Bool
approxEqV3 (V3 x1 y1 z1) (V3 x2 y2 z2) =
  approxEq x1 x2 && approxEq y1 y2 && approxEq z1 z2

-- ----------------------------------------------------------------
-- Types tests
-- ----------------------------------------------------------------

typesTests :: [TestTree]
typesTests =
  [ QC.testProperty "V3 vzero is additive identity" $
      \v -> approxEqV3 ((v :: V3) ^+^ vzero) v,
    QC.testProperty "V3 addition is commutative" $
      \a b -> approxEqV3 ((a :: V3) ^+^ b) (b ^+^ a),
    QC.testProperty "V3 scalar multiply by 1 is identity" $
      \v -> approxEqV3 (1.0 *^ (v :: V3)) v,
    QC.testProperty "V3 scalar multiply by 0 gives zero" $
      \v -> approxEqV3 (0.0 *^ (v :: V3)) vzero,
    QC.testProperty "dot product is commutative" $
      \a b -> approxEq (dot (a :: V3) b) (dot b a),
    QC.testProperty "cross product is antisymmetric" $
      \a b ->
        approxEqV3 (cross (a :: V3) b) ((-1) *^ cross b a),
    QC.testProperty "cross product is orthogonal to both inputs" $
      forAll ((,) <$> arbitraryUnitV3 <*> arbitraryUnitV3) $ \(a, b) ->
        let c = cross a b
         in approxEq (dot a c) 0 && approxEq (dot b c) 0,
    QC.testProperty "normalize produces unit length" $
      \v ->
        vlength (v :: V3) > 0.01 QC.==>
          approxEq (vlength (normalize v)) 1.0,
    QC.testProperty "normalize is idempotent" $
      \v ->
        vlength (v :: V3) > 0.01 QC.==>
          approxEqV3 (normalize (normalize v)) (normalize v),
    QC.testProperty "quaternion rotation preserves length" $
      \q v ->
        approxEq
          (vlength (v :: V3))
          (vlength (rotateV3 (q :: Quaternion) v)),
    QC.testProperty "identity quaternion is identity" $
      \v ->
        let identityQ = axisAngle (V3 0 1 0) 0
         in approxEqV3 (rotateV3 identityQ (v :: V3)) v,
    QC.testProperty "Mesh mempty is left identity" $
      \m ->
        meshVertices (mempty <> (m :: Mesh)) == meshVertices m
          && meshIndices (mempty <> m) == meshIndices m,
    QC.testProperty "Mesh mempty is right identity" $
      \m ->
        meshVertices ((m :: Mesh) <> mempty) == meshVertices m
          && meshIndices (m <> mempty) == meshIndices m,
    QC.testProperty "Mesh merge preserves vertex count" $
      \a b ->
        length (meshVertices ((a :: Mesh) <> b))
          == length (meshVertices a) + length (meshVertices b),
    QC.testProperty "Mesh merge preserves index count" $
      \a b ->
        length (meshIndices ((a :: Mesh) <> b))
          == length (meshIndices a) + length (meshIndices b),
    QC.testProperty "Mesh merge preserves index validity" $
      \a b ->
        validIndices (a :: Mesh) && validIndices b QC.==>
          validIndices (a <> b),
    QC.testProperty "generated meshes have valid indices" $
      \m -> validIndices (m :: Mesh),
    QC.testProperty "generated meshes have valid triangle count" $
      \m -> validTriangleCount (m :: Mesh),
    QC.testProperty "generated meshes have valid normals" $
      \m -> validNormals 1.0e-5 (m :: Mesh)
  ]

-- ----------------------------------------------------------------
-- Combine tests
-- ----------------------------------------------------------------

combineTests :: [TestTree]
combineTests =
  [ QC.testProperty "translate by zero is identity" $
      \m -> translate vzero (m :: Mesh) == m,
    QC.testProperty "translate preserves vertex count" $
      \v m ->
        length (meshVertices (translate (v :: V3) (m :: Mesh)))
          == length (meshVertices m),
    QC.testProperty "translate preserves index validity" $
      \v m ->
        validIndices (m :: Mesh) QC.==>
          validIndices (translate (v :: V3) m),
    QC.testProperty "uniformScale by 1 is identity" $
      \m -> uniformScale 1.0 (m :: Mesh) == m,
    QC.testProperty "uniformScale preserves index validity" $
      \s m ->
        validIndices (m :: Mesh) QC.==>
          validIndices (uniformScale (s :: Float) m),
    QC.testProperty "flipNormals is involutory" $
      \m -> flipNormals (flipNormals (m :: Mesh)) == m,
    QC.testProperty "reverseWinding is involutory" $
      \m -> reverseWinding (reverseWinding (m :: Mesh)) == m,
    QC.testProperty "merge empty list gives mempty" $
      merge [] == (mempty :: Mesh),
    QC.testProperty "merge singleton is identity" $
      \m -> merge [m :: Mesh] == m,
    QC.testProperty "rotate preserves vertex count" $
      \q m ->
        length (meshVertices (rotate (q :: Quaternion) (m :: Mesh)))
          == length (meshVertices m),
    QC.testProperty "rotate preserves index validity" $
      \q m ->
        validIndices (m :: Mesh) QC.==>
          validIndices (rotate (q :: Quaternion) m)
  ]
