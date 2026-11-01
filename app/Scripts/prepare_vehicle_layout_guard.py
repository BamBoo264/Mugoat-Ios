"""Keep vehicle layout bad entry points in MPBeach DLC from crashing the game at mission 20.

CAnimRateSet::sAnimRateTuningPair::GetRate() const (f80638) iterates vehicle layouts during
DLC loading / mission repeat. When a layout contains an unresolved entry point (bad entry points at idx : 1),
it calls Quitf (f1534) which aborts the game with Trap 5.
Replacing Quitf at the 3638710ull format string site with pg_vehicle_layout_bad_entry_point logs a warning
and allows the validation loop to cleanly continue to the next layout.
"""
from pathlib import Path
from engine_names import fn
import re

root = Path(__file__).resolve().parents[1]
FUNCTION = str(fn('CAnimRateSet::sAnimRateTuningPair::GetRate() const'))
QUITF = str(fn('Quitf(int, char const*, ...)'))

DECLARATION = 'extern void pg_vehicle_layout_bad_entry_point(w2c_game *instance, u64 fmt, u64 args);'

done = False
for path in sorted((root / 'Generated').glob('game_*.c')):
    s = path.read_text()
    func_pattern = r'w2c_game_f' + FUNCTION + r'\(w2c_game\* instance'
    if not re.search(func_pattern, s):
        continue
    start = s.find(f'w2c_game_f{FUNCTION}(')
    if start < 0:
        continue
    # find function start
    fn_start = s.rfind('\n', 0, start) + 1
    fn_end = s.find('\n}\n', start)
    if fn_end < 0:
        continue
    fn_end += 3
    body = s[fn_start:fn_end]
    if 'pg_vehicle_layout_bad_entry_point(' in body:
        print(f'vehicle layout guard: f{FUNCTION} already patched')
        done = True
        break
    if '3638710ull' not in body:
        # Check if the format string address differs or is present
        print(f'vehicle layout guard: 3638710ull not found in f{FUNCTION}, searching for call to f{QUITF}')
    pattern = r'(3638710ull;[\s\S]*?)w2c_game_f' + QUITF + r'\(instance,\s*([^,]+),\s*([^)]+)\);'
    new_body, count = re.subn(pattern, r'\1pg_vehicle_layout_bad_entry_point(instance, \2, \3);', body)
    if count == 0:
        # Fallback: if format string is slightly different constant, replace the last call to QUITF in this function
        pattern_fallback = r'w2c_game_f' + QUITF + r'\(instance,\s*([^,]+),\s*([^)]+)\);'
        matches = list(re.finditer(pattern_fallback, body))
        if matches:
            last_m = matches[-1]
            new_body = body[:last_m.start()] + f'pg_vehicle_layout_bad_entry_point(instance, {last_m.group(1)}, {last_m.group(2)});' + body[last_m.end():]
            count = 1
    if count > 0:
        s = s[:fn_start] + new_body + s[fn_end:]
        if DECLARATION not in s:
            first = re.search(r'^#include "game-[a-z-]*impl\.h"$', s, re.M)
            if first:
                s = s[:first.end()] + '\n' + DECLARATION + s[first.end():]
            else:
                s = DECLARATION + '\n' + s
        path.write_text(s)
        print(f'vehicle layout guard: patched f{FUNCTION} in {path.name}')
        done = True
        break

if not done:
    # If Generated files are not present yet (pre-codegen phase), log info
    print(f'vehicle layout guard: targets f{FUNCTION} and f{QUITF} (will apply during prepare.py)')
