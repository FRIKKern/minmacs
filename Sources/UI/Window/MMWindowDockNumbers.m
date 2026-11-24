// The dock's numbers: memory and disk beside the small ring, as two numbers and never one, and the gains right of Fix
// Everything. MMWindowDock.m draws the rest of the dock.
#import "UI/Window/MMWindowDockParts.h"

@implementation MMWindowDockView (Numbers)

#pragma mark The Mac's two numbers

/// The pointer rests on Fix Everything while it can be pressed: the dock shows the Mac after it.
- (BOOL)showsAfter { return !self.pointed && self.phase == MMWindowDockCalm && self.model.fixCount > 0 && self.fix.hovered; }

/// Beside the ring, memory and disk as two numbers, never one. While the pointer rests on a row they are that row's
/// share, and while it rests on Fix Everything they are the Mac after it: what is in use now less what the fixes that
/// need nobody give back, and what is free now plus what they free, each side on its own.
/// Each line is its words, with the number and its unit apart where it has one.
- (NSArray<NSDictionary *> *)mac {
    MMWindowRing *ring = self.model.ring;
    MMWindowRow *row = self.pointed;
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    if (row) {
        BOOL onDisk = row.kind == MMWindowWorktree || row.kind == MMWindowCache;
        [out addObject:@{@"name": row.shownName}];
        NSArray<NSString *> *size = row.showsSize ? MMWindowSize2(row.bytes, onDisk) : @[@(row.tabs).stringValue, row.tabs == 1 ? @"tab" : @"tabs"];
        // A size not measured yet is a line of words, and no number stands for it.
        if (row.sizeWord) [out addObject:@{@"label": MMWindowNotMeasured}];
        else [out addObject:@{@"big": size[0], @"unit": size[1]}];
        if (row.showsSize) {
            uint64_t used = ring.diskTotal > ring.diskFree ? ring.diskTotal - ring.diskFree : 0;
            [out addObject:@{@"label": onDisk ? [NSString stringWithFormat:@"of %@ disk in use", MMWindowBytes(used, YES)]
                                              : [NSString stringWithFormat:@"of %@ memory in use", MMWindowBytes(ring.memoryUsed, NO)]}];
        }
        NSString *cpu = MMWindowCPU(row.cpuPercent);
        if (cpu) [out addObject:@{@"label": [NSString stringWithFormat:@"CPU %@ %%", cpu], @"aside": @YES}];
    } else if (self.showsAfter) {
        NSInteger n = self.model.fixCount;
        uint64_t back = MIN(self.model.memoryBack, ring.memoryUsed);
        NSArray<NSString *> *after = MMWindowSize2(ring.memoryUsed - back, NO);
        [out addObject:@{@"label": MMWindowAfterTitle(n) ?: @"", @"lead": @YES}];
        [out addObject:@{@"big": after[0], @"unit": after[1]}];
        // A fix that gives no memory back leaves the number as it is, and the line says so and does not repeat it.
        [out addObject:@{@"label": back > 0 ? [NSString stringWithFormat:@"memory, now %@", MMWindowBytes(ring.memoryUsed, NO)] : @"memory in use, as now"}];
        // With a part not measured yet, what comes back is that much or more, and the line says so.
        [out addObject:@{@"disk": MMWindowBytes(ring.diskFree + self.model.diskBack, YES), @"label": self.model.diskBackPartial ? @"or more disk free" : @"disk free"}];
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

/// The lines as drawn: a name of its own, wrapped whole; the number with its unit and the label after it on one line,
/// and CPU after them while it fits, else on a line under; the disk on a line of its own. They stand as one block in
/// the middle of the dock.
- (void)drawMac {
    MMWindowDrawRing(self.model, NSMakePoint(38, kDockMid), NO, self.pointed, self.showsAfter);
    NSColor *text = MMWindowColor(MMWindowInkText), *label = Label(), *unit = MMWindowColor(MMWindowInkText2), *disk = MMWindowColor(MMWindowInkDisk);
    NSArray<NSDictionary *> *lines = self.mac;
    CGFloat x = kMacX, width = kMacWidth;
    // Each part: an attributed line with its height, or a name block, whose size is found first.
    NSMutableArray<NSArray *> *parts = [NSMutableArray new];
    CGFloat nameSize = 11.5;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSDictionary *l = lines[i];
        if (l[@"name"]) {
            nameSize = MMWindowFitSize(l[@"name"], 11.5, 10, NSFontWeightRegular, width);
            [parts addObject:@[@"name", l[@"name"], @(MMWindowBlockHeight(l[@"name"], 11.5, 10, NSFontWeightRegular, width))]];
        } else if (l[@"big"]) {
            NSMutableArray *runs = [NSMutableArray arrayWithObjects:MMWindowText(l[@"big"], 15, NSFontWeightMedium, text),
                MMWindowText([[l[@"unit"] hasPrefix:@"/"] ? @" " : MMWindowThin stringByAppendingString:l[@"unit"]], 11, NSFontWeightRegular, unit), nil];
            // The label that says what the number is shares its line.
            if (i + 1 < lines.count && [lines[i + 1] count] == 1 && lines[i + 1][@"label"]) {
                [runs addObject:MMWindowText([@" " stringByAppendingString:lines[++i][@"label"]], 11.5, NSFontWeightRegular, label)];
            }
            NSAttributedString *line = MMWindowJoin(runs);
            if (i + 1 < lines.count && lines[i + 1][@"aside"]) {
                NSAttributedString *more = MMWindowJoin(@[line, MMWindowText([@" · " stringByAppendingString:lines[i + 1][@"label"]], 11.5, NSFontWeightRegular, label)]);
                if (MMWindowWidth(more) <= width) { line = more; i++; }
            }
            [parts addObject:@[@"line", line, @20]];
        } else if (l[@"disk"]) {
            [parts addObject:@[@"line", MMWindowJoin(@[MMWindowText(l[@"disk"], 11.5, NSFontWeightMedium, disk),
                                                     MMWindowText([@" " stringByAppendingString:l[@"label"]], 11.5, NSFontWeightRegular, label)]), @16]];
        } else {
            [parts addObject:@[l[@"aside"] ? @"aside" : @"line", MMWindowText(l[@"label"], 11.5, NSFontWeightRegular, label), @16]];
        }
    }
    CGFloat total = 0;
    for (NSArray *p in parts) total += [p[2] doubleValue];
    // CPU gives way before the block would leave the dock.
    if (total > self.bounds.size.height - 6 && [parts.lastObject[0] isEqualToString:@"aside"]) { total -= [parts.lastObject[2] doubleValue]; [parts removeLastObject]; }
    CGFloat y = round(kDockMid - total / 2);
    for (NSArray *p in parts) {
        CGFloat h = [p[2] doubleValue];
        if ([p[0] isEqualToString:@"name"]) MMWindowDrawBlock(p[1], nameSize, 10, NSFontWeightRegular, label, x, y, width, -1, -1, 0);
        else MMWindowDraw(p[1], x, y + h / 2, -1);
        y += h;
    }
}

#pragma mark The gains

/// What Fix Everything gives back, memory and disk, each a number of its own. A side shows only when it has
/// something: a zero is no gain, so it is never drawn as one.
/// - Before a press: what the fixes give back, each side that is above zero. Disk reads "or more" while a thing the
///   fixes remove is not measured yet, and with nothing of it measured there is no disk side.
/// - While a run plays: each side the run set out to give back, counting up from zero, "so far".
/// - Once it ended: each side that did come back, on the face of the button.
/// - With nothing to fix: what came back today, each side that is above zero, after the word "today". Disk reads
///   "or more" when a removal of today was not measured.
/// Each entry is the bytes, the ink and the word after the number.
- (NSArray<NSArray *> *)gains {
    MMWindowModel *m = self.model;
    MMWindowRun *run = m.run;
    NSMutableArray<NSArray *> *out = [NSMutableArray new];
    void (^add)(double, MMWindowInk, NSString *) = ^(double bytes, MMWindowInk ink, NSString *words) {
        [out addObject:@[@((uint64_t)MAX(bytes, 0)), @(ink), words]];
    };
    if (self.phase == MMWindowDockRunning) {
        if (run.memoryPlanned > 0 || run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory");
        if (run.diskPlanned > 0 || run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk");
    } else if (self.phase == MMWindowDockEnded) {
        if (run.memoryBack > 0) add(self.memoryShown, MMWindowInkMemory, @"memory");
        if (run.diskBack > 0) add(self.diskShown, MMWindowInkDisk, @"disk");
    } else if (m.fixCount == 0) {
        if (m.memoryBackToday > 0) add(m.memoryBackToday, MMWindowInkMemory, @"memory");
        if (m.diskBackToday > 0) add(m.diskBackToday, MMWindowInkDisk, m.diskBackTodayPartial ? @"or more disk" : @"disk");
    } else {
        if (m.memoryBack > 0) add(m.memoryBack, MMWindowInkMemory, @"memory");
        if (m.diskBack > 0) add(m.diskBack, MMWindowInkDisk, m.diskBackPartial ? @"or more disk" : @"disk");
    }
    return out;
}

/// The word that stands with the gains: before them "today", after them "so far", or none.
- (NSString *)gainWord {
    if (!self.gains.count) return nil;
    if (self.phase == MMWindowDockRunning) return @"so far";
    if (self.phase == MMWindowDockCalm && self.model.fixCount == 0) return @"today";
    return nil;
}

static NSString *Side(NSArray *g) { return [NSString stringWithFormat:@"+%@ %@", MMWindowBytes([g[0] unsignedLongLongValue], [g[1] integerValue] == MMWindowInkDisk), g[2]]; }

- (NSArray<NSString *> *)gainLines {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSArray *g in self.gains) [out addObject:Side(g)];
    return out;
}

- (NSAttributedString *)gainText:(CGFloat)size dark:(BOOL)dark bright:(BOOL)bright {
    NSArray<NSArray *> *gains = self.gains;
    if (!gains.count) return nil;
    NSColor *ink = [NSColor colorWithSRGBRed:43 / 255.0 green:20 / 255.0 blue:4 / 255.0 alpha:1];
    NSColor *quiet = dark ? [ink colorWithAlphaComponent:0.7] : bright ? MMWindowColor(MMWindowInkText) : Label();
    NSString *word = self.gainWord;
    NSMutableArray<NSAttributedString *> *runs = [NSMutableArray new];
    if ([word isEqualToString:@"today"]) [runs addObject:MMWindowText(@"today  ", size, NSFontWeightRegular, quiet)];
    for (NSUInteger i = 0; i < gains.count; i++) {
        NSArray *g = gains[i];
        BOOL disk = [g[1] integerValue] == MMWindowInkDisk;
        NSColor *number = dark ? ink : [MMWindowColor((MMWindowInk)[g[1] integerValue]) colorWithAlphaComponent:bright || MMWindowContrast() ? 1 : 0.9];
        if (i) [runs addObject:MMWindowText(@"  ·  ", size, NSFontWeightRegular, quiet)];
        [runs addObject:MMWindowText([@"+" stringByAppendingString:MMWindowBytes([g[0] unsignedLongLongValue], disk)], size, NSFontWeightSemibold, number)];
        [runs addObject:MMWindowText([@" " stringByAppendingString:g[2]], size, NSFontWeightRegular, quiet)];
    }
    if ([word isEqualToString:@"so far"]) [runs addObject:MMWindowText(@" so far", size, NSFontWeightRegular, quiet)];
    return MMWindowJoin(runs);
}

@end
