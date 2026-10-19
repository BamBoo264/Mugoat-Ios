"""Guard indirect calls against null function pointer traps in w2c_game functions.

Scaleform GFx in GTA V evaluates ActionScript components (such as GAME_STREAM or phone HUD/Minimap).
When a movie clip or Flash object is missing, destroyed, or uninitialized, calling a virtual method
yields table index 0, which triggers WASM_RT_TRAP_CALL_INDIRECT ("Native trap 6") and kills the engine.
This patch guards indirect calls in w2c_game_f91082 and w2c_game_f10006 against index 0 / null func pointers.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
TARGET_FUNCTIONS = ['91082', '10006']
MARK = '/* indirect_call guard */'
PATTERN = re.compile(r'CHECK_CALL_INDIRECT\([^,]+,\s*\([^)]+\)[^,]+,\s*[^,]+,\s*(?P<idx>var_[a-zA-Z0-9]+)\);')

def make_patch_call(ret_val):
    def patch_call(match):
        idx = match.group('idx')
        ret_stmt = f'return {ret_val};' if ret_val else 'return;'
        guard = f'if ({idx} == 0 || {idx} >= instance->w2c_game_T0.size || !instance->w2c_game_T0.data[{idx}].func) {ret_stmt} {MARK}\n  '
        return guard + match.group(0)
    return patch_call

for func_id in TARGET_FUNCTIONS:
    patched = False
    for path in sorted((root / 'Generated').glob('game_*.c')):
        s = path.read_text()
        found = re.search(r'^(?P<ret>\S.*) w2c_game_f' + func_id + r'\(w2c_game\* instance[^;]*\{$', s, re.M)
        if not found:
            continue
        ret_type = found.group('ret').strip()
        ret_val = '' if ret_type == 'void' else '0ull'
        start = found.start()
        end = s.index('\n}\n', start)
        body = s[start:end]
        if MARK in body:
            print(f'indirect_call guard: already patched f{func_id} in {path.name}')
            patched = True
            break
        new_body = PATTERN.sub(make_patch_call(ret_val), body)
        if new_body != body:
            if func_id == '91082':
                if 'if (!var_p0) return 0ull;' not in new_body and 'FUNC_PROLOGUE;\n' in new_body:
                    new_body = new_body.replace('FUNC_PROLOGUE;\n', f'FUNC_PROLOGUE;\n  if (!var_p0) return 0ull; {MARK}\n', 1)
            s = s[:start] + new_body + s[end:]
            path.write_text(s)
            print(f'indirect_call guard: patched f{func_id} in {path.name}')
            patched = True
            break
    if not patched and list((root / 'Generated').glob('game_*.c')):
        print(f'indirect_call guard: warning - f{func_id} not found in Generated/game_*.c')
