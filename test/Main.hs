{-# OPTIONS_GHC -fno-warn-orphans #-}

{- HLINT ignore "Monoid law, left identity" -}
{- HLINT ignore "Monoid law, right identity" -}

module Main (main) where

import Data.Maybe (isJust, isNothing)
import GBMesh.Combine
import GBMesh.Primitives
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
      testGroup "Combine" combineTests,
      testGroup "Primitives" primitivesTests
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
    pure (mkMesh vertices indices)

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

-- | Check structural invariants on a generated mesh.
checkMesh :: Mesh -> Bool
checkMesh m =
  validIndices m
    && validTriangleCount m
    && validNormals 1.0e-4 m
    && meshVertexCount m == length (meshVertices m)
    && meshVertexCount m > 0
    && not (null (meshIndices m))

-- | Positive float generator for radii and dimensions.
positiveFloat :: Gen Float
positiveFloat = choose (0.1, 10.0)

-- | Tessellation parameter generator.
tessParam :: Gen Int
tessParam = choose (3, 20)

-- | Tessellation parameter for stacks/segments (can be lower).
stackParam :: Gen Int
stackParam = choose (1, 20)

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

-- ----------------------------------------------------------------
-- Primitives tests
-- ----------------------------------------------------------------

primitivesTests :: [TestTree]
primitivesTests =
  [ -- Sphere
    QC.testProperty "sphere rejects non-positive radius" $
      forAll (choose (-10.0, 0.0)) $ \r ->
        isNothing (sphere r 8 4),
    QC.testProperty "sphere produces valid mesh" $
      forAll ((,,) <$> positiveFloat <*> tessParam <*> stackParam) $
        \(r, sl, st) ->
          maybe False checkMesh (sphere r sl st),
    QC.testProperty "sphere vertex count matches formula" $
      forAll ((,,) <$> positiveFloat <*> tessParam <*> stackParam) $
        \(r, slRaw, stRaw) ->
          let sl = max 3 slRaw
              st = max 2 stRaw
              expected = 2 * sl + (st - 1) * (sl + 1)
           in case sphere r slRaw stRaw of
                Just m -> meshVertexCount m == expected
                Nothing -> False,
    QC.testProperty "sphere index count matches formula" $
      forAll ((,,) <$> positiveFloat <*> tessParam <*> stackParam) $
        \(r, slRaw, stRaw) ->
          let sl = max 3 slRaw
              st = max 2 stRaw
              expected = 6 * (st - 1) * sl
           in case sphere r slRaw stRaw of
                Just m -> length (meshIndices m) == expected
                Nothing -> False,
    QC.testProperty "sphere vertices within bounding sphere" $
      forAll ((,,) <$> positiveFloat <*> tessParam <*> stackParam) $
        \(r, sl, st) ->
          case sphere r sl st of
            Just m ->
              all
                (\v -> vlength (vPosition v) <= r + 1.0e-4)
                (meshVertices m)
            Nothing -> False,
    -- Capsule
    QC.testProperty "capsule rejects non-positive params" $
      forAll (choose (-10.0, 0.0)) $ \r ->
        isNothing (capsule r 1.0 8 4 2)
          && isNothing (capsule 1.0 r 8 4 2),
    QC.testProperty "capsule produces valid mesh" $
      forAll ((,) <$> positiveFloat <*> positiveFloat) $ \(r, h) ->
        maybe False checkMesh (capsule r h 8 4 2),
    QC.testProperty "capsule vertex count matches formula"
      $ forAll
        ( (,,,,)
            <$> positiveFloat
            <*> positiveFloat
            <*> tessParam
            <*> stackParam
            <*> stackParam
        )
      $ \(r, h, slRaw, hrRaw, brRaw) ->
        let sl = max 3 slRaw
            hr = max 1 hrRaw
            br = max 1 brRaw
            expected = 2 * sl + (2 * (hr - 1) + br + 1) * (sl + 1)
         in case capsule r h slRaw hrRaw brRaw of
              Just m -> meshVertexCount m == expected
              Nothing -> False,
    -- Cylinder
    QC.testProperty "cylinder rejects non-positive params" $
      forAll (choose (-10.0, 0.0)) $ \r ->
        isNothing (cylinder r 1.0 8 1 True True)
          && isNothing (cylinder 1.0 r 8 1 True True),
    QC.testProperty "cylinder produces valid mesh" $
      forAll ((,) <$> positiveFloat <*> positiveFloat) $ \(r, h) ->
        maybe False checkMesh (cylinder r h 8 1 True True),
    QC.testProperty "cylinder vertex count matches formula"
      $ forAll
        ( (,,,,)
            <$> positiveFloat
            <*> positiveFloat
            <*> tessParam
            <*> stackParam
            <*> elements [(True, True), (True, False), (False, True), (False, False)]
        )
      $ \(r, h, slRaw, hsRaw, (tc, bc)) ->
        let sl = max 3 slRaw
            hs = max 1 hsRaw
            capCount = (if tc then 1 else 0) + (if bc then 1 else 0)
            expected = (hs + 1) * (sl + 1) + capCount * (sl + 1)
         in case cylinder r h slRaw hsRaw tc bc of
              Just m -> meshVertexCount m == expected
              Nothing -> False,
    QC.testProperty "cylinder index count matches formula"
      $ forAll
        ( (,,,,)
            <$> positiveFloat
            <*> positiveFloat
            <*> tessParam
            <*> stackParam
            <*> elements [(True, True), (True, False), (False, True), (False, False)]
        )
      $ \(r, h, slRaw, hsRaw, (tc, bc)) ->
        let sl = max 3 slRaw
            hs = max 1 hsRaw
            capCount = (if tc then 1 else 0) + (if bc then 1 else 0)
            expected = 6 * hs * sl + capCount * 3 * sl
         in case cylinder r h slRaw hsRaw tc bc of
              Just m -> length (meshIndices m) == expected
              Nothing -> False,
    -- Cone
    QC.testProperty "cone rejects non-positive params" $
      forAll (choose (-10.0, 0.0)) $ \r ->
        isNothing (cone r 1.0 8 4 True)
          && isNothing (cone 1.0 r 8 4 True),
    QC.testProperty "cone produces valid mesh" $
      forAll ((,) <$> positiveFloat <*> positiveFloat) $ \(r, h) ->
        maybe False checkMesh (cone r h 8 4 True),
    QC.testProperty "cone vertex count matches formula"
      $ forAll
        ( (,,,,)
            <$> positiveFloat
            <*> positiveFloat
            <*> tessParam
            <*> stackParam
            <*> elements [True, False]
        )
      $ \(r, h, slRaw, stRaw, cap) ->
        let sl = max 3 slRaw
            st = max 1 stRaw
            capVerts = if cap then sl + 1 else 0
            expected = sl + st * (sl + 1) + capVerts
         in case cone r h slRaw stRaw cap of
              Just m -> meshVertexCount m == expected
              Nothing -> False,
    -- Torus
    QC.testProperty "torus rejects non-positive or invalid radii" $
      isNothing (torus 0 1 8 8)
        && isNothing (torus 1 0 8 8)
        && isNothing (torus 1 2 8 8),
    QC.testProperty "torus produces valid mesh"
      $ forAll
        ( do
            majR <- positiveFloat
            minR <- choose (0.1, majR)
            pure (majR, minR)
        )
      $ \(majR, minR) ->
        maybe False checkMesh (torus majR minR 8 8),
    QC.testProperty "torus vertex count matches formula"
      $ forAll
        ( do
            majR <- positiveFloat
            minR <- choose (0.1, majR)
            ri <- tessParam
            sl <- tessParam
            pure (majR, minR, ri, sl)
        )
      $ \(majR, minR, riRaw, slRaw) ->
        let ri = max 3 riRaw
            sl = max 3 slRaw
            expected = (ri + 1) * (sl + 1)
         in case torus majR minR riRaw slRaw of
              Just m -> meshVertexCount m == expected
              Nothing -> False,
    -- Box
    QC.testProperty "box rejects non-positive dimensions" $
      isNothing (box 0 1 1 1 1 1)
        && isNothing (box 1 0 1 1 1 1)
        && isNothing (box 1 1 0 1 1 1),
    QC.testProperty "box produces valid mesh" $
      forAll ((,,) <$> positiveFloat <*> positiveFloat <*> positiveFloat) $
        \(w, h, d) ->
          maybe False checkMesh (box w h d 1 1 1),
    QC.testProperty "box unit has 24 vertices and 36 indices" $
      case box 1 1 1 1 1 1 of
        Just m -> meshVertexCount m == 24 && length (meshIndices m) == 36
        Nothing -> False,
    -- Plane
    QC.testProperty "plane rejects non-positive dimensions" $
      isNothing (plane 0 1 1 1) && isNothing (plane 1 0 1 1),
    QC.testProperty "plane produces valid mesh" $
      forAll ((,) <$> positiveFloat <*> positiveFloat) $ \(w, d) ->
        maybe False checkMesh (plane w d 4 4),
    QC.testProperty "plane vertex count matches formula"
      $ forAll
        ( (,,,)
            <$> positiveFloat
            <*> positiveFloat
            <*> stackParam
            <*> stackParam
        )
      $ \(w, d, sxRaw, szRaw) ->
        let sx = max 1 sxRaw
            sz = max 1 szRaw
            expected = (sx + 1) * (sz + 1)
         in case plane w d sxRaw szRaw of
              Just m -> meshVertexCount m == expected
              Nothing -> False,
    -- Tapered Cylinder
    QC.testProperty "taperedCylinder rejects invalid params" $
      isNothing (taperedCylinder (-1) 1 1 8 1 True True)
        && isNothing (taperedCylinder 0 0 1 8 1 True True)
        && isNothing (taperedCylinder 1 1 0 8 1 True True),
    QC.testProperty "taperedCylinder produces valid mesh" $
      forAll ((,,) <$> positiveFloat <*> positiveFloat <*> positiveFloat) $
        \(topR, botR, h) ->
          maybe False checkMesh (taperedCylinder topR botR h 8 1 True True),
    QC.testProperty "taperedCylinder degenerates to cylinder" $
      forAll ((,) <$> positiveFloat <*> positiveFloat) $ \(r, h) ->
        case (taperedCylinder r r h 8 4 True True, cylinder r h 8 4 True True) of
          (Just tc, Just cyl) ->
            meshVertexCount tc == meshVertexCount cyl
              && length (meshIndices tc) == length (meshIndices cyl)
          _ -> False,
    -- Cross-cutting: all primitives produce isJust for valid params
    QC.testProperty "all primitives succeed with valid params" $
      forAll positiveFloat $ \r ->
        isJust (sphere r 8 4)
          && isJust (capsule r r 8 2 2)
          && isJust (cylinder r r 8 1 True True)
          && isJust (cone r r 8 4 True)
          && isJust (torus (r + 1) r 8 8)
          && isJust (box r r r 1 1 1)
          && isJust (plane r r 1 1)
          && isJust (taperedCylinder r (r * 0.5) r 8 1 True True)
  ]
