# MulleObjCOSBaseFoundation Library Documentation for AI
<!-- Keywords: foundation, osbase, filesystem, bundle, runloop, subprocess, defaults -->

## 1. Introduction & Purpose

- `MulleObjCOSBaseFoundation` (a.k.a. **OSBase**) provides the OS-related base
  classes of the MulleFoundation Objective-C stack: file access, bundles,
  process/subprocess control, pipes, path utilities, a run loop, and user
  defaults. It is the abstract, platform-agnostic layer that the concrete
  platform libraries build on.
- It solves the problem that Foundation's OS-facing classes need one public
  Objective-C API while the actual syscalls differ per platform. OSBase declares
  the full API and ships generic (or partial) implementations; the platform
  libraries (`MulleObjCPosixFoundation`, `MulleObjCBSDFoundation`,
  `MulleObjCDarwinFoundation`, `MulleObjCLinuxFoundation`,
  `MulleObjCFreeBSDFoundation`, `MulleObjCWindowsFoundation`) override the
  behavior with Objective-C categories.
- Key features at a high level:
  - Classes: `NSBundle`, `NSDirectoryEnumerator`, `NSFileHandle` (plus
    `NSNullDeviceFileHandle`), `NSFileManager`, `NSPipe`, `NSProcessInfo`,
    `NSRunLoop`, `NSTask`, `NSUserDefaults`.
  - Functions: `NSLog`, page allocation, and the path utility functions
    (`NSHomeDirectory`, `NSTemporaryDirectory`, `NSSearchPathForDirectoriesInDomains`, …).
  - Categories on Foundation classes for file I/O (`NSArray`, `NSData`,
    `NSDictionary`, `NSString`) and C-string conversion (`NSString`).
  - No system-specific headers are used: everything is routed through the
    public API.
- Relationship to other libraries: a foundational component of the
  `MulleFoundation` OS line. It sits at the bottom of the stack
  `Darwin -> BSD -> Posix -> OSBase`; it is itself built on
  `MulleObjCStandardFoundation` and `MulleObjCPlistFoundation`.

## 2. Key Concepts & Design Philosophy

- **Abstract base plus platform categories.** OSBase declares classes and
  methods; platform libraries override behavior by defining categories with the
  same selectors (e.g. `NSFileManager( Posix)`). Code that links a platform
  library gets native behavior without changing its own source.
- **The `( Future)` / `<MulleObjCFuture>` convention.** Many methods are
  declared in categories named `( Future)`, `( OSSpecificFuture)`,
  `( SubclassFuture)`, or `( PrivateFuture)` and conform to the
  `MulleObjCFuture` protocol. This is a mulle-objc marker for "method belongs to
  the API, will be implemented by this class or a subclass/platform". The
  compiler does not require an implementation in the same translation unit. Treat
  these methods as public API, but be aware that a bare OSBase link may leave
  some of them to be supplied by the platform layer.
- **Virtual path utilities.** `NSHomeDirectory`, `NSUserName`,
  `NSTemporaryDirectory`, etc. are plain C functions that dispatch through a
  global function-pointer table, `_NSPathUtilityVectorTable *_NSPathUtilityVectors`
  (declared in `NSPathUtilities+OSBase-Private.h`). A platform installs its
  implementation through a `_NSPathUtilityVectorTable_Loader( <Platform>)`
  category whose `+load` assigns the table. The OSBase defaults are cached after
  first use.
- **Singletons with explicit locking.** `NSFileManager`, `NSProcessInfo`, and
  `NSUserDefaults` conform to `MulleObjCSingleton` and `MulleObjCThreadSafe`;
  access them through `+defaultManager`, `+processInfo`, and
  `+standardUserDefaults`. `NSBundle` is also `MulleObjCThreadSafe` and lazily
  caches resources under its own lock.
- **`NSRunLoop` is per-thread.** It is a `select(2)`-based wrapper intended to
  exist once per thread and never be shared across threads.
- **`NSTask` delegates to `mulle-spawn`.** Process creation, pipes, and status
  vocabulary come from `mulle-spawn` (arriving via `mulle-core`/the runtime);
  OSBase only builds argv/envp/descriptors and interprets the result.
- **Filesystem attributes use global string keys.** `NSFileSize`,
  `NSFileModificationDate`, `NSFileType`, `NSFilePosixPermissions`, and the
  `NSFileType*` value constants are global `NSString *` objects.
- **Path separators are macros.** `NSFilePathComponentSeparator` expands to `@"/"`
  and `NSFilePathExtensionSeparator` to `@"."`.

## 3. Core API & Data Structures

All signatures below are copied verbatim from the installed headers. The
umbrella header is `#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>`,
which imports `NSBundle.h`, `NSDirectoryEnumerator.h`, `NSFileHandle.h`,
`NSFileManager.h`, `NSPipe.h`, `NSProcessInfo.h`, `NSRunLoop.h`, `NSTask.h`,
`NSUserDefaults.h`, `NSPageAllocation.h`, `NSPathUtilities.h`, and the category
headers `NSArray+OSBase.h`, `NSCalendarDate+NSUserDefaults.h`, `NSData+OSBase.h`,
`NSData+MulleMemoryMapping.h`, `NSDictionary+OSBase.h`, `NSFileHandle+NSRunLoop.h`,
`NSObject+NSRunLoop.h`, `NSString+CString.h`, `NSString+OSBase.h`,
`NSTimer+NSRunLoop.h`, `NSTask+System.h`.

### 3.1. `NSBundle.h`

#### `@interface NSBundle : NSObject <MulleObjCThreadSafe>`
Represents the running executable, a framework, or a loadable bundle. Public
ivars: `_path`, `_lock`, `_handle`, `_startAddress`, `_endAddress`,
`_languageCode`, `_localizedStringTables` (treat as read-only/private).

- **Lifecycle / lookup:**
  - `+ (NSBundle *) mainBundle;` — bundle of the main executable.
  - `+ (NSArray *) allFrameworks;` / `+ (NSArray *) allBundles;` — registered bundles.
  - `+ (NSBundle *) bundleWithPath:(NSString *) path;` — bundle at a path (nil if none).
  - `+ (NSBundle *) bundleWithIdentifier:(NSString *) identifier;`
  - `- (instancetype) initWithPath:(NSString *) fullPath;`
