//
//  NSTask+System.m
//  MulleObjCOSFoundation
//
//  Copyright (c) 2023 Nat! - Mulle kybernetiK.
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
// define, that make things POSIXly
#define _XOPEN_SOURCE 700

#import "NSTask+System.h"

// other files in this library
#import "NSFileManager.h"
#import "NSProcessInfo.h"
#import "NSTask-Private.h"
#import "NSString+CString.h"
#import "NSString+OSBase.h"

/*
 * mulle-spawn arrives with mulle-core, which the Objective-C runtime brings
 * into every project that can run this code. It is spelled out because nothing
 * else in this file would tell a reader where `mulle_spawn_open` -- or the
 * `_status` vocabulary of NSTask-Private.h -- is from.
 */
#include <mulle-spawn/mulle-spawn.h>

/*
 * The descriptors mulle-spawn hands back are file descriptors on POSIX and the
 * CRT's own on Windows, where they are also spelled differently. This is the
 * only place in this file that has to know that, which is the price of the
 * orchestrator being one implementation instead of two.
 */
#ifdef _WIN32
# include <io.h>
# define _taskRead( fd, buf, n)    _read( fd, buf, n)
# define _taskWrite( fd, buf, n)   _write( fd, buf, n)
# define _taskClose( fd)           _close( fd)
#else
# include <unistd.h>
# define _taskRead( fd, buf, n)    read( fd, buf, n)
# define _taskWrite( fd, buf, n)   write( fd, buf, n)
# define _taskClose( fd)           close( fd)
#endif

// #define DEBUG_IO

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskExceptionKey            = @"exception";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskTerminationStatusKey    = @"terminationStatus";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskStandardOutputDataKey   = @"standardOutputData";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskStandardOutputStringKey = @"standardOutputString";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskStandardErrorDataKey    = @"standardErrorData";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString   *NSTaskStandardErrorStringKey  = @"standardErrorString";


@implementation NSFileManager( System)

- (NSString *) mulleFindExecutable:(NSString *) name
                            inPATH:(NSString *) envPATH
{
   NSString   *executablePath;
   NSString   *absolute;

   assert( ! [name isAbsolutePath]);

   if( ! envPATH)
      envPATH = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];

#ifdef _WIN32
   for( executablePath in [envPATH componentsSeparatedByString:@";"])
#else
   for( executablePath in [envPATH componentsSeparatedByString:@":"])
#endif
   {
      if( ! [executablePath length])
         continue;
      // Convert from native filesystem format to internal format
      executablePath = [self stringWithFileSystemRepresentation:[executablePath UTF8String]
                                                          length:[executablePath length]];
      absolute = [executablePath stringByAppendingPathComponent:name];
      if( [self isExecutableFileAtPath:absolute])
         return( absolute);
   }
   return( nil);
}


@end


struct thread_info
{
   NSThread      *thread;
   NSData        *data;
   int           descriptor;
};


/*
 * Everything the child has to say, read to EOF. An error is not told apart
 * from an EOF here because on a pipe they are the same thing: the child is
 * gone, and nothing more is coming. A short read is not a reason to stop, and
 * a `0` is.
 */
static NSData   *dataFromDescriptorToEOF( int descriptor)
{
   NSMutableData   *data;
   char            buffer[ 4096];
   ssize_t         n;

   data = [NSMutableData data];
   for(;;)
   {
      n = _taskRead( descriptor, buffer, sizeof( buffer));
      if( n <= 0)
         break;

      [data appendBytes:buffer
                 length:(NSUInteger) n];
   }
   return( data);
}


/*
 * The data is written in a thread of its own while the other end of that pipe
 * is read in this one, which is the whole reason the thread exists: a child
 * that answers more than a pipe holds would otherwise wait forever for a
 * parent that is still waiting for it to answer.
 *
 * A write that comes back short is carried on with, and one that fails ends it
 * -- a child that stopped reading its stdin is not an error to report, and by
 * then there is nobody left to report it to.
 *
 * The chunks are bounded because the count these take is an `unsigned int` on
 * Windows and a `size_t` on POSIX, and one bound that is right for both is
 * simpler than one for each.
 */
