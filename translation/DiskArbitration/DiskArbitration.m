// Minimal Disk Arbitration compatibility for an iOS-hosted macOS game.
// This is NOT a disk daemon: it exposes only the subset imported by the
// current WoW Forever ARM64 executable. Keep the test adapter isolated.
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>

typedef const struct __DASession *DASessionRef;
typedef const struct __DADisk *DADiskRef;

// Apple's disk description uses the CFString value "DAVolumeNetwork".
const CFStringRef kDADiskDescriptionVolumeNetworkKey = CFSTR("DAVolumeNetwork");

DASessionRef DASessionCreate(CFAllocatorRef allocator) {
    // A real DASessionRef is a CF object owned by the caller. Use an actual
    // retainable CF object so CFRelease(session) is safe. This only models
    // the lifecycle, not system disk notifications or device arbitration.
    CFMutableDictionaryRef token = CFDictionaryCreateMutable(
        allocator, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    fprintf(stderr, "[disk-arbitration] DASessionCreate -> %p (emulated)\n", (void *)token);
    return (DASessionRef)token;
}

DADiskRef DADiskCreateFromVolumePath(CFAllocatorRef allocator,
                                    DASessionRef session, CFURLRef path) {
    if (!session || !path) return NULL;
    // Wolkara's sandbox has local storage. No network mount or IOKit device
    // can be enumerated through Disk Arbitration on iOS.
    CFMutableDictionaryRef disk = CFDictionaryCreateMutable(
        allocator, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    fprintf(stderr, "[disk-arbitration] DADiskCreateFromVolumePath -> %p (emulated)\n",
            (void *)disk);
    return (DADiskRef)disk;
}

CFDictionaryRef DADiskCopyDescription(DADiskRef disk) {
    if (!disk) return NULL;
    const void *keys[] = { kDADiskDescriptionVolumeNetworkKey };
    const void *values[] = { kCFBooleanFalse };
    // Copy-rule ownership: the caller releases this dictionary.
    return CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}

uint32_t DADiskCopyIOMedia(DADiskRef disk) {
    (void)disk;
    // No corresponding macOS IOKit media service on iOS.
    return 0;
}
