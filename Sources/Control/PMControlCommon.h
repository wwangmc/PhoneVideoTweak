#import <UIKit/UIKit.h>
@interface SpringBoard : UIApplication
- (int)_frontMostAppOrientation;
@end
static inline int PMControlRoundUp(int value, int multiple) {
    return multiple ? ((value + multiple - 1) / multiple) * multiple : value;
}
