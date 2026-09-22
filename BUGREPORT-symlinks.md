# BUGREPORT — `-stringByResolvingSymlinksInPath` loses the directory of a relative symlink target

**Component**: `MulleObjCOSBaseFoundation` → `src/Categories/NSString+OSBase.m`
**Affects**: every platform (the method is OS independent)
**Severity**: medium — silent; it makes `NSBundle` refuse a perfectly good library and hands callers a relative path where they asked for an absolute one
**Found**: loading `libsqlite3.so.0` with `NSBundle` in `MulleFoundation-demo/sqlite-to-json`
**Status**: fixed — regression test in `MulleObjCOSFoundation/test/Paths/resolving-symlinks.m`

---

## 1. Summary

`-stringByResolvingSymlinksInPath` walks the path one component at a time and,
for each prefix, follows the symlink chain:

```objc
best = s;                                                   // the absolute prefix so far
while( expanded = [manager pathContentOfSymbolicLinkAtPath:best])
   best = expanded;                                         // <-- the raw link target
if( best == s)
   continue;
[s setString:best];
```

`-pathContentOfSymbolicLinkAtPath:` returns the target **exactly as stored in
the link**, which on most systems is *relative* to the link's own directory.
The loop assigns that raw target back into `best`, so the next probe is made
against a path relative to the process's working directory, and the final
`s` is the bare target — the directory is gone.

So:

```objc
[@"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0" stringByResolvingSymlinksInPath]
   -> @"libsqlite3.so.0.8.6"        // relative!  want /usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6
```

The name promises an absolute path back for an absolute path in. It returns a
relative one whenever the first symlink has a relative target.

---

## 2. Why it went unnoticed: most libraries in a "regular file" install

A link with an **absolute** target works, because the raw target is already a
full path. A plain file works, because there is no link. Only a **relative**
target breaks, and only when the caller does not happen to run from the link's
directory.

Measured on Debian (the three libraries the demo tried, all in the same
directory):

| path | `readlink` | `-stringByResolvingSymlinksInPath` | loadable by `NSBundle` |
|---|---|---|---|
| `/usr/lib/x86_64-linux-gnu/libm.so.6` | *(regular file)* | unchanged | yes |
| `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0` | `libsqlite3.so.0.8.6` | `libsqlite3.so.0.8.6` | **no** |
| `/usr/lib/x86_64-linux-gnu/libz.so.1` | `libz.so.1.3.1` | `libz.so.1.3.1` | **no** |

`libm.so.6` is a regular file on this install, which is exactly why the
framework's own `NSBundle` test (`MulleObjCOSFoundation/test/NSBundle/load-so.m`)
passes: it loads `libm.so.6`, and there is no link to mis-resolve.

---

## 3. Blast radius

**`-stringByStandardizingPath`** calls this first
(`NSString+OSBase.m:179`), so it is wrong for the same inputs.

**`NSBundle`** standardizes and then resolves before it even checks existence
(`MulleObjCOSBaseFoundation/src/NSBundle.m:213`):

```objc
fullPath = [fullPath stringByStandardizingPath];
fullPath = [fullPath stringByResolvingSymlinksInPath];

flag = [manager fileExistsAtPath:fullPath isDirectory:&isDir];
if( ! flag)
{
   [self release];
   return( nil);
}
```

`fileExistsAtPath:@"libsqlite3.so.0.8.6"` is asked relative to the current
directory and answers NO, so `-initWithPath:` returns nil and `dlopen` is never
reached. The user sees "could not open the library" for a library that is
present, readable and `dlopen`-able:

```objc
[[NSBundle alloc] initWithPath:@"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0"]      // nil
[[NSBundle alloc] initWithPath:@"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6"]  // works
```

**Consumers** that call `-stringByResolvingSymlinksInPath` directly to canonicalize
a path get a relative path back and will resolve it against their working
directory. Anything that keys a cache by the result, or compares two resolved
paths for equality, silently disagrees depending on where it was started.

---

## 4. The fix

Resolve a relative target against the directory of the link before following it.

```objc
      best = s;
      while( (expanded = [manager pathContentOfSymbolicLinkAtPath:best]))
      {
         //
         // a link target is frequently relative to the directory of the link,
         // not to the current directory: resolve it before following on
         //
         if( ! [expanded isAbsolutePath])
            expanded = [[best stringByDeletingLastPathComponent] stringByAppendingPathComponent:expanded];
         best = expanded;
      }
      if( best == s)
         continue;
      [s setString:best];
```

