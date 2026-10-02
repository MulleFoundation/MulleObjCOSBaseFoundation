//
//  NSTask.m
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
// define, that make things POSIXly
#define _XOPEN_SOURCE 700

#import "NSTask.h"

// other files in this library
#import "NSFileManager.h"
#import "NSFileHandle.h"
#import "NSPipe.h"
#import "NSProcessInfo.h"
#import "NSString+CString.h"
#import "NSString+OSBase.h"
#import "NSTask-Private.h"

// other libraries of MulleObjCPosixFoundation

// std-c and dependencies
#ifndef _WIN32
# include <unistd.h>
#endif


@implementation NSTask

+ (NSTask *) launchedTaskWithLaunchPath:(NSString *) path
                              arguments:(NSArray *) arguments
{
   id   task;

   task = [[self new] autorelease];
   [task setLaunchPath:path];
   [task setArguments:arguments];
   [task launch];

   return( task);
}


//
// A child that is still running is let go here, never killed: `dealloc` has
// not waited for one since it existed, and it must not start. mulle-spawn's
// `close` would terminate the child -- `detach` is the call that lets it go.
//
// The price is the one detach documents: nothing will ever wait for that
// process again, so on POSIX it becomes an orphan for init to reap and on
// Windows its exit code is never collected.
//
// It goes first, before the ivars are released, because it is the only one of
// them that is still holding something alive.
//
- (void) dealloc
{
   if( _taskHandle)
   {
      mulle_spawn_detach( (struct mulle_spawn_handle *) _taskHandle);
      mulle_free( _taskHandle);
      _taskHandle = NULL;
   }

   [_standardError release];
   [_standardOutput release];
   [_standardInput release];
   [_environment release];
   [_arguments release];
   [_directoryPath release];
   [_launchPath release];

   [super dealloc];
}


//
// MEMO: missing methods need to be implemented OS specific
//       see -> Darwin
//
- (NSInteger) processIdentifier
{
   return( _pid);
}


- (NSInteger) terminationStatus
{
   return( _terminationStatus);
}


- (void) setArguments:(NSArray *) arguments
{
   [_arguments autorelease];
   _arguments = [arguments copy];
}


- (void) setCurrentDirectoryPath:(NSString *) path
{
   if( path && ! [path isAbsolutePath])
      MulleObjCThrowInvalidArgumentException( @"\"%@\" is not an absolute path", path);

   [_directoryPath autorelease];
   _directoryPath = [path copy];
}


- (void) setEnvironment:(NSDictionary *) dictionary
{
   [_environment autorelease];
   _environment = [dictionary copy];
}


- (void) setLaunchPath:(NSString *) path
{
   [_launchPath autorelease];
   _launchPath = [path copy];
}


- (void) setStandardError:(id) file
{
   [_standardError autorelease];
   _standardError = [file retain];
}


- (void) setStandardInput:(id) file
{
   [_standardInput autorelease];
   _standardInput = [file retain];
}


- (void) setStandardOutput:(id) file
{
   [_standardOutput autorelease];
   _standardOutput = [file retain];
}


- (id) standardError
{
   if( ! _standardError)
      return( [NSFileHandle fileHandleWithStandardError]);
   return( _standardError);
}


- (id) standardInput
{
   if( ! _standardInput)
      return( [NSFileHandle fileHandleWithStandardInput]);
   return( _standardInput);
}


- (id) standardOutput
{
   if( ! _standardOutput)
      return( [NSFileHandle fileHandleWithStandardOutput]);
   return( _standardOutput);
}


- (NSArray *) arguments
{
   return( _arguments);
}


- (NSString *) launchPath
{
   return( _launchPath);
}


- (NSString *) currentDirectoryPath
{
   if( ! _directoryPath)
      return( [[NSFileManager defaultManager] currentDirectoryPath]);
   return( _directoryPath);
}


- (NSDictionary *) environment
{
   // or use NSUserDefaults ??
   if( ! _environment)
      return( [[NSProcessInfo processInfo] environment]);
   return( _environment);
}


