#include <stdint.h>
#include <zlib.h>
int gi_inflate_raw(const void *in,uint32_t n,void *out,uint32_t capacity){
 z_stream s={0};s.next_in=(Bytef*)in;s.avail_in=n;s.next_out=out;s.avail_out=capacity;
 if(inflateInit2(&s,-MAX_WBITS)!=Z_OK)return 0;
 int result=inflate(&s,Z_FINISH);int ok=result==Z_STREAM_END&&s.total_out==capacity&&s.total_in==n;inflateEnd(&s);return ok;
}


// Import-time resource repacking only; returns the exact compressed length.
uint32_t gi_deflate_raw(const void *in,uint32_t n,void *out,uint32_t capacity){
 z_stream s={0};s.next_in=(Bytef*)in;s.avail_in=n;s.next_out=out;s.avail_out=capacity;
 if(deflateInit2(&s,Z_DEFAULT_COMPRESSION,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY)!=Z_OK)return 0;
 int result=deflate(&s,Z_FINISH);uint32_t written=result==Z_STREAM_END?(uint32_t)s.total_out:0;deflateEnd(&s);return written;
}

// OpenIV also writes raw DEFLATE followed by its big-endian Adler-32.
// Accept that exact checksum, never arbitrary trailing bytes or partial output.
int gi_inflate_resource(const void *in,uint32_t n,void *out,uint32_t capacity){
 z_stream s={0};s.next_in=(Bytef*)in;s.avail_in=n;s.next_out=out;s.avail_out=capacity;
 if(inflateInit2(&s,-MAX_WBITS)!=Z_OK)return 0;
 int result=inflate(&s,Z_FINISH);int ok=result==Z_STREAM_END&&s.total_out==capacity;
 if(ok&&s.total_in!=n){
  if(n-s.total_in!=4)ok=0;
  else{const unsigned char *tail=(const unsigned char*)in+s.total_in;
   uint32_t expected=(uint32_t)tail[0]<<24|(uint32_t)tail[1]<<16|(uint32_t)tail[2]<<8|tail[3];
   ok=(uint32_t)adler32(adler32(0L,Z_NULL,0),out,capacity)==expected;}
 }
 inflateEnd(&s);return ok;
}
