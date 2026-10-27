#import "PMControlServer.h"
#import "PMControlSupport.h"
#import "PMControlScreen.h"
#import "PMControlDeviceInfo.h"
#import "PMControlDeviceConfigurator.h"
#import "PMControlSocketHandler.h"
#import "PMControlExecutor.h"
#import "PMHIDEventGenerator.h"
#import <Foundation/NSDistributedNotificationCenter.h>
#include <limits.h>

static GCDWebsocketServer *webServer = nil;

static void addGETHandler(GCDWebsocketServer *server, NSString *path, GCDWebServerProcessBlock handler) {
    [server addHandlerForMethod:@"GET" path:path requestClass:[GCDWebServerRequest class] processBlock:handler];
}

static GCDWebServerResponse *imageResponse(NSData *image, NSString *contentType) {
    if (!image.length) return PMControlServerError(@"Failed to capture screen");
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:image contentType:contentType];
    [response setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
    return PMControlApplyCORS(response);
}

void PMControlStartServer(void) {
    // Initialize UIKit-dependent screen metrics on the main thread, then serialize HID work off it.
    PMControlOnMainThread(^{ [PMHIDEventGenerator sharedGenerator]; });
    // Repeated initialization must not disconnect active HTTP / WebSocket clients.
    @synchronized ([GCDWebsocketServer class]) {
        if (webServer.isRunning) return;
        GCDWebsocketServer *server = [[GCDWebsocketServer alloc] init];
        PMControlInitHandlers(server);
        NSError *error = nil;
        if ([server startWithOptions:@{
            GCDWebServerOption_Port: @(PM_CONTROL_PORT),
            GCDWebServerOption_BindToLocalhost: @YES,
            GCDWebServerOption_AutomaticallySuspendInBackground: @NO
        } error:&error]) {
            webServer = server;
            NSLog(@"[PhoneVideo] USB control listening on loopback :%d", PM_CONTROL_PORT);
        } else {
            webServer = nil;
            NSLog(@"Failed to start web server: %@", error);
        }
    }
}

static void initWebSocket(GCDWebsocketServer *server) {
    [server addWebsocketHandlerForPath:@"/" withProcessBlock:^GCDWebsocketServerHandler *(GCDWebsocketServerConnection *conn) {
        return [PMControlSocketHandler handlerWithConn:conn];
    }];
    addGETHandler(server, @"/", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return PMControlDataResponse(@{@"status": @"success", @"service": @"PhoneVideoTweak", @"version": @"0.2.0"});
    });
}