/*
 * What happens to the child once it is running. All of this lives here, and
 * not in the platform categories, because there is nothing platform-specific
 * left in it: `_taskHandle` is a mulle-spawn handle, which is the same object
 * on every platform, and `_status` is spawn's own verdict. A platform is only
 * ever asked for `launch`.
 *
 * It used to be written twice, once per category, and the two copies did not
 * agree: `terminationReason` read a signal on one and an unconditional "exit"
 * on the other, which is how a `terminate` came to look like a child that
 * chose to exit 1 on Windows.
 */
- (BOOL) isRunning
{
   if( _status != _NSTaskIsRunning)
      return( NO);

   return( [self mulleCheckIfRunning]);
}


- (void) waitUntilExit
{
   struct mulle_spawn_result   result;

   switch( _status)
   {
   default :
      // it has been waited for, and waiting again would answer with a second
      // fate for a child that only has one
      break;

   case _NSTaskIsIdle :
      MulleObjCThrowInternalInconsistencyException( @"task not started");
      break;

   case _NSTaskIsRunning :
      mulle_spawn_result_init( &result, NULL);

      if( mulle_spawn_wait( _taskHandle, MULLE_SPAWN_NO_TIMEOUT, &result) == -1)
         MulleObjCThrowErrnoException( @"could not wait for the task");

      _terminationStatus = mulleNSTaskStatusFromResult( &result);
      _status            = result.status;
      break;
   }
}


//
// All four of these are no-ops on a task that is not running, which is what
// they have always been. Whether the request reached the child is the answer
// on the two that can report one: `suspend` and `resume` say so, so a child
// that could not be stopped reports NO instead of claiming success.
//
- (void) terminate
{
   if( _status != _NSTaskIsRunning)
      return;

   mulle_spawn_terminate( (struct mulle_spawn_handle *) _taskHandle);
}


- (void) interrupt
{
   if( _status != _NSTaskIsRunning)
      return;

   mulle_spawn_interrupt( (struct mulle_spawn_handle *) _taskHandle);
}


- (BOOL) suspend
{
   if( _status != _NSTaskIsRunning)
      return( NO);

   return( mulle_spawn_suspend( (struct mulle_spawn_handle *) _taskHandle) == 0);
}


- (BOOL) resume
{
   if( _status != _NSTaskIsRunning)
      return( NO);

   return( mulle_spawn_resume( (struct mulle_spawn_handle *) _taskHandle) == 0);
}


- (NSTaskTerminationReason) terminationReason
{
   if( _status == _NSTaskIsIdle || _status == _NSTaskIsRunning)
      MulleObjCThrowInternalInconsistencyException( @"task not terminated yet");

   /*
    * An exit is the only verdict that is an exit. A signal ended the child
    * against its will, and so did mulle-spawn when the caller asked it to --
    * and because the spawn verdict is read rather than translated, those two
    * are one expression instead of a mapping per platform.
    */
   return( _status == mulle_spawn_exited
           ? NSTaskTerminationReasonExit
           : NSTaskTerminationReasonUncaughtSignal);
}

@end


@implementation NSTask( Private)

//
// "Has it stopped by itself" -- the whole of what `isRunning` is built on. The
// timeout is zero, so this reaps a child that has come back and leaves one that
// has not, without waiting for the answer to change.
//
- (BOOL) mulleCheckIfRunning
{
   struct mulle_spawn_result   result;

   switch( _status)
   {
   default :
      // it has been asked before, and a child does not come back twice
      break;

   case _NSTaskIsIdle :
      MulleObjCThrowInternalInconsistencyException( @"task not started");
      break;

   case _NSTaskIsRunning :
      mulle_spawn_result_init( &result, NULL);

      // zero seconds: "has it stopped by itself", and reap it if it has
      if( mulle_spawn_wait( _taskHandle, 0.0, &result) != 1)
         return( YES);   // still running, or nothing to ask about

      _terminationStatus = mulleNSTaskStatusFromResult( &result);
      _status            = result.status;
      break;
   }
   return( NO);
}

@end

