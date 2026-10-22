#import "PMVideoServer.h"
#import "PMVideoStream.h"
#import "PMWire.h"
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/tcp.h>
#include <unistd.h>

@implementation PMVideoServer
+ (void)start {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Match mks_tweak's portrait coordinate space, including Display Zoom.
        CGSize bounds = UIScreen.mainScreen.bounds.size;
        CGFloat scale = UIScreen.mainScreen.scale;
        CGSize pixels = CGSizeMake(MIN(bounds.width, bounds.height) * scale,
                                   MAX(bounds.width, bounds.height) * scale);
        NSString *name = UIDevice.currentDevice.name ?: @"iPhone";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            int listener = socket(AF_INET, SOCK_STREAM, 0);
            if (listener < 0) { NSLog(@"[PhoneVideo] socket failed: %d", errno); return; }
            int yes = 1;
            setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
            struct sockaddr_in address = {0};
            address.sin_family = AF_INET;
            address.sin_len = sizeof(address);
            address.sin_port = htons(PM_VIDEO_PORT);
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (bind(listener, (struct sockaddr *)&address, sizeof(address)) || listen(listener, 4)) {
                NSLog(@"[PhoneVideo] bind/listen failed: %d", errno);
                close(listener);
                return;
            }
            NSLog(@"[PhoneVideo] USB video listening on loopback :%d", PM_VIDEO_PORT);
            // A single encoder per phone. Busy connections are rejected, never queued.
            dispatch_semaphore_t available = dispatch_semaphore_create(1);
            while (YES) {
                int fd = accept(listener, NULL, NULL);
                if (fd < 0) { if (errno == EINTR) continue; break; }
                if (dispatch_semaphore_wait(available, DISPATCH_TIME_NOW)) { close(fd); continue; }
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
                setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
                int buffer = 128 * 1024;
                setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &buffer, sizeof(buffer));
                struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    @autoreleasepool {
                        PMVideoStream *stream = [[PMVideoStream alloc] initWithSocket:fd size:pixels name:name];
                        @try { [stream run]; }
                        @catch (NSException *exception) { NSLog(@"[PhoneVideo] stream exception: %@", exception); }
                        @finally { shutdown(fd, SHUT_RDWR); close(fd); dispatch_semaphore_signal(available); }
                    }
                });
            }
            close(listener);
        });
    });
}
@end