static int   writeDescriptorAndClose( NSThread *thread, void *_info)
{
   struct thread_info   *info = _info;
   const char           *bytes;
   NSUInteger           length;
   NSUInteger           want;
   ssize_t              n;

   [info->data mulleGainAccess];

#ifdef DEBUG_IO
   mulle_fprintf( stderr, "write data\n");
#endif
   bytes  = [info->data bytes];
   length = [info->data length];

   while( length)
   {
      want = (length > 65536) ? 65536 : length;
      n    = _taskWrite( info->descriptor, bytes, want);
      if( n <= 0)
         break;

      bytes  += n;
      length -= (NSUInteger) n;
   }
#ifdef DEBUG_IO
   mulle_fprintf( stderr, "close write\n");
#endif
   _taskClose( info->descriptor);

#ifdef DEBUG_IO
   mulle_fprintf( stderr, "end write thread\n");
#endif
   [info->data autorelease];
   return( 0);
}


static int   readDescriptorData( NSThread *thread, void *_info)
{
   struct thread_info   *info = _info;

#ifdef DEBUG_IO
   mulle_fprintf( stderr, "read err data\n");
#endif
   info->data = [dataFromDescriptorToEOF( info->descriptor) retain];
#ifdef DEBUG_IO
   mulle_fprintf( stderr, "end read err thread\n");
#endif
   [info->data mulleRelinquishAccess];

   return( 0);
}


/*
 * An `NSDictionary` as the envp mulle-spawn takes, in one allocation: the NULL
 * terminated array of pointers first, then a copy of every "NAME=VALUE"
 * behind it. What the caller has to `mulle_free` comes back in `allocation`.
 *
 * A nil dictionary answers NULL, which is spawn's way of saying "the parent's
 * environment, unchanged" -- so the difference that matters survives: nil is
 * the inherited environment, @{} is no environment at all.
 *
 * This used to be written out twice, once in each launch; it is one conversion
 * wanted by three callers (the two launches and the orchestrator below), so it
 * is declared in NSTask-Private.h and written once here.
 */
MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL
char   **mulleNSTaskEnvironmentStrings( NSDictionary *environment, void **allocation)
{
   NSArray      *keys;
   NSString     *key;
   NSString     *value;
   char         **envp;
   char         *s;
   char         *q;
   size_t       len;
   size_t       n;
   size_t       i;

   *allocation = NULL;
   if( ! environment)
      return( NULL);

   keys = [environment allKeys];
   n    = [keys count];

   // the array, then "NAME=VALUE" and its terminator for each pair
   len = (n + 1) * sizeof( char *) + 1;
   for( i = 0; i < n; i++)
   {
      key   = [keys objectAtIndex:i];
      value = [environment objectForKey:key];
      len  += strlen( [key UTF8String]) + 1 + strlen( [value UTF8String]) + 1;
   }

   envp = mulle_malloc( len);
   s    = (char *) &envp[ n + 1];

   for( i = 0; i < n; i++)
   {
      key   = [keys objectAtIndex:i];
      value = [environment objectForKey:key];

      envp[ i] = s;

      for( q = (char *) [key UTF8String]; *q; )
         *s++ = *q++;
      *s++ = '=';
      for( q = (char *) [value UTF8String]; *q; )
         *s++ = *q++;
      *s++ = 0;
   }
   envp[ n] = NULL;

   *allocation = envp;
   return( envp);
}

// @selector( mulleDataSystemCallWithArguments:environment:workingDirectory:standardInputData:options:)
@implementation NSTask( System)

