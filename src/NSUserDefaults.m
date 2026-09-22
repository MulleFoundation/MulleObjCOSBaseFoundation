//
//  NSUserDefaults.m
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
#import "NSUserDefaults.h"

// other files in this library
#import "NSBundle.h"
#import "NSProcessInfo.h"

// std-c and dependencies
#include <stdlib.h>


MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString          *NSGlobalDomain       = @"NSGlobalDomain";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString          *NSArgumentDomain     = @"NSArgumentDomain";

MULLE_OBJC_OS_BASE_FOUNDATION_GLOBAL_VAR
NSString          *NSRegistrationDomain = @"NSRegistrationDomain";

static NSString   *NSApplicationDomain  = @"NSApplicationDomain";


static NSMutableDictionary   *applicationDomain( NSUserDefaults *self);


@implementation NSUserDefaults

+ (NSUserDefaults *) standardUserDefaults
{
   return( [NSUserDefaults sharedInstance]);
}


- (instancetype) init
{
   _lock       = [NSLock new];
   _domains    = [NSMutableDictionary new];
   _searchList = [[NSMutableArray alloc] initWithObjects:NSApplicationDomain, nil];

   // access to both is guarded by _lock
   [_domains mulleSetThreadSafe:YES];
   [_searchList mulleSetThreadSafe:YES];

   [self _loadPersistentDomain:applicationDomain( self)];

   return( self);
}


- (void) dealloc
{
   [_domains release];
   [_searchList release];
   [_lock release];
   [super dealloc];
}


- (id) objectForKey:(id) key
{
   NSDictionary   *domain;
   NSString       *name;
   id             value;

   NSParameterAssert( [key isKindOfClass:[NSString class]]);

   value = nil;
   [_lock lock];
   {
      for( name in _searchList)
      {
         domain = [_domains objectForKey:name];
         value  = [domain objectForKey:key];
         if( value)
         {
            value = [[value retain] autorelease];
            break;
         }
      }
   }
   [_lock unlock];
   return( value);
}


// caller must hold _lock (except during -init)
static NSMutableDictionary   *applicationDomain( NSUserDefaults *self)
{
   NSMutableDictionary   *domain;

   domain = [self->_domains objectForKey:NSApplicationDomain];
   if( ! domain)
   {
      domain = [NSMutableDictionary new];
      [domain mulleSetThreadSafe:YES];  // guarded by _lock
      [self->_domains setObject:domain
                         forKey:NSApplicationDomain];
      [domain release];
   }
   return( domain);
}


- (void) setObject:(id) value
            forKey:(id <NSObject, MulleObjCImmutableCopying>) key
{
   NSParameterAssert( [(NSObject *) key isKindOfClass:[NSString class]]);

   [_lock lock];
   {
      [applicationDomain( self) setObject:value
                                  forKey:key];
   }
   [_lock unlock];
}


- (void) removeObjectForKey:(id) key
{
   NSMutableDictionary  *domain;

   NSParameterAssert( [key isKindOfClass:[NSString class]]);

   [_lock lock];
   {
      domain = [_domains objectForKey:NSApplicationDomain];
      [domain removeObjectForKey:key];
   }
   [_lock unlock];
}


- (void) registerDefaults:(NSDictionary *) defaults
{
   NSMutableDictionary  *dict;

   NSParameterAssert( [defaults isKindOfClass:[NSDictionary class]]);

   [_lock lock];
   {
      dict = [_domains objectForKey:NSRegistrationDomain];
      if( ! dict)
      {
         dict = [NSMutableDictionary dictionary];
         [dict mulleSetThreadSafe:YES];  // guarded by _lock
         [_searchList addObject:NSRegistrationDomain];
      }
      [dict addEntriesFromDictionary:defaults];

      [_domains setObject:dict
                    forKey:NSRegistrationDomain];
   }
   [_lock unlock];
}


- (NSDictionary *) dictionaryRepresentation
{
   NSMutableDictionary   *dict;
   NSDictionary          *domain;
   NSString              *name;
   NSUInteger            i;

   dict = [NSMutableDictionary dictionary];

   [_lock lock];
   {
      // walk from lowest to highest priority, so that higher priority
      // domains override lower ones
      i = [_searchList count];
      while( i--)
      {
         name   = [_searchList objectAtIndex:i];
         domain = [_domains objectForKey:name];
         if( domain)
            [dict addEntriesFromDictionary:domain];
      }
   }
   [_lock unlock];

   return( dict);
}


