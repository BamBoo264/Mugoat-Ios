"""Opt-in turbo at the stock transmission boost store; pinned engine only.

The original path is retained when disabled. No executable pattern scanning,
PC offsets, allocator, streaming or reclamation changes.
"""
from pathlib import Path
from engine_names import fn

def patch_body(body):
    if 'pg_native_turbo_boost(' in body:
        return body
    anchor = '  var_B124:;\n  f32_store_shared(wasm_rt_local_memory_base, wasm_rt_local_memory_size, instance->w2c_env_memory, (u64)checked_add_u64(var_j0, 100u), var_f1);'
    if body.count(anchor) != 1:
        raise RuntimeError('Turbo boost store changed; refusing to patch')
    # In this pinned engine, transmission: gear u16@0, RPM f32@64,
    # filtered throttle f32@80, boost f32@100. p7 is seconds per step;
    # p6 retains the previous boost at this exact point in the stock branch.
    insert = '''  var_B124:;
  var_f1 = pg_native_turbo_boost(var_p1, var_p6,
      f32_load_shared(wasm_rt_local_memory_base, wasm_rt_local_memory_size, instance->w2c_env_memory, checked_add_u64(var_p0, 64u)),
      f32_load_shared(wasm_rt_local_memory_base, wasm_rt_local_memory_size, instance->w2c_env_memory, checked_add_u64(var_p0, 80u)),
      i32_load16_u_shared(wasm_rt_local_memory_base, wasm_rt_local_memory_size, instance->w2c_env_memory, var_p0), var_p7, var_f1);
  f32_store_shared(wasm_rt_local_memory_base, wasm_rt_local_memory_size, instance->w2c_env_memory, (u64)checked_add_u64(var_j0, 100u), var_f1);'''
    return body.replace(anchor, insert)

def main():
    root=Path(__file__).resolve().parents[1]
    n=fn('CTransmission::ProcessEngine(CVehicle*, rage::Mat34V const&, rage::Vec3V const&, int, float, float, float)')
    head=f'f32 w2c_game_f{n}(w2c_game* instance, u64 var_p0, u64 var_p1, u64 var_p2, u64 var_p3, u32 var_p4, f32 var_p5, f32 var_p6, f32 var_p7) {{'
    for path in sorted((root/'Generated').glob('game_*.c')):
        text=path.read_text()
        if head not in text: continue
        begin=text.index(head);end=text.index('\n}\n',begin)+3
        text=text[:begin]+patch_body(text[begin:end])+text[end:]
        declaration='extern float pg_native_turbo_boost(uint64_t, float, float, float, uint32_t, float, float);\n'
        if declaration not in text:
            pos=text.index('\n',text.index('#include'))+1
            text=text[:pos]+declaration+text[pos:]
        path.write_text(text)
        print(f'turbo: opt-in transmission adapter f{n} in {path.name}')
        return
    raise RuntimeError('Pinned transmission signature missing')

if __name__=='__main__':main()