static void initSettingHandle(GCDWebsocketServer *server) {
    addGETHandler(server, @"/getAllSetting", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return PMControlDataResponse(@{@"status": @"success", @"timeZone": [PMControlDeviceConfigurator currentTimeZone] ?: @"",
            @"lang": [PMControlDeviceConfigurator currentLanguage] ?: @"", @"locale": [PMControlDeviceConfigurator currentLocale] ?: @""});
    });
    addGETHandler(server, @"/currentTimeZone", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return PMControlDataResponse(@{@"status": @"success", @"data": [PMControlDeviceConfigurator currentTimeZone] ?: @""});
    });
    addGETHandler(server, @"/currentLanguage", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return PMControlDataResponse(@{@"status": @"success", @"data": [PMControlDeviceConfigurator currentLanguage] ?: @""});
    });
    addGETHandler(server, @"/currentLocale", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return PMControlDataResponse(@{@"status": @"success", @"data": [PMControlDeviceConfigurator currentLocale] ?: @""});
    });
    addGETHandler(server, @"/setLocale", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *locale = PMControlString(request.query[@"locale"]);
        if (!locale.length) return PMControlMissingParamResponse();
        [PMControlDeviceConfigurator setCurrentLocale:locale];
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/setLanguage", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *lang = PMControlString(request.query[@"lang"]);
        if (!lang.length) return PMControlMissingParamResponse();
        [PMControlDeviceConfigurator setCurrentLanguage:lang];
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/setCurrentTimeZone", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *timeZone = PMControlString(request.query[@"timeZone"]);
        if (!timeZone.length || ![NSTimeZone timeZoneWithName:timeZone]) return PMControlMissingParamResponse();
        [PMControlDeviceConfigurator setCurrentTimeZone:timeZone];
        return PMControlSuccessResponse();
    });
    [server addHandlerForMethod:@"POST" path:@"/setAllSetting" requestClass:[GCDWebServerDataRequest class]
                  processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        NSError *error = nil;
        NSDictionary *body = PMControlJSONDictionary(request.data, &error);
        if (!body) return PMControlJSONFormatErrorResponse();
        // Keep query parameters compatible with existing clients, while supporting a JSON-only request.
        id timeZoneValue = request.query[@"timeZone"] ?: body[@"timeZone"];
        id langValue = request.query[@"lang"] ?: body[@"lang"];
        id localeValue = request.query[@"locale"] ?: body[@"locale"];
        NSString *timeZone = PMControlString(timeZoneValue);
        NSString *lang = PMControlString(langValue);
        NSString *locale = PMControlString(localeValue);
        if ((!timeZoneValue && !langValue && !localeValue) ||
            (timeZoneValue && (!timeZone.length || ![NSTimeZone timeZoneWithName:timeZone])) ||
            (langValue && !lang.length) || (localeValue && !locale.length)) return PMControlMissingParamResponse();
        if (locale) [PMControlDeviceConfigurator setCurrentLocale:locale];
        if (timeZone) [PMControlDeviceConfigurator setCurrentTimeZone:timeZone];
        if (lang) [PMControlDeviceConfigurator setCurrentLanguage:lang];
        return PMControlSuccessResponse();
    }];
}

static void initScreenHandle(GCDWebsocketServer *server) {
    addGETHandler(server, @"/pressPowerBtn", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        dispatch_async(PMControlInputQueue(), ^{ [[PMHIDEventGenerator sharedGenerator] powerPress]; });
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/resetDirtyFrameCount", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        [PMControlScreen resetDirtyFrameCount];
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/screenshot", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        double quality;
        if (!PMControlReadNumber(request.query[@"quality"], 0, 1, &quality)) return PMControlMissingParamResponse();
        NSError *error = nil;
        NSData *image = [PMControlScreen takeScreenshotWithQuality_v2:quality error:&error];
        if (error) return PMControlServerError(error.localizedDescription);
        if (!image.length) {
            GCDWebServerResponse *response = [GCDWebServerResponse response];
            response.statusCode = kGCDWebServerHTTPStatusCode_NoContent;
            [response setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
            return PMControlApplyCORS(response);
        }
        return imageResponse(image, @"image/jpeg");
    });
    addGETHandler(server, @"/screenshot_v2", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        double quality;
        if (!PMControlReadNumber(request.query[@"quality"], 0, 1, &quality)) return PMControlMissingParamResponse();
        return imageResponse([PMControlScreen takeScreenshotWithQuality:quality], @"image/jpeg");
    });
    addGETHandler(server, @"/screenshot_original", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return imageResponse([PMControlScreen takeScreenshot_v2], @"image/png");
    });
    addGETHandler(server, @"/screenshot_original_old", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return imageResponse([PMControlScreen takeScreenshot], @"image/png");
    });
}

