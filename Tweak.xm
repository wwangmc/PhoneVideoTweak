#import "Sources/PMVideoServer.h"
#import "Sources/Control/PMControlServer.h"
#import "Sources/Control/PMControlScreen.h"

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    CGSize size = UIScreen.mainScreen.bounds.size;
    [PMControlScreen setScreenScale:UIScreen.mainScreen.scale];
    [PMControlScreen setScreenPTSize:MIN(size.width, size.height) height:MAX(size.width, size.height)];
    PMControlStartServer();
    [PMVideoServer start];
}
%end
