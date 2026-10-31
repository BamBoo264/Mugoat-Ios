from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
s=(root/'app/Source/NativeAssets.m').read_text()
a=s.index('static const struct {const char *ext;uint32_t legacy,enhanced;} pgResourceVersions')
b=s.index('// The game\'s file index',a)
Path(sys.argv[1]).write_text('#include <stdio.h>\n#include <stdint.h>\n#include <stdbool.h>\n#include <string.h>\n#include <strings.h>\n#include <stdlib.h>\n'+s[a:b])
