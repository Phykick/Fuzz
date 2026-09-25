"""Bundle the shared Combat modules with Vector3/CFrame mocks and run the Luau
unit tests with the stand-alone `luau` CLI.   python3 tests/run_tests.py <luau-binary>"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMBAT = os.path.join(ROOT, "src", "shared", "Combat")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"


def chunk(path):
    return "(function()\n" + open(path).read() + "\nend)()"


def bundle(test_file, clips):
    ref = json.load(open(os.path.join(ROOT, "tests", "reference_poses.json")))
    out = ["local M = " + chunk(os.path.join(ROOT, "tests", "mock_roblox.luau")),
           "Vector3 = M.Vector3; CFrame = M.CFrame",
           "local MODS = {}",
           "MODS.RigData = " + chunk(os.path.join(COMBAT, "RigData.luau")),
           "MODS.Clips = " + chunk(os.path.join(COMBAT, "Clips.luau"))]
    for c in clips:
        out.append('MODS["Anim_%s"] = %s' % (c, chunk(os.path.join(COMBAT, "AnimData", c + ".luau"))))
    out.append("""
function require(m) return m.__value end
local AnimFolder = { FindFirstChild = function(_, n) local v = MODS["Anim_" .. n]; return v and { __value = v } end }
script = { Parent = { RigData = { __value = MODS.RigData }, Clips = { __value = MODS.Clips }, AnimData = AnimFolder } }
""")
    out.append("local PoseDriver = " + chunk(os.path.join(COMBAT, "PoseDriver.luau")))
    out.append("MODS.Geometry = " + chunk(os.path.join(COMBAT, "Geometry.luau")).replace("Vector3.one", "Vector3.new(1, 1, 1)"))
    lines = ["local REF = {}"]
    for k, bones in ref.items():
        lines.append('REF["%s"] = {%s}' % (k, ", ".join("%s = Vector3.new(%r, %r, %r)" % (b, *p) for b, p in bones.items())))
    out.append("\n".join(lines))
    out.append(open(os.path.join(ROOT, "tests", test_file)).read())
    return "\n".join(out)


if __name__ == "__main__":
    attacks = ["Sword_Attack_" + d for d in ("HighRight", "HighLeft", "HorizontalRL", "HorizontalLR", "Thrust")]
    code = 0
    for test, clips in (("posedriver_test.luau", ["Sword_Attack_HighRight", "Bow_FullDraw", "Sword_Idle"]),
                        ("range_test.luau", attacks + ["Sword_Idle"])):
        path = os.path.join(ROOT, "tests", "_bundle_" + test)
        open(path, "w").write(bundle(test, clips))
        r = subprocess.run([LUAU, path], capture_output=True, text=True)
        print("== " + test + "\n" + r.stdout + r.stderr)
        code = code or r.returncode or (1 if "FAIL" in r.stdout else 0)
    sys.exit(code)
