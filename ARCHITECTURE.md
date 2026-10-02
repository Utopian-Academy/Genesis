# Genesis architecture

## The one rule

**Godot is the renderer.** Genesis is a Godot 4.7.2 editor plugin written in GDScript. It
adds an architectural-visualization workflow on top of the Godot editor. It does not replace
anything the editor already does well.

## Layers

```
Genesis UX            dock panels that speak in SUN / SKY / FOG, not DirectionalLight3D
      |
Genesis systems       small scripts, one job each (below)
      |
Editor integration       plugin.gd: registers the dock, forwards 3D input, owns undo/redo
      |
Godot                    scene tree, 3D viewport, inspector, importer, renderer
```

The systems never touch editor UI. The dock never touches scene nodes directly: it asks a
system, and the system makes the change through the editor's undo/redo. That is the only
boundary we enforce. There's no engine-independence layer.

## What Godot gives us, and what we build

| Need | Godot provides | Genesis adds |
|---|---|---|
| Viewport, orbit, gizmos, selection | Editor 3D viewport, `EditorSelection` | nothing |
| Hierarchy, properties | Scene dock, Inspector | nothing |
| Undo/redo | `EditorUndoRedoManager` | every Genesis action goes through it |
| Model import | glTF/GLB importer; `.blend` direct import once Blender's path is set | a "drop your building in" action |
| Sun, sky, fog, exposure | `DirectionalLight3D`, `WorldEnvironment`, `Environment`, `ProceduralSkyMaterial` | one Environment panel; time-of-day maps to a sun angle |
| Materials | `StandardMaterial3D` | presets (Concrete, Brick, Glass...) as `.tres` files |
| Repeated vegetation | `MultiMesh` / `MultiMeshInstance3D` | a scatter brush that fills them |
| Brush input in the viewport | `EditorPlugin._forward_3d_gui_input` | the brush itself |
| Cameras | `Camera3D` | named saved views with recall |
| Still image | `SubViewport` + `Image.save_png` | an export button with 1080p/1440p/4K presets |

## Systems (all under `addons/genesis/`)

| Script | Job |
|---|---|
| `plugin.gd` | Registers and unregisters everything. It holds no feature logic. |
| `gn_scene.gd` | Finds Genesis nodes by role and adds nodes or properties through undo/redo. |
| `gn_environment.gd` | Sun, sky, fog, exposure, time of day. |
| `gn_asset_library.gd` | Scans `res://genesis_assets/`, reads each asset's licence metadata. |
| `gn_placement.gd` | Adds an asset to the scene. After that, Godot's own gizmos handle it. |
| `gn_scatter.gd` | Copies of one model as MultiMeshes, which are the only store of the copies. |
| `gn_surface.gd` | Ray tests against the scene's meshes, so the brush can paint onto any surface. |
| `gn_brush.gd` | The paint and erase brush. It takes viewport events from `plugin.gd`, or from tests. |
| `gn_materials.gd` | Lists a selection's surfaces; applies presets and adjustments as per-surface overrides. |
| `gn_cameras.gd` | Save and recall named views. |
| `gn_render.gd` | Offscreen still export: lens, supersampling, finishing pass. |
| `gn_movie.gd` | Fly-through shots (paths, orbits), sampling, clearance check, video render. |
| `gn_photomatch.gd` + `gn_photo_compose.gdshader` | Site photo per camera; differential-render compositing. |
| `gn_site.gd` | OpenStreetMap site context: geocode, fetch, parse, build massing. |
| `gn_sun.gd` | NOAA solar position; city presets. |
| `gn_quality.gd` | Final-render quality switched on only during capture. |
| `gn_sky.gd` | Photo skies, with the sun found in each photo. |
| `gn_look.gd` + `gn_post.gdshader` | Per-camera look: exposure, DOF, 2-point perspective, grading, sketch. |
| `gn_import.gd` | Copies a model into `res://assets` and lets Godot import it. |
| `set/` | Parametric set pieces (LED wall, truss, stage deck): @tool nodes edited in the Inspector. |
| `ui/` | Dock panels only. |

Systems get added when a milestone needs them, not before.

## Project layout

A Genesis project is a normal Godot project:

```
project.godot
addons/genesis/       the plugin
genesis_assets/       the asset library, one folder per category
genesis_data/         Genesis-owned resources (material presets, saved cameras)
scenes/                  the user's scenes
tools/                   Blender scripts that generate our own demo assets
```

There's no custom file format. Scenes are `.tscn` and presets are `.tres`.

## Decisions taken at recon

- **Dock, not main screen.** A Godot main-screen plugin *replaces* the 3D viewport while its tab
  is showing. Because the viewport is the product, Genesis is a dock beside it. It uses 4.7's
  `EditorDock` class, which replaces the older `add_control_to_dock`.
- **Genesis nodes are ordinary nodes** in the user's scene, tagged with metadata
  (`genesis_role`). If the plugin is disabled, the scene still opens and renders.
- **Asset licensing goes in a sidecar file.** Each asset has a `<name>.license.json` next to
  it with source, author, licence and attribution. The library won't list an asset without
  one, so an unlicensed asset can never reach a render.
- **The demo assets are ours.** The building and placeholder vegetation are generated by
  Blender scripts in `tools/`, released under the project licence.