- **Identity / state:**
  - `- (NSString *) bundleIdentifier;`
  - `- (Class) principalClass;`
  - `- (NSString *) resourcePath;`
  - `- (NSString *) executablePath;`
  - `- (NSString *) bundlePath;`
  - `- (BOOL) isLoaded;`
- **Resource lookup:**
  - `- (NSString *) pathForResource:(NSString *) name ofType:(NSString *) extension;`
  - `- (NSString *) pathForResource:(NSString *) name ofType:(NSString *) extension inDirectory:(NSString *) subpath;`
  - `- (NSArray *) pathsForResourcesOfType:(NSString *) extension inDirectory:(NSString *) subpath;`
- **Contents / localization:**
  - `- (Class) classNamed:(NSString *) className;`
  - `- (NSString *) localizedStringForKey:(NSString *) key value:(NSString *) comment table:(NSString *) tableName;`
  - `- (id) objectForInfoDictionaryKey:(NSString *) key;`
  - `- (NSDictionary *) infoDictionary;`
  - `- (NSString *) developmentLocalization;`
  - `- (NSArray *) localizations;` — stub, always empty.
  - `- (NSArray *) preferredLocalizations;` — stub.
  - `- (NSDictionary *) localizedInfoDictionary;` — stub.
- **`@interface NSBundle ( Future) < MulleObjCFuture>`:**
  - `+ (BOOL) isBundleFilesystemExtension:(NSString *) extension;` — default `NO`.
  - `+ (NSString *) pathForResource:(NSString *) name ofType:(NSString *) extension inDirectory:(NSString *) bundlePath;`
  - `+ (NSArray *) pathsForResourcesOfType:(NSString *) extension inDirectory:(NSString *) bundlePath;`
  - `- (NSString *) pathForAuxiliaryExecutable:(NSString *) executableName;`
  - `- (NSArray *) pathsForResourcesOfType:(NSString *) extension inDirectory:(NSString *) subpath;`
  - `- (NSString *) privateFrameworksPath;`
  - `- (NSString *) sharedFrameworksPath;`
  - `- (NSString *) sharedSupportPath;`
  - `- (NSString *) builtInPlugInsPath;`
- **`@interface NSBundle ( OSSpecificFuture) < MulleObjCFuture>`:**
  - `- (BOOL) loadBundle;` / `- (BOOL) unloadBundle;` (unload returns `NO` if not loaded).
  - `+ (NSBundle *) bundleForClass:(Class) aClass;`
- **`@interface NSBundle ( MulleSymbolLookup)`:**
  - `- (void *) mulleLookupSymbolUTF8String:(char *) name;`
  - `- (void *) mulleLookupSymbol:(NSString *) name;`
- **Globals / macros:**
  - `NSString *NSLoadedClasses;`, `NSString *NSBundleDidLoadNotification;`
  - function pointers `NSBundleGetOrRegisterBundleWithPath`, `NSBundleDeregisterBundleWithPath`.
  - `NSString *MulleObjCBundleLocalizedStringFromTable(NSBundle *, NSString *tableName, NSString *key, NSString *value);`
  - `NSLocalizedString`, `NSLocalizedStringFromTable`, `NSLocalizedStringFromTableInBundle`, `NSLocalizedStringWithDefaultValue` convenience macros.

### 3.2. `NSDirectoryEnumerator.h`

#### `@interface NSDirectoryEnumerator : NSEnumerator <NSEnumerator, NSFastEnumeration>`
A stateful, deep (recursive) directory enumerator returned by
`-[NSFileManager enumeratorAtPath:]`. It yields paths relative to the root,
returns directories as well as files, skips `.`, `..` and `._*` resource forks,
and does not descend into symbolic links.

- `- (NSDictionary *) directoryAttributes;` — attributes of the root directory.
- `- (NSDictionary *) fileAttributes;` — attributes of the most recent entry.
- `- (NSUInteger) count;` — total objects; iterates a fresh enumerator internally.
- `- (NSUInteger) level;` — depth of the current entry; objects directly inside
  the enumerated root report level 1 (the root directory itself is level 0).
- `- (void) skipDescendants;` / `- (void) skipDescendents;` — do not descend into
  the most recently returned directory (both spellings provided).
- `enum _MulleObjCIsDirectoryState` — `_MulleObjCIsMaybeADirectory`,
  `_MulleObjCIsNotADirectory`, `_MulleObjCIsADirectory`.
- `@interface NSDirectoryEnumerator( Future) < MulleObjCFuture>`:
  - `- (instancetype) initWithFileManager:(NSFileManager *) manager rootPath:(NSString *) root inheritedPath:(NSString *) inherited;`
  - `- (NSString *) _nextEntry:(enum _MulleObjCIsDirectoryState *) is_dir;`
  - `- (void) _close;`

### 3.3. `NSFileHandle.h`

- `NSString *NSFileHandleOperationException;`
- `enum NSFileHandleStateBit { NSFileHandleStateEOF = 1, NSFileHandleStatePipe = 2, NSFileHandleStateAgain = 4 };`

#### `@interface NSFileHandle : NSObject <MulleObjCInputStream, MulleObjCOutputStream, MulleObjCThreadSafe>`
Abstract file descriptor wrapper. A handle should be used by one thread at a
time (the underlying descriptor is a separate concern), even though the object
is marked thread-safe.

- **Creation:**
  - `+ (instancetype) fileHandleForReadingAtPath:(NSString *) path;`
  - `+ (instancetype) fileHandleForWritingAtPath:(NSString *) path;`
  - `+ (instancetype) fileHandleForUpdatingAtPath:(NSString *) path;`
  - `+ (instancetype) fileHandleWithNullDevice;`
  - `- (instancetype) initWithFileDescriptor:(int) fd;`
- **Reading:** `- (NSData *) availableData;`, `- (NSData *) readDataToEndOfFile;`,
  `- (NSData *) readDataOfLength:(NSUInteger) length;`
- **Positioning:** `- (unsigned long long) offsetInFile;`,
  `- (unsigned long long) seekToEndOfFile;`,
  `- (void) seekToFileOffset:(unsigned long long) offset;`,
  `- (void) truncateFileAtOffset:(unsigned long long) offset;`
