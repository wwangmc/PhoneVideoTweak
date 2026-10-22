#import "PMVideoStream.h"
#import "PMWire.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVPixelBufferIOSurface.h>
#import <VideoToolbox/VideoToolbox.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreImage/CoreImage.h>
#include <dlfcn.h>
#include <sys/socket.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>
#include <math.h>

typedef void (*PMRenderDisplay)(int, CFStringRef, IOSurfaceRef, int, int);
typedef CFIndex (*PMDirtyFrameCount)(void *);

static uint64_t PMNow(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}
static BOOL PMWriteAll(int fd, const void *bytes, size_t length) {
    const uint8_t *p = bytes;
    while (length) {
        ssize_t n = send(fd, p, length, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; length -= (size_t)n;
    }
    return YES;
}
static CVReturn PMCreatePool(CVPixelBufferPoolRef *pool, int width, int height, OSType format) {
    NSDictionary *attributes = @{
        (__bridge NSString *)kCVPixelBufferWidthKey: @(width), (__bridge NSString *)kCVPixelBufferHeightKey: @(height),
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(format),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{ @"IOSurfaceIsGlobal": @YES },
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
        (__bridge NSString *)kCVPixelBufferBytesPerRowAlignmentKey: @64,
    };
    return CVPixelBufferPoolCreate(NULL, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCVPixelBufferPoolMinimumBufferCountKey: @3},
                                   (__bridge CFDictionaryRef)attributes, pool);
}

@interface PMVideoStream () {
    int _fd;
    CGSize _size;
    NSString *_name;
    VTCompressionSessionRef _encoder;
    CIContext *_imageContext;
    CGColorSpaceRef _colorSpace;
    CVPixelBufferPoolRef _capturePool;
    CVPixelBufferPoolRef _encodePool;
    dispatch_semaphore_t _encoded;
    NSData *_config;
    NSData *_frame;
    OSStatus _encodeStatus;
    BOOL _sentConfig;
    BOOL _key;
}
- (void)encodedSample:(CMSampleBufferRef)sample status:(OSStatus)status;
@end

static void PMEncoded(void *context, void *source, OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    (void)source; (void)flags;
    [(__bridge PMVideoStream *)context encodedSample:sample status:status];
}

