// A size not measured yet, as the window draws it: the made-up day "measuring" has one worktree measured and fifteen
// not. Nothing may draw a 0 for a size nobody took: the row's slot, the story, the dock and the gains say it in words,
// and the word stands whole in its column. tools/render-window-polish.m includes this file. It is not built on its own.

/// Every string a view draws, with no spaces of any kind, so "0 MB" reads "0MB" whatever space joins it.
static NSArray<NSString *> *MeasuringDrawn(NSView *v) {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    MMWindowWatchDraws(^(NSString *text, NSRect used, NSRect allowed, NSRect bounds) {
        [out addObject:[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""]];
    });
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    MMWindowWatchDraws(nil);
    return out;
}

static NSInteger MeasuringCount(NSArray<NSString *> *drawn, NSString *text) {
    NSInteger n = 0;
    for (NSString *s in drawn) if ([s isEqualToString:text]) n++;
    return n;
}

static void WindowMeasuringChecks(void) {
    MMWindowView *v = PolishView(@"measuring");
    MMWindowModel *m = v.model;
    MMWindowGroup *trees = m.diskGroups[0];
    MMWindowDockView *dock = PolishDock(v);
    NSView *middle = WordViews(v, MMWindowMiddleView.class).firstObject;

    // The fixture itself: the measured row leads, and the rows not measured hold no number.
    BOOL order = trees.rows.count == 16 && trees.unmeasured == 15 && !trees.rows[0].unmeasured && trees.rows[0].showsSize;
    for (NSUInteger i = 1; i < trees.rows.count; i++) if (!trees.rows[i].unmeasured || trees.rows[i].showsSize || ![trees.rows[i].sizeWord isEqualToString:@"measuring"]) order = NO;
    Check(order, @"window measuring: the measured worktree comes first, and the fifteen not measured show the word and no size", @"");

    // The list: the word in each such row's slot, and no "0 MB" anywhere.
    NSArray<NSString *> *drawn = MeasuringDrawn(v);
    Check(MeasuringCount(drawn, @"measuring") >= 5 && MeasuringCount(drawn, @"0MB") == 0 && MeasuringCount(drawn, @"0KB") == 0,
          @"window measuring: a row not measured draws the word measuring where its size would stand, and no 0 MB is drawn",
          [NSString stringWithFormat:@"%ld words, %ld zeros", (long)MeasuringCount(drawn, @"measuring"), (long)MeasuringCount(drawn, @"0MB")]);

    // The word stands whole in the size column at every row width, with the name and the state word left of it.
    MMWindowRow *row = [MMWindowRow new];
    row.kind = MMWindowWorktree; row.key = @"u"; row.name = @"fix-auth-redirect"; row.state = @"merged"; row.unmeasured = YES;
    CGFloat word = MMWindowWidth(MMWindowText(row.sizeWord, 11.5, NSFontWeightRegular, NSColor.whiteColor));
    NSMutableArray<NSString *> *tight = [NSMutableArray new];
    for (CGFloat w = 150; w <= 420; w += 10) {
        MMWindowRowColumns fit;
        MMWindowRowName(row, MMWindowDisk, NO, NSMakeRect(5, 0, w, 24), &fit);
        BOOL clear = NSMaxX(fit.name) <= NSMaxX(fit.size) - word + 0.5 && (NSIsEmptyRect(fit.state) || NSMaxX(fit.state) <= NSMaxX(fit.size) - word + 0.5);
        if (word > NSWidth(fit.size) + 0.5 || !clear) [tight addObject:[NSString stringWithFormat:@"%g", w]];
    }
    Check(tight.count == 0, @"window measuring: the word fits its column at every row width, and the name and the state word end before it",
          [NSString stringWithFormat:@"the word is %g wide. Too tight at %@", word, [tight componentsJoinedByString:@" "]]);

    // The dock and the story of a row not measured: words, and no number for its size.
    MMWindowRow *un = trees.rows[1];
    v.pointedRow = un.key;
    NSString *onRow = [dock.macLines componentsJoinedByString:@" | "];
    NSArray<NSString *> *story = MeasuringDrawn(middle);
    // A view can draw a string in more than one pass, so each is counted as there or not.
    BOOL storySays = MeasuringCount(story, @"Notmeasuredyet") >= 1 && MeasuringCount(story, @"0MB") == 0;
    Check([onRow isEqualToString:[un.shownName stringByAppendingString:@" | Not measured yet"]] && storySays,
          @"window measuring: the dock and the story of a row not measured say Not measured yet, and show no number for it",
          [NSString stringWithFormat:@"%@ / %@", onRow, [story componentsJoinedByString:@" | "]]);
    // The measured row's story shows its size and no other row's.
    v.pointedRow = trees.rows[0].key;
    story = MeasuringDrawn(middle);
    Check(MeasuringCount(story, @"3.14GB") >= 1 && MeasuringCount(story, @"0MB") == 0,
          @"window measuring: the measured row's story shows its size and no 0 MB", [story componentsJoinedByString:@" | "]);
    v.pointedRow = nil;

    // VoiceOver hears the same.
    MMWindowListView *right = WindowLists(v).lastObject;
    NSInteger heard = 0, zeros = 0;
    for (id e in right.accessibilityChildren) {
        NSString *label = [e accessibilityLabel];
        if ([label containsString:@"size not measured yet"]) heard++;
        if ([label containsString:@", 0 MB"]) zeros++;
    }
    Check(heard == 15 && zeros == 0, @"window measuring: VoiceOver hears size not measured yet for each such row, and no 0 MB", [NSString stringWithFormat:@"%ld heard, %ld zeros", (long)heard, (long)zeros]);

    // Fix Everything: its disk back holds only what was measured, so it reads "or more", in the gains and under the pointer.
    NSString *gains = [dock.gainLines componentsJoinedByString:@" | "];
    v.pointsAtFix = YES;
    NSString *after = [dock.macLines componentsJoinedByString:@" | "];
    v.pointsAtFix = NO;
    Check(m.diskBackPartial && [gains isEqualToString:@"+3.16 GB memory | +14.5 GB or more disk"] && [after hasSuffix:@"197 GB or more disk free"],
          @"window measuring: Fix Everything's disk back reads or more while a thing it removes is not measured", [NSString stringWithFormat:@"%@ / %@", gains, after]);
    Check(!MMWindowFixture(@"busy").diskBackPartial && MMWindowFixture(@"busy").diskGroups[0].unmeasured == 0, @"window measuring: a day with every size measured says none of it", @"");
}
