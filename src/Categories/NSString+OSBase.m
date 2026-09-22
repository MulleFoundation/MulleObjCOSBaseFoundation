//
//  NSString+OSBase.m
//  MulleObjCOSFoundation
//
//  Copyright (c) 2020 Nat! - Mulle kybernetiK.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
#import "NSString+OSBase.h"

// other files in this library
#import "NSFileManager.h"
#import "NSPathUtilities.h"
#import "NSData+OSBase.h"
#import "NSString+CString.h"

// std-c and dependencies
#import "import-private.h"


#pragma clang diagnostic ignored "-Wparentheses"


@implementation NSString( OSBase)

- (BOOL) isAbsolutePath
{
   return( [self hasPrefix:NSFilePathComponentSeparator]);
}


// use string subclass that keeps components separate
+ (instancetype) pathWithComponents:(NSArray *) components
{
   NSMutableString  *s;
   NSString         *component;
   NSUInteger       i, n;

   n = [components count];
   if( ! n)
      return( @"");

   s = [NSMutableString stringWithString:[components objectAtIndex:0]];

   for( i = 1; i < n; i++)
   {
      component = [components objectAtIndex:i];

      // the root separator is a component of its own, don't double it
      if( i == 1 && [s isEqualToString:NSFilePathComponentSeparator])
         [s appendString:component];
      else
      {
         // empty components are not cleaned up, they create the separator
         [s appendString:NSFilePathComponentSeparator];
         [s appendString:component];
      }
   }

   return( s);
}

///
// This method can make the following changes in the provided string:
//
// Expand an initial tilde expression using stringByExpandingTildeInPath.
// Reduce empty components and references to the current directory (that
// is, the sequences “//” and “/./”) to single path separators.
// In absolute paths only, resolve references to the parent directory
// (that is, the component “..”) to the real parent directory if possible
// using stringByResolvingSymlinksInPath, which consults the file system
// to resolve each potential symbolic link.
// In relative paths, because symbolic links can’t be resolved, references
// to the parent directory are left in place.
//
// Remove an initial component of “/private” from the path if the result
// still indicates an existing file or directory (checked by consulting
// the file system).
//
- (NSString *) initWithPathComponents:(NSArray *) components
{
   NSString  *s;

   s = [NSString pathWithComponents:components];
   [self autorelease];
   [s retain];

   return( s);
}


- (NSArray *) pathComponents
{
   NSArray          *components;
   NSMutableArray   *result;
   NSString         *component;
   NSUInteger       i, n;
   NSUInteger       len;

   len = [self length];
   if( ! len)
      return( [NSArray array]);

   result     = [NSMutableArray array];
   components = [self componentsSeparatedByString:NSFilePathComponentSeparator];
   n          = [components count];

   // the separator at the front is a component of its own
   if( [self hasPrefix:NSFilePathComponentSeparator])
      [result addObject:NSFilePathComponentSeparator];

   for( i = 0; i < n; i++)
   {
      component = [components objectAtIndex:i];

      // empty components come from consecutive or trailing separators
      if( ! [component length])
      {
         // the separator at the end is a component of its own
         if( i == n - 1 && len > 1 && [self hasSuffix:NSFilePathComponentSeparator])
            [result addObject:NSFilePathComponentSeparator];
         continue;
      }

      [result addObject:component];
   }

   return( result);
}


- (NSString *) mulleStringBySimplifyingPath
{
   return( [self mulleStringBySimplifyingComponentsSeparatedByString:NSFilePathComponentSeparator
                                                        simplifyDots:YES]);
}

//
// this is not what darwin will do (in a category)
//
- (NSString *) _stringByRemovingPrivatePrefix
{
   return( self);
}


- (NSString *) stringByStandardizingPath
{
   NSString        *path;

   path = self;
//   path = [self stringByExpandingTildeInPath];  // already done by symlinks
   path = [path stringByResolvingSymlinksInPath];
   path = [path mulleStringBySimplifyingPath];

   //
   // that's what MacOS does, don't know why.
   // we only do this in Darwin
   path = [path _stringByRemovingPrivatePrefix];

   return( path);
}


