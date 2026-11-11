// Included by removal.m. Who is asked before Smart deletes, the wall as a rule on strings, and what a Wrap Up stages.
// The wall checks name / and the real home folder as strings only. MMRemovalWallWhyNot reads no disk and deletes
// nothing, so they are safe to ask about.

#pragma mark - Chosen or not

static void Chosen(void) {
    MMRemovalFacts *cache = Clutter(MMClutterCache, YES, YES, NO);
    MMRemovalFacts *tree = Tree(YES, NO, 0, 0, 0, 0);
    MMSetPref(MMRemovalKey, nil);
    T(@"chosen: with no value nothing is chosen, and the note says what holds until then", @"no Not chosen yet. Until you pick one, what MinMacs removes on its own goes to the Trash.",
      [NSString stringWithFormat:@"%@ %@", YN(MMRemovalChosen()), MMRemovalNotChosenNote()]);
    // Not chosen: what MinMacs starts on its own keeps a way back. The person's own press follows Smart.
    T(@"not chosen: a mode's act never deletes", @"keep keep keep", [NSString stringWithFormat:@"%@ %@ %@", Word(MMRemovalDecide(MMRemovalClutter, cache, @"proactive")),
      Word(MMRemovalDecide(MMRemovalClutter, cache, @"eager")), Word(MMRemovalDecide(MMRemovalWorktree, tree, @"guard"))]);
    T(@"not chosen: it says why", @"you have not chosen what happens to removed things yet, so a way back is kept", MMRemovalDecide(MMRemovalClutter, cache, @"proactive").why);
    T(@"not chosen: a press, the CLI and words shown before an act follow Smart", @"delete delete delete", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecide(MMRemovalClutter, cache, @"manual")), Word(MMRemovalDecide(MMRemovalClutter, cache, @"cli")), Word(MMRemovalDecide(MMRemovalClutter, cache, nil))]);
    T(@"not chosen: a who nobody knows counts as MinMacs's own act", @"keep", Word(MMRemovalDecide(MMRemovalClutter, cache, @"somebody")));
    T(@"not chosen: the same as a pure answer, for each choice a default could be", @"keep keep delete", [NSString stringWithFormat:@"%@ %@ %@",
      Word(MMRemovalDecideAs(MMRemovalSmart, NO, @"proactive", MMRemovalClutter, cache)), Word(MMRemovalDecideAs(MMRemovalDelete, NO, @"eager", MMRemovalClutter, cache)),
      Word(MMRemovalDecideAs(MMRemovalSmart, NO, @"manual", MMRemovalClutter, cache))]);
    // Chosen: Smart applies to everything, a mode's act too.
    MMSetRemovalChoice(MMRemovalSmart);
    T(@"chosen: once the person set Smart it is chosen, and the note is gone", @"yes nil", [NSString stringWithFormat:@"%@ %@", YN(MMRemovalChosen()), Or(MMRemovalNotChosenNote())]);
    T(@"chosen smart: a mode's act deletes what a tool rebuilds", @"delete delete", [NSString stringWithFormat:@"%@ %@", Word(MMRemovalDecide(MMRemovalClutter, cache, @"proactive")),
      Word(MMRemovalDecide(MMRemovalClutter, cache, @"eager"))]);
    T(@"chosen smart: and still keeps a leftover", @"keep", Word(MMRemovalDecide(MMRemovalClutter, Clutter(MMClutterLeak, NO, YES, NO), @"proactive")));
    MMSetRemovalChoice(MMRemovalTrash);
    T(@"chosen trash: nobody's act deletes", @"keep keep", [NSString stringWithFormat:@"%@ %@", Word(MMRemovalDecide(MMRemovalClutter, cache, @"manual")), Word(MMRemovalDecide(MMRemovalClutter, cache, @"eager"))]);
    MMSetPref(MMRemovalKey, nil);
}

#pragma mark - The wall, on strings

static MMRemovalPlaces *Places(NSString *home, NSString *volume, NSString *testHome, BOOL fold) {
    MMRemovalPlaces *p = [MMRemovalPlaces new];
    p.home = home; p.support = [home stringByAppendingPathComponent:@"Library/Application Support/MinMacs"];
    p.volume = volume; p.testHome = testHome; p.foldCase = fold;
    return p;
}
/// The wall's answer for a path that a finding named, so the answer is about where the path lies.
static NSString *Named(NSString *path, MMRemovalPlaces *places) { return MMRemovalWallWhyNot(path, @[path], places) ?: @"may go"; }

