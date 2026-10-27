// The clone-aware Sizer, pattern P16. Both walks run in the calling process: the worker child of P4 calls them,
// and the CLI may too. Ported from NN internal/sizer, with the rules TESTS.md question 11 measured on APFS.
//
// quick, tier 1: getattrlistbulk with allocated size, private size, clone id, clone refcount and link count.
//   A file's private bytes are freed. A full clone family's shared bytes count once, and only when every holder
//   the refcount names is in the walk. A hard-linked inode counts only when all its links are in the walk.
//   TESTS.md question 11 calls this an estimate: a partial clone can share blocks with a family it left.
// exact, tier 2: the extent union. Every inode is mapped with F_LOG2PHYS_EXT. A device stretch is freed when it
//   is private to one inode, or when two or more inodes of the set hold it and no inode of the set is known to
//   share it outside: a hard link outside the roots, or a clone family whose refcount names a holder outside.
//   Question 14 found the union too slow for large trees, so past kExactBudget it gives the quick estimate.
#import "Core/Know/MMSizer.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/vnode.h>
#include <unistd.h>

static const NSTimeInterval kExactBudget = 30;   // seconds; past it exact gives the estimate
static const NSUInteger kExactMaxFiles = 200000;

#pragma mark - One walk

/// One file as getattrlistbulk returns it.
typedef struct {
    uint64_t fileID, cloneID, flags;
    uint64_t alloc, priv;
    uint32_t links, refcnt;
    dev_t dev;
    BOOL hasPriv, hasClone, hasRefcnt;
} MMFileFacts;

typedef void (^MMFileVisit)(const MMFileFacts *f, int dirfd, const char *name);

/// The packed entry of one getattrlistbulk result, in bit order, with FSOPT_PACK_INVAL_ATTRS so the layout is fixed.
/// Values are read with memcpy, because 8-byte fields sit on 4-byte boundaries.
static BOOL Unpack(const char *entry, MMFileFacts *f, fsobj_type_t *type, const char **name) {
    const char *p = entry + sizeof(uint32_t);
    attribute_set_t got; memcpy(&got, p, sizeof got); p += sizeof got;
    attrreference_t nameRef; memcpy(&nameRef, p, sizeof nameRef);
    *name = p + nameRef.attr_dataoffset; p += sizeof nameRef;
    memcpy(&f->dev, p, sizeof(dev_t)); p += sizeof(dev_t);
    memcpy(type, p, sizeof(fsobj_type_t)); p += sizeof(fsobj_type_t);
    memcpy(&f->fileID, p, 8); p += 8;
    memcpy(&f->links, p, 4); p += 4;
    off_t alloc; memcpy(&alloc, p, 8); p += 8;
    off_t priv; memcpy(&priv, p, 8); p += 8;
    memcpy(&f->cloneID, p, 8); p += 8;
    memcpy(&f->flags, p, 8); p += 8;
    memcpy(&f->refcnt, p, 4);
    f->alloc = alloc > 0 ? (uint64_t)alloc : 0;
    f->priv = priv > 0 ? (uint64_t)priv : 0;
    f->hasPriv = (got.forkattr & ATTR_CMNEXT_PRIVATESIZE) != 0;
    f->hasClone = (got.forkattr & ATTR_CMNEXT_CLONEID) != 0;
    f->hasRefcnt = (got.forkattr & ATTR_CMNEXT_CLONE_REFCNT) != 0;
    if (!(got.fileattr & ATTR_FILE_LINKCOUNT)) f->links = 1;
    return YES;
}

