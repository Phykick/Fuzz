# Underhaven audio system

## Where things are

| What | Where |
|---|---|
| **AudioConfig**: every sound id, cue, volume, cooldown, 3D range and provenance | `ReplicatedStorage.Audio.AudioConfig` (`src/ReplicatedStorage/Audio/AudioConfig.lua`) |
| **AudioLibrary**: builds the SoundGroups and the Sound objects from AudioConfig | `ReplicatedStorage.Audio.AudioLibrary` |
| **AudioService** (server): builds the library once when the server starts | `ServerScriptService.Server.Services.AudioService` |
| **AudioManager** (client): the only thing that plays sound | `StarterPlayerScripts.Client.Controllers.AudioManager` |
| **AudioDebug** (client): test panel for developers only | `StarterPlayerScripts.Client.Controllers.AudioDebug` |

When the game runs, the server creates:

```
SoundService
├── Master     1      (multiplies every other group)
├── Music      0.35
├── SFX        0.75
├── UI         0.55
├── Ambient    0.45
└── Voice      1      (empty for now: survivor voices later)

ReplicatedStorage.Audio
├── AudioConfig, AudioLibrary
├── UI          Click, Select, Confirm, Cancel, Error, Reward
├── Vault       Generator, Machinery, Electricity, Doors, Elevator, Pipes, Water
├── Characters  Footsteps, Interaction, Injury
├── Events      Alarm, Fire, PowerFailure, WaterFailure, Raid, Explosion, Infestation
├── Resources   Food, Water, Materials, Medicine, Currency
├── Rewards     ResourceCollected, ConstructionComplete, LevelUp, Achievement, Discovery
└── Music
```

Each folder holds one Sound per cue, named after the cue, for example `ReplicatedStorage.Audio.UI.Click.UIClick`. These Sounds and SoundGroups are created at runtime from AudioConfig, so they appear in the Explorer while the game is running, not in edit mode. AudioConfig is the single source of truth.

## Numbers