static void Wall(void) {
    NSString *home = @"/Users/me";
    MMRemovalPlaces *boot = Places(home, @"/", nil, NO);
    // Clause 1: only what the fresh finding named.
    T(@"wall: a path no finding named is refused, deep and harmless as it may be", @"no fresh finding names it",
      Or(MMRemovalWallWhyNot(@"/Users/me/Library/Caches/pip", @[@"/Users/me/Library/Caches/other"], boot)));
    T(@"wall: with nothing named, nothing goes", @"no fresh finding names it no fresh finding names it", [NSString stringWithFormat:@"%@ %@",
      Or(MMRemovalWallWhyNot(@"/Users/me/Library/Caches/pip", @[], boot)), Or(MMRemovalWallWhyNot(@"/Users/me/Library/Caches/pip", nil, boot))]);
    T(@"wall: a path that is no real full path is refused", @"it has no full path|its path is not a real path|its path is not a real path|its path is not a real path", [@[
      Named(@"Library/Caches/pip", boot), Named(@"/Users/me/Library/../Documents/x", boot), Named(@"/Users/me/./Library/Caches/pip", boot), Named(@"/Users/me/Library/Caches/pip/", boot)]
      componentsJoinedByString:@"|"]);
    // Clause 2: a volume's root, the home folder, MinMacs's own folder, and whatever holds one.
    T(@"wall: / and a volume's root are refused", @"it is the root of a volume|it is the root of a volume", [@[Named(@"/", boot), Named(@"/Volumes/Disk", Places(home, @"/Volumes/Disk", nil, NO))]
      componentsJoinedByString:@"|"]);
    T(@"wall: /Users and the home folder are refused", @"it holds the home folder|it holds the home folder", [@[Named(@"/Users", boot), Named(home, boot)] componentsJoinedByString:@"|"]);
    NSString *real = NSHomeDirectory();
    T(@"wall: the real home folder and the folder above it are refused", @"it holds the home folder|it holds the home folder", [@[Named(real, Places(real, @"/", nil, NO)),
      Named(real.stringByDeletingLastPathComponent, Places(real, @"/", nil, NO))] componentsJoinedByString:@"|"]);
    T(@"wall: MinMacs's own folder and what holds it are refused", @"it holds MinMacs's own folder|it holds MinMacs's own folder|it holds MinMacs's own folder", [@[
      Named(@"/Users/me/Library/Application Support/MinMacs", boot), Named(@"/Users/me/Library/Application Support", boot), Named(@"/Users/me/Library", boot)] componentsJoinedByString:@"|"]);
    // Clause 3: inside the home folder, at least 2 levels down.
    T(@"wall: a folder at the top of the home folder is refused", @"it is a folder at the top of the home folder|it is a folder at the top of the home folder|it is a folder at the top of the home folder|it is a folder at the top of the home folder",
      [@[Named(@"/Users/me/Documents", boot), Named(@"/Users/me/Desktop", boot), Named(@"/Users/me/.npm", boot), Named(@"/Users/me/Downloads", boot)] componentsJoinedByString:@"|"]);
    T(@"wall: two levels down in the home folder may go when named", @"may go|may go|may go", [@[Named(@"/Users/me/Library/Caches/pip", boot), Named(@"/Users/me/.npm/_cacache", boot),
      Named(@"/Users/me/code/app/node_modules", boot)] componentsJoinedByString:@"|"]);
    // Clause 4: outside the home folder, at least 3 levels below the volume's root.
    T(@"wall: near the top of the boot volume is refused", @"it is too near the top of its volume|it is too near the top of its volume|it is too near the top of its volume",
      [@[Named(@"/Applications/X.app", boot), Named(@"/opt", boot), Named(@"/private/tmp", boot)] componentsJoinedByString:@"|"]);
    T(@"wall: three levels below the boot volume's root may go when named", @"may go", Named(@"/private/tmp/scratch-ab12", boot));
    MMRemovalPlaces *disk = Places(home, @"/Volumes/Disk", nil, NO);
    T(@"wall: on another volume the count starts at that volume's root", @"it is too near the top of its volume|it is too near the top of its volume|may go",
      [@[Named(@"/Volumes/Disk/code", disk), Named(@"/Volumes/Disk/code/app", disk), Named(@"/Volumes/Disk/code/app/node_modules", disk)] componentsJoinedByString:@"|"]);
    T(@"wall: a path outside the volume it was said to be on is refused", @"cannot verify which volume holds it", Named(@"/Volumes/Other/code/app/node_modules", disk));
    T(@"wall: places nobody could read refuse everything", @"cannot verify where it lies|cannot verify where it lies|cannot verify where it lies",
      [@[Named(@"/private/tmp/scratch-ab12", nil), Named(@"/private/tmp/scratch-ab12", Places(home, nil, nil, NO)), Named(@"/private/tmp/scratch-ab12", Places(nil, @"/", nil, NO))]
      componentsJoinedByString:@"|"]);
    // Other spellings: on a disk that folds case, HOME is home.
    MMRemovalPlaces *folds = Places(home, @"/", nil, YES);
    T(@"wall: on a disk that folds case another spelling of the home folder is refused", @"it holds the home folder|it holds the home folder|it is a folder at the top of the home folder",
      [@[Named(@"/USERS/ME", folds), Named(@"/users", folds), Named(@"/Users/ME/documents", folds)] componentsJoinedByString:@"|"]);
    T(@"wall: there a finding's name matches in any case", @"may go", Or(MMRemovalWallWhyNot(@"/Users/me/Library/Caches/PIP", @[@"/users/me/library/caches/pip"], folds) ?: @"may go"));
    T(@"wall: on a disk that tells case apart, another spelling is another path, and nobody named it", @"no fresh finding names it",
      Or(MMRemovalWallWhyNot(@"/Users/me/Library/Caches/PIP", @[@"/Users/me/Library/Caches/pip"], boot)));
    // Clause 5: a check deletes only inside MINMACS_HOME.
    MMRemovalPlaces *test = Places(home, @"/", @"/private/tmp/minmacs-test.x", NO);
    T(@"wall: with a test home, inside it may go, and outside it, itself and beside it may not",
      @"may go|it is outside MINMACS_HOME, and a check deletes only its own fixtures|it is outside MINMACS_HOME, and a check deletes only its own fixtures|it is outside MINMACS_HOME, and a check deletes only its own fixtures",
      [@[Named(@"/private/tmp/minmacs-test.x/fx/cache", test), Named(@"/Users/me/Library/Caches/pip", test), Named(@"/private/tmp/minmacs-test.x", test),
         Named(@"/private/tmp/minmacs-test.xy/fx/cache", test)] componentsJoinedByString:@"|"]);
    T(@"wall: a test home that could not be read keeps everything", @"it is outside MINMACS_HOME, and a check deletes only its own fixtures",
      Named(@"/private/tmp/minmacs-test.x/fx/cache", Places(home, @"/", @"", NO)));

    // The real path of an item: links above it resolved, itself never followed, in the case the disk holds.
    NSString *dir = Path(@"wall/Deep"), *file = [dir stringByAppendingPathComponent:@"Name.txt"], *link = Path(@"wall/link");
    Write(file, @"x");
    [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:dir error:nil];
    T(@"real path: through a link above it, to where it is", file, Or(MMRemovalRealPath([link stringByAppendingPathComponent:@"Name.txt"])));
    T(@"real path: a link itself is named, not followed", link, Or(MMRemovalRealPath(link)));
    T(@"real path: gone, or not a full path, is nil", @"nil nil", [NSString stringWithFormat:@"%@ %@", Or(MMRemovalRealPath(Path(@"wall/none"))), Or(MMRemovalRealPath(@"wall/Deep"))]);
    NSString *other = [[dir stringByAppendingPathComponent:@"NAME.TXT"] stringByReplacingOccurrencesOfString:@"/Deep/" withString:@"/deep/"];
    NSString *got = MMRemovalRealPath(other);
    // A disk that folds case gives the one true spelling. A disk that does not has no such file.
    T(@"real path: another spelling comes back as the disk holds it, or not at all", @"yes", YN(!got || [got isEqualToString:file]));
    MMRemovalPlaces *here = [MMRemovalPlaces placesFor:file];
    T(@"places: read from the disk for a fixture", @"yes yes yes", [NSString stringWithFormat:@"%@ %@ %@", YN(here.volume.length > 0 && [file hasPrefix:here.volume]),
      YN([here.testHome isEqualToString:MMRemovalRealPath(MMSupportDir())]), YN(here.home.length > 0)]);
}

