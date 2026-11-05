# A smaller, faster-loading Godot web export

What a player downloads for a Godot web game is `index.wasm` (the engine) and `index.pck` (the game). Hosts like itch.io
gzip both on the way: a wasm shrinks about four times, a pack hardly at all (its textures are already compressed). So
the pack is cut by finding what does not belong in it, the engine by building it without what the game never uses.

Measured on a 2D game (Godot 4.7, 4 Nov 2026):

| | before | after |
|---|---|---|
| index.wasm raw / on the wire | 38.8 / 10.1 MB | 31.2 / 8.7 MB (engine built without 3D) |
| index.pck raw | 18.5 MB | 7.3 MB (sketches, references and one dead 5 MB atlas left out) |
| load on itch.io | 21 s | 9 s |

## 1. Measure first

- **The wire**: ask one byte of each file with compression allowed; `Content-Range: bytes 0-0/<n>` is the download size:
  `curl -s -o /dev/null -D - -r 0-0 -H 'Accept-Encoding: br, gzip' "<url>/index.wasm?x=$RANDOM"`.
- **The pack by folder**: a `.pck` (format 3 and 4) has its file directory at the u64 offset stored at byte 32; each
  entry is path length (u32), path, offset (u64), size (u64), md5 (16 bytes), flags (u32). Files under
  `.godot/imported/` map back to their source through the `*.import` files (`path="res://.godot/imported/..."`). Sum by
  top folder: one file or folder is often a third of the pack.
- **The engine**: unzip the official template (`export_templates/<version>/web_release.zip`) and gzip -9 `godot.wasm`
  for the baseline.

## 2. Cut the pack

- Put every folder the game never loads (concept art, references, tests, tools, dev scenes) into **every** export
  preset's `exclude_filter` in `export_presets.cfg`, so desktop builds gain too.
- Prove a file is unused before cutting: search its name in every `.gd`, `.tscn`, `.tres`, `.json` outside tests and
  tools (a comment does not count; watch for paths built from strings, `"res://data/%s.json" % name`).
- Then prove it at run time: move the file out of the project, run the game over what would draw it, look at the
  picture and the log, move it back.
- Add a size check to the build script that refuses a pack over a budget and names the folders that grew.

## 3. A slim engine (web export template from source)

- Keep the toolchain outside the repo: Godot's source at the exact editor tag (`git clone --depth 1 -b <ver>-stable
  https://github.com/godotengine/godot.git`), Emscripten at the version Godot's CI uses for that tag (see
  `.github/workflows/web_builds.yml`, `EM_VERSION`), SCons in a venv.
- Match the official template you replace: threaded or not (`web_release.zip` is threaded, `web_nothreads_release.zip`
  is not), wasm32. Build `scons platform=web target=template_release threads=yes arch=wasm32 profile=custom.py`.
- A profile for a 2D game can drop 3D and everything only 3D uses: `disable_3d=yes`, and modules such as Jolt, CSG,
  GridMap, glTF, FBX, OpenXR, WebXR, mobile VR, lightmapper, raycast, xatlas, vhacd, meshoptimizer, mono. Bigger cuts
  (networking, unused media formats, the advanced text server) save more but are a decision for the game's owner.
- **Prove nothing used was dropped**: collect every `GDCLASS(Name,` from the folders and modules the profile removes,
  and every capitalised identifier in the game's `.gd` / `.tscn` / `.tres` / `project.godot`; the intersection must be
  empty. `SubViewport` is core, not 3D.
- The first build takes about 40 minutes; the final LTO link and wasm-opt are single-threaded. Run it on the charger,
  in the background. Point the web preset's `custom_template/release` at the built zip.
- Test in a browser with the isolation headers a threaded build needs (Godot's own
  `platform/web/serve.py -n -p <port> -r <export dir>`), and export the same commit with the official template beside
  it for comparison.

## 4. Exported builds hide their own errors

A script that uses a class from a folder the export excludes compiles in the editor and fails only in the export.
After any change to the filters, open the exported build and read the first `Parse Error` in the console: "Identifier X
not declared" means X lives somewhere the export does not carry.

## 5. On itch.io

- itch extracts an upload for a few minutes after a push. Do not open the new build's big files at their plain URL
  before it is ready: the CDN can cache the 404 that answers the first request for 15 to 20 minutes, for everyone.
  Poll with a query string (cached apart) a minute apart at most, then open the page.
- Further cuts: a thread-free build (`variant/thread_support=false`, no isolation headers needed, check the sound under
  load), and a cold and a warm load timed in the browser's DevTools (cache off, throttled network).
