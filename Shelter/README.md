# Underhaven (Shelter v1)

- `Shelterv1.rbxl`: the place file as uploaded.
- `Shelterv1-fixed.rbxl`: the same place with the bug fixes, emergency response and sound added. Only scripts changed or were added; the map, meshes and settings are untouched.
- `src/`: the game's scripts (ReplicatedStorage, ServerScriptService, StarterPlayer), extracted from the place. Edit these, then rebuild the place.
- `audio/underhaven_sounds.ogg`: every sound effect and ambience loop in one file (see **Sound**).
- `tests/`: headless tests for the server code and the sound controller (fake Roblox APIs, virtual clock, DataStores with latency and failure injection).
- `tools/`: the place file reader/writer, the sound generator and the sound uploader.
- `DESIGN_STATUS.md`: where the game stands against the design brief, section by section.

> **If you use `_DevSync`:** it overwrites scripts from your local source folder. Copy `src/` into that folder first, or a sync will undo these changes.

## Sound

The game has 34 original sounds: interface clicks, collecting, building, upgrades, alarms, fire, machinery hum, gunfire, doorbell, births, deaths and more. They play from one audio file in slices (`Sound.PlaybackRegion`), so you only upload once. The ambient loops follow the camera: generators hum and fires crackle when they're on screen, water pumps slow in a brownout, and the alarm sounds during raids. A **SOUND** button in the bottom-right corner toggles effects and ambience; the choice is saved per player.

**Roblox can't store audio inside a place file, so the game stays silent until you upload the audio once.** Upload it to the same account or group that owns the game.

- **By hand:**
  1. Upload `audio/underhaven_sounds.ogg` as audio. In Studio use the Asset Manager's import; on the web use create.roblox.com > Creations > Audio > Upload.
  2. Copy the new asset id.
  3. In Studio, open ReplicatedStorage > Shared > **SoundBank** and set `SoundBank.ATLAS_ID = "rbxassetid://<your id>"`.
- **Scripted:** `python3 tools/upload_sounds.py --api-key <Open Cloud key with Assets read+write> --user-id <your user id>` (or `--group-id`). It uploads the file, sets the id and rebuilds the place.

Roblox moderates audio, so it can take a few minutes before it plays. To change the sounds, edit `tools/make_sounds.py`, run it (needs numpy and ffmpeg), and upload the new file.

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

The script replaces the `Source` of every script that has a file under `src/`. A new `.lua` file becomes a new ModuleScript in its folder. All other data is copied byte for byte, and the result is re-read and checked.
