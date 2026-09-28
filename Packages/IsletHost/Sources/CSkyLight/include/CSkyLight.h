#pragma once

#include <CoreFoundation/CoreFoundation.h>

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

CGSConnectionID CGSMainConnectionID(void);
CGSSpaceID CGSSpaceCreate(CGSConnectionID connection, int flags, CFDictionaryRef _Nullable options);
void CGSSpaceSetAbsoluteLevel(CGSConnectionID connection, CGSSpaceID space, int level);
void CGSShowSpaces(CGSConnectionID connection, CFArrayRef _Nonnull spaces);
void CGSAddWindowsToSpaces(CGSConnectionID connection, CFArrayRef _Nonnull windows, CFArrayRef _Nonnull spaces);
void CGSRemoveWindowsFromSpaces(CGSConnectionID connection, CFArrayRef _Nonnull windows, CFArrayRef _Nonnull spaces);
