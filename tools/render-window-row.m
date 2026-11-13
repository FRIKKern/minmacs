// One row's columns, issue #62: the name, the state word, CPU, the row's own hour and the size never stand on one
// another, and none leaves the row. tools/render-window-polish.m includes this file. It is not built on its own.

/// One row drawn alone, flipped as the lists are, so its strings can be read as it draws.
@interface RowCanvas : NSView
@property MMWindowRow *row;
@property MMWindowSide side;
@property BOOL hasHour, tall;
@property NSRect rowRect;
@end
@implementation RowCanvas
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty { MMWindowDrawRow(self.row, self.rowRect, self.side, self.hasHour, NO, self.tall); }
@end

/// Draws one row as a list lays it out, 310 points wide, and says what is wrong: two of its strings on one another,
/// a string over the row's hour line, or a string past the row.
static NSArray<NSString *> *RowFaults(RowCanvas *canvas, MMWindowRow *row, MMWindowSide side, BOOL hasHour, BOOL tall) {
    MMWindowRowColumns cols;
    NSRect rect = NSMakeRect(5, 4, 310, tall ? 36 : 24);
    NSInteger lines = (NSInteger)MMWindowRowName(row, side, hasHour, rect, &cols).count;
    rect.size.height += MMWindowNameLine * (lines - 1);
    canvas.frame = NSMakeRect(0, 0, 320, NSMaxY(rect) + 4);
    canvas.row = row; canvas.side = side; canvas.hasHour = hasHour; canvas.tall = tall; canvas.rowRect = rect;
    NSMutableArray<NSArray *> *drawn = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        if (text.length && used.size.width > 0) [drawn addObject:@[text, [NSValue valueWithRect:used]]];
    });
    NSBitmapImageRep *rep = [canvas bitmapImageRepForCachingDisplayInRect:canvas.bounds];
    [canvas cacheDisplayInRect:canvas.bounds toBitmapImageRep:rep];
    MMWindowWatchDraws(nil);
    // The hour line is drawn, not written, so it is read from the rect the row worked out for it, on the line of the
    // size, the string drawn last at the row's right.
    MMWindowRowName(row, side, hasHour, rect, &cols);
    NSRect sizeAt = NSZeroRect;
    for (NSArray *d in drawn) if (fabs(NSMaxX([d[1] rectValue]) - NSMaxX(cols.size)) < 1) sizeAt = [d[1] rectValue];
    if (MMWindowHourSpan(row.hour, NULL, NULL, NULL) && !NSIsEmptyRect(cols.hour))
        [drawn addObject:@[@"the hour line", [NSValue valueWithRect:NSMakeRect(NSMinX(cols.hour), NSMidY(sizeAt) - 7, NSWidth(cols.hour), 14)]]];
    if (NSIsEmptyRect(sizeAt)) [drawn addObject:@[@"no size", [NSValue valueWithRect:NSMakeRect(-100, -100, 1, 1)]]];
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    NSString *what = [NSString stringWithFormat:@"%@ %@%@%@%@", side == MMWindowDisk ? @"disk" : @"memory", row.name, MMWindowCPU(row.cpuPercent) ? @", CPU" : @"",
                      hasHour ? (row.hour ? @", hour" : @", hour of others") : @"", row.state ? @", state" : @""];
    for (NSUInteger i = 0; i < drawn.count; i++) {
        NSRect a = [drawn[i][1] rectValue];
        if (NSMinX(a) < NSMinX(rect) - 0.5 || NSMaxX(a) > NSMaxX(rect) + 0.5 || NSMinY(a) < NSMinY(rect) - 1 || NSMaxY(a) > NSMaxY(rect) + 1)
            [faults addObject:[NSString stringWithFormat:@"%@: %@ leaves the row", what, drawn[i][0]]];
        for (NSUInteger j = i + 1; j < drawn.count; j++) {
            NSRect b = [drawn[j][1] rectValue], both = NSIntersectionRect(a, b);
            // Lines of one name stand under each other and touch only at their edges.
            if (both.size.width > 0.5 && both.size.height > MIN(a.size.height, b.size.height) * 0.5)
                [faults addObject:[NSString stringWithFormat:@"%@: %@ / %@", what, drawn[i][0], drawn[j][0]]];
        }
    }
    return faults;
}

/// The longest start of `text`, whole letters and no space at its end, that is at most `width` points at the row's type.
static NSString *RowNameOfWidth(NSString *text, CGFloat width) {
    NSString *best = [text substringToIndex:1];
    for (NSUInteger n = 1; n <= text.length; n++) {
        NSString *s = [[text substringToIndex:n] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (MMWindowWidth(MMWindowText(s, 13, NSFontWeightRegular, NSColor.whiteColor)) > width) break;
        best = s;
    }
    return best;
}

static void WindowRowChecks(void) {
    RowCanvas *canvas = [[RowCanvas alloc] initWithFrame:NSMakeRect(0, 0, 320, 40)];
    NSArray *hour = MMWindowFixture(@"busy").memoryGroups[0].rows[0].hour;

    // The row the third look found: a name of about 24 letters ran into its CPU number, "Write lane C fixtures now14 %".
    MMWindowRow *found = [MMWindowRow new];
    found.kind = MMWindowAgent; found.key = @"agent:w"; found.name = @"Write lane C fixtures now"; found.cpuPercent = 14; found.bytes = 760ull << 20; found.hour = hour;
    NSArray<NSString *> *foundFaults = RowFaults(canvas, found, MMWindowMemory, YES, NO);
    Check(foundFaults.count == 0, @"window rows: \"Write lane C fixtures now\" at 14 % CPU in a group with hours ends before its CPU number", [foundFaults componentsJoinedByString:@" | "]);

    // Every width of name, with CPU or none, with the row's hour, the group's hours only, or none, with a state word
    // or none, on both sides, one line a row and two: no two drawn parts on one another, and none past the row.
    NSString *words = @"Write lane C fixtures now and then the rest of the week's work on the search index and its ranking weights";
    NSMutableArray<NSString *> *faults = [NSMutableArray new];
    NSInteger rows = 0;
    for (CGFloat width = 40; width <= 320; width += 4) {
        NSString *name = RowNameOfWidth(words, width);
        for (NSNumber *disk in @[@NO, @YES]) for (NSNumber *cpu in @[@14, @0]) for (NSNumber *hours in @[@0, @1, @2]) for (NSNumber *state in @[@NO, @YES]) for (NSNumber *tall in @[@NO, @YES]) {
            MMWindowRow *row = [MMWindowRow new];
            row.kind = disk.boolValue ? MMWindowWorktree : MMWindowAgent; row.key = @"r"; row.name = name; row.bytes = disk.boolValue ? 18600000000ull : 1905ull << 20;
            row.cpuPercent = cpu.doubleValue;
            row.hour = hours.integerValue == 1 ? hour : nil;
            row.state = state.boolValue ? (disk.boolValue ? @"changed" : @"working") : nil;
            [faults addObjectsFromArray:RowFaults(canvas, row, disk.boolValue ? MMWindowDisk : MMWindowMemory, hours.integerValue > 0, tall.boolValue)];
            rows++;
        }
    }
    Check(faults.count == 0 && rows == 71 * 48, @"window rows: names 40 to 320 points wide, with and without CPU, hour and state word, on both sides: no two parts of a row on one another, none past the row",
          [NSString stringWithFormat:@"%ld rows. %@", (long)rows, [[faults subarrayWithRange:NSMakeRange(0, MIN(faults.count, 6))] componentsJoinedByString:@" | "]]);
}
