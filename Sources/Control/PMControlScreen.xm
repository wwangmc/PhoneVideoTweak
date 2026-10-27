#include "PMControlScreen.h"
#include "PMControlCommon.h"
#import <UIKit/UIKit.h>

// #import "headers/IOKitSPI.h"
#import <IOSurface/IOSurfaceRef.h>


// 像素高度及宽度
static CGFloat device_screen_width = 0;
static CGFloat device_screen_height = 0;

// 实际高度及宽度
static CGFloat device_screen_pt_width = 0;
static CGFloat device_screen_pt_height = 0;
static CGSize portraitSize;

static CFIndex sDirtyFrameCount = 0;
static BOOL sHasCapturedFrame = NO;
static CGFloat sLastCaptureQuality = 0;

extern "C"{
CFIndex CARenderServerGetDirtyFrameCount(void *);
}

static CGFloat device_screen_scale = 0;
OBJC_EXTERN void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
OBJC_EXTERN CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);

@implementation PMControlScreen
{
    // device screen size
}

+ (void)setScreenScale:(CGFloat) scale
{
	device_screen_scale = scale;

	if (device_screen_scale == 0 || device_screen_scale > 10000)
	{
		NSLog(@"PhoneVideo: Unable to initialze the screen scale.");
	}
}
/*
Get the size of the screen and set them.
*/
+ (void)setScreenPTSize:(CGFloat)x height:(CGFloat) y
{
	device_screen_pt_width = x;
	device_screen_pt_height = y;

	if (device_screen_pt_width == 0 || device_screen_pt_height == 0 || device_screen_pt_width > 10000 || device_screen_pt_height > 10000)
	{
		NSLog(@"PhoneVideo: Unable to initialze the screen pt size. screen width: %f, screen height: %f", device_screen_pt_width, device_screen_pt_height);
	}
	else
	{
        [PMControlScreen setScreenSize:x*device_screen_scale height:y*device_screen_scale];
        portraitSize = CGSizeMake(device_screen_pt_width,
                                device_screen_pt_height);
    }
}

