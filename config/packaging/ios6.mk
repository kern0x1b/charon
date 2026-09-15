IOS6_SDK_VERSION ?= 13.7
IOS6_DEPLOYMENT_TARGET ?= 6.0
IOS6_DEVICE_ENV ?= $(CURDIR)/../device.env

export THEOS ?= $(HOME)/theos

export TARGET := iphone:clang:$(IOS6_SDK_VERSION):$(IOS6_DEPLOYMENT_TARGET)
export ARCHS := armv7

export THEOS_PACKAGE_SCHEME :=

export ADDITIONAL_CFLAGS := -fno-modules -Wno-error=deprecated-module-dot-map

ifneq ($(wildcard $(IOS6_DEVICE_ENV)),)
export THEOS_DEVICE_IP ?= $(shell sed -n 's/^DEVICE_HOST=//p' $(IOS6_DEVICE_ENV))
export THEOS_DEVICE_PORT ?= $(shell sed -n 's/^DEVICE_PORT=//p' $(IOS6_DEVICE_ENV))
endif