// resist the urge, to standardize
//   [@"a" stringByAppendingPathComponent:@"b"]     ->  a/b
//   [@"a/" stringByAppendingPathComponent:@"b"]    ->  a/b
//   [@"/a" stringByAppendingPathComponent:@"b"]    ->  /a/b
//   [@"/a/" stringByAppendingPathComponent:@"b"]   ->  /a/b
//   [@"a" stringByAppendingPathComponent:@"b/"]    ->  a/b
//   [@"a/" stringByAppendingPathComponent:@"b/"]   ->  a/b
//   [@"/a" stringByAppendingPathComponent:@"b/"]   ->  /a/b
//   [@"/a/" stringByAppendingPathComponent:@"b/"]  ->  /a/b
//   [@"a" stringByAppendingPathComponent:@"/b"]    ->  a/b
//   [@"a/" stringByAppendingPathComponent:@"/b"]   ->  a/b
//   [@"/a" stringByAppendingPathComponent:@"/b"]   ->  /a/b
//   [@"/a/" stringByAppendingPathComponent:@"/b"]  ->  /a/b
//   [@"a" stringByAppendingPathComponent:@"/b/"]   ->  a/b
//   [@"a/" stringByAppendingPathComponent:@"/b/"]  ->  a/b
//   [@"/a" stringByAppendingPathComponent:@"/b/"]  ->  /a/b
//   [@"/a/" stringByAppendingPathComponent:@"/b/"] ->  /a/b
//
- (NSString *) stringByAppendingPathComponent:(NSString *) other
{
   return( [self mulleStringByAppendingComponent:other
                               separatedByString:NSFilePathComponentSeparator]);
}


// resist the urge, to standardize
- (NSString *) stringByAppendingPathExtension:(NSString *) extension
{
   NSString   *s;

   s = self;
   if( [s hasSuffix:@"/"])
      s = [self substringToIndex:[self length] - 1];

   return( [s stringByAppendingFormat:@"%@%@", NSFilePathExtensionSeparator, extension]);
}


//
// this only works if ~ is in front
// see: https://developer.apple.com/documentation/foundation/nsstring/1407716-stringbyexpandingtildeinpath?language=objc
//
- (NSString *) stringByExpandingTildeInPath
{
   id        components;
   NSString  *first;
   NSString  *home;

   if( ! [self hasPrefix:@"~"])
      return( self);

   components = [self pathComponents];
   first      = [components objectAtIndex:0];
   if( [first length] == 1)
      home = NSHomeDirectory();
   else
      home = NSHomeDirectoryForUser( [first substringFromIndex:1]);
   if( ! home)
      return( self);

   components = [NSMutableArray arrayWithArray:components];
   [components replaceObjectAtIndex:0
                         withObject:home];
   return( [NSString pathWithComponents:components]);
}


- (NSString *) stringByResolvingSymlinksInPath
{
   NSFileManager     *manager;
   NSArray           *components;
   NSMutableString   *s;
   NSString          *path;
   NSString          *component;
   NSString          *expanded;
   NSString          *best;
   NSUInteger        len;

   path = [self stringByExpandingTildeInPath];
   if( ! [path isAbsolutePath])
      return( path);

   manager    = [NSFileManager defaultManager];
   components = [path componentsSeparatedByString:NSFilePathComponentSeparator];
   s          = [NSMutableString string];
   for( component in components)
   {
      len = [component length];
      if( ! len)
         continue;
      [s appendString:NSFilePathComponentSeparator];
      [s appendString:component];

      best = s;
      while( expanded = [manager pathContentOfSymbolicLinkAtPath:best])
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
   }
   if( ! [s length])
      return( NSFilePathComponentSeparator);
   return( s);
}


/*
  * /tmp/scratch.tiff -> scratch.tiff
  * /tmp/scratch”     -> scratch
  * /tmp/”            -> tmp
  * scratch           -> scratch
  * /                 -> /
*/
static NSRange  getLastPathComponentRange( NSString *self)
{
   NSRange      range;
   NSUInteger   len;
   NSUInteger   end;

   len = [self length];
   if( ! len)
      return( NSRangeMake( 0, 0));

   // multiple path separators at the end are stripped
   end = len;
   while( end && [self characterAtIndex:end - 1] == (unichar) '/')
      end--;

   // nothing but separators: the root
   if( ! end)
      return( NSRangeMake( 0, 1));

   range = [self rangeOfString:NSFilePathComponentSeparator
                       options:NSLiteralSearch|NSBackwardsSearch
                         range:NSRangeMake( 0, end)];
   if( ! range.length) // no separator at all
      return( NSRangeMake( 0, end));

   return( NSRangeMake( range.location + 1, end - range.location - 1));
}


static NSRange  getPathExtensionRange( NSString *self)
{
   NSRange   range1;
   NSRange   range2;

   // first get lastPathComponent range
   range1 = getLastPathComponentRange( self);
   if( range1.length == 0)
      return( range1);

   range2 = [self rangeOfString:NSFilePathExtensionSeparator
                        options:NSBackwardsSearch
                          range:range1];
   // /.tiff is not an extension!
   if( ! range2.length || range2.location <= range1.location)
      return( NSRangeMake( NSNotFound, 0));

   ++range2.location;
   return( NSRangeMake( range2.location, (range1.location + range1.length) - range2.location));
}


