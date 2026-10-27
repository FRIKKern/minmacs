// How much does removing one pnpm worktree's node_modules free? Read-only.
// Build: clang -O2 -Wall -fblocks -I../clone-refcounts freed.c -o freed
// Usage: freed <set root>... -- <other root>...
//   The set is what would be deleted, such as every node_modules folder of one worktree.
//   The other roots are what may share blocks with it, such as the pnpm store.
// It opens files read-only to map extents and never reads their data. It prints:
//   du        allocated bytes, hard links once, as du -sk counts them
//   private   the sum of ATTR_CMNEXT_PRIVATESIZE, bytes no other file shares
//   union     the extent union of the set, Noo-Noo's UniqueAllocated
//   freed     bytes of the set that no file under the other roots holds
#include "extents.h"
#include <fts.h>
#include <time.h>

typedef struct { uint64_t files, links, sharesAll, mayShare, du, priv, mapped, unmapped; } Tally;

// Walks one root without following links or crossing volumes. tag 0 is the set, tag 1 the rest.
static void walk(const char *root, int tag, Extents *e, Tally *t, dev_t *dev) {
    char *argv[] = {(char *)root, NULL};
    FTS *f = fts_open(argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, NULL);
    if (!f) { perror(root); return; }
    FTSENT *n;
    while ((n = fts_read(f))) {
        if (n->fts_info != FTS_F) continue;
        if (*dev == 0) *dev = n->fts_statp->st_dev;
        // Extents are device offsets, so every file must sit on the same volume.
        if (n->fts_statp->st_dev != *dev) continue;
        t->files++;
        if (n->fts_statp->st_nlink > 1) t->links++;
        if (tag == 0) {
            FileAttrs a = fileattrs(n->fts_accpath);
            // du counts a hard-linked inode once. A per-run inode list would do it exactly;
            // pnpm here clones instead of linking, which the links count shows.
            if (n->fts_statp->st_nlink == 1) t->du += (uint64_t)a.alloc;
            else t->du += (uint64_t)a.alloc / n->fts_statp->st_nlink;
            t->priv += (uint64_t)a.priv;
            if (a.flags & EF_SHARES_ALL_BLOCKS) t->sharesAll++;
            if (a.flags & EF_MAY_SHARE_BLOCKS) t->mayShare++;
        }
        long long m = extents(n->fts_accpath, tag, e);
        if (m < 0) t->unmapped++; else t->mapped += (uint64_t)m;
    }
    fts_close(f);
}

static double now(void) { struct timespec s; clock_gettime(CLOCK_MONOTONIC, &s); return s.tv_sec + s.tv_nsec / 1e9; }
#define MB(x) ((x) / 1048576.0)

int main(int argc, char **argv) {
    Extents e = {0};
    Tally set = {0}, other = {0};
    dev_t dev = 0;
    int tag = 0;
    double t0 = now();
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) { tag = 1; continue; }
        walk(argv[i], tag, &e, tag ? &other : &set, &dev);
    }
    double t1 = now();
    uint64_t uni = 0, freed = freed_bytes(&e, 1, &uni);
    double t2 = now();
    printf("set:    %llu files, %llu with links, %llu share all blocks, %llu may share, %llu not mapped\n",
           set.files, set.links, set.sharesAll, set.mayShare, set.unmapped);
    printf("other:  %llu files, %llu with links, %llu not mapped\n", other.files, other.links, other.unmapped);
    printf("du      %10.1f MB\n", MB((double)set.du));
    printf("private %10.1f MB\n", MB((double)set.priv));
    printf("union   %10.1f MB\n", MB((double)uni));
    printf("freed   %10.1f MB\n", MB((double)freed));
    printf("time    walk and map %.1f s, %.1f us per file; sweep %.2f s over %zu extents\n", t1 - t0,
           (t1 - t0) * 1e6 / (double)(set.files + other.files ? set.files + other.files : 1), t2 - t1, e.n);
    return 0;
}