/*
 * Create a child, talk to it on all three streams, wait for it, and hand back
 * what it said. This is the whole of the orchestration, and it used to be an
 * NSTask: two NSPipes, three `setStandard...:` calls, a launch, a wait, and the
 * child's output picked back up through NSFileHandle objects.
 *
 * All of that was there to hand descriptors to a `fork()` that is not there
 * anymore. mulle-spawn makes the pipes, keeps the child and hands back the
 * three descriptors, so what is left here is the part that is actually
 * Objective-C: an argv from the arguments, an envp from the environment, and a
 * dictionary from what came back.
 *
 * The descriptors are read and written the same way on both platforms --
 * `read`/`write` on POSIX, the CRT's own on Windows -- which is what lets one
 * implementation stand where there would otherwise be two.
 */
+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv
                                        environment:(NSDictionary *) environment
                                   workingDirectory:(NSString *) dir
                                  standardInputData:(NSData *) inputData
                                            options:(NSTaskSystemOptions) options
{
   struct mulle_spawn_handle    handle;
   struct mulle_spawn_options   spawnOptions;
   struct mulle_spawn_result    result;
   struct thread_info           info[ 3] = { 0 };
   NSMutableDictionary          *merged;
   NSFileManager                *fileManager;
   NSString                     *absolute;
   NSString                     *envPATH;
   NSString                     *executablePath;
   char                         **args;
   char                         **envp;
   void                         *envAllocation;
   NSUInteger                   argc;
   NSUInteger                   i;
   int                          err;
   int                          rval;
   id                           exception;

   argc = [argv count];
   if( ! argc)
      return( @{ NSTaskExceptionKey: [NSException exceptionWithName:NSInvalidArgumentException
                                                             reason:@"empty arguments"
                                                           userInfo:nil] });

   exception = 0;
   rval      = -1;

   /*
    * `environment` is *added* to this process's own rather than replacing it,
    * which is the opposite of what a task's `setEnvironment:` means -- the
    * header says so, and the difference is on purpose.
    */
   merged = nil;
   if( environment)
   {
      merged = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
      [merged addEntriesFromDictionary:environment];
   }

   mulle_spawn_handle_init( &handle);

   @autoreleasepool
   {
      @try
      {
         executablePath = [argv objectAtIndex:0];
         envPATH        = merged ? [merged :@"PATH"] : nil;

         //
         // The program is resolved here rather than left to the launch: a
         // caller who named a program that is not there is owed the name of
         // it, and the child is looked up in the PATH it is about to receive.
         //
#ifdef _WIN32
         if( ! [executablePath isAbsolutePath]
             && ! ([executablePath length] >= 2
                   && [executablePath characterAtIndex:1] == ':'))
#else
         if( ! [executablePath isAbsolutePath])
#endif
         {
            fileManager = [NSFileManager defaultManager];
            absolute    = [fileManager mulleFindExecutable:executablePath
                                                    inPATH:envPATH];
         }
         else
            absolute = executablePath;

         if( ! absolute)
            [NSException raise:NSInvalidArgumentException
               format:@"executable \"%@\" must be absolute or in PATH", executablePath];

         //
         // argv, with `argv[ 0]` in the form the child's own platform means
         // by a path: a Foundation path is `/c/...` on Windows, which is not a
         // path any Win32 program would know. The working directory below goes
         // through the same conversion, for the same reason.
         //
         args        = mulle_malloc( (argc + 1) * sizeof( char *));
         args[ 0]    = (char *) [absolute fileSystemRepresentation];

         for( i = 1; i < argc; i++)
            args[ i] = (char *) [[argv objectAtIndex:i] UTF8String];
         args[ argc] = NULL;

         envp = mulleNSTaskEnvironmentStrings( merged, &envAllocation);

         mulle_spawn_options_init( &spawnOptions);
         spawnOptions.env       = envp;
         spawnOptions.directory = [dir length] ? [dir fileSystemRepresentation] : NULL;

         //
         // Only the streams that were asked for are replaced; the others are
         // this process's own, untouched.
         //
         spawnOptions.in_mode  = (options & NSTaskSystemSendStandardInput)
                                 ? MULLE_SPAWN_PIPE : MULLE_SPAWN_INHERIT;
         spawnOptions.out_mode = (options & NSTaskSystemReceiveStandardOutput)
                                 ? MULLE_SPAWN_PIPE : MULLE_SPAWN_INHERIT;
         spawnOptions.err_mode = (options & NSTaskSystemReceiveStandardError)
                                 ? MULLE_SPAWN_PIPE : MULLE_SPAWN_INHERIT;

         //
         // `open` waits for the child to reach its exec, so a 0 here means the
         // program really is running, and a -1 means no child was created at
         // all, with `errno` saying why. A launch that did not happen used to
         // come back as a task that had "launched" and "exited 127".
         //
         if( mulle_spawn_open_with_options( &handle, args, &spawnOptions) == -1)
         {
            err = errno;
            mulle_free( envAllocation);
            mulle_free( args);

            errno = err;
            MulleObjCThrowErrnoException( @"could not launch \"%@\"", executablePath);
         }

         mulle_free( envAllocation);
         mulle_free( args);

         //
         // stdin is written in a thread of its own, stderr is read in another,
         // and stdout is read here. Three streams a child can fill, so only one
         // of them may block this thread -- and it is the one this thread is
         // waiting for anyway.
         //
         if( inputData && handle.in >= 0)
         {
            info[ 0].data       = [inputData copy];
            [info[ 0].data mulleRelinquishAccess];

            info[ 0].descriptor = handle.in;
            info[ 0].thread     = [[[NSThread alloc] mulleInitWithFunction:writeDescriptorAndClose
                                                                  argument:&info[ 0]] autorelease];
            [info[ 0].thread mulleStart];
         }
         else
         {
            //
            // Nothing to write is not nothing to do: the child was given a
            // pipe for its stdin, and this end of it is what has to be closed
            // for the child to read EOF. Otherwise it waits forever for input
            // that is never coming.
            //
            if( handle.in >= 0)
            {
               _taskClose( handle.in);
               handle.in = -1;
            }
         }

         if( handle.err >= 0)
         {
            info[ 2].descriptor = handle.err;
            info[ 2].thread     = [[[NSThread alloc] mulleInitWithFunction:readDescriptorData
                                                                  argument:&info[ 2]] autorelease];
            [info[ 2].thread mulleStart];
         }

         // saving a thread by running the stdout reader in this one
         if( handle.out >= 0)
            info[ 1].data = [dataFromDescriptorToEOF( handle.out) retain];

#ifdef DEBUG_IO
         mulle_fprintf( stderr, "wait\n");
#endif
         mulle_spawn_result_init( &result, NULL);
         rval = mulle_spawn_wait( &handle, MULLE_SPAWN_NO_TIMEOUT, &result);
         err  = errno;

#ifdef DEBUG_IO
         mulle_fprintf( stderr, "join stderr\n");
#endif
         [info[ 2].thread mulleJoin];
         [info[ 2].data mulleGainAccess];
#ifdef DEBUG_IO
         mulle_fprintf( stderr, "join stdin\n");
#endif
         [info[ 0].thread mulleJoin];

         //
         // The writer thread closed this end of the child's stdin on its way
         // out, so it must not be closed a second time: descriptor numbers get
         // handed out again, and the second close would land on somebody
         // else's.
         //
         handle.in = -1;

         if( rval != 1)
         {
            mulle_spawn_close( &handle, NULL);

            errno = err;
            MulleObjCThrowErrnoException( @"could not wait for the child");
         }

         rval = mulleNSTaskStatusFromResult( &result);

         //
         // The child has been waited for, so this closes the two descriptors
         // that are left and does nothing else: there is no child left to
         // terminate.
         //
         mulle_spawn_close( &handle, NULL);
      }
      @catch( id e)
      {
         exception = [e retain];
      }
   }

   [info[ 1].data autorelease];
   [info[ 2].data autorelease];
   [exception autorelease];
   if( exception)
      return( @{ NSTaskExceptionKey: exception });

#ifdef DEBUG_IO
   if( rval)
      mulle_fprintf( stderr, "child exited with %d: \"%.*s\"\n",
                             rval,
                             [info[ 2].data length] > 512 ? 512 : [info[ 2].data length],
                             [info[ 2].data bytes]);
#endif

   return( @{
              NSTaskTerminationStatusKey : @( rval),
              NSTaskStandardOutputDataKey: (info[ 1].data ? info[ 1].data : [NSNull null]),
              NSTaskStandardErrorDataKey : (info[ 2].data ? info[ 2].data : [NSNull null])
            });
}