/// Walks the folder dirfd with getattrlistbulk, calls visit for every regular file, and stays on device dev.
/// Symlinks are never followed. A folder it cannot open counts one error.
static void WalkDir(int dirfd, dev_t dev, NSInteger *errors, BOOL (^stop)(void), MMFileVisit visit) {
    struct attrlist al = {
        .bitmapcount = ATTR_BIT_MAP_COUNT,
        .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID,
        .fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE,
        .forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS | ATTR_CMNEXT_CLONE_REFCNT,
    };
    static const size_t kBuf = 256 * 1024;
    char *buf = malloc(kBuf);
    if (!buf) { (*errors)++; return; }
    for (;;) {
        if (stop && stop()) break;
        int n = getattrlistbulk(dirfd, &al, buf, kBuf, FSOPT_PACK_INVAL_ATTRS | FSOPT_ATTR_CMN_EXTENDED);
        if (n < 0) { if (errno == EINTR) continue; (*errors)++; break; }
        if (n == 0) break;
        const char *entry = buf;
        for (int i = 0; i < n; i++) {
            uint32_t len; memcpy(&len, entry, sizeof len);
            MMFileFacts f = {0}; fsobj_type_t type = VNON; const char *name = "";
            Unpack(entry, &f, &type, &name);
            entry += len;
            if (f.dev != dev) continue;   // another volume mounted inside the tree
            if (type == VREG) visit(&f, dirfd, name);
            else if (type == VDIR) {
                int sub = openat(dirfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                if (sub < 0) { (*errors)++; continue; }
                WalkDir(sub, dev, errors, stop, visit);
                close(sub);
            }
        }
    }
    free(buf);
}

/// Walks root, a folder or one file. Returns NO when root cannot be read at all.
static BOOL WalkRoot(NSString *root, NSInteger *errors, BOOL (^stop)(void), MMFileVisit visit) {
    const char *path = root.fileSystemRepresentation;
    struct stat st;
    if (!path || lstat(path, &st) != 0) { (*errors)++; return NO; }
    if (S_ISDIR(st.st_mode)) {
        int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) { (*errors)++; return NO; }
        WalkDir(fd, st.st_dev, errors, stop, visit);
        close(fd);
        return YES;
    }
    if (!S_ISREG(st.st_mode)) return YES;
    // One file: getattrlist on its folder entry, with the same attributes the bulk walk reads.
    struct attrlist al = {
        .bitmapcount = ATTR_BIT_MAP_COUNT,
        .commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID,
        .fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE,
        .forkattr = ATTR_CMNEXT_PRIVATESIZE | ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS | ATTR_CMNEXT_CLONE_REFCNT,
    };
    char buf[4096];
    if (getattrlist(path, &al, buf, sizeof buf, FSOPT_PACK_INVAL_ATTRS | FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0) { (*errors)++; return NO; }
    MMFileFacts f = {0}; fsobj_type_t type; const char *name;
    Unpack(buf, &f, &type, &name);
    visit(&f, AT_FDCWD, path);   // an absolute path, so openat ignores the folder
    return YES;
}

#pragma mark - The clone-id estimate, tier 1

/// What the estimate keeps per inode and per clone family while it walks.
@interface MMSizeTally : NSObject {
@public
    MMSize size;
    NSMutableDictionary<NSNumber *, NSNumber *> *linksSeen;     // fileID: links walked
    NSMutableDictionary<NSNumber *, NSValue *> *inodes;         // fileID: MMFileFacts
}
@end
@implementation MMSizeTally
- (instancetype)init {
    if ((self = [super init])) { linksSeen = [NSMutableDictionary new]; inodes = [NSMutableDictionary new]; }
    return self;
}

- (void)add:(const MMFileFacts *)f {
    size.files++;
    NSNumber *key = @(f->fileID);
    NSUInteger seen = linksSeen[key].unsignedIntegerValue + 1;
    linksSeen[key] = @(seen);
    if (seen > 1) return;   // du counts a hard-linked inode once
    size.allocated += f->alloc;
    inodes[key] = [NSValue valueWithBytes:f objCType:@encode(MMFileFacts)];
}

/// TESTS.md question 11: private bytes are freed; a full clone family's shared bytes count once when every holder
/// the refcount names was walked; an inode with a link outside the walk frees nothing.
- (uint64_t)estimate {
    uint64_t freed = 0;
    NSMutableDictionary<NSNumber *, NSMutableArray<NSValue *> *> *families = [NSMutableDictionary new];
    for (NSNumber *k in inodes) {
        MMFileFacts f; [inodes[k] getValue:&f size:sizeof f];
        if (linksSeen[k].unsignedIntegerValue < f.links) continue;
        uint64_t priv = f.hasPriv ? MIN(f.priv, f.alloc) : f.alloc;
        freed += priv;
        if (f.hasClone && f.hasRefcnt && f.refcnt > 1 && (f.flags & EF_MAY_SHARE_BLOCKS)) {
            NSMutableArray *fam = families[@(f.cloneID)] ?: (families[@(f.cloneID)] = [NSMutableArray new]);
            [fam addObject:inodes[k]];
        }
    }
    for (NSNumber *c in families) {
        NSArray<NSValue *> *fam = families[c];
        MMFileFacts first; [fam.firstObject getValue:&first size:sizeof first];
        if (fam.count < first.refcnt) continue;   // a holder is outside the walk
        uint64_t shared = 0;
        for (NSValue *v in fam) { MMFileFacts f; [v getValue:&f size:sizeof f]; shared = MAX(shared, f.alloc - MIN(f.priv, f.alloc)); }
        freed += shared;
    }
    return MIN(freed, size.allocated);
}
@end

#pragma mark - The extent union, tier 2

typedef struct { uint64_t at; uint32_t inode; int8_t delta; } MMEdge;

/// Maps every allocated byte of the file at dirfd/name, never reading its data. Holes have no mapping.
static BOOL MapExtents(int dirfd, const char *name, uint32_t inode, NSMutableData *edges) {
    int fd = openat(dirfd, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return NO;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); return NO; }
    off_t off = 0;
    while (off < st.st_size) {
        struct log2phys l = { .l2p_contigbytes = st.st_size - off, .l2p_devoffset = off };
        if (fcntl(fd, F_LOG2PHYS_EXT, &l) != 0 || l.l2p_contigbytes <= 0) { off += 4096; continue; }
        uint64_t len = ((uint64_t)l.l2p_contigbytes + 4095) & ~4095ULL;   // whole 4 KB blocks, as allocation counts
        MMEdge in = { (uint64_t)l.l2p_devoffset, inode, 1 }, out = { (uint64_t)l.l2p_devoffset + len, inode, -1 };
        [edges appendBytes:&in length:sizeof in];
        [edges appendBytes:&out length:sizeof out];
        off += l.l2p_contigbytes;
    }
    close(fd);
    return YES;
}

