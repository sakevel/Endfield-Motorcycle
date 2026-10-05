# Bundled motorcycle asset

**Low-Poly Motorcycle #2** by **Sidra**.
Source: https://sketchfab.com/3d-models/low-poly-motorcycle-2-9e79295e99654e2a9fa930b5139a7d84
License: Creative Commons Attribution 4.0 International (CC BY 4.0).
https://creativecommons.org/licenses/by/4.0/
Full license and warranty disclaimer: `licenses/CC-BY-4.0.txt`.

Distributed files: `assets/sidra-bike.zmlmesh` (adapted geometry) and
`assets/Textures.png` (original palette texture).
Changes by the ZML Motorcycle mod: select the yellow-green bike, omit the
second bike and Sketchfab ground AO image; bake FBX transforms to Unity Y-up,
+Z-forward coordinates; center at ground and scale to 2.2 metres; triangulate,
quantize positions/UVs and octahedral normals; retain separate wheel, steering
and stand pivots; repaint material/UV assignments to an off-white body,
yellow frame/accents and charcoal mechanics using a mod-generated palette;
fit rim axle centres; straighten the parked fork and chassis into an upright
neutral frame; re-quantize the geometry and normals while retaining UV/index
assignments; adapt materials and animate these parts at runtime. Original palette PNG unchanged.
No endorsement by the original author is implied. Assets are provided as-is.

# Offline conversion tool
The optional FBX converter links upstream **ufbx** by Samuli Raivio,
commit 5955c5c0b042ac2dc6f32955ab206aaec0620cfc, under its MIT alternative.
https://github.com/ufbx/ufbx
ufbx is not linked into the runtime DLL or distributed in this runtime package.
Its license is retained beside the converter in the source repository.

# Native shader
The runtime clones a material loaded normally by the user's installed game,
uses only its compatible shader, and replaces base/normal/MRO textures with
our own textures. No game meshes, textures, shaders or materials are distributed.

# Mod UI icons
The browser icon is original artwork generated with the built-in image tool,
matching our other Mod emblems (broken grey hexagon, white glyph, yellow accent).
The tool-wheel icon is an original code-native SVG with deliberately thick
geometric shapes, rasterized by tools/export-icons.py. No game icons are shipped.
These icons are independent of Sidra model attribution.
