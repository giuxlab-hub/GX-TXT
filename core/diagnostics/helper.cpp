// SPDX-License-Identifier: GPL-3.0-or-later
#include "protocol.h"
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <cstdlib>
#include <poll.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/socket.h>
using namespace gxdiag;
namespace {
  Shared* signalStatus=nullptr;
  char statusPath[160]{};
  void parentGone(int signal){
    if(signalStatus)signalStatus->accepting.store(0);
    if(statusPath[0])unlink(statusPath);
    _exit(128+signal);
  }
  struct Ring {
    std::vector<char> bytes;
    size_t head=0,tail=0,used=0;
    std::mutex mutex;
    std::condition_variable ready;
    explicit Ring(size_t capacity):bytes(capacity){}
    void put(const void* source,size_t n){
      auto p=static_cast<const char*>(source);
      size_t a=std::min(n,bytes.size()-tail);
      memcpy(bytes.data()+tail,p,a);
      memcpy(bytes.data(),p+a,n-a);
      tail=(tail+n)%bytes.size();
      used+=n;
    }
    void get(void* destination,size_t n){
      auto p=static_cast<char*>(destination);
      size_t a=std::min(n,bytes.size()-head);
      memcpy(p,bytes.data()+head,a);
      memcpy(p+a,bytes.data(),n-a);
      head=(head+n)%bytes.size();
      used-=n;
    }
  };
  struct Frame {
    uint32_t length,payload;
  };
  struct Writer {
    Shared* shared;
    Fd directory,lock,file;
    uint64_t fileBytes=0,maxBytes;
    unsigned maxFiles;
    Writer(Shared* s,const std::string& path,uint64_t limit,unsigned count):shared(s),directory(openDirectory(path,true)),maxBytes(limit),maxFiles(count) {
      lock=Fd(openat(directory.n,".stderr-diagnostics.lock",O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0600));
      if(lock.n<0)throw std::runtime_error(systemError("Open diagnostics lock"));
      requireFile(lock.n);
      if(flock(lock.n,LOCK_EX|LOCK_NB))throw std::runtime_error(systemError("Lock diagnostics directory"));
      RecordLock snapshot(lock.n,F_WRLCK);
      for(unsigned i=0;i<100;++i)validate(i);
      for(unsigned i=0;i<100;++i){
        struct stat st{};
        if(!fstatat(directory.n,filename(i).c_str(),&st,AT_SYMLINK_NOFOLLOW)&&(i>=maxFiles||uint64_t(st.st_size)>maxBytes))evict(i);
      }
      openCurrent();
      recoverTail();
    }
    void validate(unsigned index) {
      Fd f(openat(directory.n,filename(index).c_str(),O_RDONLY|O_NOFOLLOW|O_CLOEXEC));
      if(f.n<0){
        if(errno==ENOENT)return;
        throw std::runtime_error(systemError("Validate managed log"));
      }
      requireFile(f.n);
      struct stat st{};
      if(fstat(f.n,&st))throw std::runtime_error(systemError("Inspect managed log"));
      if(st.st_size){
        const std::string prefix="{\"schema\":\"gxtxt.stderr_record.v1\",\"generation\":";
        char bytes[128];
        auto n=pread(f.n,bytes,std::min<size_t>(sizeof bytes,size_t(st.st_size)),0);
        if(n<=0||std::string(bytes,size_t(n)).substr(0,std::min(prefix.size(),size_t(n)))!=prefix.substr(0,std::min(prefix.size(),size_t(n))))throw std::runtime_error("Managed filename contains unrecognized diagnostics data; refusing modification");
        if(index){
          char final=0;
          if(pread(f.n,&final,1,st.st_size-1)!=1||final!='\n')throw std::runtime_error("Archived diagnostics file has an incomplete record; refusing modification");
        }
      }
    }
    void evict(unsigned index){
      struct stat st{};
      if(fstatat(directory.n,filename(index).c_str(),&st,AT_SYMLINK_NOFOLLOW)){
        if(errno==ENOENT)return;
        throw std::runtime_error(systemError("Inspect expired diagnostics file"));
      }
      if(unlinkat(directory.n,filename(index).c_str(),0))throw std::runtime_error(systemError("Remove expired diagnostics log"));
      shared->retention_evicted_files.fetch_add(1);
      shared->retention_evicted_bytes.fetch_add(uint64_t(st.st_size));
    }
    void openCurrent() {
      file=Fd(openat(directory.n,filename(0).c_str(),O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW|O_CLOEXEC,0600));
      if(file.n<0)throw std::runtime_error(systemError("Open current diagnostics log"));
      requireFile(file.n);
      struct stat st{};
      if(fstat(file.n,&st))throw std::runtime_error(systemError("Stat current diagnostics log"));
      fileBytes=uint64_t(st.st_size);
    }
    void recoverTail() {
      if(!fileBytes)return;
      Fd input(openat(directory.n,filename(0).c_str(),O_RDONLY|O_NOFOLLOW|O_CLOEXEC));
      if(input.n<0)throw std::runtime_error(systemError("Inspect current log tail"));
      requireFile(input.n);
      size_t n=std::min<uint64_t>(fileBytes,maxLine);
      std::string tail(n,'\0');
      auto read=pread(input.n,tail.data(),n,off_t(fileBytes-n));
      if(read!=ssize_t(n))throw std::runtime_error("Cannot inspect complete current diagnostics tail");
      if(tail.back()=='\n')return;
      auto pos=tail.rfind('\n');
      uint64_t truncate=pos==std::string::npos?fileBytes-n:fileBytes-n+pos+1;
      if(pos==std::string::npos&&fileBytes>n)throw std::runtime_error("Unrecoverable diagnostics tail exceeds bounded record size");
      if(ftruncate(file.n,off_t(truncate)))throw std::runtime_error(systemError("Recover incomplete diagnostic tail"));
      shared->recovered_tail_bytes.fetch_add(fileBytes-truncate);
      error(shared,"Recovered incomplete final diagnostic record after prior interruption");
      fileBytes=truncate;
    }
    void rotate() {
      RecordLock snapshot(lock.n,F_WRLCK);
      // Validate the entire managed set before touching any existing destination.
      for(unsigned i=0;i<maxFiles;++i)validate(i);
      file=Fd();
      evict(maxFiles-1);
      for(unsigned i=maxFiles-1;i>0;--i)if(renameat(directory.n,filename(i-1).c_str(),directory.n,filename(i).c_str())&&errno!=ENOENT)throw std::runtime_error(systemError("Rotate diagnostic log"));
      openCurrent();
    }
    void append(const std::string& line) {
      if(line.size()>maxBytes)throw std::runtime_error("Encoded diagnostic record exceeds configured file size");
      if(fileBytes&&fileBytes+line.size()>maxBytes)rotate();
      size_t p=0;
      while(p<line.size()){
        auto n=write(file.n,line.data()+p,line.size()-p);
        if(n<0&&errno==EINTR)continue;
        if(n<=0){
          auto message=systemError("Write diagnostics log");
          if(ftruncate(file.n,off_t(fileBytes)))message+="; rollback failed: "+std::string(strerror(errno));
          throw std::runtime_error(message);
        }
        p+=size_t(n);
      }
      fileBytes+=line.size();
    }
  };
}
int main(int argc,char** argv) {
  if(argc!=8)return 64;
  auto* shared=static_cast<Shared*>(mmap(nullptr,sizeof(Shared),PROT_READ|PROT_WRITE,MAP_SHARED,4,0));
  if(shared==MAP_FAILED)return 65;
  try {
    std::string statusFile="/dev/shm"+std::string(argv[6]);
    if(statusFile.size()>=sizeof statusPath)throw std::runtime_error("Invalid diagnostics status identity");
    memcpy(statusPath,statusFile.c_str(),statusFile.size()+1);signalStatus=shared;
    struct sigaction action{};action.sa_handler=parentGone;sigemptyset(&action.sa_mask);
    if(sigaction(SIGTERM,&action,nullptr)||prctl(PR_SET_PDEATHSIG,SIGTERM))throw std::runtime_error(systemError("Own collector parent lifetime"));
    if(getppid()!=pid_t(std::stoul(argv[7])))parentGone(SIGTERM);
    uint64_t generation=std::stoull(argv[2]), maxBytes=std::stoull(argv[3]), capacity=std::stoull(argv[5]);
    unsigned maxFiles=unsigned(std::stoul(argv[4]));
    if(capacity<65536||capacity>67108864||maxBytes<4096||maxBytes>1073741824||maxFiles<1||maxFiles>100)throw std::runtime_error("Invalid collector limits");
    Writer writer(shared,argv[1],maxBytes,maxFiles);
    Ring ring{
      size_t(capacity)
    };
    std::atomic<bool> failed{false};
    unsigned fixtureDelay=0;
    uint64_t fixtureFailAfter=UINT64_MAX;
#ifdef GXDIAG_PRIVATE_FIXTURES
    if(auto value=getenv("GXTXT_DIAG_FIXTURE_WRITER_DELAY_MS"))fixtureDelay=unsigned(std::stoul(value));
    if(auto value=getenv("GXTXT_DIAG_FIXTURE_FAIL_AFTER_RECORDS"))fixtureFailAfter=std::stoull(value);
#endif
    std::thread disk([&]{
      try {
        for(;;){
          Frame f{};
          std::string line;
          {
            std::unique_lock<std::mutex> guard(ring.mutex);
            ring.ready.wait(guard,[&]{
              return ring.used>0;
            });
            ring.get(&f,sizeof f);
            line.resize(f.length);
            ring.get(line.data(),line.size());
            shared->queue_bytes.store(ring.used);
            shared->queue_records.fetch_sub(1);
          }
          if(fixtureDelay)std::this_thread::sleep_for(std::chrono::milliseconds(fixtureDelay));
          try {
            if(shared->written_records.load()>=fixtureFailAfter){
              errno=ENOSPC;
              throw std::runtime_error(systemError("Private fixture disk failure"));
            }
            writer.append(line);
          }
          catch(...){
            shared->disk_dropped_records.fetch_add(1);
            shared->disk_dropped_bytes.fetch_add(f.payload);
            throw;
          }
          shared->written_records.fetch_add(1);
          shared->written_bytes.fetch_add(f.payload);
        }
      }
      catch(const std::exception& e){
        error(shared,e.what());
        shared->accepting.store(0);
        shared->phase.store(Failed);
        failed.store(true);
      }
    });
    disk.detach();
    shared->phase.store(Running);
    shared->accepting.store(1);
#ifdef GXDIAG_PRIVATE_FIXTURES
    if(getenv("GXTXT_DIAG_FIXTURE_BROKEN_IPC")){
      close(3);
      for(;;)pause();
    }
#endif
    uint64_t sequence=0;
    std::vector<char> packet(maxPacket);
    while(!failed.load()){
      pollfd event{
        3,POLLIN,0
      };
      int ready=poll(&event,1,25);
      if(ready<0&&errno==EINTR)continue;
      if(ready<0)throw std::runtime_error(systemError("Poll diagnostics IPC"));
      if(event.revents&(POLLHUP|POLLERR|POLLNVAL))throw std::runtime_error("Diagnostics IPC closed or failed");
      if(!(event.revents&POLLIN))continue;
      iovec bytes{packet.data(),packet.size()};
      alignas(cmsghdr) char control[CMSG_SPACE(sizeof(ucred))]{};
      msghdr message{};message.msg_iov=&bytes;message.msg_iovlen=1;message.msg_control=control;message.msg_controllen=sizeof control;
      auto n=recvmsg(3,&message,MSG_DONTWAIT|MSG_TRUNC);
      if(n<0&&(errno==EAGAIN||errno==EINTR))continue;
      auto reject=[&]{shared->ipc_rejected_records.fetch_add(1);if(n>0)shared->ipc_rejected_wire_bytes.fetch_add(uint64_t(n));error(shared,"Rejected invalid diagnostics producer credentials/packet");};
      ucred* sender=nullptr;
      for(auto* c=CMSG_FIRSTHDR(&message);c;c=CMSG_NXTHDR(&message,c))if(c->cmsg_level==SOL_SOCKET&&c->cmsg_type==SCM_CREDENTIALS&&c->cmsg_len==CMSG_LEN(sizeof(ucred)))sender=reinterpret_cast<ucred*>(CMSG_DATA(c));
      if(!sender||sender->uid!=getuid()||(message.msg_flags&MSG_CTRUNC)||n<ssize_t(sizeof(PacketHeader))||n>ssize_t(packet.size())){reject();continue;}
      PacketHeader header{};
      memcpy(&header,packet.data(),sizeof header);
      if(header.magic!=0x47584431||header.payload_bytes>maxPayload){reject();continue;}
      std::string body(packet.data()+sizeof header,size_t(n)-sizeof header);
      try {if(getNumber(body,"capture_pid")!=uint64_t(sender->pid)||getNumber(body,"pid")!=uint64_t(sender->pid)){reject();continue;}}
      catch(const std::exception&){reject();continue;}
      ++sequence;
      std::string line="{\"schema\":\"gxtxt.stderr_record.v1\",\"generation\":"+std::to_string(generation)+",\"sequence\":"+std::to_string(sequence)+",\"record_id\":"+json(std::to_string(generation)+":"+std::to_string(sequence))+","+body;
      line+=",\"record_crc32\":"+std::to_string(crc32(line))+"}\n";
      shared->received_records.fetch_add(1);
      shared->received_bytes.fetch_add(header.payload_bytes);
      // Records too large for a deliberately small configured file are explicitly dropped.
      if(line.size()>maxBytes){
        shared->ring_dropped_records.fetch_add(1);
        shared->ring_dropped_bytes.fetch_add(header.payload_bytes);
        error(shared,"Encoded record exceeds configured max_file_bytes");
        continue;
      }
      {
        std::lock_guard<std::mutex> guard(ring.mutex);
        if(line.size()+sizeof(Frame)>ring.bytes.size()-ring.used){
          shared->ring_dropped_records.fetch_add(1);
          shared->ring_dropped_bytes.fetch_add(header.payload_bytes);
          continue;
        }
        Frame f{
          uint32_t(line.size()),header.payload_bytes
        };
        ring.put(&f,sizeof f);
        ring.put(line.data(),line.size());
        shared->queue_records.fetch_add(1);
        shared->queue_bytes.store(ring.used);
        if(ring.used>shared->queue_high_water_bytes.load())shared->queue_high_water_bytes.store(ring.used);
      }
      ring.ready.notify_one();
    }
    // The process exit, rather than a GUI join, owns termination of a failed writer.
    shm_unlink(argv[6]);
    _exit(1);
  }
  catch(const std::exception& e){
    error(shared,e.what());
    shared->accepting.store(0);
    shared->phase.store(Failed);
    shm_unlink(argv[6]);
    _exit(1);
  }
}
