# BUGREPORT — `-pathComponents` is not Cocoa's, and `+pathWithComponents:` hides it

**Component**: `MulleObjCOSBaseFoundation` → `src/Categories/NSString+OSBase.m`
**Affects**: every platform (the method is OS independent)
**Severity**: medium — silent; it breaks consumers, not the framework
**Found**: porting a static site generator (`lanyon`), which could not create a
destination directory given as an absolute path
**Status**: open

---

## 1. Summary

```objc
- (NSArray *) pathComponents
{
   return( [self componentsSeparatedByString:NSFilePathComponentSeparator]);
}
```

This splits on `/`. It does not parse a path. The difference is the leading
separator of an absolute path, which comes back as an **empty component**
instead of `"/"` — while Apple documents the opposite:

> `/tmp/scratch.tiff` → `@[@"/", @"tmp", @"scratch.tiff"]`

`+pathWithComponents:` is `componentsJoinedByString:@"/"` and is wrong in the
complementary direction. So the two errors cancel and the pair round-trips
exactly, which is why nothing has caught this: any test written as
"components and then reassemble" passes. The bug only shows up when a component
is used **as a path on its own**, which is the entire reason to walk components.

---

## 2. What it actually returns

Measured (throwaway `main()` printing each component inside `<>`, then the
reassembly, then `isAbsolutePath`):

| input | `pathComponents` | reassembled |
|---|---|---|
| `/tmp/absdest` | `<> <tmp> <absdest>` | `/tmp/absdest` |
| `/tmp/lscan/out` | `<> <tmp> <lscan> <out>` | `/tmp/lscan/out` |
| `/a` | `<> <a>` | `/a` |
| `/` | `<> <>` | `/` |
| `//a/b` | `<> <> <a> <b>` | `//a/b` |
| `/a/b/` | `<> <a> <b> <>` | `/a/b/` |
| `weirdout` | `<weirdout>` | `weirdout` |
| `a/b` | `<a> <b>` | `a/b` |
| `./weird` | `<.> <weird>` | `./weird` |
| `a/` | `<a> <>` | `a/` |
| `a//b` | `<a> <> <b>` | `a//b` |
| `.` | `<.>` | `.` |
| `..` | `<..>` | `..` |
| `""` | `<>` | `""` |

Every row round-trips. Nothing is *lost* — the array is just not what Cocoa
says it is, and the empty string is not a path.

Expected (Darwin):

| input | expected | note |
|---|---|---|
| `/tmp/absdest` | `["/", "tmp", "absdest"]` | documented by Apple |
| `/` | `["/"]` | we return two components |
| `""` | `[]` | we return one |
| `/a/b/`, `a/` | trailing separator dropped | ours keeps an empty component |
| `a//b` | interior empty dropped | ours keeps it |
| `.`, `..` | kept as components | we agree |

The trailing-separator and empty-string rows are stated from memory of Darwin's
behaviour and should be confirmed on a Mac before someone treats them as
gospel; the leading `"/"` row is documented and is the one that matters.

---

## 3. Why nothing caught it: the pair is self-consistent

```objc
+ (instancetype) pathWithComponents:(NSArray *) components
{
   return( [components componentsJoinedByString:NSFilePathComponentSeparator]);
}
```

`""` joined with `"/"` then `"tmp"` is `/tmp`. The empty component is a
*placeholder for the leading separator*, and joining blindly puts it back. So:

```
["", "tmp"] -> "/tmp"     round-trip holds, both are "wrong"
["/", "tmp"] -> "//tmp"    round-trip holds, both are Cocoa
```

The two representations are equally closed. Which means **`pathComponents`
cannot be fixed on its own**: the framework's own directory walk builds
`["/", "tmp"]` and would then create `//tmp`, which is a valid path on POSIX
(a leading `//` is implementation-defined but usually a synonym for `/`) and
malformed on Windows. They have to be changed together, which is probably why
this has survived: it is not a one-line fix, it is a contract change.

---

## 4. Blast radius

**The framework itself escapes — by luck, in two different ways.**

`NSFileManager+Posix.m:296` and `NSFileManager+Windows.m:315` both walk
components through the pair:

```objc
   subComponents = [NSMutableArray array];
   components    = [path pathComponents];
   for( i = 0; i < n; i++)
   {
      [subComponents addObject:[components objectAtIndex:i]];
      subpath = [NSString pathWithComponents:subComponents];
      rc      = [self _createDirectoryAtPath:subpath attributes:attributes];
      if( rc == EEXIST)
         continue;
```

