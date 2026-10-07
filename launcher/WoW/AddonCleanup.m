#import "AddonCleanup.h"
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

static BOOL Fail(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"Wolkara.AddonCleanup" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"Could not retire the experimental WolkaraTouch addon. Move it out of Interface/AddOns before playing."}];
    return NO;
}
BOOL TKWoWRetireTouchAddon(NSString *editionDirectory, NSError **error) {
    struct stat status;
    if (!editionDirectory.isAbsolutePath || lstat(editionDirectory.fileSystemRepresentation,&status) || !S_ISDIR(status.st_mode)) return Fail(error);
    // Accept the container's /var alias, then reject symlinks below the root.
    char *resolved = realpath(editionDirectory.fileSystemRepresentation,NULL);
    if (!resolved) return Fail(error);
    NSString *root = [NSString stringWithUTF8String:resolved]; free(resolved);
    NSString *source = root;
    for (NSString *part in @[@"Interface",@"AddOns",@"WolkaraTouch"]) {
        source = [source stringByAppendingPathComponent:part];
        if (lstat(source.fileSystemRepresentation,&status)) return errno == ENOENT ? YES : Fail(error);
        if (!S_ISDIR(status.st_mode)) return Fail(error);
    }
    NSString *disabled = [root stringByAppendingPathComponent:@"Interface/DisabledAddOns"];
    if (lstat(disabled.fileSystemRepresentation,&status)) {
        if (errno != ENOENT) return Fail(error);
        if (![NSFileManager.defaultManager createDirectoryAtPath:disabled withIntermediateDirectories:NO attributes:nil error:error]) return NO;
    } else if (!S_ISDIR(status.st_mode)) return Fail(error);
    NSString *destination = [disabled stringByAppendingPathComponent:[@"WolkaraTouch-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    return [NSFileManager.defaultManager moveItemAtPath:source toPath:destination error:error];
}
