#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>


static void   probe( NSString *base, NSString *component)
{
   mulle_printf( "append<%s,%s>=<%s>\n",
                 [base UTF8String],
                 [component UTF8String],
                 [[base stringByAppendingPathComponent:component] UTF8String]);
}


int   main( int argc, char *argv[])
{
   probe( @"a",   @"b");
   probe( @"a/",  @"b");
   probe( @"/a",  @"b");
   probe( @"/a/", @"b");
   probe( @"a",   @"b/");
   probe( @"a/",  @"b/");
   probe( @"/a",  @"b/");
   probe( @"/a/", @"b/");
   probe( @"a",   @"/b");
   probe( @"a/",  @"/b");
   probe( @"/a",  @"/b");
   probe( @"/a/", @"/b");
   probe( @"a",   @"/b/");
   probe( @"a/",  @"/b/");
   probe( @"/a",  @"/b/");
   probe( @"/a/", @"/b/");
   return( 0);
}