- **Writing:** `- (void) writeData:(NSData *) data;`
- **Descriptor:** `- (NSInteger) fileDescriptor;`, plus pipe helpers
  `- (NSInteger) _fileDescriptorForReading;` and
  `- (NSInteger) _fileDescriptorForWriting;`.
- **Lifecycle/state:** `- (void) closeFile;` (does `-finalize`),
  `- (void) mulleWriteBytes:(void *) bytes length:(NSUInteger) len;` (`len == -1`
  means `strlen`), `- (void) mulleAddToStateBits:(NSUInteger) bits;`,
  `- (NSUInteger) mulleGetStateBits;`.
- `enum _MulleObjCOpenMode` (`_MulleObjCOpenReadOnly`, `_MulleObjCOpenWriteOnly`,
  `_MulleObjCOpenReadWrite`) and `enum _MulleObjCSeekMode`
  (`_MulleObjCSeekCur`, `_MulleObjCSeekSet`, `_MulleObjCSeekEnd`) are internal
  subclass protocol values.
- `@interface NSFileHandle( SubclassFuture) < MulleObjCFuture>` (backend surface
  for platform subclasses): `+ fileHandleWithStandardInput/StandardOutput/StandardError`,
  `- (instancetype) initWithFileDescriptor:(int) fd closeOnDealloc:(BOOL) flag;`,
  `- (void) closeFile;`, `- (void) synchronizeFile;`,
  `+ (instancetype) _fileHandleWithPath:(NSString *) path mode:(enum _MulleObjCOpenMode) mode;`,
  `- (size_t) _readBytes:(void *) buf length:(size_t) len;`,
  `- (size_t) _writeBytes:(void *) buf length:(size_t) len;`,
  `- (unsigned long long) _seek:(unsigned long long) offset mode:(enum _MulleObjCSeekMode) mode;`,
  `- (void) _truncate:(unsigned long long) offset;`.

#### `@interface NSNullDeviceFileHandle : NSFileHandle`
Handle for the null device; creates and instantly returns EOF.

### 3.4. `NSFileManager.h`

- `@protocol NSFileManagerHandler` with `- (void) fileManager:(NSFileManager *) fileManager willProcessPath:(NSString *) path;`
- `@protocol NSFileManagerDelegate` with the optional `shouldRemoveItemAtPath:`,
  `shouldMoveItemAtPath:toPath:`, `shouldCopyItemAtPath:toPath:`,
  `shouldProceedAfterError:removingItemAtPath:`, `shouldProceedAfterError:copyingItemAtPath:toPath:`,
  `shouldLinkItemAtPath:toPath:`, `shouldProceedAfterError:linkingItemAtPath:toPath:`,
  and `shouldProceedAfterError:movingItemAtPath:toPath:` callbacks.

#### `@interface NSFileManager : NSObject <MulleObjCSingleton, MulleObjCThreadSafe>`
- `@property(assign) id delegate;`
- `+ (NSFileManager *) defaultManager;`
- `- (NSDirectoryEnumerator *) enumeratorAtPath:(NSString *) path;`
- `- (BOOL) createFileAtPath:(NSString *) path contents:(NSData *) contents attributes:(NSDictionary *)attributes;`
- `- (NSData *) contentsAtPath:(NSString *) path;`
- `- (BOOL) contentsEqualAtPath:(NSString *) path1 andPath:(NSString *) path2;`
- `- (BOOL) removeFileAtPath:(NSString *) path handler:(id) handler;`
- `- (BOOL) createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes;`
- `- (BOOL) createSymbolicLinkAtPath:(NSString *) path pathContent:(NSString *) otherpath;`
- `@interface NSFileManager( Future) < MulleObjCFuture>`:
  - Encoding/representation: `- (char *) fileSystemRepresentationWithPath:(NSString *) path;`,
    `- (NSString *) stringWithFileSystemRepresentation:(char *) s length:(NSUInteger) len;`
  - Directory/test queries: `- (BOOL) changeCurrentDirectoryPath:(NSString *) path;`,
    `- (NSString *) currentDirectoryPath;`, `- (BOOL) fileExistsAtPath:(NSString *) path;`,
    `- (BOOL) fileExistsAtPath:(NSString *) path isDirectory:(BOOL *) isDirectory;`,
    `- (BOOL) isDeletableFileAtPath:(NSString *) path;`, `- (BOOL) isExecutableFileAtPath:(NSString *) path;`,
    `- (BOOL) isReadableFileAtPath:(NSString *) path;`, `- (BOOL) isWritableFileAtPath:(NSString *) path;`
  - Creation: `- (BOOL) createSymbolicLinkAtPath:(NSString *) path withDestinationPath:(NSString *) otherpath error:(NSError **) error;`,
    `- (BOOL) createDirectoryAtPath:(NSString *) path withIntermediateDirectories:(BOOL) createIntermediates attributes:(NSDictionary *) attributes error:(NSError **) error;`
  - Links/contents: `- (NSString *) pathContentOfSymbolicLinkAtPath:(NSString *) path;`,
    `- (NSArray *) directoryContentsAtPath:(NSString *) path;`
  - Attributes: `- (NSDictionary *) fileSystemAttributesAtPath:(NSString *) path;`,
    `- (NSDictionary *) fileAttributesAtPath:(NSString *) path traverseLink:(BOOL) flag;`,
    `- (NSDictionary *) attributesOfItemAtPath:(NSString *) path error:(NSError **) error;`,
    `- (NSDictionary *) attributesOfFileSystemForPath:(NSString *) path error:(NSError **) error;`,
    `- (BOOL) setAttributes:(NSDictionary *) attributes ofItemAtPath:(NSString *) path error:(NSError **) error;`
  - Removal/move/copy: `- (int) _createDirectoryAtPath:(NSString *) path attributes:(NSDictionary *) attributes;`,
    `- (BOOL) _removeFileAtPath:(NSString *) path;`, `- (BOOL) _removeEmptyDirectoryItemAtPath:(NSString *) path;`,
    `- (BOOL) removeItemAtPath:(NSString *) path error:(NSError **) error;`,
    `- (BOOL) movePath:(NSString *) src toPath:(NSString *) dest handler:(id) handler;`,
    `- (BOOL) copyPath:(NSString *) src toPath:(NSString *) dest handler:(id) handler;`,
    `- (BOOL) moveItemAtPath:(NSString *) srcPath toPath:(NSString *) dstPath error:(NSError **) error;`,
    `- (BOOL) copyItemAtPath:(NSString *) fromPath toPath:(NSString *) toPath error:(NSError **) error;`
