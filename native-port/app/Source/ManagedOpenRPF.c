#include "MugoatOnline.h"
#include <stdatomic.h>
static atomic_bool managedOpenRPF;
void PGSetManagedOpenRPFEnabled(bool enabled) {
    atomic_store_explicit(&managedOpenRPF, enabled, memory_order_release);
}
bool PGManagedOpenRPFEnabled(void) {
    return atomic_load_explicit(&managedOpenRPF, memory_order_acquire) && !MugoatOnlineEnabled();
}
