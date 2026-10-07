--!strict
-- Global metrics and balance knobs. Grid metrics MUST match blender/kit_*.py.
local Config = {}

Config.GAME_NAME = "UNDERHAVEN"
Config.SCHEMA_VERSION = 2 -- 2: skills, needs, materials, activities (see SaveService migrations)

-- Grid -------------------------------------------------------------------
Config.UNIT = 6 -- studs per grid column (elevator width)
Config.MODULE_UNITS = 3 -- columns per room module
Config.MODULE_WIDTH = Config.UNIT * Config.MODULE_UNITS
Config.ROW_HEIGHT = 12 -- floor-to-floor
Config.FLOOR_Y = 1 -- floor top inside a row
Config.CEIL_Y = 11
Config.GRID_COLS = 26
Config.GRID_ROWS = 25
Config.MAX_MERGE = 3
Config.LANE_Z_MIN = -1.3
Config.LANE_Z_MAX = 1.5

function Config.cellOrigin(col: number, row: number): Vector3
	return Vector3.new(col * Config.UNIT, -row * Config.ROW_HEIGHT, 0)
end

function Config.worldToCell(pos: Vector3): (number, number)
	return math.floor(pos.X / Config.UNIT), math.floor(-pos.Y / Config.ROW_HEIGHT) + 1
end

-- Simulation -------------------------------------------------------------
Config.SIM_TICK = 1 -- seconds between economy ticks
Config.COMBAT_TICK = 0.25
Config.AUTOSAVE_INTERVAL = 60
Config.OFFLINE_CAP = 8 * 3600
Config.OFFLINE_STEP = 60

Config.WALK_SPEED = 6.5 -- studs / s
Config.ELEVATOR_SPEED = 16 -- studs / s
Config.ELEVATOR_BOARD_TIME = 0.6

-- Survivors eat and drink when their needs run low (Shared/Needs, Server/LifeService); each meal
-- or drink is taken from storage. Children take half portions; pressure makes portions bigger.
Config.MEAL_FOOD = 7
Config.DRINK_WATER = 4.5
Config.BASE_STORAGE = 100 -- see Shared/Resources for per-resource base capacity
Config.START_RESOURCES = { Power = 90, Food = 90, Water = 90, Materials = 150, Bolts = 650, Scrap = 0, MedPatch = 3 }

Config.ARRIVAL_INTERVAL = { 150, 260 } -- seconds between wanderers arriving (if housing allows)
Config.ARRIVAL_SPAWN = { 70, 150 } -- studs from the bunker where a wanderer appears on the surface
Config.ARRIVAL_WALK_SPEED = 5.2 -- studs / s while they trudge to the bunker

-- Families (see Server/Services/FamilyService) ---------------------------
Config.COURT_RATE = 0.55 -- chance per minute that a free pair in Living Quarters hits it off (scaled by CHA)
Config.COURT_TIME = { 18, 40 } -- seconds of chatting + dancing; high Charisma is quicker
Config.PREGNANCY_TIME = 480 -- seconds until the baby arrives
Config.CHILD_GROW_TIME = 900 -- seconds until a child grows up and can work
Config.FAMILY_COOLDOWN = 180 -- seconds before either parent starts another romance

-- Survivors -------------------------------------------------------------
Config.HAPPINESS_DRIFT = 0.25 -- points per tick towards target
Config.REVIVE_BASE = 150
Config.REVIVE_PER_LEVEL = 60 -- each earlier revive of the same survivor adds +50%
Config.REVIVE_WINDOW = 600 -- seconds of play before the dead are laid to rest for good
Config.STARVE_DAMAGE = 0.22 -- health / s while food or water is out
Config.REGEN_LIVING = 0.12 -- health / s while relaxing in Living Quarters
Config.REGEN_OTHER = 0.025 -- health / s anywhere else
Config.MEDPATCH_HEAL = 0.45 -- share of max health one MedPatch restores
-- Someone the Overseer assigns works this many seconds after arriving before a break: only an
-- urgent need (Needs.Defs[].urgent), being badly hurt or danger pulls them away sooner, and the
-- emergency dispatcher leaves them be. Shorter than any need takes to drop from seek to urgent.
Config.ASSIGN_SHIFT = 90

-- Wanderers wait outside the bunker until the Overseer lets them in.
Config.QUEUE_MAX = 4
Config.QUEUE_PATIENCE = 600 -- seconds before a waiting wanderer gives up

Config.RUSH_BASE_FAIL = 0.22
Config.RUSH_STACK_FAIL = 0.12
Config.RUSH_COOLDOWN = 20
Config.RUSH_MINUTES = 2

Config.INCIDENT_MIN_GAP = 240 -- shrinks with pressure (Shared/Difficulty)
Config.INCIDENT_CHANCE_PER_MIN = 0.15 -- grows with pressure
Config.RAID_FIRST_DELAY = 420
Config.RAID_INTERVAL = { 720, 1200 } -- shrinks with pressure

-- Pressure curve (Shared/Difficulty): 0 for a new shelter, 1 for an old and crowded one.
Config.PRESSURE_MINUTES = 120 -- play time until shelter age maxes out
Config.PRESSURE_POP = 30 -- population at which shelter size maxes out

Config.ACTION_RATE_LIMIT = 15 -- requests per second per player

return Config
