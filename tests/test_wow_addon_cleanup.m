#import <Foundation/Foundation.h>
#import "../launcher/WoW/AddonCleanup.h"
#include <assert.h>

int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSError *error = nil;
    assert(TKWoWRetireTouchAddon(root,&error) && !error);
    NSString *addons = [root stringByAppendingPathComponent:@"Interface/AddOns"];
    NSString *source = [addons stringByAppendingPathComponent:@"WolkaraTouch"];
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSData *original = [@"original synthetic addon" dataUsingEncoding:NSUTF8StringEncoding];
    assert([original writeToFile:[source stringByAppendingPathComponent:@"Fixture.lua"] atomically:YES]);
    NSString *other = [addons stringByAppendingPathComponent:@"OtherAddon"];
    assert([fm createDirectoryAtPath:other withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert([original writeToFile:[other stringByAppendingPathComponent:@"Keep.lua"] atomically:YES]);
    assert(TKWoWRetireTouchAddon(root,&error) && ![fm fileExistsAtPath:source]);
    NSString *disabled = [root stringByAppendingPathComponent:@"Interface/DisabledAddOns"];
    NSArray *backups = [fm contentsOfDirectoryAtPath:disabled error:NULL]; assert(backups.count == 1);
    NSString *backup = [[disabled stringByAppendingPathComponent:backups[0]] stringByAppendingPathComponent:@"Fixture.lua"];
    assert([[NSData dataWithContentsOfFile:backup] isEqual:original]);
    assert([[NSData dataWithContentsOfFile:[other stringByAppendingPathComponent:@"Keep.lua"]] isEqual:original]);
    assert(TKWoWRetireTouchAddon(root,&error)); // Idempotent and no empty backups.
    assert([fm contentsOfDirectoryAtPath:disabled error:NULL].count == 1);
    // Repeated installs do not overwrite an earlier backup.
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:NO attributes:nil error:NULL]);
    assert(TKWoWRetireTouchAddon(root,&error));
    assert([fm contentsOfDirectoryAtPath:disabled error:NULL].count == 2);
    // No links at the source or its ancestors may reach another installation.
    assert([fm createSymbolicLinkAtPath:source withDestinationPath:other error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error) && error);
    assert([fm removeItemAtPath:source error:NULL]);
    assert([fm removeItemAtPath:addons error:NULL]);
    assert([fm createSymbolicLinkAtPath:addons withDestinationPath:disabled error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error));
    assert([fm removeItemAtPath:addons error:NULL]);
    assert([fm createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([fm removeItemAtPath:disabled error:NULL]);
    assert([fm createSymbolicLinkAtPath:disabled withDestinationPath:root error:NULL]);
    assert(!TKWoWRetireTouchAddon(root,&error) && [fm fileExistsAtPath:source]);
    assert([fm removeItemAtPath:root error:NULL]);
    puts("Addon cleanup PASS: retirement, exact content preservation, isolation, repeat and symlink rejection.");
} return 0; }