static void initInputHandle(GCDWebsocketServer *server) {
    addGETHandler(server, @"/pressHome", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        dispatch_async(PMControlInputQueue(), ^{ [[PMHIDEventGenerator sharedGenerator] menuPress]; });
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/doublePressHome", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        dispatch_async(PMControlInputQueue(), ^{ [[PMHIDEventGenerator sharedGenerator] menuDoublePress]; });
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/hideKeyboard", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.phonemanager.phonevideo.keyboard" object:nil
            userInfo:@{@"task_id": @(2), @"task_content": @(1)} deliverImmediately:YES];
        return PMControlSuccessResponse();
    });
    PMControlAddJSONHandler(server, @"/input", ^GCDWebServerResponse *(NSDictionary *body) {
        NSString *text = PMControlString(body[@"text"]);
        if (!text) return PMControlMissingParamResponse();
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.phonemanager.phonevideo.keyboard" object:nil
            userInfo:@{@"task_id": @(1), @"task_content": text} deliverImmediately:YES];
        return PMControlSuccessResponse();
    });
    PMControlAddJSONHandler(server, @"/keypress", ^GCDWebServerResponse *(NSDictionary *body) {
        NSString *text = PMControlString(body[@"text"]);
        if (!text) return PMControlMissingParamResponse();
        // Enumerate composed characters so surrogate pairs are never split.
        __block NSUInteger index = 0;
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
            usingBlock:^(NSString *character, NSRange range, NSRange enclosingRange, BOOL *stop) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(index++ * 0.1 * NSEC_PER_SEC)), PMControlInputQueue(), ^{
                    [[PMHIDEventGenerator sharedGenerator] keyPress:character];
                });
            }];
        return PMControlSuccessResponse();
    });
    PMControlAddJSONHandler(server, @"/runShell", ^GCDWebServerResponse *(NSDictionary *body) {
        NSString *command = PMControlString(body[@"cmd"]);
        if (!command.length) return PMControlMissingParamResponse();
        NSString *output = PMControlRunCommand(command);
        if (!output) return PMControlServerError(@"Failed to execute command");
        return PMControlDataResponse(@{@"status": @"success", @"data": output});
    });
    addGETHandler(server, @"/del", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *num = PMControlString(request.query[@"num"]);
        if (!PMControlReadInteger(num, 0, INT_MAX, NULL)) return PMControlMissingParamResponse();
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.phonemanager.phonevideo.keyboard" object:nil
            userInfo:@{@"task_id": @(4), @"task_content": num} deliverImmediately:YES];
        return PMControlSuccessResponse();
    });
    addGETHandler(server, @"/moveCursor", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        NSString *num = PMControlString(request.query[@"num"]);
        if (!PMControlReadInteger(num, INT_MIN, INT_MAX, NULL)) return PMControlMissingParamResponse();
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"com.phonemanager.phonevideo.keyboard" object:nil
            userInfo:@{@"task_id": @(3), @"task_content": num} deliverImmediately:YES];
        return PMControlSuccessResponse();
    });
    PMControlAddJSONHandler(server, @"/touch", ^GCDWebServerResponse *(NSDictionary *body) {
        if (!PMControlIsValidTouch(body)) return PMControlMissingParamResponse();
        CGPoint point = CGPointMake([body[@"x"] doubleValue], [body[@"y"] doubleValue]);
        NSString *type = body[@"type"];
        dispatch_async(PMControlInputQueue(), ^{
            PMHIDEventGenerator *generator = [PMHIDEventGenerator sharedGenerator];
            if ([type isEqualToString:@"up"]) [generator liftUp:point];
            else if ([type isEqualToString:@"tap"]) [generator tap:point];
            else [generator touchDown:point];
        });
        return PMControlSuccessResponse();
    });
}

void PMControlInitHandlers(GCDWebsocketServer *server) {
    initScreenHandle(server);
    initWebSocket(server);
    initInputHandle(server);
    initSettingHandle(server);
    addGETHandler(server, @"/deviceInfo", ^GCDWebServerResponse *(GCDWebServerRequest *request) {
        int type;
        if (!PMControlReadInteger(request.query[@"type"], 0, INT_MAX, &type)) return PMControlMissingParamResponse();
        NSError *error = nil;
        NSString *info = PMControlDeviceInfo(type, &error);
        if (error) return PMControlClientError(error.localizedDescription);
        return PMControlDataResponse(@{@"status": @"success", @"data": info ?: @""});
    });
}