`realpath(3)` is the C spelling of the same contract, and is what the demo uses
as a workaround (see §6).

Two things to keep an eye on while fixing:

* the `best == s` test is a pointer comparison that means "no link here". It
  stays correct because a followed link makes `best` a different object.
* a chain of relative links (`a -> b`, `b -> c`, both in the same directory) now
  works, because each hop is resolved against the directory of the hop before
  it, which is `best` at that moment.

---

## 5. Regression test

The system libraries are not a portable fixture. Create the link in a temp
directory with a relative target and assert the directory survives:

```c
   // /tmp/…/link -> target   (relative, the failing case)
   assert( symlink( "target", "/tmp/…/link") == 0);
   resolved = [@"/tmp/…/link" stringByResolvingSymlinksInPath];

   assert( [resolved isAbsolutePath]);
   assert( [resolved isEqualToString:@"/tmp/…/target"]);   // not @"target"
   assert( [[NSFileManager defaultManager] fileExistsAtPath:resolved]);
```

Add an absolute-target case in the same directory to pin that it still works,
and an `NSBundle`-level case (the way the demo hit it): a symlink to a real
shared object must load through `-initWithPath:`.

---

## 6. Workaround

`MulleFoundation-demo/sqlite-to-json` calls `realpath(3)` on the library path
before handing it to `NSBundle`:

```objc
static NSString   *canonicalPath( NSString *path)
{
   char   buffer[ PATH_MAX + 1];
   char   *resolved;

   resolved = realpath( [path UTF8String], buffer);
   if( ! resolved)
      return( path);
   return( [NSString stringWithUTF8String:resolved]);
}
```

It should be removed once the framework method is correct.

---

## 7. Copies that carry it

| file | note |
|---|---|
| `MulleObjCOSBaseFoundation/src/Categories/NSString+OSBase.m` | canonical source |
| `MulleFoundation/src/MulleObjCOSBaseFoundation/NSString+OSBase.m` | the amalgamation, **read-only**, regenerated at release |
| `MulleObjCOSFoundation.borked/src/OSBase/Categories/NSString+OSBase.m` | dead layout |
| `pre-split/MulleObjCOSFoundation/src/OSBase/Categories/NSString+OSBase.m` | dead layout |

A project that depends on the umbrella `MulleFoundation` links the
**amalgamation**, so fixing only the source repo does not reach it.

---

## 8. Status of the fix

Applied 2026-09-21 to `MulleObjCOSBaseFoundation/src/Categories/NSString+OSBase.m`,
exactly as §4: a relative link target is resolved against the directory of the
link before it is followed.

Verified by rebuilding the framework and the demo:

| call | before | after |
|---|---|---|
| `[@"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0" stringByResolvingSymlinksInPath]` | `libsqlite3.so.0.8.6` | `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6` |
| `NSBundle -initWithPath:` on that symlink | `nil` | loads |
| `NSBundle -initWithPath:` on `/usr/lib/x86_64-linux-gnu/libz.so.1` (relative symlink) | `nil` | loads |

`MulleFoundation-demo/sqlite-to-json` no longer calls `realpath(3)` — it hands
`libsqlite3.so.0` to `NSBundle` directly and reads the table. The amalgamation
copy in `MulleFoundation/src/MulleObjCOSBaseFoundation/NSString+OSBase.m` was
regenerated by the build, so a consumer of the umbrella gets the fix too.

The regression test from §5 was added as
`MulleObjCOSFoundation/test/Paths/resolving-symlinks.m`: a relative link, an
absolute link, a chain of relative links, and a plain file, each asserting that
the result is absolute, equals the target and exists (skipped on Windows, where
the fixture's symlinks are not available).

---

## 9. One-sentence summary

`-stringByResolvingSymlinksInPath` replaces the absolute path it has built so far
with the raw target of a relative symlink instead of resolving that target
against the link's directory, so it returns a relative path for an absolute
input, and `NSBundle` — which resolves before it checks existence — refuses
`libsqlite3.so.0`, `libz.so.1` and every other library installed as a relative
symlink.