- (BOOL) synchronize
{
   BOOL   flag;

   [_lock lock];
   {
      flag = [self _savePersistentDomain:[_domains objectForKey:NSApplicationDomain]];
   }
   [_lock unlock];

   return( flag);
}


+ (void) resetStandardUserDefaults
{
   NSUserDefaults   *defaults;

   defaults = [self sharedInstance];

   [defaults->_lock lock];
   {
      [defaults->_domains removeAllObjects];
      [defaults->_searchList removeAllObjects];
      [defaults->_searchList addObject:NSApplicationDomain];
   }
   [defaults->_lock unlock];
}

@end


@implementation NSUserDefaults( Persistent)

@dependency NSUserDefaults;


- (NSString *) _defaultsIdentifier
{
   char       *s;
   NSString   *identifier;

   s = getenv( "MULLE_USER_DEFAULTS_ID");
   if( s && *s)
      return( [NSString stringWithUTF8String:s]);

   identifier = [[NSBundle mainBundle] bundleIdentifier];
   if( ! [identifier length])
      identifier = [[NSProcessInfo processInfo] processName];
   if( ! [identifier length])
      identifier = @"mulle-objc";

   return( identifier);
}


- (BOOL) _loadPersistentDomain:(NSMutableDictionary *) domain
{
   MULLE_C_UNUSED( domain);
   return( NO);
}


- (BOOL) _savePersistentDomain:(NSDictionary *) domain
{
   MULLE_C_UNUSED( domain);
   return( NO);
}

@end


@implementation NSUserDefaults( Conveniences)

static id   objectValueOfClassForKey( NSUserDefaults *self, Class cls, NSString *key)
{
   id   value;

   value = [self objectForKey:key];
   if( ! [value isKindOfClass:cls])
      value = nil;
   return( value);
}


static id   objectValueOfSelectorForKey( NSUserDefaults *self, SEL sel, NSString *key)
{
   id   value;

   value = [self objectForKey:key];
   if( ! [value respondsToSelector:sel])
      value = nil;
   return( value);
}


- (NSInteger) integerForKey:(NSString *) key
{
   return( [objectValueOfSelectorForKey( self, @selector( integerValue), key) integerValue]);
}


- (float) floatForKey:(NSString *) key
{
   return( [objectValueOfSelectorForKey( self, @selector( floatValue), key) floatValue]);
}


- (double) doubleForKey:(NSString *) key
{
   return( [objectValueOfSelectorForKey( self, @selector( doubleValue), key) doubleValue]);
}



- (BOOL) boolForKey:(NSString *) key
{
   return( [objectValueOfSelectorForKey( self, @selector( boolValue), key) boolValue]);
}



- (NSString *) stringForKey:(NSString *) key
{
   return( objectValueOfClassForKey( self, [NSString class], key));
}


- (NSArray *) arrayForKey:(NSString *) key
{
   return( objectValueOfClassForKey( self, [NSArray class], key));
}


- (NSDictionary *) dictionaryForKey:(NSString *) key
{
   return( objectValueOfClassForKey( self, [NSDictionary class], key));
}


- (NSData *) dataForKey:(NSString *) key
{
   return( objectValueOfClassForKey( self, [NSData class], key));
}


- (NSArray *) stringArrayForKey:(NSString *) key
{
   NSArray    *array;
   NSString   *s;
   Class      cls;

   cls   = [NSString class];
   array = objectValueOfClassForKey( self, [NSArray class], key);
   for( s in array)
      if( ! [s isKindOfClass:cls])
         return( nil);
   return( array);
}


- (void) setInteger:(NSInteger)value
             forKey:(NSString *) key
{
   [self setObject:[NSNumber numberWithLongLong:(long long) value]
            forKey:key];
}


- (void) setFloat:(float) value
           forKey:(NSString *) key
{
   [self setObject:[NSNumber numberWithDouble:value]
            forKey:key];
}


- (void) setDouble:(double) value
            forKey:(NSString *) key
{
   [self setObject:[NSNumber numberWithDouble:value]
            forKey:key];
}


- (void) setBool:(BOOL) value
          forKey:(NSString *) key
{
   [self setObject:[NSNumber numberWithBool:value]
            forKey:key];
}

@end


