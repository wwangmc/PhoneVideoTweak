
#ifndef DeviceConfigurator_h
#define DeviceConfigurator_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface PMControlDeviceConfigurator : NSObject

/* Airplane */
// - (void)turnOnAirplane;
// - (void)turnOffAirplane;
// - (BOOL)isAirplaneEnabled;

/* VPN */
+ (void)turnOnVPN;
+ (void)turnOffVPN;
+ (BOOL)isVPNEnabled;

/* Utils */
/*
+ (void)takeScreenshot;
+ (void)shutdown;
+ (void)reboot;
+ (void)suspend;
*/

/* Language & Region */
+ (NSString *)currentLanguage;
+ (void)setCurrentLanguage:(NSString *)language;  // async
+ (NSString *)currentLocale;
+ (void)setCurrentLocale:(NSString *)locale;  // async
+ (NSString *)currentTimeZone;
+ (void)setCurrentTimeZone:(NSString *)timeZoneName;



@end

@interface PSTimeZoneController : UITableViewController
+ (void)setTimeZone:(NSString *)arg1;
@end

@interface InternationalSettingsController : NSObject
+ (void)setPreferredLanguages:(NSArray <NSString *> *)arg1;
+ (void)setLanguage:(NSString *)arg1;
+ (void)setCurrentLanguage:(NSString *)arg1;
- (void)setLocaleOnly:(NSString *)arg1;
+ (void)syncPreferencesAndPostNotificationForLanguageChange;
@end

@interface VPNConnection : NSObject
- (BOOL)connected;
- (BOOL)disconnected;
- (void)connect;
- (void)disconnect;
- (void)setEnabled:(BOOL)arg1;
- (BOOL)enabled;
@end

@interface VPNConnectionStore : NSObject
+ (instancetype)sharedInstance;
- (VPNConnection *)currentConnectionWithGrade:(unsigned long long)arg1;
- (unsigned long long)currentOnlyConnectionGrade;
@end

@interface PSSpecifier : NSObject
- (NSString *)identifier;
- (void)performSetterWithValue:(id)value;
@end


@interface ALCity : NSObject
@end

@interface PSGDateTimeController : NSObject
- (NSArray <PSSpecifier *> *)specifiers;
- (void)reloadTimezone;
- (PSSpecifier *)timeZoneSpecifier;
- (void)setUseAutomaticTime:(NSNumber *)arg1 specifier:(id)arg2;
- (void)setTimeZoneValue:(ALCity *)arg1 specifier:(id)arg2;
@end

#endif  /* DeviceConfigurator_h */