#pragma mark - What a Wrap Up stages

static MMUndoRecord *Part(NSString *parent, NSString *subject) {
    return [MMUndo.shared begin:@"removaltest" kind:@"trash" finding:[@"removaltest:" stringByAppendingString:subject] subject:subject
                            why:@"test" by:@"manual" parent:parent payload:@{@"part": @0}];
}

static void Staged(void) {
    MMRemovalDecision *del = MMRemovalDecideWith(MMRemovalDelete, MMRemovalConfigFiles, nil);
    MMUndoRecord *parent = Begin(@"wrapup", @"staged parent");
    // A part of a Wrap Up under Delete: its file leaves, and waits in the Trash, since a later part may still refuse.
    NSString *env = Path(@"staged/wt/.env.local");
    Write(env, @"API=1");
    MMUndoRecord *part = Part(parent.rid, @"config");
    MMRemovalNote(part, del, nil);
    MMRemovalAsk(part, @[env]);
    BOOL ok = MMRemovalApply(env, del, part, nil);
    MMRemovalDone(part, nil);
    part = Done(part);
    NSString *to = [part.payload[@"staged"] firstObject][@"to"];
    T(@"staged: a Wrap Up part's delete goes to the Trash and waits there", @"yes no yes 0", [NSString stringWithFormat:@"%@ %@ %@ %lu", YN(ok), YN(Exists(env)), YN(to.length && Exists(to)),
      (unsigned long)[part.payload[@"deleted"] count]]);
    T(@"staged: its record says staged, not deleted, and can still restore", @"delete 1 1 0 no yes", [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", part.payload[@"removal"][@"choice"],
      part.payload[@"removal"][@"wants"], part.payload[@"removal"][@"staged"], part.payload[@"removal"][@"deleted"], YN(part.deletedNow), YN(part.canRestore)]);
    // A later part refused: what was staged goes back, with what it held.
    T(@"staged: put back returns the file to its place", @"nil yes API=1 no", [NSString stringWithFormat:@"%@ %@ %@ %@", Or(MMRemovalPutBack(@[part])), YN(Exists(env)),
      [NSString stringWithContentsOfFile:env encoding:NSUTF8StringEncoding error:nil], YN(Exists(to))]);
    part = [MMUndo.shared record:part.rid];
    T(@"staged: the part then says restored, and never deleted", @"restored no", [NSString stringWithFormat:@"%@ %@", part.state == MMUndoRestored ? @"restored" : @"other", YN(part.deletedNow)]);

    // Every part went through: the staged file is deleted, and only then does the record say so.
    MMUndoRecord *two = Part(parent.rid, @"config again");
    MMRemovalNote(two, del, nil);
    MMRemovalAsk(two, @[env]);
    MMRemovalApply(env, del, two, nil);
    MMRemovalDone(two, nil);
    two = Done(two);
    to = [two.payload[@"staged"] firstObject][@"to"];
    (void)MMRemovalFinishStaged(@[two]);
    two = [MMUndo.shared record:two.rid];
    T(@"staged: finish deletes it from the Trash", @"no no", [NSString stringWithFormat:@"%@ %@", YN(Exists(env)), YN(Exists(to))]);
    T(@"staged: the record now says deleted, lists the path it came from, and cannot restore", [NSString stringWithFormat:@"1 yes no 0 0 %@", env],
      [NSString stringWithFormat:@"%@ %@ %@ %lu %lu %@", two.payload[@"removal"][@"deleted"], YN(two.deletedNow), YN(two.canRestore), (unsigned long)[two.payload[@"staged"] count],
       (unsigned long)[two.payload[@"trashed"] count], [two.payload[@"deleted"] firstObject][@"path"]]);
    T(@"staged: its restore says it was deleted", @"it was deleted and cannot be brought back", Or([MMUndo.shared restore:two.rid]));

    // Finish deletes only the very file the run staged. Something else at that place in the Trash stays.
    Write(env, @"API=2");
    MMUndoRecord *three = Part(parent.rid, @"config swapped");
    MMRemovalNote(three, del, nil);
    MMRemovalAsk(three, @[env]);
    MMRemovalApply(env, del, three, nil);
    MMRemovalDone(three, nil);
    three = Done(three);
    to = [three.payload[@"staged"] firstObject][@"to"];
    [NSFileManager.defaultManager removeItemAtPath:to error:nil];
    Write(to, @"somebody else's file");
    (void)MMRemovalFinishStaged(@[three]);
    three = [MMUndo.shared record:three.rid];
    T(@"staged: a file that is not the one it staged is left alone, and the record does not say deleted", @"yes somebody else's file no 1", [NSString stringWithFormat:@"%@ %@ %@ %lu", YN(Exists(to)),
      [NSString stringWithContentsOfFile:to encoding:NSUTF8StringEncoding error:nil], YN(three.deletedNow), (unsigned long)[three.payload[@"staged"] count]]);

    // A single action, with no Wrap Up around it, has no later part: it deletes at once.
    Write(env, @"API=3");
    MMUndoRecord *single = Begin(@"trash", @"single");
    MMRemovalNote(single, del, nil);
    MMRemovalAsk(single, @[env]);
    MMRemovalApply(env, del, single, nil);
    T(@"staged: an action that is no part of a Wrap Up deletes at once", @"no 0 1", [NSString stringWithFormat:@"%@ %lu %lu", YN(Exists(env)),
      (unsigned long)[[MMUndo.shared record:single.rid].payload[@"staged"] count], (unsigned long)[[MMUndo.shared record:single.rid].payload[@"deleted"] count]]);
    [MMUndo.shared finish:parent ok:YES freed:0 error:nil];
}