+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv
                                   workingDirectory:(NSString *) dir
                                  standardInputData:(NSData *) inputData
                                            options:(NSTaskSystemOptions) options
{
   return( [self mulleDataSystemCallWithArguments:argv
                                      environment:nil
                                 workingDirectory:dir
                                standardInputData:inputData
                                         options:options]);
}


+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv
                                        environment:(NSDictionary *) environment
                                  standardInputData:(NSData *) data
{
   return( [self mulleDataSystemCallWithArguments:argv
                                      environment:environment
                                 workingDirectory:nil
                                standardInputData:data
                                          options:NSTaskSystemOptionsDefault]);
}



+ (NSDictionary *) mulleDataSystemCallWithArguments:(NSArray *) argv
                                  standardInputData:(NSData *) data
{
   return( [self mulleDataSystemCallWithArguments:argv
                                      environment:nil
                                 workingDirectory:nil
                                standardInputData:data
                                          options:NSTaskSystemOptionsDefault]);
}




+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
                                          environment:(NSDictionary *) environment
                                     workingDirectory:(NSString *) dir
                                  standardInputString:(NSString *) stdinString
                                              options:(NSTaskSystemOptions) options
{
   NSData         *data[ 2];
   NSData         *stdinData;
   NSDictionary   *dictionary;
   NSException    *exception;
   NSNumber       *status;
   NSString       *string[ 2];
   NSUInteger     length;
   NSUInteger     original_length;
   unsigned int   i;
   char           *bytes;
   int            c;
   int            d;

   stdinData  = [stdinString dataUsingEncoding:NSUTF8StringEncoding];
   dictionary = [self mulleDataSystemCallWithArguments:argv
                                           environment:environment
                                      workingDirectory:dir
                                     standardInputData:stdinData
                                               options:options];
   assert( dictionary);

   exception = [dictionary :NSTaskExceptionKey];
   if( exception)
   {
      status     = @( -1);
      string[ 0] = @"";
      data[ 0]   = [NSData data];
      string[ 1] = [exception reason];
      data[ 1]   = [string[ 1] dataUsingEncoding:NSUTF8StringEncoding];
   }
   else
   {
      status = [dictionary :NSTaskTerminationStatusKey];
      for( i = 0; i < 2; i++)
      {
         data[ i] = [dictionary :((i == 0)
                                  ? NSTaskStandardOutputDataKey
                                  : NSTaskStandardErrorDataKey)];

         // a missing or not-received stream is NSNull, treat as empty
         if( ! [data[ i] isKindOfClass:[NSData class]])
            data[ i] = [NSData data];

         //
         // remove single trailing linefeed, if this is inconvenient use
         // the data methods
         //
         original_length = [data[ i] length];
         if( ! original_length)
         {
            string[ i] = @"";
            assert( data[ i]);
            continue;
         }

         bytes  = [data[ i] bytes];
         length = original_length;

         d = bytes[ length - 1];
         if( d == '\r' || d == '\n')
            if( ! --length)
            {
               string[ i] = @"";
               continue;
            }

         if( d == '\n')
         {
            c = bytes[ length - 1];
            if( c == '\r')
               if( ! --length)
               {
                  string[ i] = @"";
                  continue;
               }
         }

         string[ i] = [[[NSString alloc] initWithBytes:bytes
                                                length:length
                                              encoding:NSUTF8StringEncoding] autorelease];
      }
   }

   // we have data anyway, so plop it in as well
   return( @{
               NSTaskTerminationStatusKey    : status,
               NSTaskStandardOutputDataKey   : data[ 0],
               NSTaskStandardOutputStringKey : string[ 0],
               NSTaskStandardErrorDataKey    : data[ 1],
               NSTaskStandardErrorStringKey  : string[ 1]
            });
}


