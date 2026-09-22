#import <MulleObjCOSBaseFoundation/MulleObjCOSBaseFoundation.h>


static void   show( NSString *path, NSString *result)
{
   mulle_printf( "<%s>=<%s>\n", [path UTF8String], [result UTF8String]);
}


int   main( int argc, char *argv[])
{
   // lastPathComponent
   show( @"/tmp/scratch.tiff", [@"/tmp/scratch.tiff" lastPathComponent]);
   show( @"/tmp/scratch",      [@"/tmp/scratch" lastPathComponent]);
   show( @"/tmp/",             [@"/tmp/" lastPathComponent]);
   show( @"scratch///",        [@"scratch///" lastPathComponent]);
   show( @"/",                 [@"/" lastPathComponent]);
   show( @"/tmp",              [@"/tmp" lastPathComponent]);
   show( @"a/b/",              [@"a/b/" lastPathComponent]);
   show( @"scratch",           [@"scratch" lastPathComponent]);

   // stringByDeletingLastPathComponent
   show( @"/tmp/scratch.tiff", [@"/tmp/scratch.tiff" stringByDeletingLastPathComponent]);
   show( @"/tmp/lock/",        [@"/tmp/lock/" stringByDeletingLastPathComponent]);
   show( @"/tmp/",             [@"/tmp/" stringByDeletingLastPathComponent]);
   show( @"/tmp",              [@"/tmp" stringByDeletingLastPathComponent]);
   show( @"/",                 [@"/" stringByDeletingLastPathComponent]);
   show( @"scratch.tiff",      [@"scratch.tiff" stringByDeletingLastPathComponent]);
   show( @"a/b/",              [@"a/b/" stringByDeletingLastPathComponent]);

   // pathExtension
   show( @"/tmp/scratch.tiff", [@"/tmp/scratch.tiff" pathExtension]);
   show( @".scratch.tiff",     [@".scratch.tiff" pathExtension]);
   show( @"/tmp/scratch",      [@"/tmp/scratch" pathExtension]);
   show( @"/tmp/",             [@"/tmp/" pathExtension]);
   show( @"/tmp/scratch..tiff", [@"/tmp/scratch..tiff" pathExtension]);
   show( @".tiff",             [@".tiff" pathExtension]);
   show( @"scratch.",          [@"scratch." pathExtension]);

   // stringByDeletingPathExtension
   show( @"/tmp/scratch.tiff", [@"/tmp/scratch.tiff" stringByDeletingPathExtension]);
   show( @"/tmp/",             [@"/tmp/" stringByDeletingPathExtension]);
   show( @"scratch.bundle/",   [@"scratch.bundle/" stringByDeletingPathExtension]);
   show( @"scratch..tiff",     [@"scratch..tiff" stringByDeletingPathExtension]);
   show( @".tiff",             [@".tiff" stringByDeletingPathExtension]);
   show( @"/",                 [@"/" stringByDeletingPathExtension]);
   return( 0);
}