They never test a component as a path, only the reassembled prefixes, so the
placeholder does its job. (This is also why that method's own `EEXIST` bug was
independent of this one.)

`stringByExpandingTildeInPath` (`NSString+OSBase.m:183`) reads
`[components objectAtIndex:0]` and compares its length to 1 to decide between
`NSHomeDirectory()` and `NSHomeDirectoryForUser()`. That is only correct because
it is guarded by `hasPrefix:@"~"`, so the string is never absolute and index 0
is never the empty component. Fragile, not broken.

`NSDirectoryEnumerator -level` uses the raw split directly
(`[... componentsSeparatedByString:NSFilePathComponentSeparator] count]`), so a
fix to `pathComponents` does not change it — but `level` of `"/"` is 2 today.

**Consumers break.** The idiom the framework itself uses —

```objc
   subpath = @"";
   for( component in [path pathComponents])
   {
      subpath = [subpath stringByAppendingPathComponent:component];
      if( ![fileManager fileExistsAtPath:subpath isDirectory:NULL])
         [fileManager createDirectoryAtPath:subpath attributes:nil];
   }
```

— fails immediately on an absolute path, because the first iteration tests and
creates `@""`, which exists nowhere and cannot be created. It never reaches
`/tmp`. The "rebuild the prefixes yourself" spelling is the one Apple's
documentation for `createDirectoryAtPath:withIntermediateDirectories:YES`
effectively invites, and it is exactly the spelling that the placeholder breaks.

Measured in `lanyon`:

```
lanyon weird weirdout          -> code.html | 1 page
lanyon weird /tmp/absdest      -> code.md: could not create the directory for "code.html" | 0 pages
lanyon $PWD/weird weirdout     -> code.html | 1 page
lanyon $PWD/weird /tmp/absdest -> code.md: could not create the directory for "code.html" | 0 pages
lanyon ./weird ./weirdout      -> code.html | 1 page
```

Only the destination matters, and only when absolute — a static site generator
is usually invoked as `lanyon "$PWD" _site`, so this is the common case in CI.

---

## 5. The fix

Both methods, so they stay a pair. Note that `-isAbsolutePath` already exists
(`hasPrefix:NSFilePathComponentSeparator`) and is correct.

```objc
- (NSArray *) pathComponents
{
   NSArray          *components;
   NSMutableArray   *result;
   NSString         *component;
   NSUInteger       i;
   NSUInteger       n;

   result = [NSMutableArray array];

   // an absolute path has the separator itself as its first component, as
   // Darwin has it: "/tmp/x" is "/", "tmp", "x" and not "", "tmp", "x"
   if( [self hasPrefix:NSFilePathComponentSeparator])
      [result addObject:NSFilePathComponentSeparator];

   components = [self componentsSeparatedByString:NSFilePathComponentSeparator];
   n          = [components count];
   for( i = 0; i < n; i++)
   {
      component = [components objectAtIndex:i];

      // "", from a leading, repeated or trailing separator, is not a component
      if( ! [component length])
         continue;

      [result addObject:component];
   }

   return( result);
}


+ (instancetype) pathWithComponents:(NSArray *) components
{
   NSUInteger       i;
   NSUInteger       n;
   NSMutableString  *s;
   NSString         *component;

   n = [components count];
   s = [NSMutableString string];

   for( i = 0; i < n; i++)
   {
      component = [components objectAtIndex:i];

      // the separator of an absolute path is a component of its own and must
      // not be joined a second time
      if( i == 0 && [component isEqualToString:NSFilePathComponentSeparator])
      {
         [s appendString:component];
         continue;
      }

      if( ! [component length])
         continue;

      if( [s length] && ! [s hasSuffix:NSFilePathComponentSeparator])
         [s appendString:NSFilePathComponentSeparator];
      [s appendString:component];
   }

   return( s);
}
```

After the change, for both methods at once:

| input | components | reassembled |
|---|---|---|
| `/tmp/x` | `[/, tmp, x]` | `/tmp/x` |
| `/` | `[/]` | `/` |
| `""` | `[]` | `""` |
| `a/b` | `[a, b]` | `a/b` |
| `./x` | `[., x]` | `./x` |
| `/a/b/` | `[/, a, b]` | `/a/b` (normalised) |
| `a//b` | `[a, b]` | `a/b` (normalised) |
| `~/x` | `[~, x]` | `~/x` |

The last two normalise, which is a behaviour change for callers that pass a
path through the pair to have it tidy up — but nobody does that today (see §6),
and it is what the names promise.

**Callers of `+pathWithComponents:` with a hand-built array must be checked**,
since the empty first component no longer acts as a placeholder:

