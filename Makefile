DEBUG = 0
FINALPACKAGE = 1
TYPE ?= 1
ARCHS ?= arm64 arm64e
TARGET = iphone:clang:16.5:15.0

ifeq ($(TYPE),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(TYPE),2)
THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(TYPE),0)
TARGET = iphone:clang:16.5:14.0
else
$(error TYPE must be 0 (rootful), 1 (rootless), or 2 (RootHide))
endif

INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = PhoneVideo PhoneVideoKeyboard
PhoneVideo_FILES = Tweak.xm Sources/PMVideoServer.m Sources/PMVideoStream.m
PHONEVIDEO_CONTROL_FILES = $(wildcard Sources/Control/*.xm) $(wildcard Sources/Control/*.m) $(wildcard Sources/Control/hid/*.m)
PhoneVideo_FILES += $(PHONEVIDEO_CONTROL_FILES)
PhoneVideo_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -ISources/Control/headers -ISources/Control/hid -Wno-module-import-in-extern-c
# Retain the original MKS warning policy only for the copied control sources.
$(foreach source,$(PHONEVIDEO_CONTROL_FILES),$(eval $(source)_CFLAGS += -Wno-error))
PhoneVideo_FRAMEWORKS = UIKit Foundation CoreGraphics CoreImage CoreMedia CoreVideo VideoToolbox QuartzCore IOKit
PhoneVideo_PRIVATE_FRAMEWORKS = IOSurface
PhoneVideo_LDFLAGS = -LSources/Control/libs -lGCDWebServers

PhoneVideoKeyboard_FILES = Sources/Keyboard/PMKeyboard.m
PhoneVideoKeyboard_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
PhoneVideoKeyboard_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk

TOOL_NAME = phonevideo-roothelp
phonevideo-roothelp_FILES = RootHelper/main.m RootHelper/TSUtil.m
phonevideo-roothelp_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c
phonevideo-roothelp_FRAMEWORKS = Foundation
phonevideo-roothelp_CODESIGN_FLAGS = -SRootHelper/entitlements.plist
phonevideo-roothelp_INSTALL_PATH = /usr/local/bin
include $(THEOS_MAKE_PATH)/tool.mk
