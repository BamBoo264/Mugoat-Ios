"""Keep the existing typed texture-dictionary hook and the engine's true load result.

The recovery host returns the original loaded argument unchanged. This hook does not
mark absent dictionaries as loaded or skip mission/script conditions.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
FUNCTION = '50534'
MARK = 'pg_streamed_txd_loaded('
done = False
for path in sorted((root / 'Generated').glob('game_*.c')):
    s = path.read_text()
    found = re.search(r'^u32 w2c_game_f' + FUNCTION + r'\(w2c_game\* instance, u64 var_p0\) \{$', s, re.M)
    if not found: continue
    start, end = found.start(), s.index('\n}\n', found.start())
    body = s[start:end]
    if MARK not in body:
        # Keep the name: var_p0 is reused as a pointer while the store is searched.
        prologue = '  FUNC_PROLOGUE;\n'
        tail = '    var_B1:;\n    var_i0 = var_l2;\n    goto var_Bfunc;\n'
        if body.count(prologue) != 1 or body.count(tail) != 1 or 'var_l3 = var_i1;' not in body:
            raise RuntimeError(f'Pinned f{FUNCTION} (graphics_commands::HasStreamedTxdLoaded) changed')
        body = body.replace(prologue, prologue + '  u64 pg_txd_name = var_p0;\n', 1)
        body = body.replace(tail, '    var_B1:;\n    var_l2 = pg_streamed_txd_loaded(instance, pg_txd_name, var_l3, var_l2);\n'
                            '    var_i0 = var_l2;\n    goto var_Bfunc;\n', 1)
        s = s[:start] + body + s[end:]
        include = '#include "game-missing-txd-impl.h"'
        if include not in s: s = s.replace('#include "game-impl.h"', include, 1)
        path.write_text(s)
    done = True
    break
if not done: raise RuntimeError(f'Pinned function f{FUNCTION} not found')
(root / 'Generated/game-missing-txd-impl.h').write_text(
    '#include "game-impl.h"\n'
    'extern u32 pg_streamed_txd_loaded(w2c_game *instance, u64 name, u32 hash, u32 loaded);\n')
