#import "PMControlSupport.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <float.h>

NSDictionary *PMControlJSONDictionary(NSData *data, NSError **error) {
    if (error) *error = nil;
    id body = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    if (![body isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"com.phonemanager.phonevideo.webserver" code:400
                                    userInfo:@{NSLocalizedDescriptionKey: @"Expected a JSON object"}];
        }
        return nil;
    }
    return body;
}

NSString *PMControlString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

BOOL PMControlReadNumber(id value, double minimum, double maximum, double *result) {
    double number;
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
        number = [value doubleValue];
    } else if ([value isKindOfClass:[NSString class]] && [value length]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        if (![scanner scanDouble:&number] || !scanner.isAtEnd) return NO;
    } else {
        return NO;
    }
    if (!isfinite(number) || number < minimum || number > maximum) return NO;
    if (result) *result = number;
    return YES;
}

BOOL PMControlReadInteger(id value, int minimum, int maximum, int *result) {
    double number;
    if (!PMControlReadNumber(value, minimum, maximum, &number) || trunc(number) != number) return NO;
    if (result) *result = (int)number;
    return YES;
}

BOOL PMControlIsStringArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return NO;
    for (id item in value) {
        if (!PMControlString(item).length) return NO;
    }
    return YES;
}

BOOL PMControlIsValidTouch(NSDictionary *body) {
    if (![body isKindOfClass:[NSDictionary class]]) return NO;
    NSString *type = PMControlString(body[@"type"]);
    return PMControlReadNumber(body[@"x"], 0, FLT_MAX, NULL) &&
           PMControlReadNumber(body[@"y"], 0, FLT_MAX, NULL) &&
           ([type isEqualToString:@"down"] || [type isEqualToString:@"move"] ||
            [type isEqualToString:@"up"] || [type isEqualToString:@"tap"]);
}

NSString *PMControlShellQuote(NSString *value) {
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

dispatch_queue_t PMControlInputQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.phonemanager.phonevideo.input", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void PMControlOnMainThread(dispatch_block_t block) {
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

GCDWebServerResponse *PMControlApplyCORS(GCDWebServerResponse *response) {
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    [response setValue:@"GET, POST, OPTIONS" forAdditionalHeader:@"Access-Control-Allow-Methods"];
    return response;
}

GCDWebServerDataResponse *PMControlDataResponse(NSDictionary *jsonData) {
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:jsonData];
    PMControlApplyCORS(response);
    return response;
}

GCDWebServerDataResponse *PMControlSuccessResponse(void) {
    return PMControlDataResponse(@{@"status": @"success"});
}

GCDWebServerErrorResponse *PMControlClientError(NSString *message) {
    GCDWebServerErrorResponse *response = [GCDWebServerErrorResponse
        responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"%@", message];
    PMControlApplyCORS(response);
    return response;
}

GCDWebServerErrorResponse *PMControlServerError(NSString *message) {
    GCDWebServerErrorResponse *response = [GCDWebServerErrorResponse
        responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError message:@"%@", message];
    PMControlApplyCORS(response);
    return response;
}

GCDWebServerErrorResponse *PMControlMissingParamResponse(void) {
    return PMControlClientError(@"Missing or invalid parameter");
}

GCDWebServerErrorResponse *PMControlJSONFormatErrorResponse(void) {
    return PMControlClientError(@"Invalid JSON: expected an object");
}

void PMControlAddJSONHandler(GCDWebServer *server, NSString *path, PMControlJSONHandler handler) {
    [server addHandlerForMethod:@"POST" path:path requestClass:[GCDWebServerDataRequest class]
                  processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        NSError *error = nil;
        NSDictionary *body = PMControlJSONDictionary(request.data, &error);
        return body ? handler(body) : PMControlJSONFormatErrorResponse();
    }];
}
