//
//  NSProcessInfo.m
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

#import "NSProcessInfo.h"

// other files in this library

// other libraries of MulleObjCPosixFoundation

// std-c and dependencies
#include <time.h>


@implementation NSProcessInfo

+ (NSProcessInfo *) processInfo
{
   return( [self sharedInstance]);
}


- (instancetype) init
{
   // recursive, because some platform lazy initializers call back into
   // other lazy accessors (e.g. FreeBSD's _executablePath -> arguments)
   _lock = [NSRecursiveLock new];
   return( self);
}


- (void) dealloc
{
   [_arguments release];
   [_environment release];
   [_executablePath release];
   [_lock release];

   [super dealloc];
}


- (NSArray *) arguments
{
   NSArray   *value;

   [_lock lock];
   value = [[_arguments retain] autorelease];
   [_lock unlock];

   return( value);
}


- (NSDictionary *) environment
{
   NSDictionary   *value;

   [_lock lock];
   value = [[_environment retain] autorelease];
   [_lock unlock];

   return( value);
}


- (NSString *) globallyUniqueString
{
   static NSUIntegerAtomic   counter;
   NSUInteger                old;
   NSUInteger                value;

   do
   {
      old   = NSUIntegerAtomicGet( &counter);
      value = old + 1;
   }
   while( NSUIntegerAtomicUpdate( &counter, value) != old);

   return( [NSString stringWithFormat:@"%@-%ld-%ld-%lu",
                    [self hostName],
                    (long) [self processIdentifier],
                    (long) time( NULL),
                    (unsigned long) value]);
}

@end

