-- | Procedural 3D mesh generation.
--
-- Convenience re-export of the entire public API. Import individual
-- modules (e.g. @GBMesh.Primitives@) for selective access.
module GBMesh
  ( -- * Core types
    module GBMesh.Types,

    -- * Mesh transforms and merging
    module GBMesh.Combine,

    -- * Parametric primitives
    module GBMesh.Primitives,

    -- * Curves
    module GBMesh.Curve,

    -- * Surfaces
    module GBMesh.Surface,

    -- * Lofting and sweeping
    module GBMesh.Loft,

    -- * Signed distance fields
    module GBMesh.SDF,

    -- * Isosurface extraction
    module GBMesh.Isosurface,

    -- * Dual contouring
    module GBMesh.DualContour,

    -- * Convex hull
    module GBMesh.Hull,

    -- * Geodesic sphere
    module GBMesh.Icosphere,

    -- * Noise
    module GBMesh.Noise,

    -- * Deformation
    module GBMesh.Deform,

    -- * Subdivision surfaces
    module GBMesh.Subdivision,

    -- * Smoothing
    module GBMesh.Smooth,

    -- * Simplification
    module GBMesh.Simplify,

    -- * Vertex welding
    module GBMesh.Weld,

    -- * Skeleton
    module GBMesh.Skeleton,

    -- * Pose and forward kinematics
    module GBMesh.Pose,

    -- * Procedural animation
    module GBMesh.Animate,

    -- * Inverse kinematics
    module GBMesh.IK,

    -- * Skinning
    module GBMesh.Skin,

    -- * Morph targets
    module GBMesh.Morph,

    -- * Export
    module GBMesh.Export,
  )
where

import GBMesh.Animate
import GBMesh.Combine
import GBMesh.Curve
import GBMesh.Deform
import GBMesh.DualContour
import GBMesh.Export
import GBMesh.Hull
import GBMesh.IK
import GBMesh.Icosphere
import GBMesh.Isosurface
import GBMesh.Loft
import GBMesh.Morph
import GBMesh.Noise
import GBMesh.Pose
import GBMesh.Primitives
import GBMesh.SDF
import GBMesh.Simplify
import GBMesh.Skeleton
import GBMesh.Skin
import GBMesh.Smooth
import GBMesh.Subdivision
import GBMesh.Surface
import GBMesh.Types
import GBMesh.Weld
