// `minmacs window`: the menu window's model as the feed makes it, issue #62. Read only.
#import <Foundation/Foundation.h>

@class MMVerbSpec;

/// The verb. The shell adds it with MMAddVerb, since the feed lives in Sources/Shell and Sources/CLI links without it.
MMVerbSpec *MMWindowVerbSpec(void);