+ (void)setScreenSize:(CGFloat)x height:(CGFloat) y
{
	device_screen_width = x;
	device_screen_height = y;

	if (device_screen_width == 0 || device_screen_height == 0 || device_screen_width > 10000 || device_screen_height > 10000)
	{
		NSLog(@"PhoneVideo: Unable to initialze the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
	else
	{
        NSLog(@"PhoneVideo: successfully initialize the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
}

+ (int)getScreenOrientation
{
    __block int screenOrientation = -1;

    void (^readOrientation)(void) = ^{
        @try{
            SpringBoard *springboard = (SpringBoard*)[%c(SpringBoard) sharedApplication];
            screenOrientation = [springboard _frontMostAppOrientation];
            //NSLog(@"PhoneVideo: orientation %d", screenOrientation);
        }
        @catch (NSException *exception) {
            NSLog(@"PhoneVideo: Debug: %@", exception.reason);
        }
    };
    if ([NSThread isMainThread]) readOrientation();
    else dispatch_sync(dispatch_get_main_queue(), readOrientation);

    return screenOrientation;
}

+ (CGFloat)getScreenWidth
{
    if (device_screen_width == 0)
    {
        NSLog(@"PhoneVideo: Cannot get screen width. Maybe you call [PMControlScreen getScreenWidth] before springboard getting the screen size.");
    }
    return device_screen_width;
}

+ (CGFloat)getScreenHeight
{
    if (device_screen_height == 0)
    {
        NSLog(@"PhoneVideo: Cannot get screen height. Maybe you call [PMControlScreen getScreenHeight] before springboard getting the screen size.");
    }
    return device_screen_height;
}

+ (CGFloat)getScale
{
    return device_screen_scale;
}

+ (CGRect)getBounds
{
    return [UIScreen mainScreen].bounds;
}
+ (void) resetDirtyFrameCount{
    @synchronized (self) {
        sDirtyFrameCount = 0;
        sHasCapturedFrame = NO;
    }
}
+ (NSData *)takeScreenshotWithQuality_v2:(CGFloat)quality {
    return [self takeScreenshotWithQuality_v2:quality error:NULL];
}

+ (NSData *)takeScreenshotWithQuality_v2:(CGFloat)quality error:(NSError **)error {
    if (error) *error = nil;
    @synchronized (self) {
        CFIndex dirtyFrameCount = CARenderServerGetDirtyFrameCount(NULL);
        if (sHasCapturedFrame && dirtyFrameCount == sDirtyFrameCount && quality == sLastCaptureQuality) {
            return nil; // No change
        }
        CGImageRef imageRef = [PMControlScreen createScreenShotCGImageRef];
        NSData *data = nil;
        if (imageRef) {
            UIImage *image = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            data = UIImageJPEGRepresentation(image, quality);
        }
        if (!data.length) {
            if (error) *error = [NSError errorWithDomain:@"com.phonemanager.phonevideo.screenshot" code:500
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture screen"}];
            return nil;
        }
        // Failed captures must not suppress retries for the same dirty frame count.
        sDirtyFrameCount = dirtyFrameCount;
        sLastCaptureQuality = quality;
        sHasCapturedFrame = YES;
        return data;
    }
}

+ (UIImage *)captureWindowImage {
    __block UIImage *image = nil;
    void (^capture)(void) = ^{
        if (portraitSize.width <= 0 || portraitSize.height <= 0 || device_screen_scale <= 0) return;
        UIGraphicsBeginImageContextWithOptions(portraitSize, NO, device_screen_scale);
        @try {
            for (UIWindow *window in [[UIApplication sharedApplication] windows]) {
                [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
            }
            image = UIGraphicsGetImageFromCurrentImageContext();
        } @finally {
            UIGraphicsEndImageContext();
        }
    };
    if ([NSThread isMainThread]) capture();
    else dispatch_sync(dispatch_get_main_queue(), capture);
    return image;
}

+ (NSData *)takeScreenshotWithQuality:(CGFloat)quality {
    UIImage *image = [self captureWindowImage];
    return image ? UIImageJPEGRepresentation(image, quality) : nil;
}
+ (NSData *)takeScreenshot_v2 {
    CGImageRef imageRef = [PMControlScreen createScreenShotCGImageRef];
    if (!imageRef) return nil;
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    return UIImagePNGRepresentation(image);
}
+ (NSData *)takeScreenshot {
    UIImage *image = [self captureWindowImage];
    return image ? UIImagePNGRepresentation(image) : nil;
}
+ (CGImageRef)createScreenShotCGImageRef {
    if (device_screen_width <= 0 || device_screen_height <= 0) return NULL;
    // 静态变量（只计算一次）
    static int bytesPerElement = 4;
    static int bytesPerRow;
    static NSNumber *IOSurfaceBytesPerElement;
    static NSNumber *IOSurfaceBytesPerRow;
    static NSNumber *IOSurfaceAllocSize;
    static NSNumber *nheight;
    static NSNumber *nwidth;
    static NSNumber *IOSurfacePixelFormat;
    static NSNumber *IOSurfaceIsGlobal;
    static NSDictionary *propertiesTemplate;

    // 使用 dispatch_once 确保线程安全初始化
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bytesPerRow = PMControlRoundUp(bytesPerElement * device_screen_width, 32);

        // 缓存 NSNumber 对象（避免重复创建）
        IOSurfaceBytesPerElement = @(bytesPerElement);
        IOSurfaceBytesPerRow = @(bytesPerRow);
        IOSurfaceAllocSize = @(bytesPerRow * device_screen_height);
        nheight = @(device_screen_height);
        nwidth = @(device_screen_width);
        IOSurfacePixelFormat = @(1111970369); // 固定值
        IOSurfaceIsGlobal = @(1); // 固定值

        // 字典模板（避免每次重新构建）
        propertiesTemplate = @{
            @"IOSurfaceAllocSize": IOSurfaceAllocSize,
            @"IOSurfaceBytesPerElement": IOSurfaceBytesPerElement,
            @"IOSurfaceBytesPerRow": IOSurfaceBytesPerRow,
            @"IOSurfaceHeight": nheight,
            @"IOSurfaceIsGlobal": IOSurfaceIsGlobal,
            @"IOSurfacePixelFormat": IOSurfacePixelFormat,
            @"IOSurfaceWidth": nwidth
        };
    });

    // 创建 IOSurface
    IOSurfaceRef screenSurface = IOSurfaceCreate((__bridge CFDictionaryRef)propertiesTemplate);
    if (!screenSurface) return NULL;

    // 渲染截图
    if (IOSurfaceLock(screenSurface, 0, NULL) != KERN_SUCCESS) {
        CFRelease(screenSurface);
        return NULL;
    }
    CARenderServerRenderDisplay(0, CFSTR("LCD"), screenSurface, 0, 0);

    // 转换为 CGImage
    CGImageRef cgImageRef = UICreateCGImageFromIOSurface(screenSurface);

    // 清理
    IOSurfaceUnlock(screenSurface, 0, NULL);
    CFRelease(screenSurface);

    return cgImageRef;
}
@end
