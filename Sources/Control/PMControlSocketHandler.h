#import <Foundation/Foundation.h>
#import <GCDWebServers/GCDWebsocketServerHandler.h>


@interface PMControlSocketHandler : GCDWebsocketServerHandler


- (void)handleTask:(NSString *)text;

@end
