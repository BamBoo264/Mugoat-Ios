#pragma once
#include <stdint.h>
int64_t pg_local_read(const char *path,uint64_t offset,void *buffer,uint32_t length);
void pg_local_reader_close_thread(void);
