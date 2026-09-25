"""Package src/ into Roblox model files you can insert straight into Studio.

    python3 tools/build_rbxmx.py

build/CombatSystem_ReplicatedStorage.rbxmx    -> right-click ReplicatedStorage > Insert from File
build/CombatSystem_ServerScriptService.rbxmx  -> right-click ServerScriptService > Insert from File
build/CombatSystem_StarterPlayerScripts.rbxmx -> right-click StarterPlayer > StarterPlayerScripts > Insert from File
"""
import itertools
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "build")
_ref = itertools.count(1)


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def item(cls, name, source=None, children=()):
    ref = "RBX%08X" % next(_ref)
    props = ['<string name="Name">%s</string>' % esc(name)]
    if source is not None:
        props.append('<ProtectedString name="Source">%s</ProtectedString>' % cdata(source))
    inner = "".join(children)
    return '<Item class="%s" referent="%s"><Properties>%s</Properties>%s</Item>' % (cls, ref, "".join(props), inner)


def script_item(path):
    base = os.path.basename(path)
    src = open(path, encoding="utf-8").read()
    if base.endswith(".server.luau"):
        return item("Script", base[: -len(".server.luau")], src)
    if base.endswith(".client.luau"):
        return item("LocalScript", base[: -len(".client.luau")], src)
    return item("ModuleScript", base[: -len(".luau")], src)


def folder_item(path):
    kids = []
    for name in sorted(os.listdir(path)):
        full = os.path.join(path, name)
        if os.path.isdir(full):
            kids.append(folder_item(full))
        elif name.endswith(".luau"):
            kids.append(script_item(full))
    return item("Folder", os.path.basename(path), children=kids)


def write(name, body):
    os.makedirs(OUT, exist_ok=True)
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + body + "</roblox>")
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(xml)
    return path


if __name__ == "__main__":
    a = write("CombatSystem_ReplicatedStorage.rbxmx", folder_item(os.path.join(SRC, "shared", "Combat")))
    b = write("CombatSystem_ServerScriptService.rbxmx", script_item(os.path.join(SRC, "server", "CombatServer.server.luau")))
    c = write("CombatSystem_StarterPlayerScripts.rbxmx", script_item(os.path.join(SRC, "client", "CombatClient.client.luau")))
    for p in (a, b, c):
        print("%-60s %7.1f KB" % (os.path.relpath(p, ROOT), os.path.getsize(p) / 1024))
