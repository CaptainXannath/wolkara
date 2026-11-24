#import "MobileInterface.h"
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

static NSString * const Owner = @"WolkaraMobile bundled addon v1\n";
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"Wolkara.MobileInterface" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL Directory(NSString *path, BOOL create, NSError **error) {
    struct stat st;
    if (!lstat(path.fileSystemRepresentation,&st))
        return S_ISDIR(st.st_mode) || Fail(error,@"The mobile interface folder must not be a link or a file.");
    if (errno != ENOENT || !create) return Fail(error,@"The mobile interface folder could not be opened.");
    return [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:error];
}
static BOOL Exists(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation,&st)==0; }
static BOOL Owned(NSString *path, NSError **error) {
    if (!Directory(path,NO,error)) return NO;
    NSString *marker=[path stringByAppendingPathComponent:@".wolkara-owner"];
    struct stat st;
    if (lstat(marker.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_size>128 ||
        ![[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] isEqual:Owner])
        return Fail(error,@"A different addon already occupies WolkaraMobile. Move it aside before starting.");
    return YES;
}
BOOL TKWoWPrepareMobileInterface(NSString *editionDirectory, NSString *sourceDirectory, BOOL enabled, NSError **error) {
    if (![editionDirectory.lastPathComponent isEqual:@"_forever_"])
        return Fail(error,@"The mobile interface is only supported for WoW Forever.");
    if (!editionDirectory.isAbsolutePath || !Directory(editionDirectory,NO,error)) return NO;
    char *resolved=realpath(editionDirectory.fileSystemRepresentation,NULL);
    if (!resolved) return Fail(error,@"The game directory could not be resolved.");
    NSString *root=[NSString stringWithUTF8String:resolved]; free(resolved);
    NSString *interface=[root stringByAppendingPathComponent:@"Interface"];
    NSString *addons=[interface stringByAppendingPathComponent:@"AddOns"];
    if (!Directory(interface,YES,error) || !Directory(addons,YES,error)) return NO;
    NSArray *files=@[@"WolkaraMobile.toc",@"Core.lua",@"Actions.lua",@"Picker.lua",@"Abilities.lua",
        @"Menu.lua",@"Windows.lua",@"Bags.lua",@"Bridge.lua",@"LICENSE"];
    // Validate all source files before touching an existing installation.
    NSMutableDictionary<NSString *,NSData *> *contents=[NSMutableDictionary new];
    for (NSString *file in files) {
        NSString *path=[sourceDirectory stringByAppendingPathComponent:file]; struct stat st;
        if (!sourceDirectory || lstat(path.fileSystemRepresentation,&st) || !S_ISREG(st.st_mode) || st.st_size>256*1024)
            return Fail(error,@"The bundled mobile interface is missing or invalid. Reinstall Wolkara.");
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error]; if (!data) return NO;
        contents[file]=data;
    }
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *live=[addons stringByAppendingPathComponent:@"WolkaraMobile"];
    NSString *stage=[addons stringByAppendingPathComponent:@".WolkaraMobile-stage"];
    NSString *backup=[addons stringByAppendingPathComponent:@".WolkaraMobile-backup"];
    for (NSString *path in @[live,stage,backup]) if (Exists(path) && !Owned(path,error)) return NO;
    // Recover an interruption after the previous version was renamed.
    if (Exists(backup)) {
        if (Exists(live)) { if (![fm removeItemAtPath:backup error:error]) return NO; }
        else if (![fm moveItemAtPath:backup toPath:live error:error]) return NO;
    }
    if (Exists(stage) && ![fm removeItemAtPath:stage error:error]) return NO;
    if (!Directory(stage,YES,error)) return NO;
    if (![Owner writeToFile:[stage stringByAppendingPathComponent:@".wolkara-owner"] atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    for (NSString *file in files)
        if (![contents[file] writeToFile:[stage stringByAppendingPathComponent:file] options:NSDataWritingAtomic error:error]) return NO;
    // A reload uses the addon's current state; a fresh launch uses Settings' state.
    NSString *config=[NSString stringWithFormat:@"local _, ns = ...\nns.hostEnabled = %@\nns.hostSession = \"%@\"\n",enabled?@"true":@"false",NSUUID.UUID.UUIDString];
    if (![config writeToFile:[stage stringByAppendingPathComponent:@"Config.lua"] atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    if (Exists(live) && ![fm moveItemAtPath:live toPath:backup error:error]) return NO;
    if (![fm moveItemAtPath:stage toPath:live error:error]) {
        if (Exists(backup)) [fm moveItemAtPath:backup toPath:live error:nil];
        return NO;
    }
    if (Exists(backup) && ![fm removeItemAtPath:backup error:error]) return NO;
    return YES;
}
