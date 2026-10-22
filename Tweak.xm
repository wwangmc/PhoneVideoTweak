#import "Sources/PMVideoServer.h"

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [PMVideoServer start];
}
%end
