// Prints clone id, refcount, private size and flags for each path. Read-only, opens no file.
// Build: clang -O2 -Wall -I. cloneinfo.c -o cloneinfo
#include "extents.h"
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        FileAttrs a = fileattrs(argv[i]);
        struct stat st; lstat(argv[i], &st);
        printf("ino %-11llu cloneid %-11llu refcnt %-4u alloc %-9lld private %-9lld flags 0x%llx %s\n", (unsigned long long)st.st_ino,
               (unsigned long long)a.cloneid, a.refcnt, (long long)a.alloc, (long long)a.priv, (unsigned long long)a.flags, argv[i]);
    }
    return 0;
}
