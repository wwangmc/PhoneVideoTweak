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
TWEAK_NAME = PhoneVideo
PhoneVideo_FILES = Tweak.xm Sources/PMVideoServer.m Sources/PMVideoStream.m
PhoneVideo_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
PhoneVideo_FRAMEWORKS = UIKit Foundation CoreGraphics CoreImage CoreMedia CoreVideo VideoToolbox IOSurface QuartzCore
include $(THEOS_MAKE_PATH)/tweak.mk
