#import <Foundation/Foundation.h>
#import "../launcher/WoW/MobileInterface.h"
#include <assert.h>
static void Write(NSString *path, NSString *text) {
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}
int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *root = [tmp stringByAppendingPathComponent:@"_forever_"];
    assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *source = [fm.currentDirectoryPath stringByAppendingPathComponent:@"addons/WolkaraMobile"];
    NSString *live = [root stringByAppendingPathComponent:@"Interface/AddOns/WolkaraMobile"];
    NSString *config = [live stringByAppendingPathComponent:@"Config.lua"];
    NSString *backup = [root stringByAppendingPathComponent:@"Interface/AddOns/.WolkaraMobile-backup"];
    NSString *other = [root stringByAppendingPathComponent:@"Interface/AddOns/Questie.lua"];
    NSError *error = nil;
    assert(TKWoWPrepareMobileInterface(root, source, NO, &error) && !error);
    assert([[NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:NULL] containsString:@"ns.hostEnabled = false"]);
    Write(other, @"keep other addon byte for byte");
    NSString *saved = [root stringByAppendingPathComponent:@"WTF"];
    Write(saved, @"keep user layout and saved variables");
    NSData *old = [NSData dataWithContentsOfFile:config];
    assert(TKWoWPrepareMobileInterface(root, source, YES, &error));
    assert([[NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:NULL] containsString:@"ns.hostEnabled = true"]);
    assert(![[NSData dataWithContentsOfFile:config] isEqual:old]);
    assert([[NSString stringWithContentsOfFile:other encoding:NSUTF8StringEncoding error:NULL] isEqual:@"keep other addon byte for byte"]);
    assert([[NSString stringWithContentsOfFile:saved encoding:NSUTF8StringEncoding error:NULL] isEqual:@"keep user layout and saved variables"]);
    old = [NSData dataWithContentsOfFile:config];
    assert(!TKWoWPrepareMobileInterface(root, @"/nonexistent-bundled-addon", NO, &error));
    assert([[NSData dataWithContentsOfFile:config] isEqual:old]);
    // Interrupted rename is restored before the next update.
    assert([fm moveItemAtPath:live toPath:backup error:NULL]);
    assert(TKWoWPrepareMobileInterface(root, source, YES, &error));
    assert([fm fileExistsAtPath:config] && ![fm fileExistsAtPath:backup]);
    // A foreign folder, links, or another edition cannot be overwritten.
    assert([fm removeItemAtPath:[live stringByAppendingPathComponent:@".wolkara-owner"] error:NULL]);
    assert(!TKWoWPrepareMobileInterface(root, source, NO, &error));
    assert([[NSData dataWithContentsOfFile:config] isEqual:old] == NO); // New session from recovery.
    assert([fm removeItemAtPath:live error:NULL]);
    assert([fm createSymbolicLinkAtPath:live withDestinationPath:source error:NULL]);
    assert(!TKWoWPrepareMobileInterface(root, source, NO, &error));
    assert(!TKWoWPrepareMobileInterface(tmp, source, NO, &error));
    assert([fm removeItemAtPath:tmp error:NULL]);
    puts("MOBILE_INSTALL_PASS: isolation, config, interrupted upgrade, foreign-folder and symlink refusal");
} return 0; }
