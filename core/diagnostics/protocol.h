// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
namespace gxdiag {
  constexpr size_t maxPayload=32768, maxPacket=57344, maxLine=65536;
  constexpr uint64_t defaultFile=10485760, defaultRing=8388608;
  constexpr uint64_t sharedMagic=0x4758444941470001ULL;
  constexpr const char* base="stderr-diagnostics";
  inline constexpr const char* originKeys[]={
    "source","component","module_id","viewer_id","job_id","api_id","operation","process_id","stream","severity","chunk_id","chunk_index"
  };
  enum Phase {
    Starting=1, Running=2, Failed=3
  };
#define GXDIAG_COUNTERS(X) \
 X(accepted_records) X(accepted_bytes) X(transport_dropped_records) X(transport_dropped_bytes) \
 X(received_records) X(received_bytes) X(ring_dropped_records) X(ring_dropped_bytes) \
 X(disk_dropped_records) X(disk_dropped_bytes) X(written_records) X(written_bytes) \
 X(queue_records) X(queue_bytes) X(queue_high_water_bytes) X(recovered_tail_bytes) X(retention_evicted_files) X(retention_evicted_bytes) X(ipc_rejected_records) X(ipc_rejected_wire_bytes) X(producer_attachments) X(producer_failed_records) X(producer_failed_bytes)
  struct Shared {
    std::atomic<uint64_t> magic{sharedMagic}, generation{0}, producer_inflight{0};
    std::atomic<uint64_t> phase{Starting}, accepting{0}, error_serial{0};
#define GXDIAG_FIELD(n) std::atomic<uint64_t> n{0};
    GXDIAG_COUNTERS(GXDIAG_FIELD)
#undef GXDIAG_FIELD
    std::atomic<unsigned char> error[512]{};
    std::atomic_flag error_lock=ATOMIC_FLAG_INIT;
  };
  static_assert(std::atomic<uint64_t>::is_always_lock_free,"Shared counters require lock-free atomics");
  inline void errorLiteral(Shared* s,const char* message) noexcept {
    if(s->error_lock.test_and_set())return;
    s->error_serial.fetch_add(1);size_t n=strnlen(message,511);
    for(size_t i=0;i<512;++i)s->error[i].store(i<n?static_cast<unsigned char>(message[i]):0);
    s->error_serial.fetch_add(1);s->error_lock.clear();
  }
  inline void error(Shared* s,const std::string& message) {
    if(s->error_lock.test_and_set())return;
    s->error_serial.fetch_add(1);
    for(size_t i=0;i<512;++i) s->error[i].store(i<message.size()?static_cast<unsigned char>(message[i]):0);
    s->error_serial.fetch_add(1);
    s->error_lock.clear();
  }
  inline std::string errorText(Shared* s) {
    for(int attempt=0;attempt<3;++attempt) {
      auto before=s->error_serial.load();
      if(before&1) continue;
      std::string r;
      for(size_t i=0;i<512;++i) {
        auto c=s->error[i].load();
        if(!c) break;
        r.push_back(char(c));
      }
      if(before==s->error_serial.load()) return r;
    }
    return "Diagnostic error status is being updated";
  }
  inline std::string systemError(const std::string& operation) {
    return operation+": "+strerror(errno);
  }
  struct Fd {
    int n=-1;
    explicit Fd(int f=-1):n(f){}
    ~Fd(){
      if(n>=0) close(n);
    }
    Fd(const Fd&)=delete;
    Fd& operator=(const Fd&)=delete;
    Fd(Fd&& o) noexcept:n(o.n){
      o.n=-1;
    }
    Fd& operator=(Fd&& o) noexcept {
      if(n>=0)close(n);
      n=o.n;
      o.n=-1;
      return *this;
    }
    int release(){
      int r=n;
      n=-1;
      return r;
    }
  };
  struct RecordLock {
    int fd=-1;
    explicit RecordLock(int file,short type):fd(file){
      if(fd<0)return;
      struct flock request{};
      request.l_type=type;
      request.l_whence=SEEK_SET;
      request.l_start=0;
      request.l_len=1;
      while(fcntl(fd,F_SETLKW,&request)){
        if(errno==EINTR)continue;
        throw std::runtime_error(systemError("Lock diagnostics rotation snapshot"));
      }
    }
    ~RecordLock(){
      if(fd>=0){
        struct flock request{};
        request.l_type=F_UNLCK;
        request.l_whence=SEEK_SET;
        request.l_len=1;
        fcntl(fd,F_SETLK,&request);
      }
    }
  };
  inline void requireFile(int fd) {
    struct stat st{};
    if(fstat(fd,&st)||!S_ISREG(st.st_mode)||st.st_uid!=getuid()||st.st_nlink!=1||(st.st_mode&0022)) throw std::runtime_error("Managed diagnostics file must be a regular, singly linked user-owned file without group/world write access");
  }
  struct DirectoryMissing:std::runtime_error{
    using std::runtime_error::runtime_error;
  };
  inline Fd openDirectory(const std::string& path,bool create) {
    if(path.empty()||path[0]!='/'||path.size()>4096) throw std::runtime_error("Log directory must be an absolute path");
    Fd current(open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC));
    std::vector<std::string> parts;
    size_t p=1;
    while(p<path.size()) {
      size_t e=path.find('/',p);
      if(e==std::string::npos)e=path.size();
      auto part=path.substr(p,e-p);
      p=e+1;
      if(part.empty()||part==".")continue;
      if(part=="..")throw std::runtime_error("Parent traversal is forbidden in log directory");
      parts.push_back(part);
    }
    if(parts.empty()) throw std::runtime_error("Root cannot be a log directory");
    for(size_t i=0;i<parts.size();++i) {
      int n=openat(current.n,parts[i].c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
      bool privateNew=false;
      if(n<0&&errno==ENOENT&&create) {
        if(mkdirat(current.n,parts[i].c_str(),0700)&&errno!=EEXIST)throw std::runtime_error(systemError("Create log directory"));
        privateNew=true;
        n=openat(current.n,parts[i].c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
      }
      if(n<0){
        if(errno==ENOENT)throw DirectoryMissing(systemError("Open log directory component"));
        throw std::runtime_error(systemError("Open log directory component"));
      }
      if(privateNew) {
        struct stat component{};
        if(fstat(n,&component)||component.st_uid!=getuid()||(component.st_mode&0077)) {
          close(n);throw std::runtime_error("Created log directory component must remain private and user-owned");
        }
      }
      current=Fd(n);
    }
    struct stat st{};
    if(fstat(current.n,&st)||st.st_uid!=getuid()||(st.st_mode&0022)) throw std::runtime_error("Log directory must be user-owned without group/world write access");
    return current;
  }
  inline std::string filename(unsigned index) {
    return index?std::string(base)+"."+std::to_string(index)+".jsonl":std::string(base)+".current.jsonl";
  }
  inline std::string json(const std::string& value) {
    static const char hex[]="0123456789abcdef";
    std::string r="\"";
    for(unsigned char c:value) {
      switch(c){
        case '\"':r+="\\\"";
        break;
        case '\\':r+="\\\\";
        break;
        case '\b':r+="\\b";
        break;
        case '\f':r+="\\f";
        break;
        case '\n':r+="\\n";
        break;
        case '\r':r+="\\r";
        break;
        case '\t':r+="\\t";
        break;
        default:if(c<32){
          r+="\\u00";
          r+=hex[c>>4];
          r+=hex[c&15];
        }
        else r+=char(c);
      }
    }
    return r+'"';
  }
  inline std::string b64(const unsigned char* p,size_t n) {
    static const char table[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string r;
    r.reserve((n+2)/3*4);
    for(size_t i=0;i<n;i+=3){
      uint32_t v=uint32_t(p[i])<<16;
      if(i+1<n)v|=uint32_t(p[i+1])<<8;
      if(i+2<n)v|=p[i+2];
      r+=table[(v>>18)&63];
      r+=table[(v>>12)&63];
      r+=i+1<n?table[(v>>6)&63]:'=';
      r+=i+2<n?table[v&63]:'=';
    }
    return r;
  }
  inline std::string unb64(const std::string& in) {
    if(in.size()%4) throw std::runtime_error("Corrupt payload base64");
    std::string out;
    uint32_t v=0;
    int bits=0;
    bool padding=false;
    for(unsigned char c:in){
      if(c=='='){
        padding=true;
        continue;
      }
      if(padding)throw std::runtime_error("Corrupt payload base64 padding");
      int a=c>='A'&&c<='Z'?c-'A':c>='a'&&c<='z'?c-'a'+26:c>='0'&&c<='9'?c-'0'+52:c=='+'?62:c=='/'?63:-1;
      if(a<0)throw std::runtime_error("Corrupt payload base64 alphabet");
      v=(v<<6)|unsigned(a);
      bits+=6;
      if(bits>=8){
        bits-=8;
        out+=char(v>>bits);
      }
    }
    return out;
  }
  inline uint32_t crc32(const std::string& text){
    uint32_t crc=0xffffffffu;
    for(unsigned char byte:text){
      crc^=byte;
      for(int n=0;n<8;++n)crc=(crc>>1)^(0xedb88320u&uint32_t(-int32_t(crc&1)));
    }
    return ~crc;
  }
  struct PacketHeader {
    uint32_t magic=0x47584431,payload_bytes=0;
  };
  inline uint64_t getNumber(const std::string& line,const std::string& key) {
    auto p=line.find('"'+key+"\":");
    if(p==std::string::npos)throw std::runtime_error("Missing diagnostic number: "+key);
    p+=key.size()+3;
    if(p>=line.size()||line[p]<'0'||line[p]>'9')throw std::runtime_error("Corrupt diagnostic number");
    size_t n=0;
    auto r=std::stoull(line.substr(p),&n);
    return r;
  }
  // Parser for the writer's flat object and nested string-only origin. Never evaluates Tcl.
  inline std::string getString(const std::string& line,const std::string& key) {
    auto p=line.find('"'+key+"\":\"");
    if(p==std::string::npos)throw std::runtime_error("Missing diagnostic string: "+key);
    p+=key.size()+4;
    std::string r;
    while(p<line.size()){
      unsigned char c=line[p++];
      if(c=='"')return r;
      if(c!='\\'){
        r+=char(c);
        continue;
      }
      if(p>=line.size())break;
      c=line[p++];
      switch(c){
        case '"':case '\\':case '/':r+=char(c);
        break;
        case 'n':r+='\n';
        break;
        case 'r':r+='\r';
        break;
        case 't':r+='\t';
        break;
        case 'b':r+='\b';
        break;
        case 'f':r+='\f';
        break;
        case 'u':{
          if(p+4>line.size()||line.substr(p,2)!="00")throw std::runtime_error("Unsupported diagnostic escape");
          auto v=std::stoul(line.substr(p,4),nullptr,16);
          r+=char(v);
          p+=4;
          break;
        }
        default:throw std::runtime_error("Corrupt diagnostic escape");
      }
    }
    throw std::runtime_error("Unterminated diagnostic string");
  }
}
