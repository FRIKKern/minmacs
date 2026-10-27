// MinMacs 2.0. One binary: the menu bar app, or the CLI when a verb is given.
// It registers the experts linked into this build, then hands over to the shell in Sources/Shell.
#import <Foundation/Foundation.h>
#import "Shell/MMShell.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        MMRegisterBuiltInExperts();
        return MMMain(argc, argv);
    }
}
