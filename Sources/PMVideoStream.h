#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface PMVideoStream : NSObject
// Owns fd until run returns. UIKit must only be consulted by the caller on main.
- (instancetype)initWithSocket:(int)fd size:(CGSize)size name:(NSString *)name;
- (void)run;
@end
