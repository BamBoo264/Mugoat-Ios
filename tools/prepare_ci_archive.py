"""Build the macOS test-only archive library for the actual runner CPU.
The iPhone XCFramework slice is never modified.
"""
import hashlib,os,platform,shutil,subprocess,sys,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'app/Scripts'))
from safe_extract import extract

def prepare(out):
 out=Path(out).resolve()
 if platform.system()!='Darwin':raise RuntimeError('macOS host required')
 if platform.machine()=='arm64':
  return ROOT/'app/Vendor/libarchive.xcframework/macos-arm64'
 out.mkdir(parents=True,exist_ok=True)
 archive=out/'source.tar.xz'
 archive.write_bytes(urllib.request.urlopen('https://libarchive.org/downloads/libarchive-3.8.9.tar.xz',timeout=120).read())
 if hashlib.sha256(archive.read_bytes()).hexdigest()!='888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde':raise RuntimeError('libarchive source checksum mismatch')
 with tarfile.open(archive) as package:extract(package,out)
 source=out/'libarchive-3.8.9';build=out/'build';prefix=out/'install'
 args=['cmake','-S',str(source),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_ARCHITECTURES=x86_64','-DCMAKE_INSTALL_PREFIX='+str(prefix),'-DBUILD_SHARED_LIBS=OFF']
 for flag in ['TEST','TAR','CPIO','CAT','UNZIP','OPENSSL','MBEDTLS','NETTLE','LIBB2','LZ4','LZO','LZMA','ZSTD','LIBXML2','EXPAT','PCREPOSIX','PCRE2POSIX','ICONV','ACL','XATTR']:
  args+=['-DENABLE_'+flag+'=OFF']
 # ZIP/store/deflate, RAR/RAR5 and BZip2 are exercised by the real mod fixtures.
 # Optional host codecs are excluded to keep test link dependencies explicit.
 subprocess.run(args,check=True)
 subprocess.run(['cmake','--build',str(build),'--parallel','3'],check=True)
 subprocess.run(['cmake','--install',str(build)],check=True)
 shutil.copytree(prefix/'include',out/'Headers',dirs_exist_ok=True)
 shutil.copyfile(prefix/'lib/libarchive.a',out/'libarchive.a')
 return out
if __name__=='__main__':
 result=prepare(sys.argv[1]);print('Host test archive:',result)
 with open(os.environ['GITHUB_ENV'],'a') as f:f.write('PG_HOST_ARCHIVE='+str(result)+'\n')
