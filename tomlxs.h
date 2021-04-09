/* On some systems Perl clobbers free() to be its own special thing.
   That doesn’t work very well with tomlc99’s expectation that we call
   free() on some of its stuff. This works around that by providing a
   means to call free() from an XSUB.
*/

#include "toml.h"

void tomlxs_free_string(char *ptr);

void tomlxs_free_timestamp(toml_timestamp_t *ptr);
