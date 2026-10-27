// A check of MMTreeDisk for test/workforest.sh. Usage: treedisk <folder>
// The test writes treedisk.json with a walk of <folder> from an hour ago, under the folder's current change time.
// A fresh read must walk again and keep the new walk, so a cached read after it is new. A kept old walk would
// make every cached read start one more background walk, and every walk one more graph rebuild.
// Prints the age in seconds of the cached read, and of the fresh read.
#import <Foundation/Foundation.h>
#import "Core/Know/MMTreeDisk.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 2;
        NSString *path = @(argv[1]);
        MMTreeDiskFacts *fresh = [MMTreeDisk.shared factsFor:path read:MMTreeDiskFresh];
        MMTreeDiskFacts *cached = [MMTreeDisk.shared factsFor:path read:MMTreeDiskCached];
        printf("%.0f %.0f\n", -cached.at.timeIntervalSinceNow, -fresh.at.timeIntervalSinceNow);
        return 0;
    }
}