- **Global attribute keys:** `NSFileType`, `NSFileSize`, `NSFileModificationDate`,
  `NSFileReferenceCount`, `NSFileDeviceIdentifier`, `NSFileOwnerAccountName`,
  `NSFileGroupOwnerAccountName`, `NSFilePosixPermissions`, `NSFileSystemNumber`,
  `NSFileSystemFileNumber`, `NSFileSystemFreeNodes`, `NSFileSystemFreeSize`,
  `NSFileSystemNodes`, `NSFileSystemSize`, `NSFileExtensionHidden`,
  `NSFileHFSCreatorCode`, `NSFileHFSTypeCode`, `NSFileImmutable`,
  `NSFileAppendOnly`, `NSFileCreationDate`, `NSFileOwnerAccountID`,
  `NSFileGroupOwnerAccountID`, `NSFileBusy`.
- **Global `NSFileType` values:** `NSFileTypeDirectory`, `NSFileTypePipe`,
  `NSFileTypeRegular`, `NSFileTypeSymbolicLink`, `NSFileTypeSocket`,
  `NSFileTypeCharacterSpecial`, `NSFileTypeBlockSpecial`, `NSFileTypeUnknown`.
- **Macros:** `NSFilePathComponentSeparator` → `@"/"`,
  `NSFilePathExtensionSeparator` → `@"."`.

### 3.5. `NSPipe.h`

#### `@interface NSPipe : NSObject <MulleObjCImmutableProtocols>`
- `+ (instancetype) pipe;`
- `- (NSFileHandle *) fileHandleForReading;`
- `- (NSFileHandle *) fileHandleForWriting;`
- `- (NSInteger) _fileDescriptorForReading;` / `- (NSInteger) _fileDescriptorForWriting;`
- `@interface NSPipe( Future) < MulleObjCFuture>`: `- (instancetype) init;`

### 3.6. `NSProcessInfo.h`

- OS constants: `NSWindowsNTOperatingSystem`,
  `NSWindows95OperatingSystem`, `NSSolarisOperatingSystem`,
  `NSHPUXOperatingSystem`, `NSDarwinOperatingSystem`, `NSSunOSOperatingSystem`,
  `NSOSF1OperatingSystem`, `NSLinuxOperatingSystem`, `NSBSDOperatingSystem`.

#### `@interface NSProcessInfo : NSObject <MulleObjCSingleton, MulleObjCThreadSafe>`
- `+ (NSProcessInfo *) processInfo;`
- `@interface NSProcessInfo( Future) < MulleObjCFuture>`:
  - `- (NSString *) hostName;`
  - `- (NSUInteger) operatingSystem;`
  - `- (NSString *) operatingSystemName;`
  - `- (NSString *) operatingSystemVersionString;`
  - `- (NSArray *) arguments;`
  - `- (NSDictionary *) environment;`
  - `- (NSString *) _executablePath;`
  - `- (NSString *) processName;` / `- (void) setProcessName:(NSString *) name;`
  - `- (NSString *) globallyUniqueString;`
  - `- (NSInteger) processIdentifier;`
  - `- (void) mulleSetEnvironmentValue:(NSString *) value forKey:(NSString *) key;` (calls `setenv` and updates the cached `_environment`).

### 3.7. `NSRunLoop.h`

- `typedef NSString *NSRunLoopMode;`
- `struct MulleRunLoopMessage` (`order`, `generation`, `target`, `argument`, `selector`),
  `struct MulleRunLoopMessageArray`, `struct MulleRunLoopMode` — internal, not for public use.
- `NSString *NSDefaultRunLoopMode;`

#### `@interface NSRunLoop : NSObject`
A per-thread `select(2)` wrapper; the object must not be shared between threads.
- `+ (NSRunLoop *) currentRunLoop;`
- `+ (NSRunLoop *) mainRunLoop;`
- `+ (NSRunLoop *) mulleCurrentRunLoop;` — returns `nil` when the thread is tearing down instead of creating a spurious loop.
- `- (NSRunLoopMode) currentMode;`
- `- (void) acceptInputForMode:(NSRunLoopMode) modeName beforeDate:(NSDate *) limitDate;`
- `- (void) run;`
- `- (void) runUntilDate:(NSDate *) limitDate;`
- `- (BOOL) runMode:(NSRunLoopMode) modeName beforeDate:(NSDate *) limitDate;`
- `- (NSDate *) limitDateForMode:(NSRunLoopMode) modeName;`
- `- (void) performSelector:(SEL) aSelector target:(id) target argument:(id) arg order:(NSUInteger) order modes:(NSArray *) modes;`
- `- (void) cancelPerformSelector:(SEL) aSelector target:(id) target argument:(id) arg;`
- `- (void) cancelPerformSelectorsWithTarget:(id) target;`
- `- (void) addTimer:(NSTimer *) timer forMode:(NSRunLoopMode) modeName;`
- `enum MulleRunLoopInputState { MulleRunLoopTimeout = 0, MulleRunLoopInputReceived = 1, MulleRunLoopNoTimersOrInputLeft = 2 };`
- `@interface NSRunLoop( Future) < MulleObjCFuture>`:
  `- (enum MulleRunLoopInputState) _acceptInputForRunLoopMode:(struct MulleRunLoopMode *) mode beforeDate:(NSDate *) limitDate;`

### 3.8. `NSTask.h`

- `enum { NSTaskTerminationReasonExit = 1, NSTaskTerminationReasonUncaughtSignal = 2 };`
- `typedef NSInteger NSTaskTerminationReason;`

