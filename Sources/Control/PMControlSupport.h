#import <Foundation/Foundation.h>
#import <GCDWebServers/GCDWebServer.h>
#import <GCDWebServers/GCDWebServerDataRequest.h>
#import <GCDWebServers/GCDWebServerDataResponse.h>
#import <GCDWebServers/GCDWebServerErrorResponse.h>

#ifdef __cplusplus
extern "C" {
#endif

// Reject a non-object JSON root before a handler accesses dictionary keys.
NSDictionary *PMControlJSONDictionary(NSData *data, NSError **error);
NSString *PMControlString(id value);
BOOL PMControlReadNumber(id value, double minimum, double maximum, double *result);
BOOL PMControlReadInteger(id value, int minimum, int maximum, int *result);
BOOL PMControlIsStringArray(id value);
BOOL PMControlIsValidTouch(NSDictionary *body);
NSString *PMControlShellQuote(NSString *value);
dispatch_queue_t PMControlInputQueue(void);
void PMControlOnMainThread(dispatch_block_t block);

GCDWebServerResponse *PMControlApplyCORS(GCDWebServerResponse *response);
GCDWebServerDataResponse *PMControlDataResponse(NSDictionary *jsonData);
GCDWebServerDataResponse *PMControlSuccessResponse(void);
GCDWebServerErrorResponse *PMControlMissingParamResponse(void);
GCDWebServerErrorResponse *PMControlJSONFormatErrorResponse(void);
GCDWebServerErrorResponse *PMControlClientError(NSString *message);
GCDWebServerErrorResponse *PMControlServerError(NSString *message);

typedef GCDWebServerResponse *(^PMControlJSONHandler)(NSDictionary *body);
void PMControlAddJSONHandler(GCDWebServer *server, NSString *path, PMControlJSONHandler handler);

#ifdef __cplusplus
}
#endif
