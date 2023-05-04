TARGET := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = com.apple.WebKit.Networking

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WebKitNetworkingDumper

WebKitNetworkingDumper_FILES = Tweak.x
WebKitNetworkingDumper_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk