#import <Foundation/Foundation.h>
#import "../launcher/WoW/TouchAddon.h"
#include <assert.h>
#include <unistd.h>
#include <fcntl.h>

static void Write(NSString *path, NSString *text) {
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}
int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *source = [root stringByAppendingPathComponent:@"Bundle"];
    NSString *game = [root stringByAppendingPathComponent:@"Edition"];
    for (NSString *path in @[source,game]) assert([fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSArray *names = @[@"WolkaraTouch.toc",@"WolkaraTouch.lua",@"Circle.tga", @"LICENSE"];
    for (NSString *name in names) Write([source stringByAppendingPathComponent:name], [@"original-" stringByAppendingString:name]);
    NSString *folder = [game stringByAppendingPathComponent:@"Interface/AddOns/WolkaraTouch"];
    NSError *error = nil;
    BOOL first = TKWoWInstallTouchAddon(source,game,&error);
    if (!first) NSLog(@"%@",error);
    assert(first && !error);
    assert(TKWoWInstallTouchAddon(source,game,&error));
    NSString *other = [game stringByAppendingPathComponent:@"Interface/AddOns/OtherAddon.lua"];
    Write(other,@"untouched");
    NSString *lua = [folder stringByAppendingPathComponent:@"WolkaraTouch.lua"];
    NSString *srcLua = [source stringByAppendingPathComponent:@"WolkaraTouch.lua"];
    Write(srcLua,@"version-two");
    assert(TKWoWInstallTouchAddon(source,game,&error));
    assert([[NSString stringWithContentsOfFile:lua encoding:NSUTF8StringEncoding error:NULL] isEqual:@"version-two"]);
    // A process interrupted after one atomic file write resumes safely against
    // either the old receipt or the new bundled contents.
    Write(srcLua,@"version-three"); Write(lua,@"version-three");
    assert(TKWoWInstallTouchAddon(source,game,&error));
    Write(lua,@"user customization");
    Write(srcLua,@"version-four"); error = nil;
    assert(!TKWoWInstallTouchAddon(source,game,&error) && [error.localizedDescription containsString:@"manual changes"]);
    assert([[NSString stringWithContentsOfFile:lua encoding:NSUTF8StringEncoding error:NULL] isEqual:@"user customization"]);
    assert([[NSString stringWithContentsOfFile:other encoding:NSUTF8StringEncoding error:NULL] isEqual:@"untouched"]);
    // Size checks precede NSData reads, including corrupt sparse multi-GB files.
    int fd = open(lua.fileSystemRepresentation, O_WRONLY);
    assert(fd >= 0 && ftruncate(fd, (off_t)5*1024*1024*1024) == 0); close(fd);
    error = nil;
    assert(!TKWoWInstallTouchAddon(source,game,&error) && [error.localizedDescription containsString:@"too large"]);
    Write(lua,@"version-four");
    NSString *receipt = [folder stringByAppendingPathComponent:@".wolkara-managed.json"];
    fd = open(receipt.fileSystemRepresentation, O_WRONLY);
    assert(fd >= 0 && ftruncate(fd, 65537) == 0); close(fd);
    assert(!TKWoWInstallTouchAddon(source,game,NULL));
    assert([fm removeItemAtPath:receipt error:NULL]);
    assert(TKWoWInstallTouchAddon(source,game,NULL));
    // Reject a linked leaf, linked addon directory or Interface parent without
    // altering the target (including a link that points back inside the root).
    assert([fm removeItemAtPath:lua error:NULL]);
    assert(symlink(other.fileSystemRepresentation,lua.fileSystemRepresentation)==0);
    assert(!TKWoWInstallTouchAddon(source,game,NULL));
    assert([[NSString stringWithContentsOfFile:other encoding:NSUTF8StringEncoding error:NULL] isEqual:@"untouched"]);
    assert([fm removeItemAtPath:folder error:NULL]);
    assert(symlink(source.fileSystemRepresentation,folder.fileSystemRepresentation)==0);
    assert(!TKWoWInstallTouchAddon(source,game,NULL));
    assert([fm removeItemAtPath:[game stringByAppendingPathComponent:@"Interface"] error:NULL]);
    assert(symlink(source.fileSystemRepresentation,[game stringByAppendingPathComponent:@"Interface"].fileSystemRepresentation)==0);
    assert(!TKWoWInstallTouchAddon(source,game,NULL));
    assert([fm removeItemAtPath:[game stringByAppendingPathComponent:@"Interface"] error:NULL]);
    // An incomplete resource cannot partially install.
    assert([fm removeItemAtPath:[source stringByAppendingPathComponent:@"Circle.tga"] error:NULL]);
    assert(!TKWoWInstallTouchAddon(source,game,NULL));
    assert(![fm fileExistsAtPath:folder]);
    assert([fm removeItemAtPath:root error:NULL]);
    puts("Touch addon installer PASS: fresh, repeat, update, interrupted write, user edits, isolation and symlinks");
} }
