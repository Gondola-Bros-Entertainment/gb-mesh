# Changelog

## 0.1.0.0 — 2026-03-25

### Geometry Generation
- Parametric primitives: sphere, capsule, cylinder, cone, torus, box, plane, tapered cylinder
- Bezier, B-spline, and NURBS curves with arc-length parameterization
- Bezier, B-spline, and NURBS surface patches with uniform tessellation
- Lofting: revolve, ring loft, extrude, sweep with Bishop frame propagation
- Marching cubes with SDF grid pre-sampling
- Dual contouring with QEF solving for sharp feature preservation
- Incremental 3D convex hull
- Geodesic icosphere with analytical normals and UV mapping
- Heightmap terrain with thermal and hydraulic erosion

### Procedural Tools
- Signed distance fields: 6 primitives, CSG booleans, smooth blending, domain warps
- Noise: Perlin 2D/3D, simplex 2D/3D/4D, Worley 2D/3D, FBM, ridged, turbulence
- Mesh-level CSG booleans (union, intersection, difference)
- Uniform, Poisson disk, and weighted point scattering
- Planar, cylindrical, spherical, and box UV projection

### Mesh Processing
- Transform, merge, recompute normals and tangents (MikkTSpace-style)
- Deformation: twist, bend, taper, free-form deformation (FFD), displacement mapping
- Subdivision: Catmull-Clark (quads), Loop (triangles)
- Smoothing: Laplacian, Taubin volume-preserving
- Simplification: Garland-Heckbert quadric error metrics with priority queue
- Vertex welding via spatial hashing, degenerate triangle removal
- Mirror symmetry (X/Y/Z/arbitrary plane) and radial symmetry
- Level-of-detail chain generation with screen-size selection
- Isotropic remeshing (edge split/collapse/flip/relax)
- Ray-triangle intersection and BVH-accelerated mesh raycasting

### Rigging and Animation
- Generic joint tree skeletons with humanoid and quadruped convenience builders
- Forward kinematics with pose interpolation (slerp) and additive composition
- Procedural animation: oscillators, keyframe playback, easing functions, sequencing
- Inverse kinematics: CCD and FABRIK solvers with joint constraints (hinge, cone)
- Linear blend skinning and dual quaternion skinning
- Automatic skin weight computation via closest-point-on-bone
- Mesh morphing and blend shapes

### Import / Export
- Wavefront OBJ import and export (text format, single and multi-mesh)
- glTF 2.0 import and export (JSON with embedded base64 buffers, single and multi-mesh)
