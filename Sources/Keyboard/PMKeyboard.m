// Adapted from mks_tweak/appdelegate/UIKeyboard.xm. The receiver is per process,
// with a private notification name so an installed legacy plugin cannot insert twice.
#import <UIKit/UIKit.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <objc/runtime.h>

@interface UIKeyboardImpl : UIView
+ (instancetype)activeInstance;
+ (instancetype)sharedInstance;
@property (nonatomic, readonly) UIResponder<UITextInput> *inputDelegate;
- (void)insertText:(NSString *)text;
- (void)hideKeyboard;
- (void)showKeyboard;
- (void)moveCursorByAmount:(long long)amount;
- (void)deleteBackward;
@end

@interface PMKeyboardReceiver : NSObject
@end

@implementation PMKeyboardReceiver
- (void)receive:(NSNotification *)notification {
    NSDictionary *body = notification.userInfo;
    if (![body isKindOfClass:NSDictionary.class] || ![body[@"task_id"] isKindOfClass:NSNumber.class]) return;
    NSInteger task = [body[@"task_id"] integerValue];
    id value = body[@"task_content"];
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("UIKeyboardImpl");
        UIKeyboardImpl *keyboard = [cls activeInstance] ?: [cls sharedInstance];
        if (!keyboard) return;
        if (task == 1 && [value isKindOfClass:NSString.class]) {
            id<UIKeyInput> input = (id<UIKeyInput>)keyboard.inputDelegate;
            if ([input respondsToSelector:@selector(insertText:)]) [input insertText:value];
        } else if (task == 2) {
            if ([value intValue] == 1) [keyboard hideKeyboard];
            else if ([value intValue] == 2) [keyboard showKeyboard];
        } else if (task == 3) {
            [keyboard moveCursorByAmount:[value longLongValue]];
        } else if (task == 4) {
            // A malformed client must not block the app's main thread indefinitely.
            NSInteger count = MIN(MAX([value integerValue], 0), 4096);
            for (NSInteger i = 0; i < count; i++) [keyboard deleteBackward];
        }
    });
}
@end

__attribute__((constructor)) static void PMKeyboardInitialize(void) {
    @autoreleasepool {
        static PMKeyboardReceiver *receiver;
        receiver = [PMKeyboardReceiver new];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:receiver selector:@selector(receive:)
            name:@"com.phonemanager.phonevideo.keyboard" object:nil];
    }
}
