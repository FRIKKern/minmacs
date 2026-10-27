// Shared helpers for the clone and freed-size tests. Plain C, header only.
// fileattrs reads the clone attributes with getattrlist.
// extents maps a file to physical extents with F_LOG2PHYS_EXT, as Noo-Noo's extent union does.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    off_t alloc, priv;
    uint64_t cloneid, flags;
    uint32_t refcnt;
    int ok;
} FileAttrs;

// The kernel packs returned attributes in bit order with 4-byte alignment, so 8-byte values
// are read with memcpy.
static inline FileAttrs fileattrs(const char *path) {
    FileAttrs a = {0};
    struct attrlist al = {.bitmapcount = ATTR_BIT_MAP_COUNT, .fileattr = ATTR_FILE_ALLOCSIZE,
        .forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS | ATTR_CMNEXT_CLONE_REFCNT};
    char buf[256];
    if (getattrlist(path, &al, buf, sizeof buf, FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0) return a;
    char *p = buf + sizeof(uint32_t);
    memcpy(&a.alloc, p, 8); p += 8;
    memcpy(&a.priv, p, 8); p += 8;
    memcpy(&a.cloneid, p, 8); p += 8;
    memcpy(&a.flags, p, 8); p += 8;
    memcpy(&a.refcnt, p, 4);
    a.ok = 1;
    return a;
}

// One physical extent, tagged with the index of the file or group that holds it.
typedef struct { uint64_t start, end; int tag; } Extent;
typedef struct { Extent *v; size_t n, cap; } Extents;

static inline void push(Extents *e, uint64_t s, uint64_t len, int tag) {
    if (e->n == e->cap) { e->cap = e->cap ? e->cap * 2 : 1024; e->v = realloc(e->v, e->cap * sizeof(Extent)); }
    e->v[e->n++] = (Extent){s, s + len, tag};
}

// Maps every allocated byte of a regular file. Holes have no mapping and are skipped.
// It opens the file read-only and never reads its data. Returns the bytes mapped, or -1.
static inline long long extents(const char *path, int tag, Extents *out) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return -1; }
    long long mapped = 0;
    off_t off = 0;
    while (off < st.st_size) {
        struct log2phys l = {.l2p_contigbytes = st.st_size - off, .l2p_devoffset = off};
        if (fcntl(fd, F_LOG2PHYS_EXT, &l) != 0 || l.l2p_contigbytes <= 0) { off += 4096; continue; }
        // The mapped length counts whole 4 KB blocks, as allocation does.
        uint64_t len = ((uint64_t)l.l2p_contigbytes + 4095) & ~4095ULL;
        push(out, (uint64_t)l.l2p_devoffset, len, tag);
        mapped += (long long)len;
        off += l.l2p_contigbytes;
    }
    close(fd);
    return mapped;
}

// Sweeps the extents in start order. For each stretch of the device it builds the mask of tags
// that hold it. inS says which tags are in the set to delete; the stretch is freed only when
// every holder is in the set. Tags must be below 64. Returns freed bytes; union gets the bytes
// the set touches at all.
static inline uint64_t freed_bytes(Extents *e, uint64_t inS, uint64_t *unionS) {
    typedef struct { uint64_t at; int tag; int delta; } Ev;
    Ev *ev = malloc(e->n * 2 * sizeof(Ev));
    for (size_t i = 0; i < e->n; i++) {
        ev[2 * i] = (Ev){e->v[i].start, e->v[i].tag, 1};
        ev[2 * i + 1] = (Ev){e->v[i].end, e->v[i].tag, -1};
    }
    qsort_b(ev, e->n * 2, sizeof(Ev), ^int(const void *a, const void *b) {
        const Ev *x = a, *y = b;
        return x->at < y->at ? -1 : x->at > y->at;
    });
    int count[64] = {0};
    uint64_t mask = 0, freed = 0, uni = 0, last = 0;
    for (size_t i = 0; i < e->n * 2; i++) {
        uint64_t at = ev[i].at;
        if (at > last && mask) {
            if (mask & inS) uni += at - last;
            if ((mask & inS) && !(mask & ~inS)) freed += at - last;
        }
        last = at;
        count[ev[i].tag] += ev[i].delta;
        if (count[ev[i].tag] > 0) mask |= 1ULL << ev[i].tag; else mask &= ~(1ULL << ev[i].tag);
    }
    free(ev);
    if (unionS) *unionS = uni;
    return freed;
}

// Reads whether the volume reports clone support and full clone tracking, valid and set.
static inline void volcaps(const char *path, int *cloneValid, int *cloneSet, int *mapValid, int *mapSet) {
    struct attrlist al = {.bitmapcount = ATTR_BIT_MAP_COUNT, .volattr = ATTR_VOL_INFO | ATTR_VOL_CAPABILITIES};
    struct { uint32_t len; vol_capabilities_attr_t caps; } __attribute__((packed)) r;
    struct statfs sf;
    statfs(path, &sf);
    *cloneValid = *cloneSet = *mapValid = *mapSet = -1;
    if (getattrlist(sf.f_mntonname, &al, &r, sizeof r, 0) != 0) return;
    *cloneValid = !!(r.caps.valid[VOL_CAPABILITIES_INTERFACES] & VOL_CAP_INT_CLONE);
    *cloneSet = !!(r.caps.capabilities[VOL_CAPABILITIES_INTERFACES] & VOL_CAP_INT_CLONE);
    *mapValid = !!(r.caps.valid[VOL_CAPABILITIES_FORMAT] & VOL_CAP_FMT_CLONE_MAPPING);
    *mapSet = !!(r.caps.capabilities[VOL_CAPABILITIES_FORMAT] & VOL_CAP_FMT_CLONE_MAPPING);
}
