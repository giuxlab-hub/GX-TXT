// SPDX-License-Identifier: GPL-3.0-or-later
#include "mesh_disk_cache_backend.hpp"
#include <openssl/evp.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <random>
#include <stdexcept>
#include <string_view>
#if !defined(_WIN32)
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace gx3de_backend {
namespace {
constexpr uint64_t default_max_payload=1ull<<30;
constexpr uint32_t schema_version=1;
constexpr size_t header_bytes=136;
constexpr char magic[8]={'G','X','3','D','M','C','H','1'};
static_assert(sizeof(double)==8 && std::numeric_limits<double>::is_iec559,
              "mesh cache requires IEEE 754 binary64");
using Digest=std::array<unsigned char,32>;
using HashContext=std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)>;

HashContext new_hash() {
    HashContext p(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if (!p || EVP_DigestInit_ex(p.get(),EVP_sha256(),nullptr)!=1)
        throw std::runtime_error("cache SHA-256 initialization failed");
    return p;
}
void hash_bytes(EVP_MD_CTX* p,const void* bytes,size_t n) {
    if (n && EVP_DigestUpdate(p,bytes,n)!=1)
        throw std::runtime_error("cache SHA-256 update failed");
}
Digest finish_hash(EVP_MD_CTX* p) {
    Digest d{};unsigned int n=0;
    if (EVP_DigestFinal_ex(p,d.data(),&n)!=1 || n!=d.size())
        throw std::runtime_error("cache SHA-256 finish failed");
    return d;
}
void put_u32(unsigned char* p,uint32_t v) {
    for (int i=0;i<4;++i)p[i]=static_cast<unsigned char>(v>>(8*i));
}
void put_u64(unsigned char* p,uint64_t v) {
    for (int i=0;i<8;++i)p[i]=static_cast<unsigned char>(v>>(8*i));
}
uint32_t get_u32(const unsigned char* p) {
    uint32_t v=0;for (int i=0;i<4;++i)v|=uint32_t(p[i])<<(8*i);return v;
}
uint64_t get_u64(const unsigned char* p) {
    uint64_t v=0;for (int i=0;i<8;++i)v|=uint64_t(p[i])<<(8*i);return v;
}
void hash_u64(EVP_MD_CTX* p,uint64_t v) {unsigned char b[8];put_u64(b,v);hash_bytes(p,b,8);}
void hash_string(EVP_MD_CTX* p,const std::string& s) {
    hash_u64(p,s.size());hash_bytes(p,s.data(),s.size());
}
int nibble(char c) {
    if (c>='0'&&c<='9')return c-'0';
    if (c>='a'&&c<='f')return c-'a'+10;
    return -1;
}
std::string hex_digest(const Digest& d) {
    static constexpr char hex[]="0123456789abcdef";
    std::string out(64,'0');
    for (size_t i=0;i<d.size();++i){out[i*2]=hex[d[i]>>4];out[i*2+1]=hex[d[i]&15];}
    return out;
}
struct PreparedKey {Digest key,source;std::string filename;};
PreparedKey prepare(const MeshDiskCacheKey& key) {
    if (key.namespace_utf8.empty() || key.namespace_utf8.size()>255 ||
        key.importer_version.empty() || key.importer_version.size()>255 ||
        key.source_sha256_hex.size()!=64 || key.format<1 || key.format>5)
        throw std::invalid_argument("invalid mesh cache key");
    PreparedKey out{};
    for (size_t i=0;i<32;++i) {
        const int hi=nibble(key.source_sha256_hex[i*2]);
        const int lo=nibble(key.source_sha256_hex[i*2+1]);
        if (hi<0||lo<0) throw std::invalid_argument("source SHA-256 must be lowercase hexadecimal");
        out.source[i]=static_cast<unsigned char>((hi<<4)|lo);
    }
    auto hash=new_hash();
    static constexpr char tag[]="GX3DE_MESH_DISK_CACHE_v1";
    hash_bytes(hash.get(),tag,sizeof(tag));
    hash_string(hash.get(),key.namespace_utf8);
    hash_bytes(hash.get(),out.source.data(),out.source.size());
    hash_u64(hash.get(),key.format);
    hash_string(hash.get(),key.importer_version);
    out.key=finish_hash(hash.get());
    out.filename=hex_digest(out.key)+".gx3dm";
    return out;
}
uint64_t checked_payload_size(const MeshData& mesh,uint64_t max_bytes) {
    if (mesh.vertices.empty()||mesh.triangles.empty()||
        mesh.vertices.size()>UINT32_MAX||mesh.triangles.size()%3)
        throw std::invalid_argument("mesh cache input must contain indexed triangles");
    if (mesh.vertices.size()>UINT64_MAX/24 || mesh.triangles.size()>UINT64_MAX/4)
        throw std::invalid_argument("mesh cache payload size overflow");
    const uint64_t a=uint64_t(mesh.vertices.size())*24;
    const uint64_t b=uint64_t(mesh.triangles.size())*4;
    if (a>UINT64_MAX-b || a+b>max_bytes || a+b>uint64_t(INT64_MAX)-header_bytes)
        throw std::invalid_argument("mesh cache payload exceeds configured byte limit");
    for (auto v:mesh.vertices)
        if (!std::isfinite(v.x)||!std::isfinite(v.y)||!std::isfinite(v.z))
            throw std::invalid_argument("mesh cache contains a non-finite vertex");
    for (auto index:mesh.triangles)
        if (index>=mesh.vertices.size()) throw std::invalid_argument("mesh cache contains an invalid index");
    return a+b;
}
template<class Consume> void serialized_payload(const MeshData& mesh,Consume consume) {
    std::array<unsigned char,65536> buffer{};size_t used=0;
    auto append=[&](const unsigned char* p,size_t n){
        if (used+n>buffer.size()){consume(buffer.data(),used);used=0;}
        std::memcpy(buffer.data()+used,p,n);used+=n;
    };
    unsigned char bytes[8];
    for (auto v:mesh.vertices)for(double coordinate:{v.x,v.y,v.z}) {
        uint64_t bits=0;std::memcpy(&bits,&coordinate,8);put_u64(bytes,bits);append(bytes,8);
    }
    for (auto index:mesh.triangles){put_u32(bytes,index);append(bytes,4);}
    if (used)consume(buffer.data(),used);
}
Digest payload_sha256(const MeshData& mesh) {
    auto ctx=new_hash();
    serialized_payload(mesh,[&](const unsigned char* p,size_t n){hash_bytes(ctx.get(),p,n);});
    return finish_hash(ctx.get());
}
std::array<unsigned char,header_bytes> make_header(const PreparedKey& key,
             const MeshData& mesh,uint64_t payload_size,const Digest& payload_sha) {
    std::array<unsigned char,header_bytes> h{};
    std::memcpy(h.data(),magic,8);
    put_u32(h.data()+8,schema_version);put_u32(h.data()+12,1); // mesh geometry type
    put_u64(h.data()+16,mesh.vertices.size());
    put_u64(h.data()+24,mesh.triangles.size());
    put_u64(h.data()+32,payload_size);
    std::memcpy(h.data()+40,key.key.data(),32);
    std::memcpy(h.data()+72,payload_sha.data(),32);
    std::memcpy(h.data()+104,key.source.data(),32);
    return h;
}
#if !defined(_WIN32)
struct Fd {
    int value=-1;
    explicit Fd(int v=-1):value(v){}
    Fd(const Fd&)=delete;Fd& operator=(const Fd&)=delete;
    Fd(Fd&& other) noexcept:value(other.value){other.value=-1;}
    Fd& operator=(Fd&& other) noexcept {if(this!=&other){if(value>=0)::close(value);value=other.value;other.value=-1;}return *this;}
    ~Fd(){if(value>=0)::close(value);}
};
struct Failure:std::runtime_error {
    MeshDiskCacheLoad status;
    Failure(MeshDiskCacheLoad kind,const std::string& message):std::runtime_error(message),status(kind){}
};
std::string system_error(const char* action) {
    return std::string(action)+": "+std::strerror(errno);
}
/* Walk rather than canonicalize the caller's root; reject every symlink and
 * parent traversal component, including symlinks inside otherwise valid paths. */
Fd open_root(const char* root) {
    if (!root||!*root)throw Failure(MeshDiskCacheLoad::Unsafe,"empty cache root");
    const std::string path(root);
    if (path.size()>4096)throw Failure(MeshDiskCacheLoad::Unsafe,"cache root exceeds path limit");
    Fd dir(::open(path.front()=='/'?"/":".",O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW));
    if (dir.value<0)throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot open cache root base"));
    size_t pos=0;
    while(pos<path.size()) {
        const size_t slash=path.find('/',pos);
        const std::string part=path.substr(pos,slash==std::string::npos?std::string::npos:slash-pos);
        pos=slash==std::string::npos?path.size():slash+1;
        if(part.empty()||part==".")continue;
        if(part=="..")throw Failure(MeshDiskCacheLoad::Unsafe,"cache root parent traversal is forbidden");
        Fd next(::openat(dir.value,part.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW));
        if(next.value<0 && errno==ENOENT) {
            if(::mkdirat(dir.value,part.c_str(),0700)!=0 && errno!=EEXIST)
                throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot create cache directory"));
            next=Fd(::openat(dir.value,part.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW));
        }
        if(next.value<0)throw Failure((errno==ELOOP||errno==ENOTDIR)?MeshDiskCacheLoad::Unsafe:MeshDiskCacheLoad::IoError,
                                      system_error("unsafe or inaccessible cache directory"));
        dir=std::move(next);
    }
    return dir;
}
bool existing_regular_or_missing(int dir,const std::string& name) {
    struct stat st{};
    if(::fstatat(dir,name.c_str(),&st,AT_SYMLINK_NOFOLLOW)==0)return S_ISREG(st.st_mode);
    if(errno==ENOENT)return true;
    throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot inspect cache entry"));
}
void write_all(int fd,const unsigned char* p,size_t n) {
    while(n){const ssize_t count=::write(fd,p,n);if(count<0&&errno==EINTR)continue;
        if(count<=0)throw Failure(MeshDiskCacheLoad::IoError,system_error("cache write failed"));
        p+=count;n-=size_t(count);}
}
void read_all(int fd,unsigned char* p,size_t n) {
    while(n){const ssize_t count=::read(fd,p,n);if(count<0&&errno==EINTR)continue;
        if(count<=0)throw Failure(MeshDiskCacheLoad::Invalid,"cache entry is truncated");
        p+=count;n-=size_t(count);}
}
class PayloadReader {
    int fd;uint64_t unread,consumed=0;size_t first=0,last=0;
    std::array<unsigned char,65536> buffer{};
    HashContext hash=new_hash();
public:
    PayloadReader(int file,uint64_t bytes):fd(file),unread(bytes){}
    const unsigned char* take(size_t n) {
        if(n>buffer.size()||n>unread+(last-first))
            throw Failure(MeshDiskCacheLoad::Invalid,"cache payload length mismatch");
        while(last-first<n){
            if(first){std::memmove(buffer.data(),buffer.data()+first,last-first);last-=first;first=0;}
            if(!unread)throw Failure(MeshDiskCacheLoad::Invalid,"cache payload is truncated");
            const size_t want=size_t(std::min<uint64_t>(buffer.size()-last,unread));
            const ssize_t count=::read(fd,buffer.data()+last,want);
            if(count<0&&errno==EINTR)continue;
            if(count<=0)throw Failure(MeshDiskCacheLoad::Invalid,"cache payload read failed");
            hash_bytes(hash.get(),buffer.data()+last,size_t(count));
            last+=size_t(count);unread-=uint64_t(count);
        }
        const auto* p=buffer.data()+first;first+=n;consumed+=n;return p;
    }
    Digest finish(uint64_t expected) {
        if(consumed!=expected||unread||first!=last)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache payload has extra or missing bytes");
        return finish_hash(hash.get());
    }
};
std::string temp_name(const std::string& filename) {
    std::random_device random;
    unsigned char bytes[16];
    for(auto& b:bytes)b=static_cast<unsigned char>(random());
    static constexpr char hex[]="0123456789abcdef";
    std::string suffix;
    suffix.reserve(32);
    for(auto b:bytes){suffix+=hex[b>>4];suffix+=hex[b&15];}
    return "."+filename+"."+suffix+".tmp";
}
#endif
} // namespace

std::string mesh_disk_cache_filename(const MeshDiskCacheKey& key) {
    try{return prepare(key).filename;}catch(...){return {};}
}
MeshDiskCacheLoad mesh_disk_cache_load(const char* root,const MeshDiskCacheKey& key,
                                      MeshData& output,std::string& error,uint64_t max_bytes) {
#if defined(_WIN32)
    (void)root;(void)key;(void)output;(void)max_bytes;
    error="Windows disk cache backend is not implemented";return MeshDiskCacheLoad::IoError;
#else
    try {
        const auto prepared=prepare(key);
        Fd dir=open_root(root);
        struct stat entry{};
        if(::fstatat(dir.value,prepared.filename.c_str(),&entry,AT_SYMLINK_NOFOLLOW)!=0){
            if(errno==ENOENT){error.clear();return MeshDiskCacheLoad::Miss;}
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot inspect cache entry"));
        }
        if(!S_ISREG(entry.st_mode))throw Failure(MeshDiskCacheLoad::Unsafe,"cache entry is not a regular file");
        Fd file(::openat(dir.value,prepared.filename.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW));
        if(file.value<0)throw Failure(errno==ELOOP?MeshDiskCacheLoad::Unsafe:MeshDiskCacheLoad::IoError,
                                     system_error("cannot open cache entry"));
        if(::fstat(file.value,&entry)!=0)throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot stat cache entry"));
        if(!S_ISREG(entry.st_mode))throw Failure(MeshDiskCacheLoad::Unsafe,"cache entry changed type");
        if(entry.st_size<0||uint64_t(entry.st_size)<header_bytes)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache header is incomplete");
        std::array<unsigned char,header_bytes> header{};
        read_all(file.value,header.data(),header.size());
        if(std::memcmp(header.data(),magic,8)!=0||get_u32(header.data()+8)!=schema_version||
           get_u32(header.data()+12)!=1)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache schema or geometry type mismatch");
        if(std::memcmp(header.data()+40,prepared.key.data(),32)!=0||
           std::memcmp(header.data()+104,prepared.source.data(),32)!=0)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache identity mismatch");
        const uint64_t vertices=get_u64(header.data()+16);
        const uint64_t indices=get_u64(header.data()+24);
        const uint64_t bytes=get_u64(header.data()+32);
        const uint64_t limit=max_bytes?max_bytes:default_max_payload;
        if(!vertices||vertices>UINT32_MAX||!indices||indices%3||
           vertices>UINT64_MAX/24||indices>UINT64_MAX/4||
           vertices*24>UINT64_MAX-indices*4||
           bytes!=vertices*24+indices*4||bytes>limit||bytes>uint64_t(INT64_MAX)-header_bytes||
           uint64_t(entry.st_size)!=header_bytes+bytes)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache counts or byte length are invalid");
        MeshData mesh;mesh.vertices.reserve(size_t(vertices));mesh.triangles.reserve(size_t(indices));
        PayloadReader reader(file.value,bytes);
        for(uint64_t i=0;i<vertices;++i){
            gx3de_vec3 v{};double* coord[3]={&v.x,&v.y,&v.z};
            for(auto p:coord){const uint64_t bits=get_u64(reader.take(8));std::memcpy(p,&bits,8);
                if(!std::isfinite(*p))throw Failure(MeshDiskCacheLoad::Invalid,"cache has non-finite vertex");}
            mesh.vertices.push_back(v);
        }
        for(uint64_t i=0;i<indices;++i){const uint32_t id=get_u32(reader.take(4));
            if(id>=vertices)throw Failure(MeshDiskCacheLoad::Invalid,"cache has invalid triangle index");
            mesh.triangles.push_back(id);
        }
        const Digest sha=reader.finish(bytes);
        if(std::memcmp(sha.data(),header.data()+72,32)!=0)
            throw Failure(MeshDiskCacheLoad::Invalid,"cache payload SHA-256 mismatch");
        output=std::move(mesh);error.clear();return MeshDiskCacheLoad::Hit;
    }catch(const Failure& e){error=e.what();return e.status;}
     catch(const std::invalid_argument& e){error=e.what();return MeshDiskCacheLoad::Unsafe;}
     catch(const std::bad_alloc&){error="out of memory reading mesh cache";return MeshDiskCacheLoad::IoError;}
     catch(const std::exception& e){error=e.what();return MeshDiskCacheLoad::IoError;}
#endif
}
bool mesh_disk_cache_store(const char* root,const MeshDiskCacheKey& key,
                           const MeshData& mesh,std::string& error,uint64_t max_bytes) {
#if defined(_WIN32)
    (void)root;(void)key;(void)mesh;(void)max_bytes;
    error="Windows disk cache backend is not implemented";return false;
#else
    Fd dir;std::string temporary;
    try {
        const auto prepared=prepare(key);
        const uint64_t limit=max_bytes?max_bytes:default_max_payload;
        const uint64_t bytes=checked_payload_size(mesh,limit);
        const Digest payload_hash=payload_sha256(mesh);
        const auto header=make_header(prepared,mesh,bytes,payload_hash);
        dir=open_root(root);
        if(!existing_regular_or_missing(dir.value,prepared.filename))
            throw Failure(MeshDiskCacheLoad::Unsafe,"cache entry is not a regular file");
        Fd file;
        for(int attempt=0;attempt<8;++attempt){
            temporary=temp_name(prepared.filename);
            file=Fd(::openat(dir.value,temporary.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0600));
            if(file.value>=0)break;
            if(errno!=EEXIST)throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot create cache temporary file"));
        }
        if(file.value<0)throw Failure(MeshDiskCacheLoad::IoError,"cannot reserve a cache temporary file");
        write_all(file.value,header.data(),header.size());
        serialized_payload(mesh,[&](const unsigned char* p,size_t n){write_all(file.value,p,n);});
        if(::fsync(file.value)!=0)throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot sync cache temporary file"));
        file=Fd();
        if(!existing_regular_or_missing(dir.value,prepared.filename))
            throw Failure(MeshDiskCacheLoad::Unsafe,"cache entry became non-regular");
        if(::renameat(dir.value,temporary.c_str(),dir.value,prepared.filename.c_str())!=0)
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot publish cache entry"));
        temporary.clear();
        if(::fsync(dir.value)!=0)throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot sync cache directory"));
        error.clear();return true;
    }catch(const std::exception& e){
        if(dir.value>=0&&!temporary.empty())::unlinkat(dir.value,temporary.c_str(),0);
        error=e.what();return false;
    }
#endif
}

namespace {
constexpr uint64_t scientific_max_payload=256ull*1024*1024;
constexpr size_t scientific_header_bytes=88;
constexpr char scientific_magic[8]={'G','X','3','D','S','C','H','1'};
struct PreparedScientificKey {Digest hash;std::string filename;};
PreparedScientificKey prepare_scientific(const ScientificDiskCacheKey& key) {
    if(key.namespace_utf8.empty()||key.namespace_utf8.size()>255||
       key.operation_sha256_hex.size()!=64)
        throw std::invalid_argument("invalid scientific cache key");
    Digest operation{};
    for(size_t i=0;i<32;++i){
        const int hi=nibble(key.operation_sha256_hex[2*i]);
        const int lo=nibble(key.operation_sha256_hex[2*i+1]);
        if(hi<0||lo<0)
            throw std::invalid_argument("scientific operation SHA-256 must be lowercase hexadecimal");
        operation[i]=static_cast<unsigned char>((hi<<4)|lo);
    }
    auto hash=new_hash();
    static constexpr char tag[]="GX3DE_SCIENTIFIC_DISK_CACHE_v1";
    hash_bytes(hash.get(),tag,sizeof(tag));
    hash_string(hash.get(),key.namespace_utf8);
    hash_bytes(hash.get(),operation.data(),operation.size());
    auto digest=finish_hash(hash.get());
    return {digest,hex_digest(digest)+".gx3ds"};
}
std::array<unsigned char,scientific_header_bytes> scientific_header(
    const PreparedScientificKey& key,const std::string& payload) {
    auto hash=new_hash();hash_bytes(hash.get(),payload.data(),payload.size());
    const auto payload_hash=finish_hash(hash.get());
    std::array<unsigned char,scientific_header_bytes> header{};
    std::memcpy(header.data(),scientific_magic,8);
    put_u32(header.data()+8,1);put_u32(header.data()+12,1);
    put_u64(header.data()+16,payload.size());
    std::memcpy(header.data()+24,key.hash.data(),32);
    std::memcpy(header.data()+56,payload_hash.data(),32);
    return header;
}
} // namespace

std::string scientific_disk_cache_filename(const ScientificDiskCacheKey& key) {
    try{return prepare_scientific(key).filename;}catch(...){return {};}
}
MeshDiskCacheLoad scientific_disk_cache_load(const char* root,
    const ScientificDiskCacheKey& key,std::string& payload,std::string& error) {
#if defined(_WIN32)
    (void)root;(void)key;(void)payload;
    error="Windows scientific disk cache is not implemented";return MeshDiskCacheLoad::IoError;
#else
    try {
        const auto prepared=prepare_scientific(key);
        Fd dir=open_root(root);
        struct stat entry{};
        if(::fstatat(dir.value,prepared.filename.c_str(),&entry,AT_SYMLINK_NOFOLLOW)!=0){
            if(errno==ENOENT){error.clear();return MeshDiskCacheLoad::Miss;}
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot inspect scientific cache entry"));
        }
        if(!S_ISREG(entry.st_mode))
            throw Failure(MeshDiskCacheLoad::Unsafe,"scientific cache entry is not regular");
        Fd file(::openat(dir.value,prepared.filename.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW));
        if(file.value<0)
            throw Failure(errno==ELOOP?MeshDiskCacheLoad::Unsafe:MeshDiskCacheLoad::IoError,
                          system_error("cannot open scientific cache entry"));
        if(::fstat(file.value,&entry)!=0||!S_ISREG(entry.st_mode))
            throw Failure(MeshDiskCacheLoad::Unsafe,"scientific cache entry changed type");
        if(entry.st_size<0||uint64_t(entry.st_size)<scientific_header_bytes)
            throw Failure(MeshDiskCacheLoad::Invalid,"scientific cache header is incomplete");
        std::array<unsigned char,scientific_header_bytes> header{};
        read_all(file.value,header.data(),header.size());
        if(std::memcmp(header.data(),scientific_magic,8)!=0||
           get_u32(header.data()+8)!=1||get_u32(header.data()+12)!=1||
           std::memcmp(header.data()+24,prepared.hash.data(),32)!=0)
            throw Failure(MeshDiskCacheLoad::Invalid,"scientific cache header or key mismatch");
        const uint64_t bytes=get_u64(header.data()+16);
        if(!bytes||bytes>scientific_max_payload||
           uint64_t(entry.st_size)!=scientific_header_bytes+bytes)
            throw Failure(MeshDiskCacheLoad::Invalid,"scientific cache length mismatch");
        std::string read(size_t(bytes),'\0');
        read_all(file.value,reinterpret_cast<unsigned char*>(&read[0]),read.size());
        auto hash=new_hash();hash_bytes(hash.get(),read.data(),read.size());
        const auto actual=finish_hash(hash.get());
        if(std::memcmp(actual.data(),header.data()+56,32)!=0)
            throw Failure(MeshDiskCacheLoad::Invalid,"scientific cache payload SHA-256 mismatch");
        payload=std::move(read);error.clear();return MeshDiskCacheLoad::Hit;
    }catch(const Failure& e){error=e.what();return e.status;}
     catch(const std::invalid_argument& e){error=e.what();return MeshDiskCacheLoad::Unsafe;}
     catch(const std::bad_alloc&){error="out of memory reading scientific cache";return MeshDiskCacheLoad::IoError;}
     catch(const std::exception& e){error=e.what();return MeshDiskCacheLoad::IoError;}
#endif
}
bool scientific_disk_cache_store(const char* root,const ScientificDiskCacheKey& key,
    const std::string& payload,std::string& error) {
#if defined(_WIN32)
    (void)root;(void)key;(void)payload;
    error="Windows scientific disk cache is not implemented";return false;
#else
    Fd dir;std::string temporary;
    try {
        if(payload.empty()||payload.size()>scientific_max_payload)
            throw std::invalid_argument("scientific cache payload exceeds 256 MiB limit");
        const auto prepared=prepare_scientific(key);
        const auto header=scientific_header(prepared,payload);
        dir=open_root(root);
        if(!existing_regular_or_missing(dir.value,prepared.filename))
            throw Failure(MeshDiskCacheLoad::Unsafe,"scientific cache entry is not regular");
        Fd file;
        for(int attempt=0;attempt<8;++attempt){
            temporary=temp_name(prepared.filename);
            file=Fd(::openat(dir.value,temporary.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,0600));
            if(file.value>=0)break;
            if(errno!=EEXIST)
                throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot create scientific cache temporary file"));
        }
        if(file.value<0)
            throw Failure(MeshDiskCacheLoad::IoError,"cannot reserve scientific cache temporary file");
        write_all(file.value,header.data(),header.size());
        write_all(file.value,reinterpret_cast<const unsigned char*>(payload.data()),payload.size());
        if(::fsync(file.value)!=0)
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot sync scientific cache temporary file"));
        file=Fd();
        if(!existing_regular_or_missing(dir.value,prepared.filename))
            throw Failure(MeshDiskCacheLoad::Unsafe,"scientific cache entry became non-regular");
        if(::renameat(dir.value,temporary.c_str(),dir.value,prepared.filename.c_str())!=0)
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot publish scientific cache entry"));
        temporary.clear();
        if(::fsync(dir.value)!=0)
            throw Failure(MeshDiskCacheLoad::IoError,system_error("cannot sync scientific cache directory"));
        error.clear();return true;
    }catch(const std::exception& e){
        if(dir.value>=0&&!temporary.empty())::unlinkat(dir.value,temporary.c_str(),0);
        error=e.what();return false;
    }
#endif
}
} // namespace gx3de_backend