+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
                                     workingDirectory:(NSString *) dir
                                  standardInputString:(NSString *) stdinString
                                              options:(NSTaskSystemOptions) options
{
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:nil
                                   workingDirectory:dir
                                standardInputString:stdinString
                                            options:options]);
}


+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
                                          environment:(NSDictionary *) environment
                                  standardInputString:(NSString *) stdinString
{
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:environment
                                   workingDirectory:nil
                                standardInputString:stdinString
                                            options:NSTaskSystemOptionsDefault]);
}


+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
                                          environment:(NSDictionary *) environment
{
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:environment
                                   workingDirectory:nil
                                standardInputString:nil
                                            options:NSTaskSystemOptionsDefault]);
}

+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
                                  standardInputString:(NSString *) stdinString
{
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:nil
                                   workingDirectory:nil
                                standardInputString:stdinString
                                            options:NSTaskSystemOptionsDefault]);
}


+ (NSDictionary *) mulleStringSystemCallWithArguments:(NSArray *) argv
{
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:nil
                                   workingDirectory:nil
                                standardInputString:nil
                                            options:NSTaskSystemOptionsDefault]);
}



/*
 * conveniences
 */

+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s
                                         workingDirectory:(NSString *) dir
                                              environment:(NSDictionary *) environment
                                      standardInputString:(NSString *) standardInputString
{
   NSArray  *argv;

   argv = [s mulleComponentsSeparatedByWhitespaceWithSingleAndDoubleQuoting];
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:environment
                                   workingDirectory:dir
                                standardInputString:standardInputString
                                            options:NSTaskSystemOptionsDefault]);
}



