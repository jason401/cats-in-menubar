//
//  HBNativeVisibilityShim.m
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//
//  From Hidden Bar (https://github.com/dwarvesf/hidden, MIT License, see
//  LICENSES/MIT-HiddenBar.txt). Modified for Cats in Menubar: renamed, and
//  always built in (this app is never sandboxed).
//

#import "MenuBarVisibilityShim.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const CIMVisibilityErrorDomain = @"CIMVisibility";

static NSError *CIMVisibilityError(NSString *reason) {
    return [NSError errorWithDomain:CIMVisibilityErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// MenuBarClientCore is the private framework behind macOS 27's assessment
// (exam lockdown) mode, which can restrict the menu bar to an allow-list. It is
// resolved at runtime so a macOS release that changes or removes it turns into
// "unavailable" rather than a launch failure. Names are spelled out on purpose.
static NSString *const CIMFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const CIMConfigurationClassName = @"MBAssessmentModeConfiguration";
static NSString *const CIMAssertionClassName = @"MBAssessmentModeAssertion";

static SEL CIMConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL CIMActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL CIMInvalidate(void) { return @selector(invalidate); }

BOOL CIMVisibilityIsAvailable(void) {
    if (!dlopen(CIMFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(CIMConfigurationClassName);
    Class assertion = NSClassFromString(CIMAssertionClassName);
    return configuration && assertion
        && [configuration instancesRespondToSelector:CIMConfigurationInit()]
        && [assertion instancesRespondToSelector:CIMActivate()]
        && [assertion instancesRespondToSelector:CIMInvalidate()];
}

void CIMVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                           NSArray<NSString *> *allowedBundleIdentifiers,
                           void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!CIMVisibilityIsAvailable()) {
        finish(nil, CIMVisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both lists must be NSArrays: the framework indexes into them, and an
        // NSSet raises -objectAtIndex: unrecognized.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(CIMConfigurationClassName) alloc], CIMConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(CIMAssertionClassName) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, CIMVisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, CIMActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, CIMVisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void CIMVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:CIMInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, CIMInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"MenuBarVisibility: invalidate raised %@: %@", exception.name, exception.reason);
    }
}
