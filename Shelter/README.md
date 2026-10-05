# Underhaven (Shelter v1)

- `Shelterv1.rbxl`: the place file as uploaded.
- `Shelterv1-fixed.rbxl`: the same place with the bug fixes, emergency response and the audio system added. Only scripts (and the `ReplicatedStorage.Audio` folder) changed or were added; the map, meshes and settings are untouched.
- `src/`: the game's scripts (ReplicatedStorage, ServerScriptService, StarterPlayer), extracted from the place. Edit these, then rebuild the place.
- `tests/`: headless tests for the server code and the client AudioManager (fake Roblox APIs, virtual clock, DataStores with latency and failure injection).
- `tools/`: the place file reader/writer.
- `DESIGN_STATUS.md`: where the game stands against the design brief, section by section.
- `AUDIO.md`: the audio system: where everything is, what plays when, provenance of every sound, hooks for later.

> **If you use `_DevSync`:** it overwrites scripts from your local source folder. Copy `src/` into that folder first, or a sync will undo these changes.

## Sound

Every sound is public Roblox audio, listed in one file: `src/ReplicatedStorage/Audio/AudioConfig.lua` (in Studio, `ReplicatedStorage.Audio.AudioConfig`). Nothing has to be uploaded. The client's `AudioManager` plays everything; `AUDIO.md` describes the whole system.

- To change a sound, change its id in `AudioConfig.Assets`; every cue that uses it follows. Each asset is tagged `pse` / `apm` (Roblox's licensed libraries) or `community` (origin unverified).
- When a player joins, every id is checked. One that fails is recorded in `AudioConfig.Failed` and named in the Studio Output; the cue moves on to the next id in its own list, or stays silent. It is never replaced with some other sound.
- The **SOUND** button (bottom right) has Master, Music, SFX, Ambient and UI volumes, saved with the shelter.
- In Studio, press **F7** for the audio test panel (developers only).

## Run the tests

Needs the [Luau CLI](https://github.com/luau-lang/luau/releases) (`luau`) and Python 3.

```sh
LUAU=/path/to/luau python3 tests/run.py          # all tests
LUAU=/path/to/luau python3 tests/run.py smoke    # one test; -v shows output
```

Each test runs in a fresh process. `smoke` plays 25 virtual minutes with every system involved. `scale_*` measures server cost at 200 and 500 survivors. The rest each cover one bug or feature.

## Rebuild the place after editing `src/`

```sh
pip install lz4 zstandard
python3 tools/build_place.py Shelterv1.rbxl Shelterv1-fixed.rbxl
```

The script replaces the `Source` of every script that has a file under `src/`. A new `.lua` file becomes a new ModuleScript in its folder, and a folder that doesn't exist yet in the place (like `ReplicatedStorage/Audio`) becomes a new Folder. All other data is copied byte for byte, and the result is re-read and checked.