@implementation PMVideoStream
- (instancetype)initWithSocket:(int)fd size:(CGSize)size name:(NSString *)name {
    if ((self = [super init])) { _fd = fd; _size = size; _name = [name copy]; _encoded = dispatch_semaphore_create(0); }
    return self;
}
- (void)dealloc {
    if (_encoder) { VTCompressionSessionInvalidate(_encoder); CFRelease(_encoder); }
    if (_colorSpace) CGColorSpaceRelease(_colorSpace);
    if (_capturePool) CVPixelBufferPoolRelease(_capturePool);
    if (_encodePool) CVPixelBufferPoolRelease(_encodePool);
}
- (BOOL)set:(CFStringRef)key value:(CFTypeRef)value {
    OSStatus status = VTSessionSetProperty(_encoder, key, value);
    if (status) NSLog(@"[PhoneVideo] encoder property %@ failed: %d", key, (int)status);
    return status == noErr;
}
- (void)encodedSample:(CMSampleBufferRef)sample status:(OSStatus)status {
    @autoreleasepool {
        _encodeStatus = status;
        if (status || !sample || !CMSampleBufferDataIsReady(sample)) { dispatch_semaphore_signal(_encoded); return; }
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, false);
        CFDictionaryRef first = attachments && CFArrayGetCount(attachments) ? CFArrayGetValueAtIndex(attachments, 0) : NULL;
        CFBooleanRef notSync = first ? CFDictionaryGetValue(first, kCMSampleAttachmentKey_NotSync) : NULL;
        _key = !notSync || !CFBooleanGetValue(notSync);
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        int nalLength = 0;
        const uint8_t *sps = NULL; size_t spsSize = 0, count = 0;
        if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &count, &nalLength) || nalLength != 4) {
            _encodeStatus = -1; dispatch_semaphore_signal(_encoded); return;
        }
        static const uint8_t start[] = {0, 0, 0, 1};
        if (!_sentConfig) {
            NSMutableData *config = [NSMutableData data];
            for (size_t i = 0; i < count; ++i) {
                const uint8_t *parameter = NULL; size_t length = 0;
                if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, i, &parameter, &length, NULL, NULL) || length > PM_MAX_PACKET - 4 - config.length) {
                    _encodeStatus = -1; dispatch_semaphore_signal(_encoded); return;
                }
                [config appendBytes:start length:4]; [config appendBytes:parameter length:length];
            }
            _config = config;
        }
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        size_t size = block ? CMBlockBufferGetDataLength(block) : 0;
        if (!size || size > PM_MAX_PACKET) { _encodeStatus = -1; dispatch_semaphore_signal(_encoded); return; }
        NSMutableData *avcc = [NSMutableData dataWithLength:size];
        if (CMBlockBufferCopyDataBytes(block, 0, size, avcc.mutableBytes)) { _encodeStatus = -1; dispatch_semaphore_signal(_encoded); return; }
        if (!PMAnnexB(avcc.mutableBytes, size)) _encodeStatus = -1;
        if (!_encodeStatus) _frame = avcc;
        dispatch_semaphore_signal(_encoded);
    }
}
- (BOOL)sendPacket:(NSData *)data flags:(uint64_t)flags {
    uint8_t header[12];
    return PMPacketHeader(header, flags, data.length) && PMWriteAll(_fd, header, 12) && PMWriteAll(_fd, data.bytes, data.length);
}
- (void)run {
    uint8_t request[16];
    size_t offset = 0;
    while (offset < sizeof(request)) {
        ssize_t n = recv(_fd, request + offset, sizeof(request) - offset, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return;
        offset += (size_t)n;
    }
    if (!PMValidRequest(request)) return;
    int fps = (int)PMRead32(request + 4), bitRate = (int)PMRead32(request + 8), maxSize = (int)PMRead32(request + 12);
    int sourceW = (int)_size.width, sourceH = (int)_size.height;
    if (sourceW < 2 || sourceH < 2 || sourceW > 8192 || sourceH > 8192) return;
    double scale = maxSize ? fmin(1.0, (double)maxSize / MAX(sourceW, sourceH)) : 1.0;
    int width = MAX(2, ((int)(sourceW * scale)) & ~1), height = MAX(2, ((int)(sourceH * scale)) & ~1);

    // Private global-display capture is isolated here; no mks_tweak symbols or hooks are imported.
    PMRenderDisplay render = (PMRenderDisplay)dlsym(RTLD_DEFAULT, "CARenderServerRenderDisplay");
    PMDirtyFrameCount dirtyCount = (PMDirtyFrameCount)dlsym(RTLD_DEFAULT, "CARenderServerGetDirtyFrameCount");
    if (!render) { NSLog(@"[PhoneVideo] global display capture unavailable"); return; }
    BOOL needsScale = width != sourceW || height != sourceH;
    if (PMCreatePool(&_capturePool, sourceW, sourceH, kCVPixelFormatType_32BGRA) ||
        (needsScale && PMCreatePool(&_encodePool, width, height, kCVPixelFormatType_32BGRA))) {
        NSLog(@"[PhoneVideo] pixel pool creation failed"); return;
    }
    if (needsScale) {
        // VTPixelTransferSession is iOS 16+. Core Image keeps iOS 14/15 support.
        _imageContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO, kCIContextCacheIntermediates: @NO}];
        _colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!_imageContext || !_colorSpace) return;
    }

    // On iOS 14/15 H.264 uses the platform VideoToolbox encoder. The hardware-only
    // specification keys are unavailable in the iOS 16.5 SDK; do not weak-link macOS-only keys.
    NSDictionary *inputAttributes = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (__bridge NSString *)kCVPixelBufferWidthKey: @(width), (__bridge NSString *)kCVPixelBufferHeightKey: @(height), (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL,
        (__bridge CFDictionaryRef)inputAttributes, NULL, PMEncoded, (__bridge void *)self, &_encoder);
    if (status) { NSLog(@"[PhoneVideo] encoder create failed: %d", (int)status); return; }
    if (![self set:kVTCompressionPropertyKey_RealTime value:kCFBooleanTrue] ||
        ![self set:kVTCompressionPropertyKey_AllowFrameReordering value:kCFBooleanFalse] ||
        ![self set:kVTCompressionPropertyKey_ProfileLevel value:kVTProfileLevel_H264_Baseline_AutoLevel]) return;
    [self set:kVTCompressionPropertyKey_AverageBitRate value:(__bridge CFNumberRef)@(bitRate)];
    [self set:kVTCompressionPropertyKey_ExpectedFrameRate value:(__bridge CFNumberRef)@(fps)];
    [self set:kVTCompressionPropertyKey_MaxFrameDelayCount value:(__bridge CFNumberRef)@0];
    [self set:kVTCompressionPropertyKey_MaxKeyFrameInterval value:(__bridge CFNumberRef)@(fps * 2)];
    [self set:kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration value:(__bridge CFNumberRef)@2];
    status = VTCompressionSessionPrepareToEncodeFrames(_encoder);
    if (status) { NSLog(@"[PhoneVideo] encoder prepare failed: %d", (int)status); return; }

    uint8_t metadata[76] = {0};
    if (![_name getCString:(char *)metadata maxLength:64 encoding:NSUTF8StringEncoding]) {
        memset(metadata, 0, 64); memcpy(metadata, "iPhone", 6);
    }
    memcpy(metadata + 64, "h264", 4); PMWrite32(metadata + 68, width); PMWrite32(metadata + 72, height);
    if (!PMWriteAll(_fd, metadata, sizeof(metadata))) return;
    NSLog(@"[PhoneVideo] streaming %dx%d -> %dx%d, %d FPS, %d bps", sourceW, sourceH, width, height, fps, bitRate);

    NSDictionary *poolLimit = @{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey: @3};
    uint64_t began = PMNow(), next = began, lastFrame = 0, frames = 0, bytes = 0;
    CFIndex previousDirty = -1;
    BOOL captured = NO;
    while (YES) {
        @autoreleasepool {
            // Client disconnect must stop even when the display has no dirty frames.
            struct pollfd pfd = {.fd = _fd, .events = POLLIN};
            if (poll(&pfd, 1, 0) > 0) break; // Protocol has no client messages after request.
            uint64_t now = PMNow();
            if (now < next) { usleep((useconds_t)MIN((next - now) / 1000, 20000)); continue; }
            next = now + 1000000000ULL / (uint64_t)fps;
            CFIndex dirty = dirtyCount ? dirtyCount(NULL) : 0;
            // Periodic frame keeps a static stream alive and permits reconnect diagnostics.
            if (dirtyCount && captured && dirty == previousDirty && now - lastFrame < 1000000000ULL) continue;
            CVPixelBufferRef capture = NULL, input = NULL;
            if (CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(NULL, _capturePool, (__bridge CFDictionaryRef)poolLimit, &capture)) continue;
            IOSurfaceRef surface = CVPixelBufferGetIOSurface(capture);
            if (!surface || IOSurfaceLock(surface, 0, NULL) != kIOReturnSuccess) { CVPixelBufferRelease(capture); break; }
            render(0, CFSTR("LCD"), surface, 0, 0);
            IOSurfaceUnlock(surface, 0, NULL);
            if (needsScale) {
                CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(NULL, _encodePool, (__bridge CFDictionaryRef)poolLimit, &input);
                if (result) { CVPixelBufferRelease(capture); NSLog(@"[PhoneVideo] scale buffer failed: %d", (int)result); break; }
                CIImage *image = [[CIImage imageWithCVPixelBuffer:capture] imageByApplyingTransform:
                    CGAffineTransformMakeScale((double)width / sourceW, (double)height / sourceH)];
                [_imageContext render:image toCVPixelBuffer:input bounds:CGRectMake(0, 0, width, height) colorSpace:_colorSpace];
            } else {
                input = CVPixelBufferRetain(capture);
            }
            CVPixelBufferRelease(capture);
            _frame = nil; _config = nil; _encodeStatus = noErr;
            CMTime pts = CMTimeMake((int64_t)((now - began) / 1000), 1000000);
            NSDictionary *properties = captured ? nil : @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
            status = VTCompressionSessionEncodeFrame(_encoder, input, pts, CMTimeMake(1, fps), (__bridge CFDictionaryRef)properties, NULL, NULL);
            CVPixelBufferRelease(input);
            if (status || dispatch_semaphore_wait(_encoded, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC))) { NSLog(@"[PhoneVideo] encode timeout/error: %d", (int)status); break; }
            if (_encodeStatus) { NSLog(@"[PhoneVideo] output error: %d", (int)_encodeStatus); break; }
            if (!_frame.length) continue;
            if (_config.length) { if (![self sendPacket:_config flags:PM_CONFIG_FLAG]) break; _sentConfig = YES; }
            uint64_t flags = ((now - began) / 1000) | (_key ? PM_KEY_FLAG : 0);
            if (![self sendPacket:_frame flags:flags]) break;
            bytes += _frame.length; ++frames; lastFrame = now; previousDirty = dirty; captured = YES;
        }
    }
    // Stop callbacks before ARC releases this object. Never drain a growing queue.
    VTCompressionSessionInvalidate(_encoder);
    CFRelease(_encoder); _encoder = NULL;
    double seconds = (double)(PMNow() - began) / 1e9;
    NSLog(@"[PhoneVideo] stopped: %llu frames / %.2fs = %.1f FPS, %.2f Mbps", (unsigned long long)frames, seconds, frames / MAX(seconds, 0.001), bytes * 8 / MAX(seconds, 0.001) / 1e6);
}
@end