#### `@interface NSTask : NSObject`
Runs a child process. Properties are configured with setters and read back with
the matching getters; launch/control lives in the `( Future)` category.
- `+ (NSTask *) launchedTaskWithLaunchPath:(NSString *) path arguments:(NSArray *) arguments;`
- `- (void) setArguments:(NSArray *) arguments;`
- `- (void) setCurrentDirectoryPath:(NSString *) path;`
- `- (void) setEnvironment:(NSDictionary *) environmentDictionary;`
- `- (void) setLaunchPath:(NSString *) path;`
- `- (void) setStandardError:(id) file;` / `- (void) setStandardInput:(id) file;` / `- (void) setStandardOutput:(id) file;`
- `- (NSInteger) processIdentifier;`
- `- (NSInteger) terminationStatus;`
- `- (id) standardError;` / `- (id) standardInput;` / `- (id) standardOutput;`
- `- (NSArray *) arguments;` / `- (NSString *) launchPath;` / `- (NSString *) currentDirectoryPath;` / `- (NSDictionary *) environment;`
- `@interface NSTask( Future) < MulleObjCFuture>`:
  - `- (BOOL) isRunning;`
  - `- (void) interrupt;`
  - `- (void) launch;`
  - `- (BOOL) resume;`
  - `- (BOOL) suspend;`
  - `- (void) terminate;`
  - `- (void) waitUntilExit;`
  - `- (NSTaskTerminationReason) terminationReason;`

### 3.9. `NSUserDefaults.h`

#### `@interface NSUserDefaults : NSObject <MulleObjCSingleton, MulleObjCThreadSafe>`
Domain/search-list based preferences. The application domain is loaded once at
`-init`; `registerDefaults:` adds a lower-priority `NSRegistrationDomain`.
- `+ (NSUserDefaults *) standardUserDefaults;`
- `- (instancetype) init;`
- `- (id) objectForKey:(id) key;`
- `- (void) setObject:(id) value forKey:(id <NSObject, MulleObjCImmutableCopying>) key;`
- `- (void) removeObjectForKey:(id) key;`
- `- (void) registerDefaults:(NSDictionary *) registrationDictionary;`
- `- (NSDictionary *) dictionaryRepresentation;`
- `- (BOOL) synchronize;`
- `@interface NSUserDefaults( Future) < MulleObjCFuture>`: `+ (void) resetStandardUserDefaults;`
- `@interface NSUserDefaults( Persistent)`: `- (NSString *) _defaultsIdentifier;`,
  `- (BOOL) _loadPersistentDomain:(NSMutableDictionary *) domain;`,
  `- (BOOL) _savePersistentDomain:(NSDictionary *) domain;` — base class keeps
  everything in memory and returns `NO`; platform categories implement the
  on-disk storage.
- `@interface NSUserDefaults ( Conveniences)`:
  - `- (BOOL) boolForKey:(NSString *) key;`, `- (double) doubleForKey:(NSString *) key;`,
    `- (float) floatForKey:(NSString *) key;`, `- (NSArray *) arrayForKey:(NSString *) key;`,
    `- (NSArray *) stringArrayForKey:(NSString *) key;`, `- (NSData *) dataForKey:(NSString *) key;`,
    `- (NSDictionary *) dictionaryForKey:(NSString *) key;`, `- (NSInteger) integerForKey:(NSString *) key;`,
    `- (NSString *) stringForKey:(NSString *) key;`
  - `- (void) setInteger:(NSInteger)value forKey:(NSString *) key;`,
    `- (void) setFloat:(float) value forKey:(NSString *) key;`,
    `- (void) setDouble:(double) value forKey:(NSString *) key;`,
    `- (void) setBool:(BOOL) value forKey:(NSString *) key;`
- **Globals:** `NSString *NSGlobalDomain;`, `NSString *NSArgumentDomain;`,
  `NSString *NSRegistrationDomain;`.

### 3.10. `NSPathUtilities.h`

- `typedef NSUInteger NSSearchPathDomainMask;` with `NSUserDomainMask = 1`,
  `NSLocalDomainMask = 2`, `NSNetworkDomainMask = 4`, `NSSystemDomainMask = 8`,
  `NSAllDomainsMask = ~0`.
- `typedef NSUInteger NSSearchPathDirectory;` with `NSApplicationDirectory = 1`,
  `NSAdminApplicationDirectory`, `NSApplicationSupportDirectory`,
  `NSCachesDirectory`, `NSDesktopDirectory`, `NSDeveloperApplicationDirectory`,
  `NSDeveloperDirectory`, `NSDocumentationDirectory`, `NSDocumentDirectory`,
  `NSLibraryDirectory`, `NSMoviesDirectory`, `NSMusicDirectory`,
  `NSPicturesDirectory`, `NSSharedPublicDirectory`, `NSTrashDirectory`,
  `NSUserDirectory`, `NSAllApplicationsDirectory`, `NSAllLibrariesDirectory`.
- Functions (all dispatch through the platform vector table):
  - `NSString *NSFullUserName( void);`
  - `NSString *NSHomeDirectory( void);`
  - `NSString *NSHomeDirectoryForUser( NSString *userName);`
  - `NSString *NSOpenStepRootDirectory( void);`
  - `NSArray *NSSearchPathForDirectoriesInDomains( NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde);`
  - `NSString *NSTemporaryDirectory( void);`
  - `NSString *NSUserName( void);`

### 3.11. `NSPageAllocation.h`

- `void *NSAllocateMemoryPages( NSUInteger size);`
- `void NSDeallocateMemoryPages( void *ptr, NSUInteger size);`
- `NSUInteger NSPageSize( void);`
- `NSUInteger NSLogPageSize( void);`
- `static inline NSUInteger NSRoundDownToMultipleOfPageSize(NSUInteger bytes);`
- `static inline NSUInteger NSRoundUpToMultipleOfPageSize( NSUInteger bytes);`

### 3.12. `NSLog.h`

- `void NSLog( NSString *format, ...);`
- `void NSLogv( NSString *format, va_list args);`
- `void NSLogArguments( NSString *format, mulle_vararg_list args);` — mulle addition.

### 3.13. `NSData+MulleMemoryMapping.h`

- `@interface NSData( MulleMemoryMapping)`:
  `- (instancetype) initWithContentsOfMappedFile:(NSString *) path;`
  `+ (instancetype) dataWithContentsOfMappedFile:(NSString *) path;`
  Backed by the private `_MulleObjCMemoryMappedData` class (mmap of the whole file).
- `@interface NSMutableData( MulleMemoryMapping)`:
  `- (instancetype) initWithContentsOfMappedFile:(NSString *) path;` — falls back
  to a normal read into mutable data.

### 3.14. Category headers

#### `NSArray+OSBase.h` — `@interface NSArray( OSBase)`
- `+ (instancetype) arrayWithContentsOfFile:(NSString *) path;`
- `- (instancetype) initWithContentsOfFile:(NSString *) path;`
- `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag;`

