-- | Mesh export to OBJ and glTF 2.0 formats.
--
-- Wavefront OBJ (text) and glTF 2.0 (JSON with inline base64 buffer)
-- exporters. No external dependencies beyond @base@.
module GBMesh.Export
  ( -- * Wavefront OBJ
    meshToOBJ,
    meshesToOBJ,

    -- * glTF 2.0
    meshToGLTF,
    meshesToGLTF,
  )
where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.Char (chr, ord)
import Data.List (foldl', intercalate)
import Data.Word (Word32, Word8)
import GBMesh.Types (Mesh (..), V2 (..), V3 (..), V4 (..), Vertex (..))
import GHC.Float (castFloatToWord32)

-- ================================================================
-- OBJ export
-- ================================================================

-- | Export a single mesh to Wavefront OBJ text format.
--
-- Emits @v@, @vn@, @vt@, and @f@ lines. Face indices are 1-based
-- and reference position, texcoord, and normal in @v\/vt\/vn@ form.
meshToOBJ :: Mesh -> String
meshToOBJ mesh =
  unlines (vertexLines ++ normalLines ++ uvLines ++ faceLines)
  where
    vertices = meshVertices mesh
    indices = meshIndices mesh

    vertexLines = map formatPosition vertices
    normalLines = map formatNormal vertices
    uvLines = map formatUV vertices
    faceLines = formatFaces indices

-- | Export multiple named meshes to a single Wavefront OBJ string.
--
-- Each mesh is preceded by an @o@ (object name) line. Vertex indices
-- are offset so that each mesh references the correct global vertices.
meshesToOBJ :: [(String, Mesh)] -> String
meshesToOBJ namedMeshes =
  unlines (concatMap emitObject offsetPairs)
  where
    offsets = scanl (\acc (_, mesh) -> acc + meshVertexCount mesh) 0 namedMeshes
    offsetPairs = zip offsets namedMeshes

    emitObject (offset, (name, mesh)) =
      let vertices = meshVertices mesh
          indices = meshIndices mesh
          headerLine = "o " ++ name
          posLines = map formatPosition vertices
          nrmLines = map formatNormal vertices
          texLines = map formatUV vertices
          facLines = formatFacesOffset offset indices
       in headerLine : posLines ++ nrmLines ++ texLines ++ facLines

-- ----------------------------------------------------------------
-- OBJ formatting helpers
-- ----------------------------------------------------------------

-- | Format a vertex position as an OBJ @v@ line.
formatPosition :: Vertex -> String
formatPosition vert =
  let V3 px py pz = vPosition vert
   in "v " ++ showFloat px ++ " " ++ showFloat py ++ " " ++ showFloat pz

-- | Format a vertex normal as an OBJ @vn@ line.
formatNormal :: Vertex -> String
formatNormal vert =
  let V3 nx ny nz = vNormal vert
   in "vn " ++ showFloat nx ++ " " ++ showFloat ny ++ " " ++ showFloat nz

-- | Format a vertex UV as an OBJ @vt@ line.
formatUV :: Vertex -> String
formatUV vert =
  let V2 tu tv = vUV vert
   in "vt " ++ showFloat tu ++ " " ++ showFloat tv

-- | Format triangle faces from indices with a base offset of 0.
formatFaces :: [Word32] -> [String]
formatFaces = formatFacesOffset 0

-- | Format triangle faces from indices, adding a 1-based offset.
-- OBJ indices are 1-based, so we add @globalOffset + 1@.
formatFacesOffset :: Int -> [Word32] -> [String]
formatFacesOffset globalOffset = go
  where
    go (idx0 : idx1 : idx2 : rest) =
      formatTriangle idx0 idx1 idx2 : go rest
    go _ = []

    formatTriangle idx0 idx1 idx2 =
      "f "
        ++ faceVertex idx0
        ++ " "
        ++ faceVertex idx1
        ++ " "
        ++ faceVertex idx2

    faceVertex idx =
      let oneBasedIndex = show (fromIntegral idx + globalOffset + objIndexBase)
       in oneBasedIndex ++ "/" ++ oneBasedIndex ++ "/" ++ oneBasedIndex

-- | OBJ files use 1-based indexing.
objIndexBase :: Int
objIndexBase = 1

-- ================================================================
-- glTF 2.0 export
-- ================================================================

-- | Export a single mesh to a self-contained glTF 2.0 JSON string.
--
-- The binary buffer is embedded as a base64-encoded data URI.
-- Includes accessors for positions (VEC3), normals (VEC3),
-- texcoords (VEC2), tangents (VEC4), and indices (SCALAR UNSIGNED_INT).
-- Position accessor includes min\/max bounds.
meshToGLTF :: Mesh -> String
meshToGLTF mesh = meshesToGLTF [("mesh", mesh)]

-- | Export multiple named meshes to a single glTF 2.0 JSON string.
--
-- All mesh data shares one binary buffer, partitioned by buffer
-- views and accessors.
meshesToGLTF :: [(String, Mesh)] -> String
meshesToGLTF namedMeshes =
  jsonObject
    [ ("asset", gltfAsset),
      ("scene", "0"),
      ("scenes", jsonArray [jsonObject [("nodes", jsonArray (map show nodeIndices))]]),
      ("nodes", jsonArray (zipWith formatNode nodeIndices namedMeshes)),
      ("meshes", jsonArray (zipWith formatMeshEntry [0 :: Int ..] namedMeshes)),
      ("accessors", jsonArray allAccessors),
      ("bufferViews", jsonArray allBufferViews),
      ("buffers", jsonArray [formatBuffer totalBufferBytes allBytes])
    ]
  where
    meshCount = length namedMeshes
    nodeIndices = take meshCount [0 :: Int ..]

    allMeshData = map buildMeshData namedMeshes

    -- Each mesh produces 5 accessors and 5 buffer views
    buildMeshData :: (String, Mesh) -> MeshData
    buildMeshData (_, mesh) =
      let vertices = meshVertices mesh
          indices = meshIndices mesh
          vertCount = meshVertexCount mesh
          idxCount = length indices

          posBytes = concatMap (encodeV3 . vPosition) vertices
          nrmBytes = concatMap (encodeV3 . vNormal) vertices
          texBytes = concatMap (encodeV2 . vUV) vertices
          tanBytes = concatMap (encodeV4 . vTangent) vertices
          idxBytes = concatMap encodeWord32 indices

          posByteLen = vertCount * bytesPerVec3
          nrmByteLen = vertCount * bytesPerVec3
          texByteLen = vertCount * bytesPerVec2
          tanByteLen = vertCount * bytesPerVec4
          idxByteLen = idxCount * bytesPerWord32

          (posMin, posMax) = computePositionBounds vertices
       in MeshData
            { mdVertexCount = vertCount,
              mdIndexCount = idxCount,
              mdPositionBytes = posBytes,
              mdNormalBytes = nrmBytes,
              mdTexcoordBytes = texBytes,
              mdTangentBytes = tanBytes,
              mdIndexBytes = idxBytes,
              mdPositionByteLength = posByteLen,
              mdNormalByteLength = nrmByteLen,
              mdTexcoordByteLength = texByteLen,
              mdTangentByteLength = tanByteLen,
              mdIndexByteLength = idxByteLen,
              mdPositionMin = posMin,
              mdPositionMax = posMax
            }

    -- Compute byte offsets for all mesh data laid out sequentially
    allByteOffsets = scanl (\acc md -> acc + meshDataTotalBytes md) 0 allMeshData

    totalBufferBytes = foldl' (\_ offset -> offset) 0 allByteOffsets

    allBytes = concatMap meshDataAllBytes allMeshData

    -- Build buffer views: 5 per mesh (position, normal, texcoord, tangent, index)
    allBufferViews = concatMap (uncurry buildBufferViews) (zip allByteOffsets allMeshData)

    -- Build accessors: 5 per mesh
    allAccessors = concatMap buildAccessorGroup (zipWith3Tuples [0 ..] allByteOffsets allMeshData)

    -- Format a node referencing its mesh
    formatNode nodeIdx (name, _) =
      jsonObject
        [ ("mesh", show nodeIdx),
          ("name", jsonString name)
        ]

    -- Format a mesh entry referencing its accessors
    formatMeshEntry meshIdx (name, _) =
      let baseAccessor = meshIdx * accessorsPerMesh
       in jsonObject
            [ ( "primitives",
                jsonArray
                  [ jsonObject
                      [ ( "attributes",
                          jsonObject
                            [ ("POSITION", show baseAccessor),
                              ("NORMAL", show (baseAccessor + normalAccessorOffset)),
                              ("TEXCOORD_0", show (baseAccessor + texcoordAccessorOffset)),
                              ("TANGENT", show (baseAccessor + tangentAccessorOffset))
                            ]
                        ),
                        ("indices", show (baseAccessor + indexAccessorOffset))
                      ]
                  ]
              ),
              ("name", jsonString name)
            ]

-- ----------------------------------------------------------------
-- Mesh data record
-- ----------------------------------------------------------------

-- | Intermediate data for a single mesh being exported to glTF.
data MeshData = MeshData
  { mdVertexCount :: Int,
    mdIndexCount :: Int,
    mdPositionBytes :: [Word8],
    mdNormalBytes :: [Word8],
    mdTexcoordBytes :: [Word8],
    mdTangentBytes :: [Word8],
    mdIndexBytes :: [Word8],
    mdPositionByteLength :: Int,
    mdNormalByteLength :: Int,
    mdTexcoordByteLength :: Int,
    mdTangentByteLength :: Int,
    mdIndexByteLength :: Int,
    mdPositionMin :: V3,
    mdPositionMax :: V3
  }

-- | Total byte size of all buffer data for one mesh.
meshDataTotalBytes :: MeshData -> Int
meshDataTotalBytes md =
  mdPositionByteLength md
    + mdNormalByteLength md
    + mdTexcoordByteLength md
    + mdTangentByteLength md
    + mdIndexByteLength md

-- | Concatenate all buffer data for one mesh in attribute order.
meshDataAllBytes :: MeshData -> [Word8]
meshDataAllBytes md =
  mdPositionBytes md
    ++ mdNormalBytes md
    ++ mdTexcoordBytes md
    ++ mdTangentBytes md
    ++ mdIndexBytes md

-- ----------------------------------------------------------------
-- glTF buffer views and accessors
-- ----------------------------------------------------------------

-- | Number of accessors generated per mesh.
accessorsPerMesh :: Int
accessorsPerMesh = 5

-- | Number of buffer views generated per mesh.
bufferViewsPerMesh :: Int
bufferViewsPerMesh = 5

-- | Accessor offset for normals within a mesh's accessor group.
normalAccessorOffset :: Int
normalAccessorOffset = 1

-- | Accessor offset for texcoords within a mesh's accessor group.
texcoordAccessorOffset :: Int
texcoordAccessorOffset = 2

-- | Accessor offset for tangents within a mesh's accessor group.
tangentAccessorOffset :: Int
tangentAccessorOffset = 3

-- | Accessor offset for indices within a mesh's accessor group.
indexAccessorOffset :: Int
indexAccessorOffset = 4

-- | glTF component type for 32-bit float.
componentTypeFloat :: Int
componentTypeFloat = 5126

-- | glTF component type for 32-bit unsigned integer.
componentTypeUnsignedInt :: Int
componentTypeUnsignedInt = 5125

-- | glTF buffer view target for vertex attributes.
bufferTargetArrayBuffer :: Int
bufferTargetArrayBuffer = 34962

-- | glTF buffer view target for element (index) arrays.
bufferTargetElementArrayBuffer :: Int
bufferTargetElementArrayBuffer = 34963

-- | Build 5 buffer views for one mesh at the given byte offset.
buildBufferViews :: Int -> MeshData -> [String]
buildBufferViews baseOffset md =
  [ formatBufferView posOffset (mdPositionByteLength md) bufferTargetArrayBuffer,
    formatBufferView nrmOffset (mdNormalByteLength md) bufferTargetArrayBuffer,
    formatBufferView texOffset (mdTexcoordByteLength md) bufferTargetArrayBuffer,
    formatBufferView tanOffset (mdTangentByteLength md) bufferTargetArrayBuffer,
    formatBufferView idxOffset (mdIndexByteLength md) bufferTargetElementArrayBuffer
  ]
  where
    posOffset = baseOffset
    nrmOffset = posOffset + mdPositionByteLength md
    texOffset = nrmOffset + mdNormalByteLength md
    tanOffset = texOffset + mdTexcoordByteLength md
    idxOffset = tanOffset + mdTangentByteLength md

-- | Build 5 accessors for one mesh.
buildAccessors :: Int -> Int -> MeshData -> [String]
buildAccessors meshIdx _baseOffset md =
  [ formatAccessor posView (mdVertexCount md) componentTypeFloat "VEC3" (Just (mdPositionMin md, mdPositionMax md)),
    formatAccessor nrmView (mdVertexCount md) componentTypeFloat "VEC3" Nothing,
    formatAccessor texView (mdVertexCount md) componentTypeFloat "VEC2" Nothing,
    formatAccessor tanView (mdVertexCount md) componentTypeFloat "VEC4" Nothing,
    formatAccessor idxView (mdIndexCount md) componentTypeUnsignedInt "SCALAR" Nothing
  ]
  where
    baseView = meshIdx * bufferViewsPerMesh
    posView = baseView
    nrmView = baseView + 1
    texView = baseView + 2
    tanView = baseView + 3
    idxView = baseView + 4

-- ----------------------------------------------------------------
-- glTF JSON formatting
-- ----------------------------------------------------------------

-- | glTF asset metadata.
gltfAsset :: String
gltfAsset =
  jsonObject
    [ ("version", jsonString "2.0"),
      ("generator", jsonString "gb-mesh")
    ]

-- | Format a buffer view as a JSON object.
formatBufferView :: Int -> Int -> Int -> String
formatBufferView byteOffset byteLength target =
  jsonObject
    [ ("buffer", "0"),
      ("byteOffset", show byteOffset),
      ("byteLength", show byteLength),
      ("target", show target)
    ]

-- | Format an accessor as a JSON object, optionally with min/max.
formatAccessor :: Int -> Int -> Int -> String -> Maybe (V3, V3) -> String
formatAccessor bufferView count componentType accessorType maybeBounds =
  jsonObject (baseFields ++ boundsFields)
  where
    baseFields =
      [ ("bufferView", show bufferView),
        ("componentType", show componentType),
        ("count", show count),
        ("type", jsonString accessorType)
      ]
    boundsFields = case maybeBounds of
      Nothing -> []
      Just (V3 minX minY minZ, V3 maxX maxY maxZ) ->
        [ ("min", jsonFloatArray [minX, minY, minZ]),
          ("max", jsonFloatArray [maxX, maxY, maxZ])
        ]

-- | Format a buffer as a JSON object with a data URI.
formatBuffer :: Int -> [Word8] -> String
formatBuffer byteLength bytes =
  jsonObject
    [ ("uri", jsonString (bufferDataURIPrefix ++ encodeBase64 bytes)),
      ("byteLength", show byteLength)
    ]

-- | Data URI prefix for an octet-stream buffer.
bufferDataURIPrefix :: String
bufferDataURIPrefix = "data:application/octet-stream;base64,"

-- ----------------------------------------------------------------
-- JSON builder helpers
-- ----------------------------------------------------------------

-- | Build a JSON object from key-value pairs.
-- Values are already formatted as JSON strings.
jsonObject :: [(String, String)] -> String
jsonObject pairs =
  "{" ++ intercalate "," (map formatPair pairs) ++ "}"
  where
    formatPair (key, val) = jsonString key ++ ":" ++ val

-- | Build a JSON array from pre-formatted elements.
jsonArray :: [String] -> String
jsonArray elems = "[" ++ intercalate "," elems ++ "]"

-- | Wrap a Haskell string as a JSON string literal with escaping.
jsonString :: String -> String
jsonString str = "\"" ++ concatMap escapeChar str ++ "\""
  where
    escapeChar '"' = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar '\t' = "\\t"
    escapeChar ch = [ch]

-- | Format a list of floats as a JSON array.
jsonFloatArray :: [Float] -> String
jsonFloatArray = jsonArray . map showFloat

-- ----------------------------------------------------------------
-- Position bounds computation
-- ----------------------------------------------------------------

-- | Compute axis-aligned bounding box for vertex positions.
-- Returns (min, max). For empty vertex lists, returns zero vectors.
computePositionBounds :: [Vertex] -> (V3, V3)
computePositionBounds [] = (V3 0 0 0, V3 0 0 0)
computePositionBounds (firstVert : rest) =
  foldl' accumBounds (initialPos, initialPos) rest
  where
    initialPos = vPosition firstVert
    accumBounds (V3 minX minY minZ, V3 maxX maxY maxZ) vert =
      let V3 px py pz = vPosition vert
       in ( V3 (min minX px) (min minY py) (min minZ pz),
            V3 (max maxX px) (max maxY py) (max maxZ pz)
          )

-- ----------------------------------------------------------------
-- Binary encoding
-- ----------------------------------------------------------------

-- | Bytes per VEC3 (3 floats x 4 bytes).
bytesPerVec3 :: Int
bytesPerVec3 = 12

-- | Bytes per VEC2 (2 floats x 4 bytes).
bytesPerVec2 :: Int
bytesPerVec2 = 8

-- | Bytes per VEC4 (4 floats x 4 bytes).
bytesPerVec4 :: Int
bytesPerVec4 = 16

-- | Bytes per Word32 index.
bytesPerWord32 :: Int
bytesPerWord32 = 4

-- | Encode a V3 as 12 bytes (3 little-endian IEEE 754 floats).
encodeV3 :: V3 -> [Word8]
encodeV3 (V3 x y z) = encodeFloat32 x ++ encodeFloat32 y ++ encodeFloat32 z

-- | Encode a V2 as 8 bytes (2 little-endian IEEE 754 floats).
encodeV2 :: V2 -> [Word8]
encodeV2 (V2 x y) = encodeFloat32 x ++ encodeFloat32 y

-- | Encode a V4 as 16 bytes (4 little-endian IEEE 754 floats).
encodeV4 :: V4 -> [Word8]
encodeV4 (V4 x y z w) =
  encodeFloat32 x ++ encodeFloat32 y ++ encodeFloat32 z ++ encodeFloat32 w

-- | Encode a Float as 4 little-endian bytes (IEEE 754).
encodeFloat32 :: Float -> [Word8]
encodeFloat32 = encodeWord32 . castFloatToWord32

-- | Encode a Word32 as 4 little-endian bytes.
encodeWord32 :: Word32 -> [Word8]
encodeWord32 word =
  [ fromIntegral (word .&. byteMask),
    fromIntegral (shiftR word 8 .&. byteMask),
    fromIntegral (shiftR word 16 .&. byteMask),
    fromIntegral (shiftR word 24 .&. byteMask)
  ]

-- | Bitmask for extracting one byte from a Word32.
byteMask :: Word32
byteMask = 0xFF

-- ----------------------------------------------------------------
-- Base64 encoding
-- ----------------------------------------------------------------

-- | Encode a list of bytes to a base64 string (RFC 4648).
encodeBase64 :: [Word8] -> String
encodeBase64 = go
  where
    go (byte0 : byte1 : byte2 : rest) =
      let combined =
            shiftL (fromIntegral byte0 :: Word32) 16
              .|. shiftL (fromIntegral byte1 :: Word32) 8
              .|. fromIntegral byte2
          char0 = base64CharAt (shiftR combined 18 .&. base64IndexMask)
          char1 = base64CharAt (shiftR combined 12 .&. base64IndexMask)
          char2 = base64CharAt (shiftR combined 6 .&. base64IndexMask)
          char3 = base64CharAt (combined .&. base64IndexMask)
       in char0 : char1 : char2 : char3 : go rest
    go [byte0, byte1] =
      let combined =
            shiftL (fromIntegral byte0 :: Word32) 16
              .|. shiftL (fromIntegral byte1 :: Word32) 8
          char0 = base64CharAt (shiftR combined 18 .&. base64IndexMask)
          char1 = base64CharAt (shiftR combined 12 .&. base64IndexMask)
          char2 = base64CharAt (shiftR combined 6 .&. base64IndexMask)
       in [char0, char1, char2, base64PadChar]
    go [byte0] =
      let combined = shiftL (fromIntegral byte0 :: Word32) 16
          char0 = base64CharAt (shiftR combined 18 .&. base64IndexMask)
          char1 = base64CharAt (shiftR combined 12 .&. base64IndexMask)
       in [char0, char1, base64PadChar, base64PadChar]
    go [] = []

-- | 6-bit mask for extracting base64 indices.
base64IndexMask :: Word32
base64IndexMask = 0x3F

-- | Base64 padding character.
base64PadChar :: Char
base64PadChar = '='

-- | Look up a base64 character by its 6-bit index (0--63).
-- Uses arithmetic over the RFC 4648 alphabet ranges rather
-- than partial list indexing.
base64CharAt :: Word32 -> Char
base64CharAt idx
  | idx < 26 = chr (ord 'A' + fromIntegral idx)
  | idx < 52 = chr (ord 'a' + fromIntegral (idx - 26))
  | idx < 62 = chr (ord '0' + fromIntegral (idx - 52))
  | idx == 62 = '+'
  | otherwise = '/'

-- ----------------------------------------------------------------
-- Float formatting
-- ----------------------------------------------------------------

-- | Show a float value for export formats. Uses Haskell's 'show'.
showFloat :: Float -> String
showFloat = show

-- ----------------------------------------------------------------
-- Utility
-- ----------------------------------------------------------------

-- | Zip three lists into a list of triples.
zipWith3Tuples :: [a] -> [b] -> [c] -> [(a, b, c)]
zipWith3Tuples (x : xs) (y : ys) (z : zs) = (x, y, z) : zipWith3Tuples xs ys zs
zipWith3Tuples _ _ _ = []

-- | Apply a function of three arguments to a triple.
buildAccessorGroup :: (Int, Int, MeshData) -> [String]
buildAccessorGroup (meshIdx, byteOffset, md) = buildAccessors meshIdx byteOffset md
