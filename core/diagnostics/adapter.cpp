// SPDX-License-Identifier: GPL-3.0-or-later
#define _GNU_SOURCE 1
#include "protocol.h"
#include <tcl.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <thread>
#include <sstream>
#include <dlfcn.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/random.h>
#include <sys/wait.h>
extern char** environ;
using namespace gxdiag;
namespace {
  struct Config {
    std::string directory;
    uint64_t maxBytes=defaultFile,ringBytes=defaultRing;
    unsigned maxFiles=5;
  };
  struct CounterSnapshot {
#define GXDIAG_FIELD(n) uint64_t n=0;
    GXDIAG_COUNTERS(GXDIAG_FIELD)
#undef GXDIAG_FIELD
    uint64_t interrupted_records=0,interrupted_bytes=0;
  };
  struct LogFile {
    Fd fd;
    unsigned index=0;
    uint64_t device=0,inode=0,size=0,modified=0,firstGeneration=0,firstSequence=0;
  };
  struct Record {
    std::string raw,payload,id;
    std::map<std::string,std::string> origin;
    uint64_t generation=0,sequence=0,time=0,pid=0;
  };
  struct Task {
    std::atomic<int> state{0};
    std::atomic<bool> cancel{false};
    std::atomic<bool> mutationStarted{false};
    std::mutex mutationBoundary;
    // 0 running, 1 done, 2 error, 3 cancelled
    std::string token,kind,error,code="IO_ERROR",cursor,path;
    std::vector<Record> records;
    struct Meta {
      unsigned index;
      uint64_t device,inode,size,modified;
      std::string guard{};
      bool removed=false;
    };
    std::vector<Meta> files;
    uint64_t bytes=0,recordCount=0;
    bool eof=false;
  };
  struct Selection {
    std::string cursor;
    std::set<std::string> ids;
    std::set<std::string> files;
    unsigned limit=100;
    uint64_t maxBytes=262144;
  };
  uint64_t nowMicros(){
    return uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count());
  }
  uint64_t remaining(uint64_t accepted,uint64_t written,uint64_t ring,uint64_t disk){
    uint64_t removed=written+ring+disk;
    return accepted>removed?accepted-removed:0;
  }
  std::string fileCursor(uint64_t dd,uint64_t di,const LogFile& f,uint64_t position) {
    if(!f.firstGeneration||!f.firstSequence)return {};
    return std::to_string(dd)+":"+std::to_string(di)+":"+std::to_string(f.device)+":"+std::to_string(f.inode)+":"+std::to_string(f.firstGeneration)+":"+std::to_string(f.firstSequence)+":"+std::to_string(position);
  }
  std::array<uint64_t,7> parseCursor(const std::string& value){
    std::array<uint64_t,7> fields{};
    std::istringstream in(value);
    std::string part;
    for(auto& field:fields){
      if(!std::getline(in,part,':')||part.empty()||part.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid diagnostics cursor");
      field=std::stoull(part);
    }
    if(std::getline(in,part,':'))throw std::runtime_error("Invalid diagnostics cursor");
    return fields;
  }
  Record parseRecord(const std::string& raw) {
    auto checksum=raw.rfind(",\"record_crc32\":");
    if(checksum==std::string::npos||raw.substr(checksum)!=",\"record_crc32\":"+std::to_string(crc32(raw.substr(0,checksum)))+"}"||getString(raw,"schema")!="gxtxt.stderr_record.v1")throw std::runtime_error("Corrupt diagnostics record checksum/schema");
    Record r;
    r.raw=raw;
    r.generation=getNumber(raw,"generation");
    r.sequence=getNumber(raw,"sequence");
    r.time=getNumber(raw,"timestamp_us");
    r.pid=getNumber(raw,"pid");
    r.id=getString(raw,"record_id");
    for(const char* key:originKeys)r.origin[key]=getString(raw,key);
    r.payload=unb64(getString(raw,"payload_base64"));
    if(r.payload.size()!=getNumber(raw,"payload_bytes")||r.payload.size()>maxPayload||r.id!=std::to_string(r.generation)+":"+std::to_string(r.sequence))throw std::runtime_error("Corrupt diagnostics record identity or payload length");
    return r;
  }
  std::vector<LogFile> logFiles(int directory,unsigned maxFiles) {
    std::vector<LogFile> files;
    // FDs pin inodes across concurrent rename/unlink; no mutable pathname is used later.
    for(unsigned n=maxFiles;n>0;--n){
      unsigned index=n-1;
      Fd fd(openat(directory,filename(index).c_str(),O_RDONLY|O_NOFOLLOW|O_CLOEXEC));
      if(fd.n<0){
        if(errno==ENOENT)continue;
        throw std::runtime_error(systemError("Open retained diagnostics file"));
      }
      requireFile(fd.n);
      struct stat st{};
      if(fstat(fd.n,&st))throw std::runtime_error(systemError("Stat retained diagnostics file"));
      LogFile file;
      file.fd=std::move(fd);
      file.index=index;
      file.device=uint64_t(st.st_dev);
      file.inode=uint64_t(st.st_ino);
      file.size=uint64_t(st.st_size);
      file.modified=uint64_t(st.st_mtime);
      if(file.size){
        char prefix[256];
        auto n=pread(file.fd.n,prefix,sizeof prefix,0);
        if(n>0){
          std::string text(prefix,size_t(n));
          file.firstGeneration=getNumber(text,"generation");
          file.firstSequence=getNumber(text,"sequence");
        }
      }
      files.push_back(std::move(file));
    }
    // Rotation while opening can expose the same inode twice. Preserve one snapshot.
    std::set<std::pair<uint64_t,uint64_t>> seen;
    std::vector<LogFile> unique;
    for(auto& f:files)if(seen.emplace(f.device,f.inode).second)unique.push_back(std::move(f));
    return unique;
  }
  // Buffered bounded line reader: at most one 64KiB record plus a 16KiB read buffer.
  struct Lines {
    int fd;
    uint64_t position,end;
    std::array<char,16384> buffer{};
    size_t cursor=0,available=0;
    Lines(int f,uint64_t p,uint64_t e):fd(f),position(p),end(e){}
    bool next(std::string& line,uint64_t& nextPosition) {
      line.clear();
      uint64_t start=position;
      while(position<end){
        if(cursor==available){
          auto n=pread(fd,buffer.data(),std::min<uint64_t>(buffer.size(),end-position),off_t(position));
          if(n<0&&errno==EINTR)continue;
          if(n<0)throw std::runtime_error(systemError("Read retained diagnostics file"));
          if(!n){
            position=start;
            return false;
          }
          cursor=0;
          available=size_t(n);
        }
        char c=buffer[cursor++];
        ++position;
        if(c=='\n'){
          nextPosition=position;
          return true;
        }
        line+=c;
        if(line.size()>maxLine)throw std::runtime_error("Corrupt diagnostics record exceeds bounded record limit");
      }
      position=start;
      return false;
      // A concurrently interrupted/in-flight final line is not exposed.
    }
  };
  void checkCancelled(const std::shared_ptr<Task>& task){
    if(task->cancel.load())throw std::runtime_error("Diagnostics request cancelled");
  }
  std::string maintenanceGuard(unsigned index,const struct stat& directory,const struct stat& file) {
    return std::to_string(index)+":"+std::to_string(directory.st_dev)+":"+std::to_string(directory.st_ino)+":"+
      std::to_string(file.st_dev)+":"+std::to_string(file.st_ino)+":"+std::to_string(file.st_size)+":"+
      std::to_string(file.st_mtim.tv_sec)+":"+std::to_string(file.st_mtim.tv_nsec)+":"+
      std::to_string(file.st_ctim.tv_sec)+":"+std::to_string(file.st_ctim.tv_nsec);
  }
  void runMaintenance(const std::shared_ptr<Task>& task,const Config& config,const Selection& selection) {
    // The same directory, managed filename, record validator and writer lock
    // as capture/rotation define ownership. No caller supplies a delete path.
    auto directory=openDirectory(config.directory,false);
    Fd control(openat(directory.n,".stderr-diagnostics.lock",O_RDWR|O_NOFOLLOW|O_CLOEXEC));
    if(control.n<0)throw std::runtime_error("Diagnostics owner lock is unavailable; cleanup refused");
    requireFile(control.n);
    if(flock(control.n,LOCK_EX|LOCK_NB))throw std::runtime_error("Diagnostics writer is active; stop capture explicitly before cleanup");
    struct flock request{};
    request.l_type=F_WRLCK;request.l_whence=SEEK_SET;request.l_len=1;
    if(fcntl(control.n,F_SETLK,&request))throw std::runtime_error("Diagnostics snapshot is busy; cleanup refused");
    struct stat ds{};
    if(fstat(directory.n,&ds))throw std::runtime_error(systemError("Stat diagnostics directory"));
    auto files=logFiles(directory.n,100);
    std::set<std::string> observed;
    for(auto& f:files){
      checkCancelled(task);
      if(f.size>1073741824)throw std::runtime_error("Diagnostics file exceeds the owner size bound");
      Lines input(f.fd.n,0,f.size);
      std::string line;uint64_t next=0,records=0;
      while(input.next(line,next)){checkCancelled(task);parseRecord(line);++records;}
      if(input.position!=f.size)throw std::runtime_error("Incomplete diagnostics record; cleanup refused");
      struct stat st{};
      if(fstat(f.fd.n,&st))throw std::runtime_error(systemError("Stat cleanup candidate"));
      auto guard=maintenanceGuard(f.index,ds,st);
      if(uint64_t(st.st_size)!=f.size)throw std::runtime_error("Diagnostics file changed during preview");
      observed.insert(guard);
      task->files.push_back({f.index,f.device,f.inode,f.size,f.modified,guard,false});
      task->bytes+=f.size;task->recordCount+=records;
    }
    if(task->kind=="cleanup"){
      if(observed!=selection.files)throw std::runtime_error("Diagnostics changed after preview; inspect again");
      // Validate every candidate first. Cancellation is honored until this
      // boundary; a failure during unlink reports each completed removal.
      {
        std::lock_guard<std::mutex> boundary(task->mutationBoundary);
        checkCancelled(task);
        task->mutationStarted.store(true);
      }
      for(auto& f:task->files){
        struct stat current{};
        if(fstatat(directory.n,filename(f.index).c_str(),&current,AT_SYMLINK_NOFOLLOW)||
            !S_ISREG(current.st_mode)||maintenanceGuard(f.index,ds,current)!=f.guard)
          throw std::runtime_error("Diagnostics changed before removal; remaining files preserved");
        if(unlinkat(directory.n,filename(f.index).c_str(),0))throw std::runtime_error(systemError("Remove selected diagnostics"));
        f.removed=true;
      }
      if(fsync(directory.n))throw std::runtime_error(systemError("Flush diagnostics cleanup"));
    }
    task->eof=true;
  }
  void runRead(const std::shared_ptr<Task>& task,const Config& config,const Selection& selection,bool exporting,const std::string& target) {
    Fd directory;
    try{
      directory=openDirectory(config.directory,false);
    }
    catch(const DirectoryMissing&){
      if(exporting||!selection.ids.empty())throw std::runtime_error("SELECTION_EXPIRED: no retained diagnostics exist");
      task->eof=true;
      return;
    }
    struct stat ds{};
    if(fstat(directory.n,&ds))throw std::runtime_error(systemError("Stat log directory"));
    std::vector<LogFile> files;
    {
      Fd control(openat(directory.n,".stderr-diagnostics.lock",O_RDONLY|O_NOFOLLOW|O_CLOEXEC));
      if(control.n<0&&errno!=ENOENT)throw std::runtime_error(systemError("Open diagnostics snapshot lock"));
      if(control.n>=0)requireFile(control.n);
      RecordLock snapshot(control.n,F_RDLCK);
      files=logFiles(directory.n,config.maxFiles);
    }
    if(task->kind=="meta"){
      for(auto& f:files)task->files.push_back({
        f.index,f.device,f.inode,f.size,f.modified
      });
      task->eof=true;
      return;
    }
    size_t start=0;
    uint64_t offset=0;
    if(!selection.cursor.empty()){
      auto cursor=parseCursor(selection.cursor);
      bool found=false;
      if(cursor[0]!=uint64_t(ds.st_dev)||cursor[1]!=uint64_t(ds.st_ino))throw std::runtime_error("CURSOR_EXPIRED: diagnostics directory changed");
      for(size_t i=0;i<files.size();++i)if(files[i].device==cursor[2]&&files[i].inode==cursor[3]&&files[i].firstGeneration==cursor[4]&&files[i].firstSequence==cursor[5]){
        start=i;
        offset=cursor[6];
        if(offset>files[i].size)throw std::runtime_error("CURSOR_EXPIRED: diagnostics file truncated");
        found=true;
        break;
      }
      if(!found)throw std::runtime_error("CURSOR_EXPIRED: diagnostics file left retention");
    }
    std::set<std::string> missing=selection.ids;
    // Explicit stable-ID selections may scan retained logs, bounded by configured retention,
    // without collecting unmatched records. This work always runs off Tcl/Tk.
    for(size_t i=start;i<files.size();++i){
      auto& file=files[i];
      Lines input(file.fd.n,i==start?offset:0,file.size);
      std::string line;
      uint64_t next=0;
      while(input.next(line,next)){
        checkCancelled(task);
        if(line.empty())throw std::runtime_error("Empty/corrupt diagnostic record");
        auto record=parseRecord(line);
        bool selected=selection.ids.empty()||selection.ids.count(record.id);
        if(selected){
          if(task->records.size()>=selection.limit||task->bytes+line.size()+1>selection.maxBytes){
            if(task->records.empty())throw std::runtime_error("READ_BUDGET_TOO_SMALL: next record requires "+std::to_string(line.size()+1)+" bytes");
            task->eof=false;
            goto readDone;
          }
          task->bytes+=line.size()+1;
          task->records.push_back(std::move(record));
          missing.erase(task->records.back().id);
        }
        task->cursor=fileCursor(uint64_t(ds.st_dev),uint64_t(ds.st_ino),file,next);
        if(!selection.ids.empty()&&missing.empty()){
          task->eof=true;
          goto readDone;
        }
      }
      if(file.firstGeneration)task->cursor=fileCursor(uint64_t(ds.st_dev),uint64_t(ds.st_ino),file,input.position);
    }
    task->eof=true;
    readDone: if(!selection.ids.empty()&&!missing.empty())throw std::runtime_error("SELECTION_EXPIRED: selected records are unavailable or exceed export bounds");
    task->recordCount=task->records.size();
    if(!exporting)return;
    checkCancelled(task);
    auto slash=target.rfind('/');
    if(slash==std::string::npos||slash==target.size()-1||target[0]!='/')throw std::runtime_error("Export requires an absolute trusted-host destination");
    std::string name=target.substr(slash+1),parent=slash?target.substr(0,slash):"/";
    if(name=="."||name==".."||name.rfind("stderr-diagnostics",0)==0||name==".stderr-diagnostics.lock")throw std::runtime_error("Export must not replace a managed diagnostics file");
    auto outputDirectory=openDirectory(parent,false);
    struct stat existing{};
    if(!fstatat(outputDirectory.n,name.c_str(),&existing,AT_SYMLINK_NOFOLLOW)||errno!=ENOENT)throw std::runtime_error("Export destination already exists or cannot be inspected; choose a new filename");
    std::string temporary=".gxtxt-diagnostics-export-"+task->token+".tmp";
    Fd out(openat(outputDirectory.n,temporary.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600));
    if(out.n<0)throw std::runtime_error(systemError("Create temporary diagnostics export"));
    try {
      for(auto& record:task->records){
        checkCancelled(task);
        std::string line=record.raw+'\n';
        size_t p=0;
        while(p<line.size()){
          auto n=write(out.n,line.data()+p,line.size()-p);
          if(n<0&&errno==EINTR)continue;
          if(n<=0)throw std::runtime_error(systemError("Write diagnostics export"));
          p+=size_t(n);
        }
      }
      if(fsync(out.n))throw std::runtime_error(systemError("Flush diagnostics export"));
      checkCancelled(task);
      // linkat publishes atomically without replacing a file created after the check.
      if(linkat(outputDirectory.n,temporary.c_str(),outputDirectory.n,name.c_str(),0))throw std::runtime_error(systemError("Publish diagnostics export without replacement"));
      if(unlinkat(outputDirectory.n,temporary.c_str(),0))throw std::runtime_error(systemError("Remove diagnostics export temporary link"));
      task->path=target;
    }
    catch(...){
      unlinkat(outputDirectory.n,temporary.c_str(),0);
      throw;
    }
    task->records.clear();
  }
  Tcl_Obj* stringObj(const std::string& s){
    return Tcl_NewStringObj(s.data(),int(s.size()));
  }
  void put(Tcl_Interp* i,Tcl_Obj* d,const char* key,Tcl_Obj* value){
    Tcl_DictObjPut(i,d,Tcl_NewStringObj(key,-1),value);
  }
  void put(Tcl_Interp* i,Tcl_Obj* d,const char* key,const std::string& value){
    put(i,d,key,stringObj(value));
  }
  void number(Tcl_Interp* i,Tcl_Obj* d,const char* key,uint64_t value){
    put(i,d,key,Tcl_NewWideIntObj(Tcl_WideInt(value)));
  }
  Tcl_Obj* configObj(Tcl_Interp* i,const Config& c){
    auto d=Tcl_NewDictObj();
    put(i,d,"log_directory",c.directory);
    number(i,d,"max_file_bytes",c.maxBytes);
    number(i,d,"max_files",c.maxFiles);
    number(i,d,"ring_bytes",c.ringBytes);
    return d;
  }
  std::string objString(Tcl_Obj* obj){
    int n=0;
    const char* p=Tcl_GetStringFromObj(obj,&n);
    Tcl_DString converted;
    Tcl_DStringInit(&converted);
    Tcl_Encoding encoding=Tcl_GetEncoding(nullptr,"utf-8");
    Tcl_UtfToExternalDString(encoding,p,n,&converted);
    std::string text(Tcl_DStringValue(&converted),size_t(Tcl_DStringLength(&converted)));
    Tcl_DStringFree(&converted);
    Tcl_FreeEncoding(encoding);
    return text;
  }
  uint64_t boundedNumber(Tcl_Interp* i,Tcl_Obj* value,uint64_t low,uint64_t high,const char* key){
    Tcl_WideInt n=0;
    if(Tcl_GetWideIntFromObj(i,value,&n)!=TCL_OK||n<0||uint64_t(n)<low||uint64_t(n)>high)throw std::runtime_error(std::string(key)+" outside supported bounds "+std::to_string(low)+".."+std::to_string(high));
    return uint64_t(n);
  }
  Config parseConfig(Tcl_Interp* i,Tcl_Obj* object,Config config){
    Tcl_DictSearch search;
    Tcl_Obj *key=nullptr,*value=nullptr;
    int done=0;
    if(Tcl_DictObjFirst(i,object,&search,&key,&value,&done)!=TCL_OK)throw std::runtime_error("Diagnostics configuration must be a dictionary");
    try{
      for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
        auto name=objString(key);
        if(name=="log_directory"){
          config.directory=objString(value);
          if(config.directory.empty()||config.directory[0]!='/'||config.directory.size()>4096||config.directory.find('\0')!=std::string::npos)throw std::runtime_error("log_directory must be a nonempty absolute path");
        }
        else if(name=="max_file_bytes")config.maxBytes=boundedNumber(i,value,4096,1073741824,name.c_str());
        else if(name=="max_files")config.maxFiles=unsigned(boundedNumber(i,value,1,100,name.c_str()));
        else if(name=="ring_bytes")config.ringBytes=boundedNumber(i,value,65536,67108864,name.c_str());
        else throw std::runtime_error("Unknown diagnostics configuration key: "+name);
      }
    }
    catch(...){
      Tcl_DictObjDone(&search);
      throw;
    }
    Tcl_DictObjDone(&search);
    return config;
  }
  class Native {
    public: Config config;
    Shared* shared=nullptr;
    Fd socket,sharedFd;
    pid_t child=-1;
    bool stopping=false,faulted=false,restartRequested=false,ownsShm=false;
    uint64_t generation=0,serial=0;
    std::string lastError;
    std::string endpoint,shmName,descriptor;
    CounterSnapshot retired;
    std::vector<Shared*> retiredPages;
    std::map<std::string,std::shared_ptr<Task>> tasks;
    void unlinkStatus(){if(ownsShm){shm_unlink(shmName.c_str());ownsShm=false;}}
    ~Native(){
      if(shared)shared->accepting.store(0);
      unlinkStatus();
      if(child>0){
        auto pid=child;
        kill(pid,SIGKILL);
        std::thread([pid]{
          int status;
          while(waitpid(pid,&status,0)<0&&errno==EINTR){}
        }).detach();
      }
      for(auto& entry:tasks)entry.second->cancel.store(true);
      if(shared)munmap(shared,sizeof(Shared));
      for(auto page:retiredPages)munmap(page,sizeof(Shared));
    }
    CounterSnapshot snapshot(Shared* page=nullptr){
      if(!page)page=shared;
      CounterSnapshot s;
      if(page){
#define GXDIAG_COPY(n) s.n=page->n.load();
        GXDIAG_COUNTERS(GXDIAG_COPY)
#undef GXDIAG_COPY
      }
      return s;
    }
    static void addRetired(CounterSnapshot& target,CounterSnapshot s){
#define GXDIAG_RETIRED(n) target.n+=s.n;
      target.queue_high_water_bytes=std::max(target.queue_high_water_bytes,s.queue_high_water_bytes);
      s.queue_records=0;
      s.queue_bytes=0;
      s.queue_high_water_bytes=0;
      GXDIAG_COUNTERS(GXDIAG_RETIRED)
#undef GXDIAG_RETIRED
      target.interrupted_records+=remaining(s.accepted_records,s.written_records,s.ring_dropped_records,s.disk_dropped_records);
      target.interrupted_bytes+=remaining(s.accepted_bytes,s.written_bytes,s.ring_dropped_bytes,s.disk_dropped_bytes);
    }
    void collectRetired(){
      for(auto it=retiredPages.begin();it!=retiredPages.end();){
        if((*it)->producer_inflight.load()){++it;continue;}
        addRetired(retired,snapshot(*it));munmap(*it,sizeof(Shared));it=retiredPages.erase(it);
      }
    }
    void reap(){
      collectRetired();
      if(child<=0)return;
      int status=0;
      pid_t result=waitpid(child,&status,WNOHANG);
      if(result!=child&&!(result<0&&errno==ECHILD))return;
      shared->accepting.store(0);
      if(!stopping&&shared->phase.load()!=Failed){
        error(shared,"Collector exited unexpectedly");
        shared->phase.store(Failed);
      }
      lastError=errorText(shared);
      faulted=!stopping;
      if(shared->producer_inflight.load())retiredPages.push_back(shared);
      else {addRetired(retired,snapshot(shared));munmap(shared,sizeof(Shared));}
      child=-1;
      socket=Fd();
      unlinkStatus();
      descriptor.clear();
      shared=nullptr;
      sharedFd=Fd();
      stopping=false;
    }
    void stop(){
      restartRequested=false;
      reap();
      faulted=false;
      if(child>0){
        shared->accepting.store(0);
        unlinkStatus();
        descriptor.clear();
        stopping=true;
        socket=Fd();
        kill(child,SIGKILL);
        reap();
      }
    }
    void start(){
      reap();
      if(child>0)throw std::runtime_error("Collector is already active or stopping");
      if(retiredPages.size()>=64)throw std::runtime_error("Interrupted producer counter-page limit reached; restart the owning host");
      if(config.directory.empty())throw std::runtime_error("Configure log_directory before starting diagnostics");
      try {
        Dl_info info{};
        if(!dladdr(reinterpret_cast<void*>(&nowMicros),&info)||!info.dli_fname)throw std::runtime_error("Cannot locate diagnostics helper");
        std::string library=info.dli_fname;
        auto helper=library.substr(0,library.rfind('/')+1)+"gxtxt-diagnostics-helper";
        uint64_t nonce=0;
        if(getrandom(&nonce,sizeof nonce,GRND_NONBLOCK)!=ssize_t(sizeof nonce))throw std::runtime_error(systemError("Allocate diagnostic generation identity"));
        generation=nonce&0x7fffffffffffffffULL;
        if(!generation)generation=1;
        std::string identity=std::to_string(getuid())+"."+std::to_string(generation);
        endpoint="gxtxt.diag."+identity;
        shmName="/gxtxt-diag-"+identity;
        sharedFd=Fd(shm_open(shmName.c_str(),O_CREAT|O_EXCL|O_RDWR|O_CLOEXEC,0600));
        ownsShm=sharedFd.n>=0;
        if(sharedFd.n<0||ftruncate(sharedFd.n,sizeof(Shared)))throw std::runtime_error(systemError("Create diagnostics shared status"));
        shared=static_cast<Shared*>(mmap(nullptr,sizeof(Shared),PROT_READ|PROT_WRITE,MAP_SHARED,sharedFd.n,0));
        if(shared==MAP_FAILED){
          shared=nullptr;
          throw std::runtime_error(systemError("Map diagnostics shared status"));
        }
        new(shared)Shared;
        shared->generation.store(generation);
        Fd receiver(::socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0));
        if(receiver.n<0)throw std::runtime_error(systemError("Create diagnostics nonblocking IPC"));
        int credentials=1;
        if(setsockopt(receiver.n,SOL_SOCKET,SO_PASSCRED,&credentials,sizeof credentials))throw std::runtime_error(systemError("Enable diagnostics producer credentials"));
        sockaddr_un address{};address.sun_family=AF_UNIX;
        if(endpoint.size()+1>sizeof address.sun_path)throw std::runtime_error("Diagnostics endpoint exceeds UNIX bound");
        memcpy(address.sun_path+1,endpoint.data(),endpoint.size());
        socklen_t addressSize=socklen_t(offsetof(sockaddr_un,sun_path)+1+endpoint.size());
        if(bind(receiver.n,reinterpret_cast<sockaddr*>(&address),addressSize))throw std::runtime_error(systemError("Bind diagnostics producer endpoint"));
        socket=Fd(::socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0));
        if(socket.n<0||connect(socket.n,reinterpret_cast<sockaddr*>(&address),addressSize))throw std::runtime_error(systemError("Connect host diagnostics producer endpoint"));
        Fd inheritedSocket(fcntl(receiver.n,F_DUPFD_CLOEXEC,10)),inheritedStatus(fcntl(sharedFd.n,F_DUPFD_CLOEXEC,10));
        if(inheritedSocket.n<0||inheritedStatus.n<0)throw std::runtime_error(systemError("Prepare helper handles"));
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions,inheritedSocket.n,3);
        posix_spawn_file_actions_adddup2(&actions,inheritedStatus.n,4);
        std::string gen=std::to_string(generation),size=std::to_string(config.maxBytes),count=std::to_string(config.maxFiles),ring=std::to_string(config.ringBytes);
        std::string parent=std::to_string(getpid());
        char* argv[]={
          helper.data(),config.directory.data(),gen.data(),size.data(),count.data(),ring.data(),shmName.data(),parent.data(),nullptr
        };
        posix_spawn_file_actions_addclosefrom_np(&actions,5);
        int result=posix_spawn(&child,helper.c_str(),&actions,nullptr,argv,environ);
        posix_spawn_file_actions_destroy(&actions);
        if(result){
          child=-1;
          socket=Fd();
          munmap(shared,sizeof(Shared));
          shared=nullptr;
          sharedFd=Fd();
          throw std::runtime_error("Start diagnostics helper: "+std::string(strerror(result)));
        }
        lastError.clear();
        descriptor="gxdiag1:"+endpoint+":"+shmName+":"+gen;
        faulted=false;
      }
      catch(...){
        if(child<=0){
          socket=Fd();
          unlinkStatus();
          descriptor.clear();
          sharedFd=Fd();
          if(shared){
            munmap(shared,sizeof(Shared));
            shared=nullptr;
          }
        }
        throw;
      }
    }
    Tcl_Obj* status(Tcl_Interp* i){
      reap();
      if(restartRequested&&child<0){
        restartRequested=false;
        start();
      }
      auto d=Tcl_NewDictObj();
      put(i,d,"schema",std::string("gxtxt.stderr_status.v1"));
      std::string state=child>0?(stopping?"stopping":shared->phase.load()==Running?"running":shared->phase.load()==Failed?"error":"starting"):faulted?"error":"off";
      put(i,d,"state",state);
      number(i,d,"enabled",shared&&!stopping&&shared->accepting.load());
      number(i,d,"helper_pid",child>0?uint64_t(child):0);
      number(i,d,"generation",generation);
      number(i,d,"capture_ipc",socket.n>=0);
      number(i,d,"writer",child>0&&!stopping&&shared->phase.load()==Running);
      put(i,d,"config",configObj(i,config));
      put(i,d,"log_directory",config.directory);
      put(i,d,"last_error",shared?errorText(shared):lastError);
      auto current=snapshot(),total=retired;
      uint64_t inflight=shared?shared->producer_inflight.load():0;
      for(auto page:retiredPages){addRetired(total,snapshot(page));inflight+=page->producer_inflight.load();}
      uint64_t retiredHighWater=total.queue_high_water_bytes;
      number(i,d,"retired_status_pages",retiredPages.size());number(i,d,"producer_inflight",inflight);
      auto counters=Tcl_NewDictObj(),gen=Tcl_NewDictObj();
#define GXDIAG_STATUS(n) number(i,gen,#n,current.n);total.n+=current.n;number(i,counters,#n,total.n);number(i,d,#n,total.n);
      GXDIAG_COUNTERS(GXDIAG_STATUS)
#undef GXDIAG_STATUS
      number(i,counters,"interrupted_records",total.interrupted_records);
      number(i,counters,"interrupted_bytes",total.interrupted_bytes);
      number(i,d,"interrupted_records",total.interrupted_records);
      number(i,d,"interrupted_bytes",total.interrupted_bytes);
      number(i,d,"dropped_records",total.transport_dropped_records+total.ring_dropped_records+total.disk_dropped_records+total.interrupted_records);
      number(i,d,"dropped_bytes",total.transport_dropped_bytes+total.ring_dropped_bytes+total.disk_dropped_bytes+total.interrupted_bytes);
      number(i,d,"pending_records",remaining(current.accepted_records,current.written_records,current.ring_dropped_records,current.disk_dropped_records));
      number(i,d,"pending_bytes",remaining(current.accepted_bytes,current.written_bytes,current.ring_dropped_bytes,current.disk_dropped_bytes));
      number(i,d,"queue_high_water_bytes",std::max(retiredHighWater,current.queue_high_water_bytes));
      number(i,counters,"queue_high_water_bytes",std::max(retiredHighWater,current.queue_high_water_bytes));
      number(i,d,"queue_records",current.queue_records);
      number(i,d,"queue_bytes",current.queue_bytes);
      number(i,counters,"queue_records",current.queue_records);
      number(i,counters,"queue_bytes",current.queue_bytes);
      number(i,counters,"dropped_records",total.transport_dropped_records+total.ring_dropped_records+total.disk_dropped_records+total.interrupted_records);
      number(i,counters,"dropped_bytes",total.transport_dropped_bytes+total.ring_dropped_bytes+total.disk_dropped_bytes+total.interrupted_bytes);
      put(i,d,"counters",counters);
      put(i,d,"generation_counters",gen);
      return d;
    }
    Tcl_Obj* emit(Tcl_Interp* i,Tcl_Obj* origin,Tcl_Obj* payload){
      reap();
      auto result=Tcl_NewDictObj();
      number(i,result,"accepted",0);
      if(!shared||stopping||!shared->accepting.load()){
        put(i,result,"reason",std::string("off"));
        return result;
      }
      int length=0;
      auto bytes=Tcl_GetByteArrayFromObj(payload,&length);
      if(length>int(maxPayload)){
        shared->transport_dropped_records.fetch_add(1);
        shared->transport_dropped_bytes.fetch_add(uint64_t(length));
        put(i,result,"reason",std::string("oversize"));
        return result;
      }
      std::string body="\"timestamp_us\":"+std::to_string(nowMicros())+",\"pid\":"+std::to_string(getpid())+",\"capture_pid\":"+std::to_string(getpid())+",\"origin\":{";
      bool first=true;
      size_t originBytes=0;
      for(const char* key:originKeys){
        Tcl_Obj* value=nullptr;
        Tcl_Obj* name=Tcl_NewStringObj(key,-1);
        Tcl_IncrRefCount(name);
        int code=Tcl_DictObjGet(i,origin,name,&value);
        Tcl_DecrRefCount(name);
        if(code!=TCL_OK)throw std::runtime_error("emit origin must be a dictionary");
        std::string text=value?objString(value):"unknown";
        originBytes+=text.size();
        if(text.size()>512||originBytes>2048||text.find('\0')!=std::string::npos)throw std::runtime_error("Diagnostic origin fields must be UTF-8 text of at most512 bytes each and2048 bytes total");
        if(!first)body+=',';
        first=false;
        body+=json(key)+":"+json(text);
      }
      body+="},\"payload_bytes\":"+std::to_string(length)+",\"payload_base64\":"+json(b64(bytes,size_t(length)));
      PacketHeader header;
      header.payload_bytes=uint32_t(length);
      std::string packet(sizeof header,'\0');
      memcpy(packet.data(),&header,sizeof header);
      packet+=body;
      auto sent=send(socket.n,packet.data(),packet.size(),MSG_DONTWAIT|MSG_NOSIGNAL);
      if(sent==ssize_t(packet.size())){
        shared->accepted_records.fetch_add(1);
        shared->accepted_bytes.fetch_add(uint64_t(length));
        number(i,result,"accepted",1);
        put(i,result,"reason",std::string("queued"));
      }
      else {
        shared->transport_dropped_records.fetch_add(1);
        shared->transport_dropped_bytes.fetch_add(uint64_t(length));
        put(i,result,"reason",std::string(errno==EAGAIN||errno==EWOULDBLOCK?"overload":"broken_ipc"));
        if(errno!=EAGAIN&&errno!=EWOULDBLOCK){
          error(shared,systemError("Emit diagnostics IPC"));
          shared->accepting.store(0);
          shared->phase.store(Failed);
          kill(child,SIGKILL);
        }
      }
      return result;
    }
    std::string launch(const std::string& kind,const Selection& selection,const std::string& target){
      for(auto& entry:tasks)if(entry.second->state.load()==0)throw std::runtime_error("A diagnostics read/export request is already active");
      if(tasks.size()>=16)throw std::runtime_error("Consume completed diagnostics requests before submitting more");
      if(config.directory.empty())throw std::runtime_error("Configure log_directory before reading diagnostics");
      auto task=std::make_shared<Task>();
      task->token=std::to_string(getpid())+"-"+std::to_string(++serial);
      task->kind=kind;
      tasks[task->token]=task;
      auto captured=config;
      std::thread([task,captured,selection,target]{
        try{
          if(task->kind=="cleanup_preview"||task->kind=="cleanup")runMaintenance(task,captured,selection);
          else runRead(task,captured,selection,task->kind=="export",target);
          task->state.store(task->cancel.load()&&!task->mutationStarted.load()?3:1);
        }
        catch(const std::exception& e){
          task->error=e.what();
          if(task->error.rfind("CURSOR_EXPIRED",0)==0)task->code="CURSOR_EXPIRED";
          else if(task->error.rfind("SELECTION_EXPIRED",0)==0)task->code="SELECTION_EXPIRED";
          else if(task->error.rfind("READ_BUDGET_TOO_SMALL",0)==0)task->code="READ_BUDGET_TOO_SMALL";
          task->state.store(task->cancel.load()&&!task->mutationStarted.load()?3:2);
        }
      }).detach();
      return task->token;
    }
    Tcl_Obj* request(Tcl_Interp* i,const std::string& token){
      auto found=tasks.find(token);
      if(found==tasks.end())throw std::runtime_error("Unknown diagnostics request");
      auto task=found->second;
      int state=task->state.load();
      auto d=Tcl_NewDictObj();
      put(i,d,"state",std::string(state==0?"pending":state==1?"done":state==3?"cancelled":"error"));
      put(i,d,"token",token);
      if(state==0)return d;
      if(state==2){
        put(i,d,"message",task->error);
        put(i,d,"error_code",task->code);
        auto removed=Tcl_NewListObj(0,nullptr);
        for(auto& f:task->files)if(f.removed)Tcl_ListObjAppendElement(i,removed,stringObj(filename(f.index)));
        put(i,d,"removed_files",removed);
      }
      else if(state==1){
        auto result=Tcl_NewDictObj();
        put(i,result,"schema",std::string("gxtxt.stderr_read.v1"));
        put(i,result,"operation",task->kind);
        put(i,result,"cursor",task->cursor);
        number(i,result,"eof",task->eof);
        number(i,result,"bytes",task->bytes);
        number(i,result,"record_count",task->recordCount);
        if(!task->path.empty())put(i,result,"path",task->path);
        auto records=Tcl_NewListObj(0,nullptr);
        for(auto& r:task->records){
          auto record=Tcl_NewDictObj(),origin=Tcl_NewDictObj();
          put(i,record,"schema",std::string("gxtxt.stderr_record.v1"));
          put(i,record,"record_id",r.id);
          number(i,record,"generation",r.generation);
          number(i,record,"sequence",r.sequence);
          number(i,record,"timestamp_us",r.time);
          number(i,record,"pid",r.pid);
          number(i,record,"capture_pid",r.pid);
          for(auto& field:r.origin)put(i,origin,field.first.c_str(),field.second);
          put(i,record,"origin",origin);
          put(i,record,"payload",Tcl_NewByteArrayObj(reinterpret_cast<const unsigned char*>(r.payload.data()),int(r.payload.size())));
          number(i,record,"payload_bytes",r.payload.size());
          put(i,record,"raw_json",r.raw);
          Tcl_ListObjAppendElement(i,records,record);
        }
        put(i,result,"records",records);
        auto files=Tcl_NewListObj(0,nullptr);
        for(auto& f:task->files){
          auto file=Tcl_NewDictObj();
          put(i,file,"name",filename(f.index));
          number(i,file,"device",f.device);
          number(i,file,"inode",f.inode);
          number(i,file,"bytes",f.size);
          number(i,file,"modified_unix_s",f.modified);
          if(!f.guard.empty()){put(i,file,"guard",f.guard);number(i,file,"removed",f.removed);}
          Tcl_ListObjAppendElement(i,files,file);
        }
        put(i,result,"files",files);
        put(i,d,"result",result);
      }
      tasks.erase(found);
      return d;
    }
  };
  Native* owner=nullptr;
  Tcl_Interp* ownerInterp=nullptr;
  void cleanup(ClientData data,Tcl_Interp*){
    delete static_cast<Native*>(data);
    owner=nullptr;
    ownerInterp=nullptr;
  }
  Selection parseSelection(Tcl_Interp* i,Tcl_Obj* object){
    Selection s;
    s.limit=4096;
    s.maxBytes=8388608;
    Tcl_DictSearch search;
    Tcl_Obj *key,*value;
    int done;
    if(Tcl_DictObjFirst(i,object,&search,&key,&value,&done)!=TCL_OK)throw std::runtime_error("Export selection must be a dictionary");
    try{
      for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){
        auto name=objString(key);
        if(name=="cursor")s.cursor=objString(value);
        else if(name=="limit")s.limit=unsigned(boundedNumber(i,value,1,4096,"limit"));
        else if(name=="max_bytes")s.maxBytes=boundedNumber(i,value,1,8388608,"max_bytes");
        else if(name=="record_ids"){
          int n;
          Tcl_Obj** ids;
          if(Tcl_ListObjGetElements(i,value,&n,&ids)!=TCL_OK||n<1||n>4096)throw std::runtime_error("record_ids must contain1..4096 stable identities");
          for(int j=0;j<n;++j){
            auto id=objString(ids[j]);
            if(id.size()>64||id.find_first_not_of("0123456789:")!=std::string::npos||id.find(':')==std::string::npos)throw std::runtime_error("Invalid stable diagnostic record identity");
            s.ids.insert(id);
          }
        }
        else throw std::runtime_error("Unknown export selection key: "+name);
      }
    }
    catch(...){
      Tcl_DictObjDone(&search);
      throw;
    }
    Tcl_DictObjDone(&search);
    if(!s.ids.empty()&&!s.cursor.empty())throw std::runtime_error("Export selection must use record_ids or cursor interval");
    return s;
  }
  int command(ClientData data,Tcl_Interp* i,int objc,Tcl_Obj* const objv[]){
    auto& native=*static_cast<Native*>(data);
    try{
      if(objc<2)throw std::runtime_error("Expected a diagnostics operation");
      auto operation=objString(objv[1]);
      Tcl_Obj* result=nullptr;
      if(operation=="info"&&objc==2){
        result=Tcl_NewDictObj();
        put(i,result,"schema",std::string("gxtxt.stderr_api.v1"));
        number(i,result,"api_version",1);
        put(i,result,"native_build_id",std::string("dev111.p026.stderr.v1"));
        number(i,result,"max_payload_bytes",maxPayload);
        number(i,result,"available",1);
#ifdef GXDIAG_PRIVATE_FIXTURES
        number(i,result,"private_fixture_build",1);
#else
        number(i,result,"private_fixture_build",0);
#endif
      }
      else if(operation=="status"&&objc==2)result=native.status(i);
      else if(operation=="producer_descriptor"&&objc==2){
        native.reap();
        result=stringObj(native.shared&&!native.stopping&&native.shared->phase.load()==Running&&native.shared->accepting.load()?native.descriptor:"");
      }
      else if((operation=="start"||operation=="configure")&&(objc==2||objc==3)){
        Config config=objc==3?parseConfig(i,objv[2],native.config):native.config;
        native.reap();
        bool active=native.child>0&&!native.stopping&&native.shared->phase.load()!=Failed;
        bool same=config.directory==native.config.directory&&config.maxBytes==native.config.maxBytes&&config.ringBytes==native.config.ringBytes&&config.maxFiles==native.config.maxFiles;
        if(active&&!same){
          native.stop();
          native.config=config;
          native.restartRequested=true;
        }
        else native.config=config;
        if(operation=="start"&&!active){
          if(native.child>0){
            if(!native.stopping)native.stop();
            native.restartRequested=true;
          }
          else native.start();
        }
        result=native.status(i);
      }
      else if(operation=="stop"&&objc==2){
        native.stop();
        result=native.status(i);
      }
      else if(operation=="emit"&&objc==4)result=native.emit(i,objv[2],objv[3]);
      else if(operation=="meta"&&objc==2){
        Selection selection;
        result=stringObj(native.launch("meta",selection,""));
      }
      else if(operation=="cleanup_preview"&&objc==2){
        Selection selection;
        result=stringObj(native.launch(operation,selection,""));
      }
      else if(operation=="cleanup"&&objc==3){
        Selection selection;int count=0;Tcl_Obj** values=nullptr;
        if(Tcl_ListObjGetElements(i,objv[2],&count,&values)!=TCL_OK||count>100)throw std::runtime_error("Expected at most100 diagnostic preview guards");
        for(int n=0;n<count;++n){auto value=objString(values[n]);
          if(value.empty()||value.size()>256||value.find_first_not_of("0123456789:")!=std::string::npos)throw std::runtime_error("Invalid diagnostics preview guard");
          if(!selection.files.insert(value).second)throw std::runtime_error("Duplicate diagnostics preview guard");
        }
        result=stringObj(native.launch(operation,selection,""));
      }
      else if(operation=="read"&&objc>=2&&objc<=5){
        Selection selection;
        if(objc>2)selection.cursor=objString(objv[2]);
        if(objc>3)selection.limit=unsigned(boundedNumber(i,objv[3],1,256,"limit"));
        if(objc>4)selection.maxBytes=boundedNumber(i,objv[4],1,1048576,"max_bytes");
        result=stringObj(native.launch("read",selection,""));
      }
      else if(operation=="export"&&objc==4){
        auto selection=parseSelection(i,objv[2]);
        auto target=objString(objv[3]);
        if(target.find('\0')!=std::string::npos||target.size()>4096)throw std::runtime_error("Invalid export destination");
        result=stringObj(native.launch("export",selection,target));
      }
      else if(operation=="request"&&objc==3)result=native.request(i,objString(objv[2]));
      else if(operation=="cancel"&&objc==3){
        auto found=native.tasks.find(objString(objv[2]));
        if(found==native.tasks.end())throw std::runtime_error("Unknown diagnostics request");
        std::lock_guard<std::mutex> boundary(found->second->mutationBoundary);
        bool cancellable=!found->second->mutationStarted.load();
        if(cancellable)found->second->cancel.store(true);
        result=Tcl_NewIntObj(cancellable?1:0);
      }
      else throw std::runtime_error("Unknown diagnostics operation or invalid arguments: "+operation);
      Tcl_SetObjResult(i,result);
      return TCL_OK;
    }
    catch(const std::exception& e){
      Tcl_SetObjResult(i,Tcl_NewStringObj(e.what(),-1));
      Tcl_SetErrorCode(i,"GX","STDERR_DIAGNOSTICS","INVALID_OR_FAILED",nullptr);
      return TCL_ERROR;
    }
  }
}
extern "C" int Gxdiagnostics_Init(Tcl_Interp* interp){
  if(!Tcl_InitStubs(interp,"8.6",0))return TCL_ERROR;
  if(Tcl_IsSafe(interp)){
    Tcl_SetObjResult(interp,Tcl_NewStringObj("Diagnostics is a trusted CORE host API",-1));
    return TCL_ERROR;
  }
  if(owner&&ownerInterp!=interp){
    Tcl_SetObjResult(interp,Tcl_NewStringObj("Diagnostics already belongs to another CORE interpreter",-1));
    return TCL_ERROR;
  }
  if(!owner){
    owner=new Native;
    ownerInterp=interp;
    Tcl_SetAssocData(interp,"gxdiag.owner",cleanup,owner);
  }
  if(Tcl_Eval(interp,"namespace eval ::GX::StderrDiagnostics {}")!=TCL_OK)return TCL_ERROR;
  Tcl_CreateObjCommand(interp,"::GX::StderrDiagnostics::_native",command,owner,nullptr);
  return Tcl_PkgProvide(interp,"gxtxt_stderr_diagnostics_native","1.0");
}