- (NSString *) lastPathComponent
{
   NSRange   range;

   range = getLastPathComponentRange( self);
   return( [self substringWithRange:range]);
}


- (NSString *) stringByDeletingLastPathComponent
{
   NSRange      range;
   NSUInteger   len;
   NSUInteger   end;

   len = [self length];
   if( ! len)
      return( self);

   end = len;
   while( end && [self characterAtIndex:end - 1] == (unichar) '/')
      end--;

   if( ! end) // only separators, the root
      return( NSFilePathComponentSeparator);

   range = [self rangeOfString:NSFilePathComponentSeparator
                       options:NSLiteralSearch|NSBackwardsSearch
                         range:NSRangeMake( 0, end)];
   if( ! range.length) // a single component, delete it all
      return( @"");

   if( ! range.location) // the component follows the leading separator
      return( NSFilePathComponentSeparator);

   return( [self substringToIndex:range.location]);
}


- (NSString *) pathExtension
{
   NSRange   range;

   range = getPathExtensionRange( self);
   if( ! range.length)
      return( @"");
   return( [self substringWithRange:range]);
}


- (NSString *) stringByDeletingPathExtension
{
   NSRange      range;
   NSString     *base;
   NSUInteger   len;
   NSUInteger   end;

   len = [self length];
   end = len;
   // strip trailing path separators before checking for an extension
   while( end && [self characterAtIndex:end - 1] == (unichar) '/')
      end--;

   if( ! end) // only separators, the root
      return( self);

   base  = [self substringToIndex:end];
   range = getPathExtensionRange( base);
   if( ! range.length)
      return( base);

   // also snip off "dot"
   return( [base substringToIndex:range.location - 1]);
}


//
// TODO: need to convert to proper characterset
//
- (char *) fileSystemRepresentation
{
   return( [[NSFileManager sharedInstance] fileSystemRepresentationWithPath:self]);
}


// this is not as fast as you may think :)
- (BOOL) getFileSystemRepresentation:(char *) buf
                           maxLength:(NSUInteger) max
{
   char     *s;
   size_t   len;

   s = [[NSFileManager sharedInstance] fileSystemRepresentationWithPath:self];
   if( ! s)
      return( NO);
   len = strlen( s);
   if( len > max)
      return( NO);

   memcpy( buf, s, len);
   return( YES);
}


+ (instancetype) stringWithContentsOfFile:(NSString *) path
{
   return( [[[self alloc] initWithContentsOfFile:path] autorelease]);
}



static NSStringEncoding  encodingForBOMOfData( NSData *p)
{
   struct mulle_data   data;
   mulle_utf16_t       c16;
   mulle_utf32_t       c32;
   uint8_t             *bytes;

   data = [p mulleCData];
   if( data.length >= 2)
   {
      bytes = data.bytes;
      // length must be at least 2 now
      c16   = (mulle_utf16_t) ((bytes[ 0] << 8) | bytes[ 1]);
      if( mulle_utf16_get_bomcharacter() == c16)
         return( NSUTF16BigEndianStringEncoding);

      c16   = (mulle_utf16_t) ((bytes[ 1] << 8) | bytes[ 0]);
      if( mulle_utf16_get_bomcharacter() == c16)
         return( NSUTF16LittleEndianStringEncoding);

      if( mulle_utf8_has_leading_bomcharacter( (char *) bytes, data.length))
         return( NSUTF8StringEncoding);

      if( data.length >= 4)
      {
         c32 = (mulle_utf32_t) ((bytes[ 0] << 24) |
                                (bytes[ 1] << 16) |
                                (bytes[ 2] << 8) |
                                bytes[ 3]);
         if( mulle_utf32_get_bomcharacter() == c32)
            return( NSUTF32BigEndianStringEncoding);

         c32 = (mulle_utf32_t) ((bytes[ 3] << 24) |
                                (bytes[ 2] << 16) |
                                (bytes[ 1] << 8) |
                                bytes[ 0]);
         if( mulle_utf32_get_bomcharacter() == c32)
            return( NSUTF32LittleEndianStringEncoding);
      }
   }

   return( 0);
}


- (instancetype) initWithContentsOfFile:(NSString *) path
{
   NSData             *data;
   NSStringEncoding   encoding;

   data = [NSData dataWithContentsOfFile:path];
   if( ! data)
   {
      [self release];
      return( nil);
   }

   encoding = encodingForBOMOfData( data);
   if( ! encoding)
      encoding = [NSString defaultCStringEncoding];

#if 0
   return( [self initWithData:data
                     encoding:encoding]);
#else
   return( [self mulleInitWithDataNoCopy:data
                                encoding:encoding]);
#endif
}


