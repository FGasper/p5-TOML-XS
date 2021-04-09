/* On some systems Perl clobbers free() to be its own special thing.
   That doesn’t work very well with tomlc99’s expectation that we call
   free() on some of its stuff. This works around that by providing a
   means to call free() from an XSUB.
*/
void tomlxs_sysfree(void *ptr);
