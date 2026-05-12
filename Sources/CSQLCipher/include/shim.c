// Shim to force SPM module compilation
#include "sqlite3.h"
void* __sqlcipher_shim(void) { return (void*)sqlite3_key; }