```
[NSString pathWithComponents:@["", "tmp"]]   old "/tmp"   new "tmp"
```

The framework's own two walks build their array from `pathComponents`, so they
are fixed by the same change; grep found no other live caller. That is why this
has to be one commit, not two.

---

## 6. Regression test

`MulleObjCOSBaseFoundation` has no `test/` yet, so `mulle-sde test init` first.
The cases that matter, in one method:

```c
   // the leading separator is a component of its own
   _assert_n_equal( [@"/tmp/scratch.tiff" pathComponents],           @[@"/", @"tmp", @"scratch.tiff"]);
   _assert_n_equal( [@"/" pathComponents],                           @[@"/"]);
   _assert_n_equal( [@"" pathComponents],                            @[]);
   _assert_n_equal( [@"/a/b/" pathComponents],                       @[@"/", @"a", @"b"]);
   _assert_n_equal( [@"a//b" pathComponents],                        @[@"a", @"b"]);
   _assert_n_equal( [@"./x" pathComponents],                         @[@".", @"x"]);

   // and the pair round-trips, which is the property that hid the bug
   _assert_n_equal( [NSString pathWithComponents:[@"/tmp/x" pathComponents]],   @"/tmp/x");
   _assert_n_equal( [NSString pathWithComponents:@[@"/", @"tmp"]],             @"/tmp");
```

The round-trip assertions are the important ones: they pass **before** the fix
for the current pair, so they say nothing about the bug — the *value*
assertions are the regression test, and the round-trips are there to stop the
fix from breaking the walks in `NSFileManager`.

The behaviour that motivated the report, at the level a consumer sees it: walk
`[@"/tmp/x/y" pathComponents]`, feed each prefix to
`fileExistsAtPath:isDirectory:`, and assert that the first prefix tested is
`"/"` and not `@""`.

---

## 7. Workaround, and when to remove it

`lanyon` carries `createDirectory()` in `src/LanyonSite.m`, which puts the root
back by hand:

```objc
   subpath = [path hasPrefix:@"/"] ? @"/" : @"";
   ...
      if( ! [component length])     // the empty component, already accounted for
         continue;
```

That helper also exists to work around `createDirectoryAtPath:`
`withIntermediateDirectories:` and can be deleted entirely once **both** bugs
are fixed — the framework's method will then be correct and this file goes back
to one call. It should not be left in place "just in case", or it becomes the
reason nobody notices that the framework is fixed.

---

## 8. Copies that carry it

| file | note |
|---|---|
| `MulleObjCOSBaseFoundation/src/Categories/NSString+OSBase.m` | canonical source |
| `MulleFoundation/src/MulleObjCOSBaseFoundation/NSString+OSBase.m` | the amalgamation, **read-only**, regenerated at release |
| `MulleObjCOSFoundation.borked/src/OSBase/…/NSString+OSBase.m` | dead layout |
| `pre-split/MulleObjCOSFoundation/src/OSBase/…/NSString+OSBase.m` | dead layout |

Worth knowing which one a project actually links: `lanyon` depends on the
umbrella `MulleFoundation`, so it builds against the **amalgamation** copy. Fixing
only the source repo does not reach it — the same trap as the
`createDirectoryAtPath:` report.

`MulleObjC{BSD,Darwin,FreeBSD,Linux,Posix,Windows,Locale}Foundation/.git/…`
contain third and fourth copies; those are repository history, not build input.

---

## 9. Reproducing

With the current framework, in five lines from any project that can call
`NSFileManager`:

```objc
   mulle_printf( "%@\n", [@"/tmp/x" pathComponents]);   // ( "", tmp, x )   want ( /, tmp, x )
   mulle_printf( "%@\n", [@"/" pathComponents]);        // ( "", "" )       want ( / )
```

Through `lanyon`, which is how it was found:

```bash
cd MulleWeb-demo/lanyon
mulle-sde craft
mkdir -p /tmp/src && printf -- '---\ntitle: T\n---\n\nhi\n' > /tmp/src/a.md
./kitchen/Debug/lanyon /tmp/src /tmp/dest          # -> 1 page
./kitchen/Debug/lanyon /tmp/src "$PWD/dest-abs"    # -> could not create the directory, 0 pages
```

---

## 10. One-sentence summary

`-pathComponents` hands out an empty component where Cocoa hands out the root
separator, `+pathWithComponents:` joins it back so the pair round-trips and the
error stays invisible, and any consumer that treats a component as a path —
which is the only reason to ask for components at all — fails on absolute
paths, as `lanyon` did.
