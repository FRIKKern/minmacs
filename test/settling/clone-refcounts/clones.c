// Are clone refcounts exact on a volume that reports clone mapping valid but not set?
// Fixtures only: every file lives in the folder given as the first argument.
// Build: clang -O2 -Wall -fblocks clones.c -o clones     Run: ./clones <empty folder on APFS>
//
// It makes one 16 MB file, clones it, clones a clone, hard-links it, changes one block of a clone,
// and deletes a clone. After each step it prints clone id, refcount, private size and flags.
// Then it compares three ways to say what deleting a set frees:
//   priv    the sum of ATTR_CMNEXT_PRIVATESIZE
//   rule    priv, plus the size of a clone id once when every holder of that id is in the set,
//           by its refcount. This is the rule SYNTHESIS.md A3 proposes for the Sizer.
//   truth   the extent union over every fixture file: bytes held only by files in the set.
// Last it deletes sets for real and reads the statfs delta.
#include "extents.h"
#include <copyfile.h>
#include <sys/clonefile.h>
#include <time.h>

#define MB (1024 * 1024)
static char dir[1024];
static const char *names[] = {"base", "c1", "c2", "c3", "hl", "c4"};
enum { NFILES = 6 };

static void p(const char *n, char *out) { snprintf(out, 1100, "%s/%s", dir, n); }

static void show(const char *step) {
    printf("-- %s\n", step);
    for (int i = 0; i < NFILES; i++) {
        char path[1100]; p(names[i], path);
        struct stat st;
        if (lstat(path, &st) != 0) continue;
        FileAttrs a = fileattrs(path);
        printf("   %-5s ino %-10llu nlink %u alloc %6.2f MB  private %6.2f MB  cloneid %-12llu refcnt %u flags 0x%llx\n",
               names[i], (unsigned long long)st.st_ino, st.st_nlink, a.alloc / (double)MB, a.priv / (double)MB,
               (unsigned long long)a.cloneid, a.refcnt, (unsigned long long)a.flags);
    }
}

// Prints priv, rule and truth for the set of file indexes in mask.
static void predict(const char *label, unsigned mask) {
    Extents e = {0};
    double priv = 0;
    typedef struct { uint64_t id; uint32_t ref, seen; off_t alloc; } Fam;
    Fam fam[NFILES]; int nf = 0;
    uint64_t seenIno[NFILES]; int ni = 0;
    for (int i = 0; i < NFILES; i++) {
        char path[1100]; p(names[i], path);
        struct stat st;
        if (lstat(path, &st) != 0) continue;
        extents(path, i, &e);
        if (!(mask & (1u << i))) continue;
        // A hard link is the same inode: count it once, as du does.
        int dup = 0;
        for (int k = 0; k < ni; k++) if (seenIno[k] == st.st_ino) dup = 1;
        if (dup) continue;
        seenIno[ni++] = st.st_ino;
        FileAttrs a = fileattrs(path);
        priv += a.priv;
        if (a.refcnt > 1) {
            int k = 0;
            while (k < nf && fam[k].id != a.cloneid) k++;
            if (k == nf) fam[nf++] = (Fam){a.cloneid, a.refcnt, 0, a.alloc};
            fam[k].seen++;
        }
    }
    double rule = priv;
    for (int k = 0; k < nf; k++) if (fam[k].seen >= fam[k].ref) rule += fam[k].alloc;
    // Tags in the set: every index in mask. Hard links share extents, so they fall out by themselves.
    uint64_t uni = 0;
    uint64_t truth = freed_bytes(&e, mask, &uni);
    printf("   %-28s priv %7.2f  rule %7.2f  truth %7.2f  union %7.2f MB\n", label, priv / MB, rule / MB,
           truth / (double)MB, uni / (double)MB);
    free(e.v);
}

static uint64_t freeBytes(void) {
    struct statfs s;
    sync();
    statfs(dir, &s);
    return (uint64_t)s.f_bavail * s.f_bsize;
}