- **73 cues:** 69 one-shots and 4 continuous layers (vault air, generator hum, water flow, fire).
- **62 distinct audio assets:**
  - 38 are the ids from the audio brief, used unchanged.
  - 24 are Pro Sound Effects picked earlier, for game events the brief has no sound for (gunfire, creatures, fire, family moments, the generator hum, the vault's air bed). They are listed separately as `Assets.Earlier` and can be swapped in one line.
- **45 cues are 3D** (placed where they happen). The rest are 2D: UI, notifications, power and alarm.

## Systems connected

| System | What you hear |
|---|---|
| UI | Every button press clicks. Selecting a room or survivor uses UIButtonSelect. Confirm dialogs use Click Button SOUND, and cancel uses the alternate click, lower. A refused action buzzes. Sounds within 80 ms of each other don't stack: the more important one wins. |
| Construction | Build mode: toggle switch, once even if spammed. Placing a room: toggle switch in 3D at the site, then the Sounds of Success sting. Upgrade: electric whoosh plus the sting. Demolish, rush (charge-up) and repair (switch) have their own sounds. |
| Resources | Only when collected by hand: Coin Drop, pitched per resource, and Coin sound for bolts. The simulation's own deposits are silent. |
| Generator | **Off:** no hum. **Starting** (first worker, or repaired): Electric sound. **Running:** low hum at the nearest visible generators. **Damaged** (breakdown or brownout): occasional Electrical Zaps. **Failed:** Lightning Flashes bursts plus the alarm. **Restored:** start-up plus success sting. |
| Water purifier | Water fountain loop at the nearest visible running purifiers. It slows in a brownout. Occasional drips and sloshes. It starts with the Electric sound, winds down when it stops, and a breakdown leaks (puddle splash). |
| Power failure | Triggered when the grid meets less than half the demand, with hysteresis. You hear Static Zap Blast plus the alarm, the machinery and vault air get quieter, and the water slows. When power returns: Electric sound, machinery fades back in, and a success sting after an outage of more than 5 s. |
| Emergencies | One alarm layer (Alarm Master 19) for fire, infestation, power failure, water failure (dry tanks or a broken purifier), raid and explosion. It bursts at 0.55 when something new goes wrong, then plays quieter reminders after 14, 22 and 30 s while it lasts, and stops at the all clear. It never loops for the whole emergency and never stacks. The UI alert row shows the emergency as before. |
| Fire | Whoosh at the room, crackle there while it burns (louder the bigger it is), sparks if machinery is burning, water splatter while survivors fight it, Water Splash when it's out. Explosions happen only when a rush overloads a machine or raiders breach the door, never for an ordinary fire. |
| Doors | The blast door uses Door Push Open 4 (heavy) when it rolls open or shut, and when explorers leave or return or a wanderer is let in. It is debounced, so an interrupted animation doesn't replay it. Door Long Squeaks 18 is kept for abandoned places in the wasteland. Door Open and Door Close are used for the elevator and any future room doors. |
| Elevator | When a car starts: button (toggle switch), door close, then a motor built from the Electric Whoosh slowed to 0.6. The motor follows the car. On arrival: a clunk (slowed toggle) and door open. Only for on-screen cars when zoomed in, at most once per car every 8 s and one ride every 4 s across the vault. |
| Footsteps | Driven by the walk and run animation's real footfalls, not every frame: the three concrete samples at random, 0.15 to 0.3 volume, 0.95 to 1.05 speed. Water rooms use a wet-floor mapping (puddle step). Footsteps only play zoomed in and near the middle of the screen (the selected survivor always), within a budget of 6 per second for the whole vault. |
| Survivor activities | Starting a repair, drinking, farming, fighting a fire or working a station makes a small sound, only when zoomed in, at most once every 12 s per survivor and one survivor at a time. |
| Ambience | **Low:** the vault's air (Eerie Ambience), always. **Medium:** machinery at visible rooms. **Occasional:** ticks, switches and drips from staffed, powered rooms, at least 2.5 s apart; bedrooms, storage and the cafeteria stay quiet. **Rare:** a distant mechanical sound from an off-screen room every couple of minutes, and "Electricity" (APM music) every 7 to 14 minutes when nothing is wrong. |
| Story moments | A birth plays the Forgotten Memories sting. A death plays a drone. A level-up plays a shimmer. In the wasteland, finding a bunker plays the squeaky door and the sting. A safe return from an expedition plays the success sting. Raids repelled play the sting, and raids lost play a power-down. |
| Combat | Each weapon has its own gunshot, placed where the shooter stands. |
| Volume | The SOUND button (bottom right) opens Master, Music, SFX, Ambient and UI sliders in 10% steps, saved with the shelter. Saving waits 1.5 s after the last tap. |

## Sounds that failed to load

None are known to fail, but this hasn't been run in Studio: Roblox can't be reached from the environment this was built in. The game checks every id when a player joins (`ContentProvider:PreloadAsync`):
- An id that fails is recorded in `AudioConfig.Failed` and listed in the Studio Output.
- The cue moves on to the next id in its own list (for example, the alarm falls back to the brief's other alarms).
- A cue with nothing loadable stays silent and is named in the Output.
- Nothing is ever replaced with a random sound.

The AudioDebug panel's **Report → Output** button prints the same list.

Of the brief's 41 ids, 12 store listings could be confirmed from outside Roblox. The other 29 aren't indexed anywhere reachable, which says nothing about whether they work. Each asset's `checked` field records this.

## Questionable provenance

- **Not used:** **6034003547 "Footstep Module"** is a Model (a script plus sound ids), not audio, and its listing says the sounds are CS:GO footsteps.
- **Not used:** **131700277400105 "ZRK's Advanced Footstep Sounds"** is most likely a Model with scripts. It couldn't be inspected, so nothing from it was inserted.
- **Not used:** **5348162330 "Alarm Sound"** is a community upload of unclear origin (fan sites credit it to "The Sound"). The brief said to use it only if its provenance is acceptable.
- **Used, but flagged:** **9042708412 "Forgotten Memories sting"** is not the official APM upload. Those are 1842074746 and 1845175569.
- **Used, but flagged:** the other community uploads have unverified origins:
  - UI Click 1, UIClick, UIButtonSelect, Click Button SOUND, Coin sound, Coin Drop
  - Electric sound
  - Door Open and Close, Door Open, Door Close
  - the three footstep samples
  - "alarm", "Alarm", "ALARM"
  - Water Splash, Water fountain loop, Water Drop
  - both Explosions
- Every asset is tagged `pse`, `apm` or `community` in AudioConfig, so the community ones are easy to find and replace before a big release. The `pse` and `apm` ones are Roblox's licensed libraries.

## Hooks for later

- `AudioManager:Emergency("CriticalDamage", true/false)` for structural damage or anything else without its own state.
- `AudioManager:Door(key, opening, position, kind)` for room doors, if rooms get door models. Rooms have no doors today, so door sounds come from the blast door and the elevator.
- `AudioManager:Voice(kind, position)` with `AudioConfig.Voice[kind] = { cue names }`, for talking, eating, laughing, arguments, crying, injuries, panic and celebration. The Voice group is ready.
- `AudioConfig.Footsteps.roomSurface` and `.surfaces` map room types to footstep sets; add one when new floor types appear.
- `AudioConfig.RoomActivity` lists sounds per room type; cafeteria, bedrooms and storage are deliberately empty.
- `AudioConfig.Music.tracks` for more music.

## Scripts

- **Created:**
  - `AudioConfig`, `AudioLibrary` and the `ReplicatedStorage.Audio` folder
  - `AudioService`
  - `AudioManager`
  - `AudioDebug`
- **Removed:**
  - `SoundController` (replaced by AudioManager)
  - `SoundBank` (replaced by AudioConfig)
  - `SoundAtlas`, and the generated-sound tooling that went with it
- **Modified (hooks only):**
  - `Main.server.lua` and `Main.client.lua` (load order)
  - `VaultService` (saves the volumes)
  - `StateStore` (passes each action's payload to listeners)
  - `DwellerController` (footsteps, activities)
  - `Render/Animator` (footfall timing)
  - `VaultRenderer` (blast door, elevator cars)
  - `WastelandController` (encounters, shots, loot)
  - `UIController` (confirm dialog)
  - `Ui/Kit`, `RoomPanel`, `DwellerPanel`, `BuildMenu`, `ListModal` (UI cues)
- No third-party scripts were inserted.

## Performance

- At most 14 one-shots play at once. Expendable sounds (footsteps, drips, ticks) are dropped first, and important ones (alarm, explosion) replace the least important.
- Small voice pools per cue (2 by default) are reused, never created per play. 3D sounds hang off attachments on a single invisible part.
- Continuous layers use a fixed set of emitters: 1 for the air, 2 each for generators, water and fire. They pause when silent. Off-screen rooms make no ambient noise.
- The game state is read 4 times a second. Only the listener and fades update every frame.
- Footsteps are budgeted at 6 per second for the whole vault and are off when zoomed out.
- **Concern:** checking every id downloads each audio file once per player when they join, a few MB in total. The checks run one at a time, starting 3 s after joining, so they don't compete with the first load.

## Testing in Studio

1. Press Play. After a few seconds the Output prints `[Audio] N sound assets checked; all of them load`, or lists the ones that failed.
2. Press **F7** (or the AUDIO DEBUG button on the left) for the test panel. It has buttons for:
   - UI click, select, confirm, reward, success sting
   - door, blast door, generator, electrical zap, water, footsteps, elevator
   - alarm on/off, explosion, power failure, power restored, follow game
   - discovery, music, and a report to the Output
3. The panel only exists in Studio, for the game's owner, or for user ids in `AudioConfig.Debug.UserIds`.

Headless tests cover most of this: `python3 tests/run.py`, which includes the 17 `client_audio_tests` and the server test `audio_volumes_saved`.
