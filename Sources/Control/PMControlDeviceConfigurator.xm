#import "PMControlDeviceConfigurator.h"
#import <objc/runtime.h>
#import "pac_helper.h"

static ALCity *(*PSCityForTimeZone)(CFTimeZoneRef timeZone);


@implementation PMControlDeviceConfigurator

+ (void)loadVPNPreferencesBundle
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load];
    });
}

+ (void)loadInternationalSettingsBundle
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/InternationalSettings.bundle"] load];
    });
}

+ (void)loadGeneralSettingsUIFramework
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/Settings/GeneralSettingsUI.framework"] load];
    });
}


+ (void)turnOnVPN
{
    @autoreleasepool {
        [PMControlDeviceConfigurator loadVPNPreferencesBundle];
        VPNConnectionStore *store = [objc_getClass("VPNConnectionStore") sharedInstance];
        unsigned long long grade = [store currentOnlyConnectionGrade];
        VPNConnection *vpn = [store currentConnectionWithGrade:grade];
        [vpn connect];
    }
}

+ (void)turnOffVPN
{
    @autoreleasepool {
        [PMControlDeviceConfigurator loadVPNPreferencesBundle];
        VPNConnectionStore *store = [objc_getClass("VPNConnectionStore") sharedInstance];
        unsigned long long grade = [store currentOnlyConnectionGrade];
        VPNConnection *vpn = [store currentConnectionWithGrade:grade];
        [vpn disconnect];
    }
}

+ (BOOL)isVPNEnabled
{
    @autoreleasepool {
        [PMControlDeviceConfigurator loadVPNPreferencesBundle];
        VPNConnectionStore *store = [objc_getClass("VPNConnectionStore") sharedInstance];
        unsigned long long grade = [store currentOnlyConnectionGrade];
        VPNConnection *vpn = [store currentConnectionWithGrade:grade];
        return [vpn connected];
    }
}

+ (void)takeScreenshot
{
/*    @autoreleasepool {
        [(SpringBoard *)[%c(SpringBoard) sharedApplication] takeScreenshot];
    }
*/
}

+ (NSString *)currentLanguage
{
    return [[NSLocale preferredLanguages] firstObject];
}

+ (NSString *)currentLocale
{
    return [[NSLocale currentLocale] localeIdentifier];
}
+ (NSString *)currentTimeZone
{
    return [[NSTimeZone systemTimeZone] name];
}

+ (void)setCurrentLanguage:(NSString *)language
{

    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [PMControlDeviceConfigurator loadInternationalSettingsBundle];
                NSString *languageCode = language;

                // NSString *languageCode = InternationalSettingsExtractLanguageCode(language);
                [%c(InternationalSettingsController) setPreferredLanguages:@[languageCode]];
                if ([%c(InternationalSettingsController) respondsToSelector:@selector(setCurrentLanguage:)])
                {
                    [%c(InternationalSettingsController) setCurrentLanguage:languageCode];
                }
                else if ([%c(InternationalSettingsController) respondsToSelector:@selector(setLanguage:)])
                {
                    [%c(InternationalSettingsController) setLanguage:languageCode];
                }
            }
        });
    }
}

+ (InternationalSettingsController *)sharedInternationalSettingsController
{
    static InternationalSettingsController *isCtrl = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self loadInternationalSettingsBundle];
        isCtrl = [[objc_getClass("InternationalSettingsController") alloc] init];
    });
    return isCtrl;
}


+ (void)setCurrentLocale:(NSString *)locale
{
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [[PMControlDeviceConfigurator sharedInternationalSettingsController] setLocaleOnly:locale];
                [%c(InternationalSettingsController) syncPreferencesAndPostNotificationForLanguageChange];
            }
        });
    }
}

+ (PSGDateTimeController *)sharedPSGDateTimeController
{
    static PSGDateTimeController *dtCtrl = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self loadGeneralSettingsUIFramework];
        dtCtrl = [[objc_getClass("PSGDateTimeController") alloc] init];
    });
    return dtCtrl;
}

+ (void)setCurrentTimeZone:(NSString *)timeZoneName
{
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [PMControlDeviceConfigurator loadGeneralSettingsUIFramework];

                MSImageRef PreferencesBinary = MSGetImageByName("/System/Library/PrivateFrameworks/Preferences.framework/Preferences");
                if (PreferencesBinary)
                {
                    PSCityForTimeZone = (ALCity *(*)(CFTimeZoneRef))make_sym_callable(MSFindSymbol(PreferencesBinary, "_PSCityForTimeZone"));
                }

                if (PSCityForTimeZone)
                {
                    CFTimeZoneRef timeZone = CFTimeZoneCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)timeZoneName, true);

                    if (timeZone)
                    {
                        ALCity *cityObject = PSCityForTimeZone(timeZone);
                        if (cityObject)
                        {
                            PSGDateTimeController *dateTimeCtrl = [PMControlDeviceConfigurator sharedPSGDateTimeController];
                            [dateTimeCtrl reloadTimezone];

                            PSSpecifier *autoTimeZoneSpecifierObject = nil;
                            for (PSSpecifier *specifierObject in [dateTimeCtrl specifiers]) {
                                if ([[specifierObject identifier] isEqualToString:@"SET_AUTOMATICALLY"])
                                {
                                    autoTimeZoneSpecifierObject = specifierObject;
                                    break;
                                }
                            }

                            if (autoTimeZoneSpecifierObject)
                            {
                                [autoTimeZoneSpecifierObject performSetterWithValue:@(NO)];
                            }

                            PSSpecifier *timeZoneSpecifierObject = [dateTimeCtrl timeZoneSpecifier];
                            if (timeZoneSpecifierObject)
                            {
                                [timeZoneSpecifierObject performSetterWithValue:cityObject];
                            }

                            // this is where changes actually happen
                            [objc_getClass("PSTimeZoneController") setTimeZone:timeZoneName];
                        }

                        CFRelease(timeZone);
                    }
                }
            }
        });
    }
}

@end