#### `NSData+OSBase.h`
- `enum { NSDataReadingMappedIfSafe = 1UL << 0, NSDataReadingUncached = 1UL << 1, NSDataReadingMappedAlways = 1UL << 3 };`
  `typedef NSUInteger NSDataReadingOptions;`
- `@interface NSData( OSBase)`: `+ (instancetype) dataWithContentsOfFile:(NSString *) path;`,
  `+ (instancetype) dataWithContentsOfFile:(NSString *) path options:(NSDataReadingOptions) options error:(NSError **) error;`
- `@interface NSData( OSBaseFuture) < MulleObjCFuture>`:
  `- (instancetype) initWithContentsOfFile:(NSString *) path;`,
  `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag;`,
  `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag error:(NSError **) error;`

#### `NSDictionary+OSBase.h` — `@interface NSDictionary( OSBase)`
- `+ (instancetype) dictionaryWithContentsOfFile:(NSString *) path;`
- `- (instancetype) initWithContentsOfFile:(NSString *) path;`
- `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag;`

#### `NSCalendarDate+NSUserDefaults.h`
- `@interface NSCalendarDate( NSUserDefaults)`:
  `+ (instancetype) _calendarDateWithNaturalLanguageString:(NSString *) string locale:(id) locale referenceCalendarDate:(NSCalendarDate *) today;`
- `@interface NSDate( NSUserDefaults)`:
  `+ (instancetype) dateWithNaturalLanguageString:(NSString *) string locale:(id) locale;`,
  `+ (instancetype) dateWithNaturalLanguageString:(NSString *) string;`

#### `NSString+CString.h`
- `NSStringEncoding mulle_cstring_encoding_for_codeset( char *codeset);` — maps a
  codeset name to an encoding; unknown codesets answer `NSUTF8StringEncoding`.
- `@interface NSString( CString)`:
  `+ (instancetype) stringWithCString:(char *) s;`,
  `+ (instancetype) stringWithCString:(char *) s length:(NSUInteger) length;`,
  `- (instancetype) initWithCString:(char *) s length:(NSUInteger) len;`,
  `- (instancetype) initWithCString:(char *) s;`,
  `- (instancetype) initWithCStringNoCopy:(char *) s length:(NSUInteger) length freeWhenDone:(BOOL) flag;`,
  `- (void) getCString:(char *) bytes;`,
  `- (void) getCString:(char *) bytes maxLength:(NSUInteger) maxLength;`,
  `- (void) getCString:(char *) bytes maxLength:(NSUInteger) maxLength encoding:(NSStringEncoding) encoding;`,
  `- (void) getCString:(char *) bytes maxLength:(NSUInteger) maxLength range:(NSRange) aRange remainingRange:(NSRangePointer) leftoverRange;`
- `@interface NSString( CStringFuture) < MulleObjCFuture>`:
  `- (NSUInteger) cStringLength;`,
  `+ (NSStringEncoding) defaultCStringEncoding;`,
  `- (NSStringEncoding) _cStringEncoding;`,
  `- (char *) cString;`,
  `- (NSUInteger) cStringLength;`

#### `NSString+OSBase.h`
- `@interface NSString( OSBase)`:
  `+ (instancetype) pathWithComponents:(NSArray *) components;`,
  `- (BOOL) isAbsolutePath;`,
  `- (NSString *) lastPathComponent;`,
  `- (NSString *) pathExtension;`,
  `- (NSString *) stringByAppendingPathComponent:(NSString *) component;`,
  `- (NSString *) stringByAppendingPathExtension:(NSString *) extension;`,
  `- (NSString *) stringByDeletingLastPathComponent;`,
  `- (NSString *) stringByDeletingPathExtension;`,
  `- (NSString *) stringByExpandingTildeInPath;`,
  `- (NSString *) stringByResolvingSymlinksInPath;`,
  `- (NSString *) stringByStandardizingPath;`,
  `- (NSArray *) pathComponents;`,
  `- (NSString *) initWithPathComponents:(NSArray *) components;`,
  `- (char *) fileSystemRepresentation;`,
  `- (BOOL) getFileSystemRepresentation:(char *) buf maxLength:(NSUInteger) max;`,
  `+ (instancetype) stringWithContentsOfFile:(NSString *) path;`,
  `- (NSUInteger) completePathIntoString:(NSString **) outputName caseSensitive:(BOOL) flag matchesIntoArray:(NSArray **) outputArray filterTypes:(NSArray *) filterTypes;`
  - mulle additions: `- (instancetype) mulleInitWithLossyContentsOfFile:(NSString *) path;`,
    `+ (instancetype) mulleStringWithLossyContentsOfFile:(NSString *) path;`,
    `- (NSString *) mulleStringBySimplifyingPath;` (removes `/./` and `/../`),
    `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag;`,
    `- (BOOL) writeToFile:(NSString *) path atomically:(BOOL) flag encoding:(NSStringEncoding) encoding error:(NSError **) error;`
- `@interface NSString( OSBaseFuture) < MulleObjCFuture>`:
  `- (instancetype) initWithContentsOfFile:(NSString *) path;`
- `@interface NSString( FileSystemString)`:
  `- (NSString *) mulleUnixFileSystemString;` / `- (NSString *) mulleWindowsFileSystemString;`

#### `NSFileHandle+NSRunLoop.h` — `@interface NSFileHandle( NSRunLoop)`
- `- (void) readInBackgroundAndNotify;`
- `- (void) readInBackgroundAndNotifyForModes:(NSArray *) modes;`
- Notification name globals: `NSFileHandleConnectionAcceptedNotification`,
  `NSFileHandleDataAvailableNotification`,
  `NSFileHandleReadToEndOfFileCompletionNotification`,
  `NSFileHandleReadCompletionNotification`, `NSFileHandleNotificationDataItem`,
  `NSFileHandleNotificationFileHandleItem`.

#### `NSObject+NSRunLoop.h` — `@interface NSObject( NSRunLoop)`
- `- (void) performSelector:(SEL) aSelector withObject:(id) anArgument afterDelay:(NSTimeInterval) delay inModes:(NSArray *) modes;`
- `- (void) performSelector:(SEL) aSelector withObject:(id) anArgument afterDelay:(NSTimeInterval) delay;`
- `+ (void) cancelPreviousPerformRequestsWithTarget:(id) aTarget selector:(SEL) aSelector object:(id) anArgument;`
- `+ (void) cancelPreviousPerformRequestsWithTarget:(id) aTarget;`

