# Underhaven (Shelter v1)

- `Shelterv1.rbxl`: the place file as uploaded.
- `Shelterv1-fixed.rbxl`: the same place with the bug fixes applied. Only the `Source` of 10 server/shared scripts differs.
- `src/`: the game's scripts (ReplicatedStorage, ServerScriptService, StarterPlayer), extracted from the place. Edit these, then rebuild the place.
- `tests/`: a headless test harness for the server code (fake Roblox APIs, virtual clock, DataStores with latency and failure injection).
- `tools/`: a reader/writer for the binary place format.

## Run the server tests

Needs the [Luau CLI](https://github.com/luau-lang/luau/releases) (`luau`) and Python 3.

```sh
LUAU=/path/to/luau python3 tests/run.py          # all tests
LUAU=/path/to/luau python3 tests/run.py smoke    # one test; -v shows output
```

Each test runs in a fresh "server" process. `smoke` plays 25 virtual minutes with every system involved. The other tests each cover one bug.

## Rebuild the place after editing `src/`

```sh
pip install lz4 zstandard
python3 tools/build_place.py Shelterv1.rbxl Shelterv1-fixed.rbxl
```

The script replaces the `Source` of every script that has a file under `src/` and copies all other data byte for byte. It then re-reads the output and checks it.
