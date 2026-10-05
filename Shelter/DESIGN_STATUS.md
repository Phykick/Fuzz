# Underhaven: where the game stands against the design brief

Status per section of the "Survival + Life Sim + Colony Management" brief. **Done** means it's in the game and checked. **Partial** means the core is in and the listed parts are missing. **Later** means the brief itself puts it after the vertical slice.

## Vertical slice (§36): complete

| Slice item | Status | Where |
|---|---|---|
| Rooms: elevator, generator, water purifier, hydroponics + cafeteria, bedrooms, storage, medbay | Done (also a workshop) | `Shared/RoomDefinitions` |
| 5–10 survivors | Done: 6 founders, with jobs, a couple and two friendships | `VaultService.seedNewShelter` |
| Food, water, power, materials: production, consumption, storage, shortages | Done | `ResourceService`, `Simulation`, `Resources` |
| Hunger, thirst, energy, happiness, jobs, personalities, relationships, autonomous movement | Done | `LifeService`, `Needs`, `DwellerDefinitions` |
| Construct, upgrade, merge, capacity, furnished rooms | Done | `RoomService`, `Grid`, client `RoomDressing` |
| Event: fire / power failure | Done: fires, infestations, breakdowns (power failure), raids | `IncidentService`, `CombatService` |
| HUD production/consumption, warnings, survivor inspection | Done | client `Hud`, `UIController.refreshAlerts`, `DwellerPanel` |
| 2.5D camera, zoom, pan, follow a survivor | Done | client `CameraController` |
| Persistent colony | Done: session locks, migrations, repair of damaged saves | `SaveService`, `VaultService` |

## Section by section

| § | Topic | Status | Notes |
|---|---|---|---|
| 3–4 | Resources | Done | Food, Water, Power, Materials, Medicine, Population, Bolts (currency). A new resource is one entry in `Resources.Defs`. |
| 5 | Production chains | Partial | Water → Hydroponics → Food; Water → Medbay → Medicine; power grid → every room; scrap → Materials. Fuel, chemicals and components come later. |
| 6 | Power matters | Done | Every room draws power; brownouts are graded; lights flicker and machines slow; rooms produce less. |
| 7 | Consumption scales with population | Done | Meal by meal per survivor, scaled up by the pressure curve. |
| 8 | Storage | Partial | Caps, waste when full, Storage Depot, fire destroys stored goods, raids steal. Water contamination is missing. |
| 9 | Escalating shortages | Partial | Need stages: mood → work speed → health → death. Illness and stress aren't modelled yet. |
| 10 | Living simulation | Done | Needs-driven routines. **New:** survivors elsewhere respond to fires, infestations and paid repairs (the "Sarah runs to Generator 2" story). |
| 11 | Needs | Partial | Hunger, thirst, energy, health, happiness. Hygiene, social, fun, comfort, safety and stress slot into `Needs.Defs`, but each also needs rooms (bathroom, recreation). |
| 12 | Personality | Done | Name, age, looks, 2 of 13 traits, 9 skills, job, relationships, memories. A written history is missing. |
| 13 | Jobs | Done | Skills drive output per room. |
| 14 | Assignment has consequences | Done | **New:** a partner or family member worries while someone is out exploring, and is relieved when they're back. |
| 15 | Population is a liability | Done | More mouths, beds and power, and the pressure curve brings more incidents and bigger raids. |
| 16 | Arrivals | Partial | Wanderers walk up and wait; you can let them in or turn them away after reading their profile. Quarantine, injured or sick arrivals are missing. |
| 17 | Housing | Done | Beds cap who can be let in; overcrowding hurts mood; people sleep on the floor without a bunk. |
| 18 | Relationships | Done | Friends, rivals, couples; people visit injured partners in the Medbay. |
| 19 | Families | Done (ahead of plan) | Courting, pregnancy, children who grow up into workers. |
| 20 | Rooms as living spaces | Partial | Cafeteria meals and chat, Medbay beds and visits, bunks. A recreation room is missing. |
| 21 | Building | Partial | Build, merge up to 3 modules, 3 levels, demolish. Free placement of furniture and decor, and component or research costs, are missing. |
| 22 | Hard choices | Done | Repairs cost the same Materials that construction does. |
| 23 | Events | Partial | Fire, two creature infestations, breakdowns and raids, all chaining through the economy. Contamination, disease, structural damage and conflicts are missing. |
| 24 | Security | Partial | Guards at the blast door, weapons, raids. Security rooms, armory and training are missing. |
| 25–26 | Exploration | Partial | Solo explorers bring back loot, food, medicine, scrap and recruits, with real risk. Teams, destination choice and trade are missing. |
| 27 | Long-term progression | Partial | Early game plays well. Mid and late game content (districts, research) is missing. |
| 28 | Multiplayer-ready | Done (architecture) | One persistent colony per player, server authoritative, clients send intents only. |
| 29–30 | Visuals, characters | Done | Custom Blender meshes, profession outfits. Not re-checked visually here; this environment can't run Studio. |
| — | Sound | Done | Full audio system (`AUDIO.md`): every id from the audio brief plus earlier Pro Sound Effects picks, one AudioConfig, SoundGroups (Master/Music/SFX/UI/Ambient/Voice), 3D sound at rooms and survivors, footsteps from the walk cycle, one controlled alarm for all emergencies, power failure and restore, generator and purifier states, doors, elevator, construction, volume sliders saved per player, a developer test panel. Every id is checked at runtime; failures are recorded, never replaced. |
| 31–34 | Camera, HUD, alerts, visible simulation | Done | **New:** every fire, infestation, breakdown and raid shows in the alert row; responders run to emergencies with a bark. |
| 35 | Chain reactions | Partial | Power → water → thirst → mood → output works. Sickness is the missing link to "Medbay overloaded". |
| 38 | Performance | Done (server) | Decisions are staggered and the client uses LOD. Measured server cost per simulated second: 2 ms at 200 survivors, 5 ms at 500, 5.5 ms at 500 with three fires (`tests/run.py scale_*`). Client cost at 500 characters isn't measured. |

## Suggested next steps (in the brief's priority order)

1. **Illness:** shortages and infestations make survivors sick, and the Medbay fills up (completes §9 and §35).
2. **Stress plus one comfort need:** add Stress, and Social or Fun with a Recreation room (§11, §20).
3. **Water contamination** as a second storage threat (§8, §23).
4. **Arrival decisions:** injured or sick wanderers and a quarantine choice (§16).
5. **Components:** Workshop turns materials into components that upgrades need (§5, §21).