#### `NSTimer+NSRunLoop.h` — `@interface NSTimer( NSRunLoop)`
- `+ (NSTimer *) scheduledTimerWithTimeInterval:(NSTimeInterval) timeInterval target:(id) target selector:(SEL) selector userInfo:(id) userInfo repeats:(BOOL) repeats;`
- `+ (NSTimer *) scheduledTimerWithTimeInterval:(NSTimeInterval) timeInterval invocation:(NSInvocation *) invocation repeats:(BOOL) repeats;`
- `- (void) invalidate;`

#### `NSTask+System.h` — convenience subprocess helpers
- `typedef NS_ENUM( int, NSTaskSystemOptions) { NSTaskSystemSendStandardInput = 0x1, NSTaskSystemReceiveStandardOutput = 0x2, NSTaskSystemReceiveStandardError = 0x4 };`
- `#define NSTaskSystemOptionsDefault (NSTaskSystemSendStandardInput|NSTaskSystemReceiveStandardOutput|NSTaskSystemReceiveStandardError)`
- Result-dictionary keys: `NSTaskExceptionKey` (`@"exception"`),
  `NSTaskTerminationStatusKey` (`@"terminationStatus"`),
  `NSTaskStandardOutputDataKey` (`@"standardOutputData"`),
  `NSTaskStandardOutputStringKey` (`@"standardOutputString"`),
  `NSTaskStandardErrorDataKey` (`@"standardErrorData"`),
  `NSTaskStandardErrorStringKey` (`@"standardErrorString"`).
- `@interface NSTask( System)` (data variants return data keys; string variants
  return data **and** string keys; on an exception the result carries
  `NSTaskExceptionKey` and termination status `-1`):
  - `+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv environment:(NSDictionary *) environment workingDirectory:(NSString *) dir standardInputData:(NSData *) inputData options:(NSTaskSystemOptions) options;`
  - `+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv workingDirectory:(NSString *) dir standardInputData:(NSData *) inputData options:(NSTaskSystemOptions) options;`
  - `+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv environment:(NSDictionary *) environment standardInputData:(NSData *) data;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv environment:(NSDictionary *) environment workingDirectory:(NSString *) dir standardInputString:(NSString *) stdinString options:(NSTaskSystemOptions) options;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv workingDirectory:(NSString *) dir standardInputString:(NSString *) stdinString options:(NSTaskSystemOptions) options;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv environment:(NSDictionary *) environment standardInputString:(NSString *) stdinString;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv standardInputString:(NSString *) stdinString;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv environment:(NSDictionary *) environment;`
  - `+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv;`
  - `+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s workingDirectory:(NSString *) dir environment:(NSDictionary *) environment standardInputString:(NSString *) stdinString;`
  - `+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s environment:(NSDictionary *) environment standardInputString:(NSString *) stdinString;`
  - `+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s standardInputString:(NSString *) stdinString;`
  - `+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s environment:(NSString *) environment;`
  - `+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s;`
- `NSTask+System.m` also defines a semi-private `NSFileManager( System)` with
  `- (NSString *) mulleFindExecutable:(NSString *) name inPATH:(NSString *) envPATH;`
  (no public header). It is used by the system-call machinery; treat it as internal.

### 3.15. Internal / private surface (do not use from application code)

- `NSPathUtilities+OSBase-Private.h`: `struct _NSPathUtilityVectorTable` and
  `_NSPathUtilityVectorTable *_NSPathUtilityVectors`, plus
  `@interface _NSPathUtilityVectorTable_Loader`.
- `NSBundle-Private.h`: `struct _MulleObjCSharedLibrary`, `+_bundleDictionary`,
  `+_allBundlesWhichAreFrameworks:`, `+_bundleForHandle:`, `_executablePath`,
  `_resourcePath`, `mulleContainsAddress:`, `+_allSharedLibraries`, etc.
- `NSFileManager-Private.h`: `enum _MulleObjCFilenameType` and
  `-_isValidDirectoryContentsFilenameAsCString:`.
- `NSTask-Private.h`: `mulleNSTaskStatusFromResult()`, `mulleNSTaskEnvironmentStrings()`,
  `@interface NSTask( Private)` with `-mulleCheckIfRunning`.
- `NSArray+OSBase-Private.h`: `+_newWithArgc:argv:`;
  `NSDictionary+OSBase-Private.h`: `+_newWithEnvironment:`;
  `NSDate+OSBase-Private.h`: `-_printDate:...`; `NSPageAllocation-Private.h`.
- `NSCondition( NSString)` and `NSConditionLock( NSString)`: override
  `-description` to append `LOCKED`/`UNLOCKED`.

## 4. Performance Characteristics

- **`NSBundle`**: path/identity accessors are O(1) string work plus zero or more
  `stat`-backed existence checks. `infoDictionary` and localized string tables
  are lazily parsed and cached; localization access is serialized by `_lock`.
  `+allBundles` / `+allFrameworks` walk the registered-bundle table (O(n)).
- **`NSFileManager`**: single operations are one or a few syscalls; attribute and
  existence checks are `stat` calls. `-enumeratorAtPath:` is O(total entries),
  recursively opening directories.
- **`NSDirectoryEnumerator`**: `-nextObject` is O(1) amortized per entry; `-count`
  is O(n) because it materializes a fresh enumerator. `-level` is O(depth) for
  the root and delegates to the child for nested entries.
- **`NSFileHandle`**: blocking `read`/`write`; no buffering beyond what the OS
  provides. Marked `MulleObjCThreadSafe` but concurrent use of one handle is not
  meaningful. `mulleWriteBytes:length:` with `len == -1` scans for `'\0'`.
- **`NSRunLoop`**: each iteration is O(f + t) over registered file descriptors and
  timers, bounded by the `select(2)` timeout. Messages are sorted by
  `order`/`generation`. Not thread-safe; use one per thread.
- **`NSTask`**: `-launch`/`-waitUntilExit` typically fork/exec/`waitpid`; the
  System-call helpers buffer the whole stdout/stderr in memory and may spawn one
  writer thread to feed stdin while reading outputs, avoiding pipe deadlock.
