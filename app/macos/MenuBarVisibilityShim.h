//
//  HBNativeVisibilityShim.h
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//
//  From Hidden Bar (https://github.com/dwarvesf/hidden, MIT License, see
//  LICENSES/MIT-HiddenBar.txt). Modified for Cats in Menubar: renamed, and
//  always built in (this app is never sandboxed).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The only boundary to macOS 27's private MenuBarClientCore framework.
// Objective-C so that exceptions a changed private API raises can be caught
// instead of crashing the app.

// Whether the framework, both classes and every selector used below resolve.
BOOL CIMVisibilityIsAvailable(void);

// Keeps only the given system items and apps visible; macOS hides every other
// status item and reflows the bar. The completion runs on the main queue with
// the assertion to hold (hiding lasts until it is invalidated or this process
// exits) or with an error.
void CIMVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                           NSArray<NSString *> *allowedBundleIdentifiers,
                           void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void CIMVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
