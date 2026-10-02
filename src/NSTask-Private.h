//
//  NSTask-Private.h
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
//
//  The class's own state is mulle-spawn's vocabulary, not a second one of its
//  own. A task is idle, running, or it is done -- and "done" is a verdict
//  mulle-spawn has already reached, so it is read rather than translated. The
//  four states that used to be here said the same thing in words of their own,
//  which is how a platform gets to disagree with the library it ports onto:
//  `terminationReason` mapped them, and POSIX and Windows mapped them
//  differently for the very same call.
//
#ifndef mulle_objc_os_base_foundation_nstask_private_h__
#define mulle_objc_os_base_foundation_nstask_private_h__

#include <mulle-spawn/mulle-spawn.h>


/*
 * `_status` is what is known about the child:
 *
 *    mulle_spawn_unknown      nothing was launched
 *    _NSTaskIsRunning         a child is running, and has not been asked yet
 *    mulle_spawn_exited       it stopped by itself, `exit_code` is what it said
 *    mulle_spawn_signalled    POSIX: a signal ended it, `signal_number` names it
 *    mulle_spawn_terminated   mulle-spawn ended it, so it has no code of its own
 *
 * Only `_NSTaskIsRunning` is not one of spawn's, and it has no reason to be:
 * spawn reports on a child it has *looked* at, and an open handle is a child
 * that is still going.
 */
enum
{
   _NSTaskIsIdle     = mulle_spawn_unknown,
   _NSTaskIsRunning  = mulle_spawn_terminated + 1
};


/*
 * The child's fate as `terminationStatus` answers it: the code it exited with,
 * or the number of the signal that ended it. `mulle_spawn_terminated` has
 * neither -- there is no code of the child's own to report when mulle-spawn
 * ended it -- so the answer is 0, and it is `terminationReason` that says it
 * was not an exit.
 */
static inline int   mulleNSTaskStatusFromResult( struct mulle_spawn_result const *result)
{
   switch( result->status)
   {
   case mulle_spawn_exited    : return( result->exit_code);
   case mulle_spawn_signalled : return( result->signal_number);
   default                    : return( 0);
   }
}


#ifdef __OBJC__
@class NSDictionary;


/*
 * `NSDictionary` as the envp mulle-spawn takes: one allocation holding the
 * NULL terminated array of pointers, with a copy of every "NAME=VALUE" string
 * behind it. `allocation` is what the caller has to `mulle_free`.
 *
 * A nil dictionary answers NULL, which is spawn's way of saying "the parent's
 * environment, unchanged" -- so nil and @{} stay different things, as they
 * should be: the first inherits, the second is no environment at all.
 *
 * Shared, because three places want exactly this conversion and none of them
 * wants a different one: the POSIX launch, the Windows launch, and the system
 * call orchestrator. It is the same on all three, so it is written once.
 */
MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL
char   **mulleNSTaskEnvironmentStrings( NSDictionary *environment, void **allocation);


/*
 * The private half of the spawn lifecycle. `NSTask.m` implements it itself,
 * because there is nothing platform-specific left in it: a category is only
 * ever asked for `launch` -- build an argv, an envp and three descriptors, and
 * hand them to mulle-spawn.
 */
@interface NSTask( Private)

- (BOOL) mulleCheckIfRunning;

@end
#endif


#endif
