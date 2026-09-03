TARGET := iphone:clang:16.5:14.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AssistiveGlass

AssistiveGlass_FILES := AssistiveGlass.xm
AssistiveGlass_CFLAGS := -fobjc-arc
AssistiveGlass_FRAMEWORKS := UIKit QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