- (instancetype) mulleInitWithLossyContentsOfFile:(NSString *) path
{
   NSMutableData      *data;
   NSStringEncoding   encoding;

   data = [NSMutableData dataWithContentsOfFile:path];
   if( ! data)
   {
      [self release];
      return( nil);
   }

   encoding = encodingForBOMOfData( data);
   if( ! encoding)
      encoding = [NSString defaultCStringEncoding];

   /*
    * flip bytes now, if needed
    */
   switch( encoding)
   {
#ifdef __BIG_ENDIAN__
   case NSUTF16LittleEndianStringEncoding :
#endif
#ifdef __LITTLE_ENDIAN__
   case NSUTF16BigEndianStringEncoding    :
#endif
      [data mulleSwapUTF16Characters];
      encoding = NSUTF16StringEncoding;
      break;

#ifdef __BIG_ENDIAN__
   case NSUTF32LittleEndianStringEncoding :
#endif
#ifdef __LITTLE_ENDIAN__
   case NSUTF32BigEndianStringEncoding    :
#endif
      [data mulleSwapUTF32Characters];
      encoding = NSUTF32StringEncoding;
      break;
   }

   // do a lossy conversion for invalid characters
   [data mulleReplaceInvalidCharactersWithASCIICharacter:'?'
                                                encoding:encoding];

   return( [self mulleInitWithDataNoCopy:data
                                encoding:encoding]);
}


+ (instancetype) mulleStringWithLossyContentsOfFile:(NSString *) path
{
   return( [[[self alloc] mulleInitWithLossyContentsOfFile:path] autorelease]);
}



- (BOOL) writeToFile:(NSString *) path
          atomically:(BOOL) flag
{
   NSData  *data;

   data = [self dataUsingEncoding:NSUTF8StringEncoding];
   assert( data);
   return( [data writeToFile:path
                  atomically:flag]);
}


- (BOOL) writeToFile:(NSString *) path
          atomically:(BOOL) flag
            encoding:(NSStringEncoding) encoding
               error:(NSError **) error
{
   NSData  *data;

   data = [self dataUsingEncoding:encoding];
   return( [data writeToFile:path
                  atomically:flag
                       error:error]);
}


// complete like bash here, if the file exists and is a directory
// complete with '/', if that isn't part of the name. If it is
// use it as directory.
// Otherwise if it it doesn't exist. Use lastPath component as prefix
// and enumerate dir
//
- (NSUInteger) completePathIntoString:(NSString **) outputName
                        caseSensitive:(BOOL) flag
                     matchesIntoArray:(NSArray **) outputArray
                          filterTypes:(NSArray *) filterTypes
{
   NSFileManager           *fileManager;
   NSDirectoryEnumerator   *rover;
   NSString                *prefix;
   NSString                *directory;
   NSString                *fileName;
   NSString                *matchName;
   NSString                *extension;
   NSString                *maxName;
   id                      set;
   NSUInteger              n;
   NSUInteger              length;
   NSUInteger              maxLength;
   BOOL                    isDirectory;
   NSMutableArray          *array;


   fileManager = [NSFileManager defaultManager];
   if( [fileManager fileExistsAtPath:self
                         isDirectory:&isDirectory])
   {
      prefix    = @"";
      directory = nil;
      if( isDirectory)
      {
         if( ! [self hasSuffix:NSFilePathComponentSeparator])
         {
            if( outputName)
               *outputName = [self stringByAppendingString:NSFilePathComponentSeparator];
            if( outputArray)
               *outputArray = nil;
            return( 1);
         }
         directory = self;
      }
   }
   else
   {
      prefix    = [self lastPathComponent];
      directory = [self stringByDeletingLastPathComponent];
   }

   if( ! flag)
      prefix = [prefix lowercaseString];

   // use a set, if we have very many file extensions
   set = filterTypes;
   if( [set count] > 16)
      set = [NSSet setWithArray:filterTypes];

   maxName   = nil;
   maxLength = 0;
   n         = 0;
   array     = nil;

   rover = [fileManager enumeratorAtPath:directory];
   while( fileName = [rover nextObject])
   {
      if( set)
      {
         extension = [fileName pathExtension];
         if( ! [set containsObject:extension])
            continue;
      }

      // for matching conver to lowercase if needed
      matchName = flag ? fileName : [fileName lowercaseString];
      if( ! [matchName hasPrefix:prefix])
         continue;

      if( outputArray && ! array)
         array = [NSMutableArray array];
      [array addObject:fileName];
      ++n;

      length = [fileName length];
      if( length > maxLength)
      {
         maxName   = fileName;
         maxLength = length;
      }
   }

   if( outputName)
      *outputName = maxName;
   if( outputArray)
      *outputArray = array;
   return( n);
}

@end
