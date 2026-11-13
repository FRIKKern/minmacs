// The dock's numbers: memory and disk beside the ring, as two numbers and never one, and the gains right of Fix
// Everything. MMWindowDock.m draws the rest of the dock.
#import "UI/Window/MMWindowDockParts.h"

@implementation MMWindowDockView (Numbers)

#pragma mark The Mac's two numbers

/// The pointer rests on Fix Everything while it can be pressed: the dock shows the Mac after it.
- (BOOL)showsAfter { return !self.pointed && self.phase == MMWindowDockCalm && self.model.fixCount > 0 && self.fix.hovered; }

/// Beside the ring, memory and disk as two numbers, never one. While the pointer rests on a row they are that row's
/// share, and while it rests on Fix Everything they are the Mac after it: what is in use now less what the fixes that
/// need nobody give back, and what is free now plus what they free, each side on its own.
/// Each line is its words, with the large number and its unit apart where it has one.
- (NSArray<NSDictionary *> *)mac {
    MMWindowRing *ring = self.model.ring;
    MMWindowRow *row = self.pointed;
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    if (row) {
        BOOL onDisk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
        [out addObject:@{@"name": row.shownName}];
        NSArray<NSString *> *size = row.showsSize ? MMWindowSize2(row.bytes, onDisk) : @[@(row.tabs).stringValue, row.tabs == 1 ? @"tab" : @"tabs"];
        [out addObject:@{@"big": size[0], @"unit": size[1]}];
        if (row.showsSize) {
            uint64_t used = ring.diskTotal > ring.diskFree ? ring.diskTotal - ring.diskFree : 0;
            [out addObject:@{@"label": onDisk ? [NSString stringWithFormat:@"of %@ disk in use", MMWindowBytes(used, YES)]
                                              : [NSString stringWithFormat:@"of %@ memory in use", MMWindowBytes(ring.memoryUsed, NO)]}];
        }
        NSString *cpu = MMWindowCPU(row.cpuPercent);
        if (cpu) [out addObject:@{@"label": [NSString stringWithFormat:@"CPU %@ %%", cpu]}];
    } else if (self.showsAfter) {
        NSInteger n = self.model.fixCount;
        uint64_t back = MIN(self.model.memoryBack, ring.memoryUsed);
        NSArray<NSString *> *after = MMWindowSize2(ring.memoryUsed - back, NO);
        [out addObject:@{@"label": MMWindowAfterTitle(n) ?: @""}];
        [out addObject:@{@"big": after[0], @"unit": after[1]}];
        // A fix that gives no memory back leaves the number as it is, and the line says so and does not repeat it.
        [out addObject:@{@"label": back > 0 ? [NSString stringWithFormat:@"memory, now %@", MMWindowBytes(ring.memoryUsed, NO)] : @"memory in use, as now"}];
        [out addObject:@{@"disk": MMWindowBytes(ring.diskFree + self.model.diskBack, YES), @"label": @"disk free"}];
    } else {
        NSArray<NSString *> *used = MMWindowSize2(ring.memoryUsed, NO);
        NSString *total = MMWindowWhole(ring.memoryTotal, NO);
        [out addObject:@{@"big": used[0], @"unit": [total hasSuffix:used[1]] ? [@"/ " stringByAppendingString:total] : [NSString stringWithFormat:@"%@ / %@", used[1], total]}];
        [out addObject:@{@"label": @"memory in use"}];
        [out addObject:@{@"disk": MMWindowBytes(ring.diskFree, YES), @"label": @"disk free"}];
    }
    return out;
}

- (NSArray<NSString *> *)macLines {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSDictionary *l in self.mac) {
        NSMutableArray *words = [NSMutableArray new];
        for (NSString *k in @[@"name", @"big", @"unit", @"disk", @"label"]) if (l[k]) [words addObject:l[k]];
        [out addObject:[words componentsJoinedByString:@" "]];
    }
    return out;
}

