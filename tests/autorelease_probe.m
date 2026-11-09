// Compiled without ARC: deliberately leave a temporary in the enclosing pool.
// No imported application or private runtime API is involved.
#import <Foundation/Foundation.h>
static unsigned live;
@interface AKFixtureTemporary : NSObject
@end
@implementation AKFixtureTemporary
- (instancetype)init { if ((self=[super init])) live++; return self; }
- (void)dealloc { live--; [super dealloc]; }
@end
void AKFixtureAutoreleaseTemporary(void) { [[[AKFixtureTemporary alloc] init] autorelease]; }
unsigned AKFixtureLiveTemporaries(void) { return live; }