// After a clone is deleted, how long until the others' refcount drops? Runs n trials and prints
// how many read a stale refcount right after unlink, and the longest wait until it was right.
static int lag(int n) {
    char a[1100], b[1100], c[1100];
    p("lag-a", a); p("lag-b", b); p("lag-c", c);
    char *buf = malloc(1 << 20);
    int stale = 0, staleClone = 0; double worst = 0;
    for (int t = 0; t < n; t++) {
        int fd = open(a, O_CREAT | O_TRUNC | O_WRONLY, 0644);
        arc4random_buf(buf, 1 << 20); write(fd, buf, 1 << 20); fcntl(fd, F_FULLFSYNC); close(fd);
        clonefile(a, b, 0); clonefile(a, c, 0);
        if (fileattrs(a).refcnt != 3) staleClone++;
        unlink(b);
        struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
        uint32_t r = fileattrs(c).refcnt;
        if (r != 2) stale++;
        while (r != 2) {
            usleep(100);
            r = fileattrs(c).refcnt;
            clock_gettime(CLOCK_MONOTONIC, &t1);
            double ms = (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
            if (ms > worst) worst = ms;
            if (ms > 5000) { printf("   trial %d: refcount still %u after 5 s\n", t, r); break; }
        }
        unlink(c); unlink(a);
    }
    printf("lag: %d of %d trials read a stale refcount right after clonefile\n", staleClone, n);
    printf("lag: %d of %d trials read a stale refcount right after unlink; longest wait %.1f ms\n", stale, n, worst);
    free(buf);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: clones <empty folder> [lag <trials>]\n"); return 2; }
    snprintf(dir, sizeof dir, "%s", argv[1]);
    if (argc > 3 && !strcmp(argv[2], "lag")) return lag(atoi(argv[3]));
    int cv, cs, mv, ms;
    volcaps(dir, &cv, &cs, &mv, &ms);
    struct statfs sf; statfs(dir, &sf);
    printf("volume %s (%s): clone valid %d set %d, clone mapping valid %d set %d\n", sf.f_mntonname, sf.f_fstypename, cv, cs, mv, ms);

    char base[1100], c1[1100], c2[1100], c3[1100], hl[1100], c4[1100];
    p("base", base); p("c1", c1); p("c2", c2); p("c3", c3); p("hl", hl); p("c4", c4);
    // 16 MB of random bytes, so no block can be deduplicated or compressed.
    int fd = open(base, O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (fd < 0) { perror(base); return 1; }
    char *buf = malloc(MB);
    for (int i = 0; i < 16; i++) { arc4random_buf(buf, MB); write(fd, buf, MB); }
    fcntl(fd, F_FULLFSYNC); close(fd);
    show("base only");

    clonefile(base, c1, 0); clonefile(base, c2, 0);
    show("base, c1 and c2 are clones of base");
    clonefile(c1, c3, 0);
    show("c3 is a clone of c1");
    link(base, hl);
    show("hl is a hard link to base");

    // Change one 4 KB block in the middle of c2. It now shares all but one block.
    fd = open(c2, O_WRONLY);
    arc4random_buf(buf, 4096); pwrite(fd, buf, 4096, 8 * MB); fcntl(fd, F_FULLFSYNC); close(fd);
    show("one block of c2 changed");

    // c4 is a clone of c2, so a partial clone has a full clone of its own.
    clonefile(c2, c4, 0);
    show("c4 is a clone of c2");

    printf("-- what deleting each set frees\n");
    predict("{c3}", 1u << 3);
    predict("{c2}", 1u << 2);
    predict("{c2,c4}", 1u << 2 | 1u << 5);
    predict("{base}", 1u << 0);
    predict("{base,hl}", 1u << 0 | 1u << 4);
    predict("{base,hl,c1,c3}", 1u << 0 | 1u << 4 | 1u << 1 | 1u << 3);
    predict("{all}", 0x3f);

    unlink(c1);
    show("c1 deleted");
    printf("-- after c1 is gone\n");
    predict("{base,hl,c3}", 1u << 0 | 1u << 4 | 1u << 3);
    predict("{all}", 0x3f);

    // The real thing: delete files one step at a time and read the statfs delta.
    // Other writers on the volume add noise, so each step is small and checked against truth.
    printf("-- statfs delta on delete (the volume is shared, so a few KB of noise is normal)\n");
    uint64_t before = freeBytes();
    unlink(c3);
    printf("   delete c3:            freed %7.2f MB\n", ((double)freeBytes() - (double)before) / MB);
    before = freeBytes();
    unlink(c4);
    printf("   delete c4:            freed %7.2f MB\n", ((double)freeBytes() - (double)before) / MB);
    show("c3 and c4 deleted: base and hl are one inode, c2 is a partial clone of it");
    printf("-- the case where the rule counts too little\n");
    predict("{c2}", 1u << 2);
    predict("{base,hl}", 1u << 0 | 1u << 4);
    predict("{base,hl,c2}", 1u << 0 | 1u << 4 | 1u << 2);
    before = freeBytes();
    unlink(c2);
    printf("   delete c2:            freed %7.2f MB\n", ((double)freeBytes() - (double)before) / MB);
    before = freeBytes();
    unlink(base); unlink(hl);
    printf("   delete base and hl:   freed %7.2f MB\n", ((double)freeBytes() - (double)before) / MB);
    free(buf);
    return 0;
}