- (void)drawMac {
    NSColor *text = MMWindowColor(MMWindowInkText), *label = Label(), *unit = MMWindowColor(MMWindowInkText2), *disk = MMWindowColor(MMWindowInkDisk);
    NSArray<NSDictionary *> *lines = self.mac;
    CGFloat x = 128, width = 150;
    BOOL lead = self.pointed || self.showsAfter;
    // Three lines sit at 46.5, 73.5 and 92. With a line above the number, four sit at 31.5, 54, 81 and 99.5. A
    // pointed row's name is whole: when it needs more lines than one, it grows upward first and then pushes the rest down.
    CGFloat at[4] = {lead ? 31.5 : 46.5, lead ? 54 : 73.5, lead ? 81 : 92, 99.5}, push = 0;
    for (NSUInteger i = 0; i < lines.count && i < 4; i++) {
        NSDictionary *l = lines[i];
        // A name of many lines pushes the lines under it down. The last of them, CPU, gives way before it would leave the dock.
        if (i == 3 && at[i] + push > self.bounds.size.height - 12) break;
        if (l[@"name"]) {
            CGFloat size = MMWindowFitSize(l[@"name"], 11.5, 10, NSFontWeightRegular, width), line = MMWindowLineHeight(size);
            NSInteger n = (NSInteger)MMWindowLines(l[@"name"], size, NSFontWeightRegular, width).count;
            push = MAX(0, (n - 2) * line);
            MMWindowDrawBlock(l[@"name"], 11.5, 10, NSFontWeightRegular, label, x, at[i] + line / 2 + push, width, -1, 1, 0);
        } else if (l[@"big"]) {
            MMWindowDraw(MMWindowJoin(@[MMWindowText(l[@"big"], 25, NSFontWeightMedium, text),
                                        MMWindowText([[l[@"unit"] hasPrefix:@"/"] ? @" " : MMWindowThin stringByAppendingString:l[@"unit"]], 12, NSFontWeightRegular, unit)]), x, at[i] + push, -1);
        } else if (l[@"disk"]) {
            MMWindowDraw(MMWindowJoin(@[MMWindowText(l[@"disk"], 11.5, NSFontWeightMedium, disk),
                                        MMWindowText([@" " stringByAppendingString:l[@"label"]], 11.5, NSFontWeightRegular, label)]), x, at[i] + push, -1);
        } else MMWindowDraw(MMWindowText(l[@"label"], 11.5, NSFontWeightRegular, label), x, at[i] + push, -1);
    }
}

#pragma mark The gains

/// What Fix Everything gives back, memory and disk, each a large number of its own. A side shows only when it has
/// something: a zero is no gain, so it is never drawn as one.
/// - Before a press: what the fixes give back, each side that is above zero.
/// - While a run plays: each side the run set out to give back, counting up from zero.
/// - Once it ended: each side that did come back.
/// - With nothing to fix: what came back today, each side that is above zero.
/// Each entry is the bytes, the ink and the words.
- (NSArray<NSArray *> *)gains {
    MMWindowModel *m = self.model;
    MMWindowRun *run = m.run;
    NSMutableArray<NSArray *> *out = [NSMutableArray new];
    void (^add)(double, MMWindowInk, NSString *) = ^(double bytes, MMWindowInk ink, NSString *words) {
        [out addObject:@[@((uint64_t)MAX(bytes, 0)), @(ink), words]];
    };
    if (self.phase == MMWindowDockRunning) {
        if (run.memoryPlanned > 0 || run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory back so far");
        if (run.diskPlanned > 0 || run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk back so far");
    } else if (self.phase == MMWindowDockEnded) {
        if (run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory back");
        if (run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk back");
    } else if (m.fixCount == 0) {
        if (m.memoryBackToday > 0) add(m.memoryBackToday, MMWindowInkMemory, @"memory back today");
        if (m.diskBackToday > 0) add(m.diskBackToday, MMWindowInkDisk, @"disk back today");
    } else {
        if (m.memoryBack > 0) add(m.memoryBack, MMWindowInkMemory, @"memory back");
        if (m.diskBack > 0) add(m.diskBack, MMWindowInkDisk, @"disk back");
    }
    return out;
}

- (NSArray<NSString *> *)gainLines {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSArray *g in self.gains) [out addObject:[NSString stringWithFormat:@"%@ %@", MMWindowBytes([g[0] unsignedLongLongValue], [g[1] integerValue] == MMWindowInkDisk), g[2]]];
    return out;
}

- (void)drawGains {
    NSColor *t2 = Label();
    NSMutableArray<NSAttributedString *> *lines = [NSMutableArray new];
    for (NSArray *g in self.gains)
        [lines addObject:MMWindowJoin(@[MMWindowText(MMWindowBytes([g[0] unsignedLongLongValue], [g[1] integerValue] == MMWindowInkDisk), 23, NSFontWeightMedium, MMWindowColor((MMWindowInk)[g[1] integerValue])),
                                        MMWindowText([@"  " stringByAppendingString:g[2]], 12, NSFontWeightRegular, t2)])];
    // Two lines sit at 50 and 81. One line sits between them, level with the middle of the button.
    if (lines.count == 1) MMWindowDraw(lines[0], 764, 65.5, -1);
    else for (NSUInteger i = 0; i < lines.count; i++) MMWindowDraw(lines[i], 764, 50 + 31 * i, -1);
}

@end