@implementation MMSizer

+ (MMSize)quick:(NSString *)root {
    MMSizeTally *t = [MMSizeTally new];
    NSInteger errors = 0;
    if (root.length) WalkRoot(root.stringByStandardizingPath, &errors, nil, ^(const MMFileFacts *f, int dirfd, const char *name) { [t add:f]; });
    MMSize s = t->size;
    s.freedIfDeleted = [t estimate];
    s.errors += errors;
    return s;
}

+ (uint64_t)exact:(NSArray<NSString *> *)roots {
    NSDate *start = NSDate.date;
    MMSizeTally *t = [MMSizeTally new];
    NSInteger errors = 0;
    __block BOOL over = NO;
    BOOL (^stop)(void) = ^BOOL { return over; };
    // Pass 1: the inodes, their links and their clone families, with no file opened.
    NSMutableArray<NSString *> *walked = [NSMutableArray new];
    for (NSString *r in roots) {
        if (![r isKindOfClass:NSString.class] || !r.length) continue;
        NSString *root = r.stringByStandardizingPath;
        // A root inside another root is the same files twice.
        BOOL inside = NO;
        for (NSString *w in walked) if ([root isEqualToString:w] || [root hasPrefix:[w stringByAppendingString:@"/"]]) inside = YES;
        if (inside) continue;
        [walked addObject:root];
        WalkRoot(root, &errors, stop, ^(const MMFileFacts *f, int dirfd, const char *name) {
            [t add:f];
            if (t->size.files > (NSInteger)kExactMaxFiles || -start.timeIntervalSinceNow > kExactBudget) over = YES;
        });
    }
    if (over) {
        // Too large for the union. The estimate over every root at once.
        MMSizeTally *e = [MMSizeTally new];
        for (NSString *root in walked) WalkRoot(root, &errors, nil, ^(const MMFileFacts *f, int dirfd, const char *name) { [e add:f]; });
        return [e estimate];
    }

    // Which inodes hold blocks someone outside the roots may also hold.
    NSMutableDictionary<NSNumber *, NSNumber *> *familySeen = [NSMutableDictionary new];
    for (NSNumber *k in t->inodes) {
        MMFileFacts f; [t->inodes[k] getValue:&f size:sizeof f];
        if (f.hasClone) familySeen[@(f.cloneID)] = @(familySeen[@(f.cloneID)].unsignedIntegerValue + 1);
    }
    NSArray<NSNumber *> *ids = t->inodes.allKeys;
    NSMutableDictionary<NSNumber *, NSNumber *> *index = [NSMutableDictionary dictionaryWithCapacity:ids.count];
    BOOL *outside = calloc(ids.count + 1, sizeof(BOOL));
    uint64_t freed = 0;
    for (NSUInteger i = 0; i < ids.count; i++) {
        index[ids[i]] = @(i);
        MMFileFacts f; [t->inodes[ids[i]] getValue:&f size:sizeof f];
        BOOL linkOut = t->linksSeen[ids[i]].unsignedIntegerValue < f.links;
        BOOL familyOut = f.hasClone && (f.flags & EF_MAY_SHARE_BLOCKS) &&
                         (!f.hasRefcnt || familySeen[@(f.cloneID)].unsignedIntegerValue < f.refcnt) && f.refcnt != 1;
        outside[i] = linkOut || familyOut;
        // Private bytes are freed, unless a hard link outside keeps the whole inode.
        if (!linkOut) freed += f.hasPriv ? MIN(f.priv, f.alloc) : (f.flags & EF_MAY_SHARE_BLOCKS ? 0 : f.alloc);
    }

    // Pass 2: map each inode once and sweep the device in order.
    NSMutableData *edges = [NSMutableData new];
    NSMutableSet<NSNumber *> *mapped = [NSMutableSet new];
    for (NSString *root in walked)
        WalkRoot(root, &errors, nil, ^(const MMFileFacts *f, int dirfd, const char *name) {
            NSNumber *k = @(f->fileID);
            if ([mapped containsObject:k] || !index[k]) return;
            [mapped addObject:k];
            if (!(f->flags & EF_MAY_SHARE_BLOCKS)) return;   // shares nothing, so its private size above is all of it
            MapExtents(dirfd, name, (uint32_t)index[k].unsignedIntegerValue, edges);
        });
    NSUInteger n = edges.length / sizeof(MMEdge);
    MMEdge *e = edges.mutableBytes;
    qsort_b(e, n, sizeof(MMEdge), ^int(const void *a, const void *b) {
        const MMEdge *x = a, *y = b;
        return x->at < y->at ? -1 : x->at > y->at;
    });
    uint32_t *count = calloc(ids.count + 1, sizeof(uint32_t));
    NSUInteger holders = 0, outsideHolders = 0;
    uint64_t last = 0;
    for (NSUInteger i = 0; i < n; i++) {
        // The stretch since the last edge is freed when two or more set inodes hold it and none shares outside.
        // A stretch with one holder is that inode's private bytes, counted above.
        if (e[i].at > last && holders >= 2 && outsideHolders == 0) freed += e[i].at - last;
        last = e[i].at;
        uint32_t k = e[i].inode;
        BOOL was = count[k] > 0;
        count[k] = (uint32_t)((int64_t)count[k] + e[i].delta);
        BOOL is = count[k] > 0;
        if (was != is) {
            if (is) { holders++; if (outside[k]) outsideHolders++; }
            else { holders--; if (outside[k]) outsideHolders--; }
        }
    }
    free(count);
    free(outside);
    return MIN(freed, t->size.allocated);
}

+ (int64_t)freedOnVolume:(NSString *)path by:(BOOL (^)(void))action {
    struct statfs before, after;
    NSString *p = path.length ? path : NSHomeDirectory();
    // The path may go away in the action, so the volume is read from the nearest folder that exists.
    while (p.length > 1 && ![NSFileManager.defaultManager fileExistsAtPath:p]) p = p.stringByDeletingLastPathComponent;
    BOOL have = statfs(p.fileSystemRepresentation, &before) == 0;
    BOOL ok = action ? action() : NO;
    if (!have || statfs(p.fileSystemRepresentation, &after) != 0) return 0;
    (void)ok;   // a failed action can still have freed or used space, so the delta is reported either way
    return (int64_t)after.f_bavail * (int64_t)after.f_bsize - (int64_t)before.f_bavail * (int64_t)before.f_bsize;
}

@end
