-- | Heightmap terrain generation and erosion simulation.
--
-- Grid-based terrain from height functions or explicit heightmaps,
-- with thermal and hydraulic erosion, terracing, plateau clamping,
-- and heightmap blending.
module GBMesh.Terrain
  ( -- * Height function
    HeightFn,

    -- * Terrain generation
    terrain,
    fromHeightmap,
    sampleGrid,

    -- * Heightmap transforms
    terrace,
    plateau,
    clampHeights,
    blendHeightmaps,

    -- * Erosion
    thermalErosion,
    hydraulicErosion,
  )
where

import Data.Array (Array, array, bounds, listArray, range, (!))
import Data.List (foldl')
import Data.Word (Word32)
import GBMesh.Types

-- ----------------------------------------------------------------
-- Types
-- ----------------------------------------------------------------

-- | A height function mapping (x, z) world coordinates to a y height.
type HeightFn = Float -> Float -> Float

-- ----------------------------------------------------------------
-- Terrain generation
-- ----------------------------------------------------------------

-- | Generate an XZ grid mesh from a height function.
--
-- The grid spans from @(-width\/2, -depth\/2)@ to @(width\/2, depth\/2)@
-- with @(segsX+1) * (segsZ+1)@ vertices. Returns 'Nothing' if width
-- or depth is not positive.
terrain ::
  -- | Height function mapping (x, z) to y
  HeightFn ->
  -- | Width (X extent)
  Float ->
  -- | Depth (Z extent)
  Float ->
  -- | Segments along X (clamped to >= 1)
  Int ->
  -- | Segments along Z (clamped to >= 1)
  Int ->
  Maybe Mesh
terrain heightFn width depth segsXRaw segsZRaw
  | width <= 0 || depth <= 0 = Nothing
  | otherwise = Just (mkMesh vertices indices)
  where
    segsX = max 1 segsXRaw
    segsZ = max 1 segsZRaw
    sz = segsZ + 1
    dx = width / fromIntegral segsX
    dz = depth / fromIntegral segsZ
    halfW = width / 2.0
    halfD = depth / 2.0
    fSegsX = fromIntegral segsX :: Float
    fSegsZ = fromIntegral segsZ :: Float

    -- Pre-sample heights into an array for O(1) normal lookups
    heightArr :: Array (Int, Int) Float
    heightArr =
      array
        ((0, 0), (segsX, segsZ))
        [ ((ix, iz), heightFn x z)
        | ix <- [0 .. segsX],
          let x = -halfW + fromIntegral ix * dx,
          iz <- [0 .. segsZ],
          let z = -halfD + fromIntegral iz * dz
        ]

    -- Look up height with clamped indices for boundary normals
    heightAt :: Int -> Int -> Float
    heightAt ix iz = heightArr ! (clampI 0 segsX ix, clampI 0 segsZ iz)

    vertices =
      [ let x = -halfW + fromIntegral ix * dx
            z = -halfD + fromIntegral iz * dz
            y = heightArr ! (ix, iz)
            -- Central differences for normal
            nx = (heightAt (ix - 1) iz - heightAt (ix + 1) iz) / (2.0 * dx)
            nz = (heightAt ix (iz - 1) - heightAt ix (iz + 1)) / (2.0 * dz)
            nrm = normalize (V3 nx 1.0 nz)
            u = fromIntegral ix / fSegsX
            v = fromIntegral iz / fSegsZ
         in Vertex (V3 x y z) nrm (V2 u v) (V4 1 0 0 1)
      | ix <- [0 .. segsX],
        iz <- [0 .. segsZ]
      ]

    indices =
      [ idx
      | ix <- [0 .. segsX - 1],
        iz <- [0 .. segsZ - 1],
        let tl = fromIntegral (ix * sz + iz) :: Word32
            tr = fromIntegral (ix * sz + iz + 1)
            bl = fromIntegral ((ix + 1) * sz + iz)
            br = fromIntegral ((ix + 1) * sz + iz + 1),
        idx <- [tl, bl, tr, tr, bl, br]
      ]

-- | Build a terrain mesh from an explicit heightmap grid.
--
-- The outer list is rows along X, inner list is columns along Z.
-- Returns 'Nothing' if width or depth is not positive, the grid is
-- empty, or rows have inconsistent lengths.
fromHeightmap ::
  -- | Width (X extent)
  Float ->
  -- | Depth (Z extent)
  Float ->
  -- | Heightmap grid (outer = X rows, inner = Z columns)
  [[Float]] ->
  Maybe Mesh
fromHeightmap _ _ [] = Nothing
fromHeightmap width depth grid@(firstRow : _)
  | width <= 0 || depth <= 0 = Nothing
  | cols == 0 = Nothing
  | any (\r -> length r /= cols) grid = Nothing
  | otherwise = Just (mkMesh vertices indices)
  where
    rows = length grid
    cols = length firstRow
    segsX = rows - 1
    segsZ = cols - 1
    sz = cols
    dx = if segsX > 0 then width / fromIntegral segsX else 1.0
    dz = if segsZ > 0 then depth / fromIntegral segsZ else 1.0
    halfW = width / 2.0
    halfD = depth / 2.0
    fSegsX = fromIntegral (max 1 segsX) :: Float
    fSegsZ = fromIntegral (max 1 segsZ) :: Float

    -- Build array from grid
    heightArr :: Array (Int, Int) Float
    heightArr =
      array
        ((0, 0), (segsX, segsZ))
        [ ((ix, iz), (grid !! ix) !! iz)
        | ix <- [0 .. segsX],
          iz <- [0 .. segsZ]
        ]

    heightAt :: Int -> Int -> Float
    heightAt ix iz = heightArr ! (clampI 0 segsX ix, clampI 0 segsZ iz)

    vertices =
      [ let x = -halfW + fromIntegral ix * dx
            z = -halfD + fromIntegral iz * dz
            y = heightArr ! (ix, iz)
            nx = (heightAt (ix - 1) iz - heightAt (ix + 1) iz) / (2.0 * dx)
            nz = (heightAt ix (iz - 1) - heightAt ix (iz + 1)) / (2.0 * dz)
            nrm = normalize (V3 nx 1.0 nz)
            u = fromIntegral ix / fSegsX
            v = fromIntegral iz / fSegsZ
         in Vertex (V3 x y z) nrm (V2 u v) (V4 1 0 0 1)
      | ix <- [0 .. segsX],
        iz <- [0 .. segsZ]
      ]

    indices
      | segsX < 1 || segsZ < 1 = []
      | otherwise =
          [ idx
          | ix <- [0 .. segsX - 1],
            iz <- [0 .. segsZ - 1],
            let tl = fromIntegral (ix * sz + iz) :: Word32
                tr = fromIntegral (ix * sz + iz + 1)
                bl = fromIntegral ((ix + 1) * sz + iz)
                br = fromIntegral ((ix + 1) * sz + iz + 1),
            idx <- [tl, bl, tr, tr, bl, br]
          ]

-- | Sample a height function into a grid of @(segsX+1)@ rows of
-- @(segsZ+1)@ values.
sampleGrid ::
  -- | Height function
  HeightFn ->
  -- | Segments along X (clamped to >= 1)
  Int ->
  -- | Segments along Z (clamped to >= 1)
  Int ->
  -- | Width (X extent)
  Float ->
  -- | Depth (Z extent)
  Float ->
  [[Float]]
sampleGrid heightFn segsXRaw segsZRaw width depth =
  [ [ heightFn x z
    | iz <- [0 .. segsZ],
      let z = -halfD + fromIntegral iz * dz
    ]
  | ix <- [0 .. segsX],
    let x = -halfW + fromIntegral ix * dx
  ]
  where
    segsX = max 1 segsXRaw
    segsZ = max 1 segsZRaw
    halfW = width / 2.0
    halfD = depth / 2.0
    dx = width / fromIntegral segsX
    dz = depth / fromIntegral segsZ

-- ----------------------------------------------------------------
-- Heightmap transforms
-- ----------------------------------------------------------------

-- | Quantize heights to @n@ discrete terrace levels.
--
-- If @n <= 0@ or the height range is zero, the grid is returned
-- unchanged.
terrace ::
  -- | Number of terrace levels
  Int ->
  -- | Input heightmap
  [[Float]] ->
  [[Float]]
terrace n grid
  | n <= 0 = grid
  | rangeH < nearZeroLength = grid
  | otherwise = map (map quantize) grid
  where
    allHeights = concat grid
    minH = minimum allHeights
    maxH = maximum allHeights
    rangeH = maxH - minH
    fn = fromIntegral n :: Float

    quantize h =
      let t = (h - minH) / rangeH
          level = fromIntegral (fastFloor (t * fn)) / fn
       in level * rangeH + minH

-- | Flatten all heights above a threshold to a replacement value.
plateau ::
  -- | Threshold height
  Float ->
  -- | Replacement height for cells above threshold
  Float ->
  -- | Input heightmap
  [[Float]] ->
  [[Float]]
plateau threshold replacement = map (map clampCell)
  where
    clampCell h = if h > threshold then replacement else h

-- | Clamp all heightmap values to the range @[lo, hi]@.
clampHeights ::
  -- | Minimum height
  Float ->
  -- | Maximum height
  Float ->
  -- | Input heightmap
  [[Float]] ->
  [[Float]]
clampHeights lo hi = map (map (clampF lo hi))

-- | Blend two heightmaps element-wise. Each cell is
-- @(1 - t) * a + t * b@. If grids differ in size, the smaller
-- dimensions are used.
blendHeightmaps ::
  -- | Blend weight (0 = all A, 1 = all B)
  Float ->
  -- | Heightmap A
  [[Float]] ->
  -- | Heightmap B
  [[Float]] ->
  [[Float]]
blendHeightmaps t =
  zipWith (zipWith blendCell)
  where
    blendCell a b = (1.0 - t) * a + t * b

-- ----------------------------------------------------------------
-- Erosion
-- ----------------------------------------------------------------

-- | Iterative thermal erosion simulation.
--
-- Each iteration transfers material from higher to lower cells when
-- the height difference exceeds the talus angle. Uses 'Data.Array'
-- internally for O(1) access.
thermalErosion ::
  -- | Number of iterations (clamped to >= 0)
  Int ->
  -- | Talus angle threshold
  Float ->
  -- | Input heightmap
  [[Float]] ->
  [[Float]]
thermalErosion _ _ [] = []
thermalErosion itersRaw talusAngle grid@(firstRow : _)
  | null firstRow = grid
  | iters <= 0 = grid
  | otherwise = arrayToGrid rows cols (iterateN iters erodeStep initArr)
  where
    iters = max 0 itersRaw
    rows = length grid
    cols = length firstRow
    maxR = rows - 1
    maxC = cols - 1

    initArr :: Array (Int, Int) Float
    initArr = gridToArray grid rows cols

    erodeStep :: Array (Int, Int) Float -> Array (Int, Int) Float
    erodeStep arr =
      let updates = concatMap (cellUpdates arr) (range ((0, 0), (maxR, maxC)))
       in applyUpdates arr updates

    cellUpdates :: Array (Int, Int) Float -> (Int, Int) -> [((Int, Int), Float)]
    cellUpdates arr (i, j) =
      let h = arr ! (i, j)
          ns = neighbors4 maxR maxC i j
       in concatMap (transferTo arr h (i, j)) ns

    transferTo :: Array (Int, Int) Float -> Float -> (Int, Int) -> (Int, Int) -> [((Int, Int), Float)]
    transferTo arr h src dst =
      let hN = arr ! dst
          diff = h - hN
       in if diff > talusAngle
            then
              let amount = (diff - talusAngle) * 0.5
               in [(src, negate amount), (dst, amount)]
            else []

-- | Simplified hydraulic erosion simulation.
--
-- Each iteration adds rain, flows water to the lowest neighbor,
-- erodes proportional to water, deposits in local minima, and
-- evaporates. Uses 'Data.Array' internally for O(1) access.
hydraulicErosion ::
  -- | Number of iterations (clamped to >= 0)
  Int ->
  -- | Rain amount per iteration
  Float ->
  -- | Erosion strength
  Float ->
  -- | Input heightmap
  [[Float]] ->
  [[Float]]
hydraulicErosion _ _ _ [] = []
hydraulicErosion itersRaw rainAmount erosionStrength grid@(firstRow : _)
  | null firstRow = grid
  | iters <= 0 = grid
  | otherwise = arrayToGrid rows cols finalHeight
  where
    iters = max 0 itersRaw
    rows = length grid
    cols = length firstRow
    maxR = rows - 1
    maxC = cols - 1

    initHeight :: Array (Int, Int) Float
    initHeight = gridToArray grid rows cols

    initWater :: Array (Int, Int) Float
    initWater =
      listArray ((0, 0), (maxR, maxC)) (replicate (rows * cols) 0.0)

    (finalHeight, _) = iterateN iters stepHydraulic (initHeight, initWater)

    stepHydraulic ::
      (Array (Int, Int) Float, Array (Int, Int) Float) ->
      (Array (Int, Int) Float, Array (Int, Int) Float)
    stepHydraulic (hArr, wArr) =
      let -- Step 1: Add rain
          wRain = fmap (+ rainAmount) wArr
          -- Steps 2-5: Flow, erode, deposit, evaporate
          cells = range ((0, 0), (maxR, maxC))
          (hUpdates, wUpdates) = foldl' (processCell hArr wRain) ([], []) cells
          hArr' = applyUpdates hArr hUpdates
          wArr' = applyUpdates wRain wUpdates
          -- Step 6: Evaporate
          wFinal = fmap (* 0.9) wArr'
       in (hArr', wFinal)

    processCell ::
      Array (Int, Int) Float ->
      Array (Int, Int) Float ->
      ([((Int, Int), Float)], [((Int, Int), Float)]) ->
      (Int, Int) ->
      ([((Int, Int), Float)], [((Int, Int), Float)])
    processCell hArr wArr (hAcc, wAcc) (i, j) =
      let h = hArr ! (i, j)
          w = wArr ! (i, j)
          ns = neighbors4 maxR maxC i j
          -- Find lowest neighbor
          lowestN = case ns of
            [] -> (i, j)
            (first : rest) ->
              foldl' (\best nb -> if hArr ! nb < hArr ! best then nb else best) first rest
          hLow = hArr ! lowestN
          -- Step 3: Flow water to lowest neighbor
          wFlow = w * 0.5
          wUpd =
            if hLow < h && not (null ns)
              then [((i, j), negate wFlow), (lowestN, wFlow)]
              else []
          -- Step 4: Erode
          erodeAmt = erosionStrength * w
          hErosion = [((i, j), negate erodeAmt)]
          -- Step 5: Deposit in local minima
          isLocalMin = not (null ns) && all (\nb -> hArr ! nb >= h) ns
          hDeposit =
            [((i, j), erosionStrength * 0.5 * w) | isLocalMin]
       in (hAcc ++ hErosion ++ hDeposit, wAcc ++ wUpd)

-- ----------------------------------------------------------------
-- Internal helpers
-- ----------------------------------------------------------------

-- | Clamp an integer to a range.
clampI :: Int -> Int -> Int -> Int
clampI lo hi x = max lo (min hi x)

-- | Get 4-connected neighbor indices within grid bounds.
neighbors4 :: Int -> Int -> Int -> Int -> [(Int, Int)]
neighbors4 maxR maxC i j =
  [ (ni, nj)
  | (di, dj) <- [(-1, 0), (1, 0), (0, -1), (0, 1)],
    let ni = i + di,
    let nj = j + dj,
    ni >= 0,
    ni <= maxR,
    nj >= 0,
    nj <= maxC
  ]

-- | Convert a nested list to an Array.
gridToArray :: [[Float]] -> Int -> Int -> Array (Int, Int) Float
gridToArray g r c =
  array
    ((0, 0), (r - 1, c - 1))
    [((i, j), (g !! i) !! j) | i <- [0 .. r - 1], j <- [0 .. c - 1]]

-- | Convert an Array back to a nested list.
arrayToGrid :: Int -> Int -> Array (Int, Int) Float -> [[Float]]
arrayToGrid r c arr =
  [[arr ! (i, j) | j <- [0 .. c - 1]] | i <- [0 .. r - 1]]

-- | Apply additive updates to an array.
applyUpdates :: Array (Int, Int) Float -> [((Int, Int), Float)] -> Array (Int, Int) Float
applyUpdates =
  foldl' addDelta
  where
    addDelta baseArr (k, delta) =
      let old = baseArr ! k
       in replaceAt baseArr k (old + delta)
    replaceAt baseArr k val =
      array (bounds baseArr) (map (overrideOne k val baseArr) (range (bounds baseArr)))
    overrideOne k val baseArr idx
      | idx == k = (idx, val)
      | otherwise = (idx, baseArr ! idx)

-- | Apply a function n times.
iterateN :: Int -> (a -> a) -> a -> a
iterateN n f x = foldl' (\acc _ -> f acc) x [1 .. n]
