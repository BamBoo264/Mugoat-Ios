#include "MugoatOnline.h"
#include <assert.h>
static bool online;
bool MugoatOnlineEnabled(void) { return online; }
int main(void) {
    assert(!PGManagedOpenRPFEnabled());
    PGSetManagedOpenRPFEnabled(true);
    assert(PGManagedOpenRPFEnabled());
    online = true;
    assert(!PGManagedOpenRPFEnabled());
    online = false;
    PGSetManagedOpenRPFEnabled(false);
    assert(!PGManagedOpenRPFEnabled());
}
