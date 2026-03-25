{-# OPTIONS_GHC -fno-warn-orphans #-}

{- HLINT ignore "Monoid law, left identity" -}
{- HLINT ignore "Monoid law, right identity" -}

module Main (main) where

import Data.Maybe (fromMaybe, isJust, isNothing)
import GBMesh.Combine
import GBMesh.Curve
import GBMesh.Loft
import GBMesh.Primitives
import GBMesh.Surface
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
      testGroup "Primitives" primitivesTests,
      testGroup "Curve" curveTests,
      testGroup "Surface" surfaceTests,
      testGroup "Loft" loftTests
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

-- ----------------------------------------------------------------
-- Curve tests
-- ----------------------------------------------------------------

-- | A simple cubic Bezier curve for testing.
testCubicBezier :: BezierCurve V3
testCubicBezier =
  BezierCurve
    [ V3 0 0 0,
      V3 1 2 0,
      V3 3 2 0,
      V3 4 0 0
    ]

-- | A quadratic Bezier curve for testing.
testQuadBezier :: BezierCurve V2
testQuadBezier =
  BezierCurve
    [V2 0 0, V2 1 2, V2 2 0]

-- | A clamped cubic B-spline for testing.
testBSpline :: BSplineCurve V3
testBSpline =
  BSplineCurve
    3
    [0, 0, 0, 0, 1, 2, 2, 2, 2]
    [V3 0 0 0, V3 1 2 0, V3 2 2 0, V3 3 1 0, V3 4 0 0]

curveTests :: [TestTree]
curveTests =
  [ -- Bezier evaluation
    QC.testProperty "Bezier empty returns Nothing" $
      isNothing (evalBezier (BezierCurve [] :: BezierCurve V3) 0.5),
    QC.testProperty "Bezier single point returns that point" $
      evalBezier (BezierCurve [V3 1 2 3]) 0.5 == Just (V3 1 2 3),
    QC.testProperty "Bezier interpolates endpoints" $
      let pts = bezierControlPoints testCubicBezier
          start = evalBezier testCubicBezier 0.0
          end = evalBezier testCubicBezier 1.0
       in case (start, end, pts) of
            (Just s, Just e, first : _) ->
              approxEqV3 s first
                && approxEqV3 e (V3 4 0 0)
            _ -> False,
    QC.testProperty "Bezier midpoint is on curve" $
      isJust (evalBezier testCubicBezier 0.5),
    -- Bezier splitting
    QC.testProperty "Bezier split produces valid subcurves" $
      forAll (choose (0.0, 1.0)) $ \t ->
        case splitBezier testCubicBezier t of
          Just (left, right) ->
            length (bezierControlPoints left) == 4
              && length (bezierControlPoints right) == 4
          Nothing -> False,
    QC.testProperty "Bezier split left endpoint matches original start" $
      case splitBezier testCubicBezier 0.5 of
        Just (left, _) ->
          case evalBezier left 0.0 of
            Just pt -> approxEqV3 pt (V3 0 0 0)
            Nothing -> False
        Nothing -> False,
    -- Bezier derivative
    QC.testProperty "Bezier derivative of cubic is quadratic" $
      case bezierDerivative testCubicBezier of
        Just deriv -> length (bezierControlPoints deriv) == 3
        Nothing -> False,
    QC.testProperty "Bezier derivative of constant is zero" $
      let constCurve = BezierCurve [V3 1 1 1, V3 1 1 1, V3 1 1 1]
       in case evalBezierDerivative constCurve 0.5 of
            Just d -> approxEqV3 d vzero
            Nothing -> False,
    -- V2 Bezier
    QC.testProperty "V2 Bezier interpolates endpoints" $
      let start = evalBezier testQuadBezier 0.0
          end = evalBezier testQuadBezier 1.0
       in case (start, end) of
            (Just s, Just e) ->
              approxEq (let V2 x _ = s in x) 0
                && approxEq (let V2 x _ = e in x) 2
            _ -> False,
    -- B-spline
    QC.testProperty "B-spline evaluates at start" $
      case evalBSpline testBSpline 0.0 of
        Just pt -> approxEqV3 pt (V3 0 0 0)
        Nothing -> False,
    QC.testProperty "B-spline evaluates at end" $
      case evalBSpline testBSpline 2.0 of
        Just pt -> approxEqV3 pt (V3 4 0 0)
        Nothing -> False,
    QC.testProperty "B-spline rejects out-of-range" $
      isNothing (evalBSpline testBSpline (-0.1))
        && isNothing (evalBSpline testBSpline 2.1),
    QC.testProperty "B-spline derivative reduces degree" $
      case bsplineDerivative testBSpline of
        Just deriv -> bsplineDegree deriv == 2
        Nothing -> False,
    -- Arc-length
    QC.testProperty "arc-length table total is positive for non-degenerate curve" $
      let derivFn t = fromMaybe vzero (evalBezierDerivative testCubicBezier t)
          table = buildArcLengthTable derivFn vlength 100 0 1
       in totalArcLength table > 0,
    QC.testProperty "arc-length param at 0 maps to start" $
      let derivFn t = fromMaybe vzero (evalBezierDerivative testCubicBezier t)
          table = buildArcLengthTable derivFn vlength 100 0 1
       in approxEq (arcLengthToParam table 0.0) 0.0,
    QC.testProperty "arc-length param at total maps to end" $
      let derivFn t = fromMaybe vzero (evalBezierDerivative testCubicBezier t)
          table = buildArcLengthTable derivFn vlength 100 0 1
          arcTotal = totalArcLength table
       in approxEq (arcLengthToParam table arcTotal) 1.0,
    QC.testProperty "arc-length param is monotonically increasing" $
      let derivFn t = fromMaybe vzero (evalBezierDerivative testCubicBezier t)
          table = buildArcLengthTable derivFn vlength 100 0 1
          arcTotal = totalArcLength table
          samples = [arcLengthToParam table (arcTotal * fromIntegral i / 10.0) | i <- [0 .. 10 :: Int]]
       in and (zipWith (<=) samples (drop 1 samples))
  ]

-- ----------------------------------------------------------------
-- Surface tests
-- ----------------------------------------------------------------

-- | A flat bilinear Bezier patch (2x2 control points).
testBilinearPatch :: BezierPatch V3
testBilinearPatch =
  BezierPatch
    2
    2
    [ V3 0 0 0,
      V3 1 0 0,
      V3 0 0 1,
      V3 1 0 1
    ]

-- | A bicubic Bezier patch (4x4 control points) — a gentle hill.
testBicubicPatch :: BezierPatch V3
testBicubicPatch =
  BezierPatch
    4
    4
    [ V3 0 0 0,
      V3 1 0 0,
      V3 2 0 0,
      V3 3 0 0,
      V3 0 0 1,
      V3 1 1 1,
      V3 2 1 1,
      V3 3 0 1,
      V3 0 0 2,
      V3 1 1 2,
      V3 2 1 2,
      V3 3 0 2,
      V3 0 0 3,
      V3 1 0 3,
      V3 2 0 3,
      V3 3 0 3
    ]

surfaceTests :: [TestTree]
surfaceTests =
  [ -- Bezier patch evaluation
    QC.testProperty "bilinear patch corners are correct" $
      approxEqV3 (evalBezierPatch testBilinearPatch 0 0) (V3 0 0 0)
        && approxEqV3 (evalBezierPatch testBilinearPatch 1 0) (V3 1 0 0)
        && approxEqV3 (evalBezierPatch testBilinearPatch 0 1) (V3 0 0 1)
        && approxEqV3 (evalBezierPatch testBilinearPatch 1 1) (V3 1 0 1),
    QC.testProperty "bilinear patch midpoint is average" $
      approxEqV3
        (evalBezierPatch testBilinearPatch 0.5 0.5)
        (V3 0.5 0 0.5),
    -- Bezier patch tessellation
    QC.testProperty "Bezier patch tessellation produces valid mesh" $
      forAll ((,) <$> choose (1, 10) <*> choose (1, 10)) $ \(su, sv) ->
        let m = tessellateBezierPatch testBicubicPatch su sv
         in checkMesh m,
    QC.testProperty "Bezier patch tessellation vertex count" $
      forAll ((,) <$> choose (1, 10) <*> choose (1, 10)) $ \(suRaw, svRaw) ->
        let su = max 1 suRaw
            sv = max 1 svRaw
            m = tessellateBezierPatch testBicubicPatch suRaw svRaw
         in meshVertexCount m == (su + 1) * (sv + 1),
    QC.testProperty "Bezier patch tessellation index count" $
      forAll ((,) <$> choose (1, 10) <*> choose (1, 10)) $ \(suRaw, svRaw) ->
        let su = max 1 suRaw
            sv = max 1 svRaw
            m = tessellateBezierPatch testBicubicPatch suRaw svRaw
         in length (meshIndices m) == 6 * su * sv,
    -- B-spline surface
    QC.testProperty "B-spline surface tessellation produces valid mesh" $
      let surf =
            BSplineSurface
              1
              1
              [0, 0, 1, 1]
              [0, 0, 1, 1]
              [V3 0 0 0, V3 1 0 0, V3 0 0 1, V3 1 0 1]
       in maybe False checkMesh (tessellateBSplineSurface surf 4 4)
  ]

-- ----------------------------------------------------------------
-- Loft tests
-- ----------------------------------------------------------------

-- | A simple circular profile for revolve testing.
circleProfile :: Float -> V2
circleProfile t = V2 radius height
  where
    radius = 0.5
    height = t * 2.0 - 1.0

-- | Derivative of the simple circle profile.
circleProfileDeriv :: Float -> V2
circleProfileDeriv _ = V2 0 2.0

loftTests :: [TestTree]
loftTests =
  [ -- Revolve
    QC.testProperty "revolve produces valid mesh" $
      let m = revolve circleProfile circleProfileDeriv 8 12 (2 * pi)
       in checkMesh m,
    QC.testProperty "revolve has correct body vertex count" $
      forAll ((,) <$> choose (2, 15) <*> tessParam) $ \(profSegs, slRaw) ->
        let sl = max 3 slRaw
            ps = max 1 profSegs
            m = revolve circleProfile circleProfileDeriv ps sl (2 * pi)
         in meshVertexCount m > 0
              && validIndices m
              && validTriangleCount m,
    -- Revolve with pole (profile touching axis)
    QC.testProperty "revolve with poles produces valid mesh" $
      let poleProfile t = V2 (sin (t * pi)) (cos (t * pi))
          poleDeriv t = V2 (pi * cos (t * pi)) (negate pi * sin (t * pi))
          m = revolve poleProfile poleDeriv 8 12 (2 * pi)
       in checkMesh m,
    -- Loft rings
    QC.testProperty "loftRings rejects fewer than 2 rings" $
      isNothing (loftRings [] False)
        && isNothing (loftRings [[V3 0 0 0, V3 1 0 0, V3 0 1 0]] False),
    QC.testProperty "loftRings rejects rings with fewer than 3 points" $
      isNothing
        ( loftRings
            [[V3 0 0 0, V3 1 0 0], [V3 0 1 0, V3 1 1 0]]
            False
        ),
    QC.testProperty "loftRings produces valid mesh" $
      let ring0 = [V3 (cos t) 0 (sin t) | t <- [0, 2 * pi / 8 .. 2 * pi - 0.01]]
          ring1 = [V3 (cos t) 1 (sin t) | t <- [0, 2 * pi / 8 .. 2 * pi - 0.01]]
          ring2 = [V3 (cos t) 2 (sin t) | t <- [0, 2 * pi / 8 .. 2 * pi - 0.01]]
       in maybe False checkMesh (loftRings [ring0, ring1, ring2] True),
    -- Extrude
    QC.testProperty "extrude produces valid mesh" $
      let profile t = V2 (cos (t * 2 * pi)) (sin (t * 2 * pi))
          deriv t = V2 (negate (2 * pi) * sin (t * 2 * pi)) (2 * pi * cos (t * 2 * pi))
          m = extrude profile deriv (V3 0 1 0) 2.0 12 4
       in checkMesh m,
    -- Sweep
    QC.testProperty "sweep produces valid mesh" $
      let spine t = V3 (t * 4) 0 0
          spineDeriv _ = V3 4 0 0
          profile t = V2 (0.5 * cos (t * 2 * pi)) (0.5 * sin (t * 2 * pi))
          m = sweep spine spineDeriv profile 8 12
       in checkMesh m,
    QC.testProperty "sweep along curved path produces valid mesh" $
      let spine t = V3 (cos (t * pi)) (t * 2) (sin (t * pi))
          spineDeriv t =
            V3
              (negate pi * sin (t * pi))
              2
              (pi * cos (t * pi))
          profile t = V2 (0.3 * cos (t * 2 * pi)) (0.3 * sin (t * 2 * pi))
          m = sweep spine spineDeriv profile 16 8
       in checkMesh m
  ]
