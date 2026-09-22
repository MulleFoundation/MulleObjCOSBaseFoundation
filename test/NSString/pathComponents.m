#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>


static void   probe_components( NSString *path)
{
   NSArray      *components;
   NSUInteger   i, n;

   components = [path pathComponents];
   n          = [components count];

   mulle_printf( "pathComponents<%s>=", [path UTF8String]);
   for( i = 0; i < n; i++)
      mulle_printf( "<%s>", [[components objectAtIndex:i] UTF8String]);
   mulle_printf( "\n");
}


static void   probe_builder( id a, id b, id c)
{
   NSArray      *components;
   NSString     *s;
   NSUInteger   i, n;

   if( c)
      components = [NSArray arrayWithObjects:a, b, c, nil];
   else
      components = [NSArray arrayWithObjects:a, b, nil];

   mulle_printf( "pathWithComponents<");
   n = [components count];
   for( i = 0; i < n; i++)
   {
      if( i)
         mulle_printf( ",");
      mulle_printf( "%s", [[components objectAtIndex:i] UTF8String]);
   }

   s = [NSString pathWithComponents:components];
   mulle_printf( ">=<%s>\n", [s UTF8String]);
}


int   main( int argc, char *argv[])
{
   // leading separator is a component of its own
   probe_components( @"/tmp/scratch.tiff");
   probe_components( @"/");
   probe_components( @"");
   probe_components( @"/a/b/");
   probe_components( @"a/");
   probe_components( @"a//b");
   probe_components( @"//a/b");
   probe_components( @"./x");
   probe_components( @"scratch");

   // builder: root slash is not doubled, empties are not cleaned up
   probe_builder( @"/", @"tmp", nil);
   probe_builder( @"a", @"b", nil);
   probe_builder( @"a", @"", nil);
   probe_builder( @"a", @"", @"b");
   probe_builder( @"", @"tmp", nil);
   probe_builder( @"/", @"", nil);
   return( 0);
}