+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s
                                              environment:(NSDictionary *) environment
                                      standardInputString:(NSString *) standardInputString
{
   NSArray  *argv;

   argv = [s mulleComponentsSeparatedByWhitespaceWithSingleAndDoubleQuoting];
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:environment
                                   workingDirectory:nil
                                standardInputString:standardInputString
                                            options:NSTaskSystemOptionsDefault]);
}


+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s
                                      standardInputString:(NSString *) standardInputString
{
   NSArray  *argv;

   argv = [s mulleComponentsSeparatedByWhitespaceWithSingleAndDoubleQuoting];
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:nil
                                   workingDirectory:nil
                                standardInputString:standardInputString
                                            options:NSTaskSystemOptionsDefault]);
}


+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s
                                              environment:(NSDictionary *) environment
{
   NSArray  *argv;

   argv = [s mulleComponentsSeparatedByWhitespaceWithSingleAndDoubleQuoting];
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:environment
                                   workingDirectory:nil
                                standardInputString:nil
                                            options:NSTaskSystemOptionsDefault]);
}



+ (NSDictionary *) mulleStringSystemCallWithCommandString:(NSString *) s
{
   NSArray  *argv;

   argv = [s mulleComponentsSeparatedByWhitespaceWithSingleAndDoubleQuoting];
   return( [self mulleStringSystemCallWithArguments:argv
                                        environment:nil
                                   workingDirectory:nil
                                standardInputString:nil
                                            options:NSTaskSystemOptionsDefault]);
}


@end
