"""Bind pinned R007 commands to Nova's existing split wasm2c functions."""
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT.parent / "vendor/mugoat-r007"
SCRIPTS = VENDOR / "native-port/app/Scripts"

def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def main(engine):
    exporter = load("prepare_online_exports")
    generator = load("prepare_online_c")
    mp = (VENDOR / "src/mp.rs").read_text(encoding="utf-8")
    commands = re.findall(r'\("([^"]+)", "([^"]+)"\)', mp.split("const ACTIVE_THREAD_TLS")[0])
    patched, metadata = exporter.prepare(engine.read_bytes(), commands)
    # Use the export analysis for indices only. Nova codegen keeps the original engine and function names.
    for kind, body, _ in exporter.sections(patched):
        if kind != 7:
            continue
        reader = exporter.Reader(body)
        for _ in range(reader.uint()):
            name = reader.string()
            export_kind = reader.data[reader.pos]
            reader.pos += 1
            index = reader.uint()
            if name == "mugoat:tls-base" and export_kind == 3:
                tls = f"w2c_g{index}"
                break
        else:
            raise RuntimeError("R007 TLS export missing")
        break

    generated = ROOT / "Generated"
    header = (generated / "game.h").read_text()
    if not re.search(r"\bu64\s+" + tls + r"\b", header):
        raise RuntimeError(f"Nova generated header does not expose TLS field {tls}")
    prototype = re.compile(r"^(u32|u64|f32|f64|void) (w2c_game_f(\d+))\(w2c_game\* instance((?:,\s+(?:u32|u64|f32|f64) var_p\d+)*)\) \{", re.M)
    symbols = {}
    units = list(generated.glob("game_*.c"))
    for path in units:
        for match in prototype.finditer(path.read_text()):
            result, symbol, index, params = match.groups()
            types = re.findall(r"(u32|u64|f32|f64) var_p", params)
            symbols[int(index)] = f"{result} {symbol}(w2c_game*" + "".join(", " + t for t in types) + ");"
    exports, declarations = [], set()
    missing = []
    for name, index in metadata["indices"].items():
        declaration = symbols.get(index)
        if not declaration:
            missing.append(name)
            continue
        exports.append(name)
        declarations.add(declaration)
        header += f"\n/* export: '{name}' */\n{declaration}\n"
    for name in ("PlayerPedId", "GetEntityCoords", "CreatePed", "CreateVehicle",
                 "RequestModel", "HasModelLoaded", "SetEntityCoordsNoOffset",
                 "TaskEnterVehicle", "SetEntityVelocity", "SetCanAttackFriendly",
                 "SetPedShootsAtCoord", "TaskPlayAnim", "AddExplosion"):
        if "mp:" + name not in exports:
            raise RuntimeError("R007 required Nova command missing: " + name)
    header += "\n/* export: 'mugoat:tls-base' */\nu64* nova_unused_tls(w2c_game*);\n"
    source, _ = generator.generate(header, {"exports": exports})
    source = source.replace('#include <string.h>\n', '#include <string.h>\n' + '\n'.join(sorted(declarations)) + '\n')
    (generated / "MugoatCommands.c").write_text(source)
    hooks = {"script": f"mugoat_script_tick(instance,var_p0,instance->{tls});",
             "explosion": "pg_nova_explosion(var_p0); mugoat_explosion(var_p0);",
             "timewarp": "var_p1=mugoat_time_warp(var_p1);"}
    for hook, index in metadata["hooks"].items():
        count = 0
        for path in units:
            before = path.read_text()
            after = generator.patch_hook(before, index, hooks[hook])
            if after is not None:
                count += 1
                path.write_text('#include "MugoatOnline.h"\n' + after)
        if count != 1:
            raise RuntimeError(f"R007 {hook} matched {count} functions, expected one")
    print(f"R007: linked {len(exports)} typed commands and 3 engine hooks; {len(missing)} optional commands unavailable")

if __name__ == "__main__":
    main(Path(sys.argv[1]))
