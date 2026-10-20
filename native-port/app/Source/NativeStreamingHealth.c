// Streaming health for the Health line (GTA-116): how long the engine's streaming requests (textures,
// models, map data) wait before they are loaded, how many are still waiting, and how many it unloads.
//
// Scripts/prepare_streaming_health.py calls these from the engine's rage::strStreamingInfoManager:
// RequestObject → pg_stream_requested, SetObjectToLoaded → pg_stream_loaded, RemoveObject →
// pg_stream_removed. The engine also "requests" objects that are already loaded, to keep them; those
// are skipped by reading the object's status, and an entry leaves the table once its object is no
// longer requested or loading, so "waiting" counts real waits only.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <os/lock.h>

#define SLOTS 16384u		// power of two; requests beyond three quarters of it are counted but not timed
#define SLOW_MS 10000u
extern const uint8_t *pg_engine_memory(uint64_t *size);	// EngineHost.c

// strStreamingInfoManager's object table: a pointer at 11607304 and a count at 11607312, 16 bytes per
// object, its status in the low 2 bits of byte 4: 0 not loaded, 1 loaded, 2 requested, 3 loading.
enum { NOT_LOADED, LOADED, REQUESTED, LOADING, UNKNOWN };
static int status(uint32_t index) {
	uint64_t size, base;
	uint32_t count;
	const uint8_t *m = pg_engine_memory(&size);
	if (!m || size < 11607316) return UNKNOWN;
	memcpy(&base, m + 11607304, 8);
	memcpy(&count, m + 11607312, 4);
	if (index >= count || base + index * 16ull + 16 > size) return UNKNOWN;
	return m[base + index * 16ull + 4] & 3;
}
static struct { uint32_t key, ms; } table[SLOTS];	// key = engine index + 1 (0 = empty), ms = when requested
static uint32_t used, loadedCount, removedCount, waits[512], waitCount;
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

static uint32_t nowMS(void) { return (uint32_t)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000); }
static uint32_t home(uint32_t key) { return (key * 2654435761u) >> 18; }

// Linear probing. Erasing shifts the following entries back, so a lookup never stops at a hole.
static int lookup(uint32_t key) {
	for (uint32_t i = home(key), n = 0; n < SLOTS; i = (i + 1) & (SLOTS - 1), n++) {
		if (!table[i].key) return -1;
		if (table[i].key == key) return (int)i;
	}
	return -1;
}
static void erase(uint32_t i) {
	table[i].key = 0;
	used--;
	for (uint32_t j = (i + 1) & (SLOTS - 1); table[j].key; j = (j + 1) & (SLOTS - 1)) {
		if (((j - home(table[j].key)) & (SLOTS - 1)) >= ((j - i) & (SLOTS - 1))) {
			table[i] = table[j];
			table[j].key = 0;
			i = j;
		}
	}
}

void pg_stream_requested(uint32_t index) {
	if (status(index) == LOADED) return;	// kept, not loaded again
	uint32_t key = index + 1, now = nowMS();
	os_unfair_lock_lock(&lock);
	if (used < SLOTS / 4 * 3) {
		uint32_t i = home(key);
		while (table[i].key && table[i].key != key) i = (i + 1) & (SLOTS - 1);
		if (!table[i].key) { table[i].key = key; table[i].ms = now; used++; }
	}
	os_unfair_lock_unlock(&lock);
}

void pg_stream_loaded(uint32_t index) {
	uint32_t now = nowMS();
	os_unfair_lock_lock(&lock);
	int i = lookup(index + 1);
	if (i >= 0) {
		waits[waitCount < 512 ? waitCount : loadedCount % 512] = now - table[i].ms;
		if (waitCount < 512) waitCount++;
		erase((uint32_t)i);
	}
	loadedCount++;
	os_unfair_lock_unlock(&lock);
}

void pg_stream_removed(uint32_t index) {
	os_unfair_lock_lock(&lock);
	int i = lookup(index + 1);
	if (i >= 0) erase((uint32_t)i);
	removedCount++;
	os_unfair_lock_unlock(&lock);
}

static int byValue(const void *a, const void *b) {
	uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
	return x < y ? -1 : x > y;
}

// Since the last call: out = {waiting now, of those waiting over 10 s, loaded, median wait ms,
// 95th-percentile wait ms, unloaded}.
void PGStreamingHealth(uint64_t out[6]) {
	uint32_t now = nowMS(), waiting = 0, slow = 0, done[1024], doneCount = 0;
	os_unfair_lock_lock(&lock);
	for (uint32_t i = 0; i < SLOTS; i++) {
		if (!table[i].key) continue;
		int state = status(table[i].key - 1);
		if (state != REQUESTED && state != LOADING && state != UNKNOWN) {	// loaded another way, or cancelled
			if (doneCount < 1024) done[doneCount++] = table[i].key;
			continue;
		}
		waiting++;
		if (now - table[i].ms > SLOW_MS) slow++;
	}
	for (uint32_t k = 0; k < doneCount; k++) { int i = lookup(done[k]); if (i >= 0) erase((uint32_t)i); }
	qsort(waits, waitCount, sizeof waits[0], byValue);
	out[0] = waiting;
	out[1] = slow;
	out[2] = loadedCount;
	out[3] = waitCount ? waits[waitCount / 2] : 0;
	out[4] = waitCount ? waits[waitCount * 95 / 100] : 0;
	out[5] = removedCount;
	loadedCount = removedCount = waitCount = 0;
	os_unfair_lock_unlock(&lock);
}
