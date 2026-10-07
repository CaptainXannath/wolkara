#import "TouchAddon.h"
#import <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"Wolkara.TouchAddon" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static NSString *Digest(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof digest; i++) [text appendFormat:@"%02x", digest[i]];
    return text;
}
static BOOL Directory(NSString *path, BOOL create, NSError **error) {
    // Check every ancestor without resolving a symlink into another location.
    NSString *current = @"/";
    for (NSString *part in path.pathComponents) {
        if ([part isEqual:@"/"]) continue;
        current = [current stringByAppendingPathComponent:part];
        struct stat status;
        if (lstat(current.fileSystemRepresentation, &status) == 0) {
            if (!S_ISDIR(status.st_mode)) return Fail(error, @"The addon folder contains a link or a non-directory. No addon files were replaced.");
        } else if (errno == ENOENT && create) {
            if (![NSFileManager.defaultManager createDirectoryAtPath:current withIntermediateDirectories:NO attributes:nil error:error]) return NO;
        } else return Fail(error, @"The addon directory could not be opened.");
    }
    return YES;
}
static BOOL RegularOrMissing(NSString *path, BOOL *exists, NSUInteger limit, NSError **error) {
    struct stat status;
    if (lstat(path.fileSystemRepresentation, &status) != 0) {
        *exists = NO;
        return errno == ENOENT ? YES : Fail(error, @"An addon file could not be inspected.");
    }
    *exists = YES;
    if (status.st_size < 0 || (uint64_t)status.st_size > limit)
        return Fail(error, @"An addon file is too large. Move the WolkaraTouch folder aside and retry; no addon files were replaced.");
    return S_ISREG(status.st_mode) && status.st_nlink == 1 ? YES :
        Fail(error, @"An addon file is a link or a special file. No addon files were replaced.");
}
BOOL TKWoWInstallTouchAddon(NSString *source, NSString *editionDirectory, NSError **error) {
    if (!source.isAbsolutePath || !editionDirectory.isAbsolutePath)
        return Fail(error, @"The bundled touch addon could not be located.");
    // The system may spell its container prefix /var or /private/var. Accept
    // those aliases, but the trusted roots themselves must be real directories.
    struct stat sourceStatus, editionStatus;
    if (lstat(source.fileSystemRepresentation, &sourceStatus) || !S_ISDIR(sourceStatus.st_mode) ||
        lstat(editionDirectory.fileSystemRepresentation, &editionStatus) || !S_ISDIR(editionStatus.st_mode))
        return Fail(error, @"The addon source or game directory is unavailable.");
    char *sourcePath = realpath(source.fileSystemRepresentation, NULL);
    char *editionPath = realpath(editionDirectory.fileSystemRepresentation, NULL);
    if (!sourcePath || !editionPath) {
        free(sourcePath); free(editionPath);
        return Fail(error, @"The addon directories could not be resolved.");
    }
    source = [NSString stringWithUTF8String:sourcePath];
    editionDirectory = [NSString stringWithUTF8String:editionPath];
    free(sourcePath); free(editionPath);
    if (!Directory(source, NO, error) || !Directory(editionDirectory, NO, error)) return NO;
    NSArray<NSString *> *names = @[@"WolkaraTouch.toc", @"WolkaraTouch.lua", @"Circle.tga", @"LICENSE"];
    NSMutableDictionary<NSString *, NSData *> *files = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *hashes = [NSMutableDictionary new];
    for (NSString *name in names) {
        NSString *path = [source stringByAppendingPathComponent:name]; BOOL exists;
        if (!RegularOrMissing(path, &exists, 2*1024*1024, error)) return NO;
        NSData *data = exists ? [NSData dataWithContentsOfFile:path options:0 error:error] : nil;
        if (!data || !data.length || data.length > 2*1024*1024)
            return Fail(error, @"The bundled touch addon is incomplete. Rebuild Wolkara before playing.");
        files[name] = data; hashes[name] = Digest(data);
    }
    NSString *folder = [editionDirectory stringByAppendingPathComponent:@"Interface/AddOns/WolkaraTouch"];
    if (!Directory(folder, YES, error)) return NO;
    NSString *receipt = [folder stringByAppendingPathComponent:@".wolkara-managed.json"];
    BOOL exists;
    if (!RegularOrMissing(receipt, &exists, 64*1024, error)) return NO;
    NSDictionary *previous = nil;
    if (exists) {
        NSData *data = [NSData dataWithContentsOfFile:receipt options:0 error:error];
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
        if (![value isKindOfClass:NSDictionary.class] || ![value[@"files"] isKindOfClass:NSDictionary.class])
            return Fail(error, @"The WolkaraTouch install record is damaged. Move that addon folder aside and retry.");
        previous = value[@"files"];
    }
    // Preflight every file before writing any. An interrupted update can have
    // either the previous or current bundled bytes and is safe to resume.
    for (NSString *name in names) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (!RegularOrMissing(path, &exists, 2*1024*1024, error)) return NO;
        if (!exists) continue;
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
        if (!data) return NO;
        NSString *hash = Digest(data);
        if (![hash isEqual:hashes[name]] && ![hash isEqual:previous[name]])
            return Fail(error, @"WolkaraTouch has manual changes. Move that addon folder aside before installing the bundled version; your changes have been preserved.");
    }
    for (NSString *name in names) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if ([[NSData dataWithContentsOfFile:path] isEqual:files[name]]) continue;
        if (![files[name] writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"files":hashes} options:NSJSONWritingSortedKeys error:error];
    return data && [data writeToFile:receipt options:NSDataWritingAtomic error:error];
}
