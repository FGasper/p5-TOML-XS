#include <stdlib.h>

#include "toml.h"

void tomlxs_free_string(char *ptr) {
    free(ptr);
}

void tomlxs_free_timestamp(toml_timestamp_t *ptr) {
    free(ptr);
}