- **`NSUserDefaults`**: `-objectForKey:` is O(d) in the number of domains in the
  search list (typically 1–2); all domain access is serialized by `_lock` and the
  dictionaries are configured thread-safe. `-synchronize` delegates to the
  platform `_savePersistentDomain:`.
- **Path functions**: results are cached in a global `NSPathCache` after first
  call; individual lookups are O(1).
- **Thread safety**: `NSBundle`, `NSFileManager`, `NSProcessInfo`, `NSFileHandle`,
  and `NSUserDefaults` are `MulleObjCThreadSafe`. `NSRunLoop` is explicitly not
  shared across threads. `NSTask` is not documented as thread-safe; configure a
  task from one thread.

## 5. AI Usage Recommendations & Patterns

- **Best practices:**
  - Import the umbrella once: `#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>`.
  - Use the singletons: `[NSFileManager defaultManager]`,
    `[NSProcessInfo processInfo]`, `[NSUserDefaults standardUserDefaults]`,
    `[NSRunLoop currentRunLoop]`.
  - Prefer the `-mulleStringSystemCall...` helpers over hand-rolling
    `NSTask` + `NSPipe` unless you need streaming I/O.
  - Use `NSData`/`NSString`/`NSArray`/`NSDictionary` `+...WithContentsOfFile:`
    categories for simple file I/O; use `NSData( MulleMemoryMapping)` for large
    read-only files.
  - Treat methods declared in `( Future)` categories as usable public API.
- **Common pitfalls:**
  - Do not call underscore-prefixed methods (`-_removeFileAtPath:`,
    `-_executablePath`, `-_readBytes:length:`, `-_acceptInputForRunLoopMode:...`,
    `+_newWithArgc:argv:`, …) or touch `_NSPathUtilityVectors`; they are the
    platform/subclass override surface.
  - Do not instantiate `NSRunLoop` and share it across threads; use
    `+currentRunLoop`. Use `+mulleCurrentRunLoop` in teardown code where you must
    not create a loop.
  - Do not assume `localizations` / `preferredLocalizations` /
    `localizedInfoDictionary` return data — they are stubs in this base layer.
  - The base `NSUserDefaults( Persistent)` does not persist to disk; only the
    platform category does. `-synchronize` returns `NO` on the base class.
  - Path utility C functions require a platform loader to have installed the
    vector table (they assert on `_NSPathUtilityVectors`). Link a platform
    library for real functionality.
  - `NSFileManager` file-system representability can fail; check the `char *`
    result for `NULL` and inspect `errno`.
  - System-call helpers flatten exceptions: check `NSTaskExceptionKey` and a
    termination status of `-1` before trusting output.
- **Idiomatic usage (mulle-objc way):** 3-space indent, Allman braces, aligned
  declarations, C89 variable rules, one variable per line, `return( expr);`, no
  dot-syntax in Objective-C. Objective-C examples must not use `alloc`/`init` or
  `retain`/`release` outside `-init`/`-dealloc`.

## 6. Integration Examples

### Example 1: Recursively enumerating a directory

```objc
#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>
#include <stdio.h>

void   list_directory( NSString *path)
{
   NSFileManager         *manager;
   NSDirectoryEnumerator *enumerator;
   NSString              *entry;
   NSUInteger            level;
   NSUInteger            i;

   manager    = [NSFileManager defaultManager];
   enumerator = [manager enumeratorAtPath:path];

   while( (entry = [enumerator nextObject]))
   {
      level = [enumerator level];
      for( i = 0; i < level; i++)
         putchar( ' ');

      printf( "%s\n", [entry UTF8String]);
   }
}
```

### Example 2: Running a command and capturing its output

```objc
#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>
#include <stdio.h>

void   run_command( void)
{
   NSDictionary   *result;
   NSNumber       *status;
   NSString       *output;
   NSException    *exception;

   result = [NSTask mulleStringSystemCallWithCommandString:@"uname -a"];

   exception = [result objectForKey:NSTaskExceptionKey];
   if( exception)
   {
      printf( "failed: %s\n", [[exception reason] UTF8String]);
      return;
   }

   status = [result objectForKey:NSTaskTerminationStatusKey];
   output = [result objectForKey:NSTaskStandardOutputStringKey];

   printf( "status: %ld\n", (long) [status integerValue]);
   printf( "%s\n", [output UTF8String]);
}
```

### Example 3: Reading and writing a plist-style file

```objc
#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>
#include <stdio.h>

void   read_and_write( NSString *path)
{
   NSDictionary *dictionary;
   NSArray      *keys;

   dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
   if( ! dictionary)
   {
      printf( "could not read %s\n", [path UTF8String]);
      return;
   }

   keys = [dictionary allKeys];
   printf( "%lu keys\n", (unsigned long) [keys count]);

   if( ! [dictionary writeToFile:@"/tmp/copy.plist" atomically:YES])
      printf( "write failed\n");
}
```

### Example 4: Storing user-defaults values

```objc
#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>
#include <stdio.h>

void   store_preferences( void)
{
   NSUserDefaults *defaults;
   NSInteger      count;

   defaults = [NSUserDefaults standardUserDefaults];

   [defaults setInteger:42
                 forKey:@"answer"];
   [defaults setBool:YES
              forKey:@"enabled"];

   count = [defaults integerForKey:@"answer"];
   printf( "answer: %ld, enabled: %d\n",
           (long) count,
           [defaults boolForKey:@"enabled"]);

   [defaults synchronize];
}
```

## 7. Dependencies

Direct `mulle-sde` library dependencies (from
`.mulle/etc/sourcetree/config` / `clib.json`):

- `MulleObjCStandardFoundation` — the standard Objective-C foundation classes
  this library extends.
- `MulleObjCPlistFoundation` — plist parsing, pulled in via
  `MulleObjCDeps( MulleObjCOSBaseFoundation)`.
- `mulle-objc-tools` — build/tooling dependency (marked
  `no-all-load,no-bequeath,no-cmake-inherit,no-header,no-import,no-link`).

Position in the hierarchy: the bottom OS layer, built on the standard
foundation, with platform libraries layered on top
(`Posix -> OSBase`, then `BSD -> Posix`, `Darwin -> BSD/Posix`, and the Linux,
FreeBSD, and Windows equivalents).
