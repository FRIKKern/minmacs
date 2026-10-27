// How much does removing one pnpm worktree's node_modules free? Read-only, and no file is opened.
// The extent union in freed.c opens every file, and on this Mac each open costs about 6 ms,
// because Microsoft Defender's Endpoint Security extension checks it. This program reads only
// directories, with getattrlistbulk, as the Sizer's periodic tier would.
// Build: clang -O2 -Wall bulk.c -o bulk
// Usage: bulk <set root>... -- <other root>...
// For every file it reads allocated size, private size, clone id, clone refcount and flags.
// A clone id's refcount counts every full clone of that data, wherever it lives. So for each clone
// id the set holds, it can say whether all holders are in the set, all others are in the other
// roots, or some sit elsewhere. clones.c showed refcounts are exact for full clones on this volume.
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <sys/vnode.h>
#include <time.h>
#include <unistd.h>

typedef struct { uint64_t id; uint32_t ref, inSet, inOther; uint64_t alloc; } Fam;
static Fam *fams; static size_t famCap = 1 << 22;
static Fam *fam(uint64_t id) {
    size_t i = (id * 0x9E3779B97F4A7C15ULL) & (famCap - 1);
    while (fams[i].id && fams[i].id != id) i = (i + 1) & (famCap - 1);
    fams[i].id = id;
    return &fams[i];
}
// Hard links are one inode: count each file id once.
static uint64_t *ids; static size_t idCap = 1 << 22;
static int seen(uint64_t id) {
    size_t i = (id * 0x9E3779B97F4A7C15ULL) & (idCap - 1);
    while (ids[i] && ids[i] != id) i = (i + 1) & (idCap - 1);
    if (ids[i]) return 1;
    ids[i] = id; return 0;
}

typedef struct { uint64_t files, dirs, du, priv, sharesAll, partial, links, errors; } Tally;

static void walk(const char *root, int other, Tally *t) {
    struct attrlist al = {.bitmapcount = ATTR_BIT_MAP_COUNT,
        .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID,
        .fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE,
        .forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS | ATTR_CMNEXT_CLONE_REFCNT};
    size_t cap = 1024, n = 0;
    char **stack = malloc(cap * sizeof(char *));
    stack[n++] = strdup(root);
    static char buf[256 * 1024];
    while (n) {
        char *dir = stack[--n];
        int fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
        if (fd < 0) { t->errors++; free(dir); continue; }
        t->dirs++;
        int count;
        while ((count = getattrlistbulk(fd, &al, buf, sizeof buf, FSOPT_ATTR_CMN_EXTENDED | FSOPT_PACK_INVAL_ATTRS)) > 0) {
            char *e = buf;
            for (int i = 0; i < count; i++) {
                char *p = e;
                uint32_t len; memcpy(&len, p, 4); p += 4;
                attribute_set_t ret; memcpy(&ret, p, sizeof ret); p += sizeof ret;
                attrreference_t nameRef; memcpy(&nameRef, p, sizeof nameRef);
                const char *name = p + nameRef.attr_dataoffset; p += sizeof nameRef;
                uint32_t type; memcpy(&type, p, 4); p += 4;
                uint64_t fileid; memcpy(&fileid, p, 8); p += 8;
                if (type == VDIR) {
                    if (n == cap) { cap *= 2; stack = realloc(stack, cap * sizeof(char *)); }
                    size_t l = strlen(dir) + strlen(name) + 2;
                    char *c = malloc(l); snprintf(c, l, "%s/%s", dir, name);
                    stack[n++] = c;
                } else if (type == VREG) {
                    uint32_t links; memcpy(&links, p, 4); p += 4;
                    off_t alloc; memcpy(&alloc, p, 8); p += 8;
                    off_t priv; memcpy(&priv, p, 8); p += 8;
                    uint64_t cid; memcpy(&cid, p, 8); p += 8;
                    uint64_t flags; memcpy(&flags, p, 8); p += 8;
                    uint32_t ref; memcpy(&ref, p, 4);
                    if (links > 1 && seen(fileid)) { e += len; continue; }
                    if (!other) {
                        t->files++; t->du += (uint64_t)alloc; t->priv += (uint64_t)priv;
                        if (links > 1) t->links++;
                        if (flags & EF_SHARES_ALL_BLOCKS) t->sharesAll++;
                        else if (flags & EF_MAY_SHARE_BLOCKS) t->partial++;
                    } else t->files++;
                    if (ref > 1) {
                        Fam *f = fam(cid);
                        f->ref = ref; f->alloc = (uint64_t)alloc;
                        if (other) f->inOther++; else f->inSet++;
                    }
                }
                e += len;
            }
        }
        close(fd);
        free(dir);
    }
    free(stack);
}

#define MB(x) ((double)(x) / 1048576.0)
int main(int argc, char **argv) {
    fams = calloc(famCap, sizeof(Fam)); ids = calloc(idCap, sizeof(uint64_t));
    Tally set = {0}, oth = {0};
    int other = 0;
    struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--")) { other = 1; continue; }
        walk(argv[i], other, other ? &oth : &set);
    }
    clock_gettime(CLOCK_MONOTONIC, &b);
    uint64_t whole = 0, withOther = 0, elsewhere = 0, nWhole = 0, nOther = 0, nElse = 0, elseSeen = 0;
    for (size_t i = 0; i < famCap; i++) {
        Fam *f = &fams[i];
        if (!f->id || !f->inSet) continue;
        if (f->inSet >= f->ref) { whole += f->alloc; nWhole++; }
        else if (f->inSet + f->inOther >= f->ref) { withOther += f->alloc; nOther++; }
        else { elsewhere += f->alloc; nElse++; if (f->inOther) elseSeen++; }
    }
    double s = (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
    printf("set:   %llu files in %llu folders, %llu share all blocks, %llu share some, %llu hard-linked, %llu unreadable folders\n",
           set.files, set.dirs, set.sharesAll, set.partial, set.links, set.errors);
    printf("other: %llu files in %llu folders\n", oth.files, oth.dirs);
    printf("du                                 %10.1f MB\n", MB(set.du));
    printf("private, freed for sure            %10.1f MB\n", MB(set.priv));
    printf("clone ids held only by the set     %10.1f MB  (%llu ids)\n", MB(whole), nWhole);
    printf("clone ids shared with other roots  %10.1f MB  (%llu ids)\n", MB(withOther), nOther);
    printf("clone ids also held elsewhere      %10.1f MB  (%llu ids, %llu of them also in the other roots)\n", MB(elsewhere), nElse, elseSeen);
    printf("estimate freed = private + ids held only by the set: %.1f MB\n", MB(set.priv + whole));
    printf("time %.1f s, %.1f us per file\n", s, s * 1e6 / (double)(set.files + oth.files ? set.files + oth.files : 1));
    return 0;
}
