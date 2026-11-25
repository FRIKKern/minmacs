// A category's story in the middle: under its sentence and its facts, its processes, biggest first, near-identical
// ones folded, "12 mdworker_shared", as many as fit whole and 12 at most, then one line for what is left, "and 40
// smaller, 210 MB". Each line holds its name, what launched it, its CPU and its size, in the category's tint, and the
// pointer on a line shows its details, pid, parent, launched by, since when and path, as its tooltip.
#import "UI/Window/MMWindowParts.h"

static const CGFloat kLine = 21, kTail = 18, kHead = 28;

/// One laid-out line: its row, its rect in the view and its height.
@interface MMWindowRestPlaced : NSObject
@property MMWindowRow *row;
@property NSRect rect;
@end
@implementation MMWindowRestPlaced
@end

/// What launched a line, its owner, where a fact says it and it is not the category's own words.
static NSString *OwnerOf(MMWindowRow *line) {
    if (line.members) return nil;
    for (MMWindowFact *f in line.facts) if ([f.label isEqualToString:@"Launched by"]) return f.phrase;
    return nil;
}

/// The tooltip of a line: a fold's count and pids, or one process's facts.
static NSString *TipOf(MMWindowRow *line) {
    if (!line.members) return MMWindowRestDetailsText(line);
    NSMutableArray *pids = [NSMutableArray new];
    for (MMWindowRow *m in line.members) for (MMWindowFact *f in m.facts) if ([f.label isEqualToString:@"Pid"]) [pids addObject:f.value];
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@, %@ together", line.name, MMWindowSizeText(line.bytes, NO)]];
    MMWindowFact *raw = nil;
    for (MMWindowFact *f in line.members.firstObject.facts) if ([f.label isEqualToString:@"Process"]) raw = f;
    if (raw) [lines addObject:[@"Process: " stringByAppendingString:raw.value]];
    if (pids.count) [lines addObject:[@"Pids: " stringByAppendingString:[pids componentsJoinedByString:@", "]]];
    return [lines componentsJoinedByString:@"\n"];
}

@implementation MMWindowMiddleView (Rest)

/// The lines that fit from y to bottom, and the words of what is left. The view draws and places with these sums.
- (NSArray<MMWindowRestPlaced *> *)restLines:(MMWindowRow *)row from:(CGFloat)y width:(CGFloat)w bottom:(CGFloat)bottom
                                        tail:(NSArray<NSString *> *__autoreleasing *)tail {
    NSInteger room = (NSInteger)floor((bottom - y - kHead - 2 * kTail) / kLine);
    MMWindowRestList *list = MMWindowRestListOf(row, MIN(MMWindowRestMostLines, MAX(room, 0)));
    NSMutableArray<NSString *> *words = [NSMutableArray new];
    NSString *more = MMWindowRestMoreLine(list.more, list.moreBytes), *other = MMWindowRestUnmeasuredLine(list.unmeasured, more != nil || list.lines.count > 0);
    if (more) [words addObject:more];
    if (other) [words addObject:other];
    if (tail) *tail = words;
    NSMutableArray<MMWindowRestPlaced *> *out = [NSMutableArray new];
    CGFloat at = y + kHead;
    for (MMWindowRow *line in list.lines) {
        MMWindowRestPlaced *p = [MMWindowRestPlaced new];
        p.row = line; p.rect = NSMakeRect(14, at, w, kLine);
        [out addObject:p];
        at += kLine;
    }
    return out;
}

- (void)drawRest:(MMWindowRow *)row from:(CGFloat)y {
    CGFloat x = 14, w = self.bounds.size.width - 28, bottom = [self storyBottom];
    if (y + kHead + kLine > bottom) return;
    NSColor *text = MMWindowColor(MMWindowInkText), *t2 = MMWindowColor(MMWindowInkText2), *t3 = MMWindowColor(MMWindowInkText3);
    NSArray<NSString *> *tail = nil;
    NSArray<MMWindowRestPlaced *> *lines = [self restLines:row from:y width:w bottom:bottom tail:&tail];
    y += 6;
    [[NSColor colorWithWhite:1 alpha:MMWindowContrast() ? 0.3 : 0.07] setFill];
    NSRectFillUsingOperation(NSMakeRect(x, y, w, 1), NSCompositingOperationSourceOver);
    NSInteger n = MMWindowRestProcessCount(row);
    NSString *head = n == 1 ? @"Its one process" : [NSString stringWithFormat:@"Its %ld processes, biggest first", (long)n];
    MMWindowDraw(MMWindowText(head, 11, NSFontWeightRegular, t2), x, y + 17, -1);
    NSColor *tint = [MMWindowRestTint(row.key) colorWithAlphaComponent:1];
    for (MMWindowRestPlaced *p in lines) {
        MMWindowRow *line = p.row;
        CGFloat mid = NSMidY(p.rect);
        [tint setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x + 1, mid - 3, 6, 6)] fill];
        NSAttributedString *size = MMWindowText(MMWindowBytes(line.bytes, NO), 11.5, NSFontWeightRegular, t2);
        NSString *cpu = MMWindowCPU(line.cpuPercent);
        NSAttributedString *c = cpu ? MMWindowJoin(@[MMWindowText(cpu, 11.5, NSFontWeightRegular, line.cpuPercent >= 3 ? text : t2),
                                                     MMWindowText([MMWindowThin stringByAppendingString:@"%"], 10.5, NSFontWeightRegular, t3)]) : nil;
        MMWindowDraw(size, x + w, mid, 1);
        CGFloat right = x + w - 64;
        if (c) { MMWindowDraw(c, right, mid, 1); right -= 52; }
        // The name whole, and its owner beside it only where both fit on the line. A name never ends on an ellipsis.
        NSString *owner = OwnerOf(line);
        NSAttributedString *name = MMWindowText(line.name, 12.5, NSFontWeightRegular, line.quiet ? t2 : text);
        CGFloat room = right - (x + 14) - 8;
        if (owner) {
            NSAttributedString *both = MMWindowJoin(@[name, MMWindowText([@"  " stringByAppendingString:owner], 11.5, NSFontWeightRegular, t3)]);
            if (MMWindowWidth(both) <= room) name = both;
        }
        if (MMWindowWidth(name) <= room) MMWindowDraw(name, x + 14, mid, -1);
        else MMWindowDrawBlock(line.name, 12.5, 10, NSFontWeightRegular, line.quiet ? t2 : text, x + 14, mid - 7, room, -1, -1, kLine);
    }
    CGFloat at = y - 6 + kHead + kLine * lines.count + 4;
    for (NSString *t in tail) {
        if (at + kTail > bottom) break;
        MMWindowDraw(MMWindowText(t, 11, NSFontWeightRegular, t3), x + 14, at + 9, -1);
        at += kTail;
    }
}

- (void)placeRestTips:(MMWindowRow *)row from:(CGFloat)y {
    [self removeAllToolTips];
    if (row.kind != MMWindowSystem || !row.members.count) return;
    CGFloat w = self.bounds.size.width - 28, bottom = [self storyBottom];
    if (y + kHead + kLine > bottom) return;
    for (MMWindowRestPlaced *p in [self restLines:row from:y width:w bottom:bottom tail:NULL]) {
        NSString *tip = TipOf(p.row);
        if (tip.length) [self addToolTipRect:p.rect owner:tip userData:NULL];
    }
}

@end
