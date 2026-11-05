#pragma once
#include <stdint.h>
#include <stdatomic.h>
#ifndef NOVA_CACHED_MEMORY_BASE
#define NOVA_CACHED_MEMORY_BASE 0
#endif
// Only the base address is cached. Size, atomic operations, fences and wait/notify stay unchanged.
#if NOVA_CACHED_MEMORY_BASE
#define NOVA_FUNCTION_MEMORY_BASE(instance) ((uint8_t *)(void *)(instance)->w2c_env_memory->data)
#define NOVA_MEM_ADDR(base, mem, at, width) ((base) ? (void *)((base)+(at)) : (void *)MEM_ADDR(mem, at, width))
#define NOVA_SIMD_ADDRESS(base, mem, at) ((base) ? (_Atomic volatile uint8_t *)(void *)((base)+(at)) : (mem)->data+(at))
#else
#define NOVA_FUNCTION_MEMORY_BASE(instance) NULL
#define NOVA_MEM_ADDR(base, mem, at, width) MEM_ADDR(mem, at, width)
#define NOVA_SIMD_ADDRESS(base, mem, at) ((mem)->data+(at))
#endif
