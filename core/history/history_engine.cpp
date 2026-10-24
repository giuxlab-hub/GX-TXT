// SPDX-License-Identifier: GPL-3.0-or-later
// GX-TXT P017. Tcl objects never leave the interpreter's owning thread.
#include <tcl.h>
#include <openssl/sha.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr size_t MaxAuxiliary = 8388608;
constexpr size_t MaxRecord = 8388608, MaxQueue = 32*1024*1024, MaxFrame = 32*1024*1024;
constexpr size_t MaxSteps = 4096, MaxEngines = 32;
const std::string Deleted = "@gxtxt.recipe.delete";
using Digest = std::array<unsigned char, SHA256_DIGEST_LENGTH>;
struct Error : std::runtime_error { using std::runtime_error::runtime_error; };
std::string str(Tcl_Obj* o) { int n; const char* s=Tcl_GetStringFromObj(o,&n); return std::string(s,n); }
Tcl_Obj* obj(const std::string& s) { return Tcl_NewStringObj(s.data(),static_cast<int>(s.size())); }
struct Ref {
    Tcl_Obj* p=nullptr;
    Ref()=default; explicit Ref(Tcl_Obj* q):p(q){ if(p) Tcl_IncrRefCount(p); }
    Ref(const Ref& r):Ref(r.p){} Ref(Ref&& r)noexcept:p(r.p){r.p=nullptr;}
    Ref& operator=(Ref r){std::swap(p,r.p);return *this;}
    ~Ref(){if(p) Tcl_DecrRefCount(p);}
    operator Tcl_Obj*()const{return p;}
};
void ok(int r,Tcl_Interp* i){if(r!=TCL_OK)throw Error(str(Tcl_GetObjResult(i)));}
Tcl_Obj* get(Tcl_Interp* i,Tcl_Obj* d,const char* k,bool required=true){
    Ref key(Tcl_NewStringObj(k,-1)); Tcl_Obj* v=nullptr; ok(Tcl_DictObjGet(i,d,key,&v),i);
    if(!v&&required)throw Error(std::string("History requires ")+k);
    return v;
}
void put(Tcl_Interp* i,Tcl_Obj* d,const char* k,Tcl_Obj* v){Ref key(Tcl_NewStringObj(k,-1));ok(Tcl_DictObjPut(i,d,key,v),i);}
void putS(Tcl_Interp* i,Tcl_Obj* d,const char* k,const std::string& v){put(i,d,k,obj(v));}
void putN(Tcl_Interp* i,Tcl_Obj* d,const char* k,Tcl_WideInt v){put(i,d,k,Tcl_NewWideIntObj(v));}
long long number(Tcl_Interp* i,Tcl_Obj* o){Tcl_WideInt n;ok(Tcl_GetWideIntFromObj(i,o,&n),i);return n;}
void dict(Tcl_Interp* i,Tcl_Obj* o){int n;ok(Tcl_DictObjSize(i,o,&n),i);}
size_t auxiliarySize(Tcl_Interp* i,Tcl_Obj* value){dict(i,value);int n=0;Tcl_GetStringFromObj(value,&n);if(static_cast<size_t>(n)>MaxAuxiliary)throw Error("History auxiliary state exceeds 8388608 bytes");return static_cast<size_t>(n);}
std::vector<Ref> list(Tcl_Interp* i,Tcl_Obj* o){int n;Tcl_Obj** v;ok(Tcl_ListObjGetElements(i,o,&n,&v),i);std::vector<Ref> r;r.reserve(n);for(int j=0;j<n;++j)r.emplace_back(v[j]);return r;}
std::string element(const std::string& s){int flags=0;int n=Tcl_ScanCountedElement(s.data(),static_cast<int>(s.size()),&flags);std::vector<char> bytes(static_cast<size_t>(n)+1);int used=Tcl_ConvertCountedElement(s.data(),static_cast<int>(s.size()),bytes.data(),flags);return std::string(bytes.data(),used);}
// Worker-safe Tcl list quoting: no Tcl API, mutable Tcl object or interpreter.
std::string quote(const std::string& s){
    if(s.empty())return "{}";
    bool simple=true,braces=true;int depth=0;
    for(size_t n=0;n<s.size();++n){
        unsigned char c=static_cast<unsigned char>(s[n]);
        if(c==' '||c=='\t'||c=='\n'||c=='\r'||c=='\v'||c=='\f'||c=='\\'||c=='{'||c=='}'||c=='['||c==']'||c=='$'||c=='"'||c==';')simple=false;
        if(c=='\\'){
            if(n+1==s.size()){braces=false;break;}
            if(s[n+1]=='\n')braces=false;
            ++n;
        }else if(c=='{')++depth;else if(c=='}'){if(--depth<0)braces=false;}
    }
    if(simple)return s;
    if(braces&&depth==0)return "{"+s+"}";
    std::string out;out.reserve(s.size()+16);
    for(unsigned char c:s){switch(c){
        case ' ':out+="\\ ";break;case '\t':out+="\\t";break;case '\n':out+="\\n";break;case '\r':out+="\\r";break;
        case '\v':out+="\\v";break;case '\f':out+="\\f";break;
        case '\\':case '{':case '}':case '[':case ']':case '$':case '"':case ';':out+='\\';out+=static_cast<char>(c);break;
        default:out+=static_cast<char>(c);
    }}return out;
}
std::string event(const std::string& kind,const std::string& value){return kind+" "+quote(value);}
std::string sys(const std::string& what){return what+": "+std::strerror(errno);}
void writeAll(int fd,const char* p,size_t n){while(n){ssize_t w=::write(fd,p,n);if(w<0){if(errno==EINTR)continue;throw Error(sys("History write failed"));}if(!w)throw Error("History write made no progress");p+=w;n-=w;}}
void syncFd(int fd){if(::fsync(fd))throw Error(sys("History fsync failed"));}
void syncDir(const std::string& p){auto k=p.find_last_of('/');std::string d=k==std::string::npos?".":p.substr(0,k);int fd=::open(d.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(fd<0)throw Error(sys("History directory open failed"));try{syncFd(fd);}catch(...){::close(fd);throw;}::close(fd);}
int safeOpen(const std::string& p,int flags,mode_t mode=0600){int f=::open(p.c_str(),flags|O_CLOEXEC|O_NOFOLLOW,mode);if(f<0)throw Error(sys("History open "+p));struct stat st{};if(fstat(f,&st)||!S_ISREG(st.st_mode)){::close(f);throw Error("History path is not a regular file");}return f;}
void u32(std::string& s,uint32_t n){for(int k=0;k<4;++k)s+=static_cast<char>((n>>(k*8))&255);}
void u64(std::string& s,uint64_t n){for(int k=0;k<8;++k)s+=static_cast<char>((n>>(k*8))&255);}
uint32_t r32(const char* s){uint32_t n=0;for(int k=0;k<4;++k)n|=uint32_t(static_cast<unsigned char>(s[k]))<<(8*k);return n;}
uint64_t r64(const char* s){uint64_t n=0;for(int k=0;k<8;++k)n|=uint64_t(static_cast<unsigned char>(s[k]))<<(8*k);return n;}
Digest digest(const std::string& s){Digest d{};SHA256(reinterpret_cast<const unsigned char*>(s.data()),s.size(),d.data());return d;}
std::string header(const std::string& identity){std::string h("GXH17\0\2\n",8);u32(h,static_cast<uint32_t>(identity.size()));h+=identity;Digest d=digest(h);h.append(reinterpret_cast<const char*>(d.data()),d.size());return h;}
std::string frame(uint64_t revision,const std::string& payload,const Digest& previous,Digest& next){
    std::string data;u64(data,revision);u32(data,static_cast<uint32_t>(payload.size()));data.append(reinterpret_cast<const char*>(previous.data()),previous.size());data+=payload;next=digest(data);
    std::string out=data.substr(0,44);out.append(reinterpret_cast<const char*>(next.data()),next.size());Digest headerHash=digest(out);out.append(reinterpret_cast<const char*>(headerHash.data()),headerHash.size());out+=payload;return out;
}
struct Frame {uint64_t revision;std::string payload;Digest hash;};
struct Scan {std::vector<Frame> frames;bool torn=false;size_t validBytes=0;Digest last{};};
std::string readFile(const std::string& path){
    int fd=safeOpen(path,O_RDONLY);std::string s;char b[65536];
    try{for(;;){ssize_t n=::read(fd,b,sizeof(b));if(n<0){if(errno==EINTR)continue;throw Error(sys("History read failed"));}if(!n)break;s.append(b,n);if(s.size()>256*1024*1024)throw Error("History journal exceeds bounded recovery size");}syncFd(fd);}catch(...){::close(fd);throw;}::close(fd);return s;
}
bool exists(const std::string& p){struct stat s{};if(lstat(p.c_str(),&s)==0){if(S_ISLNK(s.st_mode))throw Error("History symlinks are forbidden");return true;}if(errno!=ENOENT)throw Error(sys("History stat failed"));return false;}
Scan scan(const std::string& path,const std::string& identity,bool checkpoint){
    Scan result;if(!exists(path))return result;std::string s=readFile(path),h=header(identity);
    if(s.size()<h.size()||s.compare(0,h.size(),h)!=0)throw Error("History identity/header checksum mismatch");
    size_t p=h.size();Digest previous{};uint64_t revision=0;
    while(p<s.size()){
        if(s.size()-p<108){result.torn=true;break;}
        const char* b=s.data()+p;Digest headerHash=digest(std::string(b,76));if(memcmp(b+76,headerHash.data(),headerHash.size()))throw Error("History frame header checksum mismatch");uint64_t rev=r64(b);uint32_t n=r32(b+8);
        if(n>MaxFrame)throw Error("History frame length is corrupt");
        if(s.size()-p-108<n){result.torn=true;break;}
        if(!result.frames.empty()&&rev!=revision+1)throw Error("History revisions are not monotonic");
        if(memcmp(b+12,previous.data(),previous.size()))throw Error("History checksum chain mismatch");
        std::string payload(b+108,n),signedBytes(b,44);signedBytes+=payload;Digest hash=digest(signedBytes);
        if(memcmp(b+44,hash.data(),hash.size()))throw Error("History frame checksum mismatch");
        result.frames.push_back(Frame{rev,std::move(payload),hash});previous=hash;revision=rev;p+=108+n;
    }
    if(checkpoint&&(result.torn||result.frames.size()!=1))throw Error("History checkpoint is incomplete or corrupt");
    result.validBytes=p;result.last=previous;return result;
}
struct Step {Ref semantic,inverse,summary;std::string bytes;size_t encoded=0;};
Ref apply(Tcl_Interp* i,Tcl_Obj* state,Tcl_Obj* patch,Ref* inverse=nullptr){
    Ref out(Tcl_DuplicateObj(state)),undo(Tcl_NewDictObj());Tcl_DictSearch search;Tcl_Obj *key,*value;int done;
    ok(Tcl_DictObjFirst(i,patch,&search,&key,&value,&done),i);
    while(!done){Tcl_Obj* old=nullptr;ok(Tcl_DictObjGet(i,out,key,&old),i);
        if(inverse)ok(Tcl_DictObjPut(i,undo,key,old?old:obj(Deleted)),i);
        if(str(value)==Deleted)ok(Tcl_DictObjRemove(i,out,key),i);else ok(Tcl_DictObjPut(i,out,key,value),i);
        Tcl_DictObjNext(&search,&key,&value,&done);
    }Tcl_DictObjDone(&search);if(inverse)*inverse=std::move(undo);return out;
}
Ref difference(Tcl_Interp* i,Tcl_Obj* before,Tcl_Obj* after){
    dict(i,after);Ref patch(Tcl_NewDictObj());Tcl_DictSearch search;Tcl_Obj *key,*value;int done;
    ok(Tcl_DictObjFirst(i,after,&search,&key,&value,&done),i);
    while(!done){Tcl_Obj* old=nullptr;ok(Tcl_DictObjGet(i,before,key,&old),i);if(!old||str(old)!=str(value))ok(Tcl_DictObjPut(i,patch,key,value),i);Tcl_DictObjNext(&search,&key,&value,&done);}Tcl_DictObjDone(&search);
    ok(Tcl_DictObjFirst(i,before,&search,&key,&value,&done),i);
    while(!done){Tcl_Obj* v=nullptr;ok(Tcl_DictObjGet(i,after,key,&v),i);if(!v)ok(Tcl_DictObjPut(i,patch,key,obj(Deleted)),i);Tcl_DictObjNext(&search,&key,&value,&done);}Tcl_DictObjDone(&search);return patch;
}
struct Model {
    std::string metadata,base,auxiliary;std::vector<std::string> steps;size_t cursor=0;
    std::string record()const{std::string l;for(auto& s:steps){if(!l.empty())l+=' ';l+=quote(s);}return metadata+" base "+quote(base)+" steps "+quote(l)+" cursor "+std::to_string(cursor);}
    std::string bundle()const{return "record "+quote(record())+" auxiliary "+quote(auxiliary);}
    void update(const std::string& kind,const std::string& value){
        if(kind=="append"){steps.push_back(value);cursor=steps.size();}
        else if(kind=="navigate")cursor=std::stoull(value);
        else if(kind=="branch"){cursor=std::stoull(value);steps.resize(cursor);}
        else if(kind=="clear"){base=value;steps.clear();cursor=0;}
        else if(kind=="auxiliary")auxiliary=value;
    }
};
struct Job {uint64_t revision=0;std::string kind,value,payload;size_t bytes=0;bool checkpoint=false;};
struct Worker {
    std::string path,identity;int lock=-1;std::thread thread;std::mutex mutex;std::condition_variable cv;
    std::deque<Job> queue;size_t queuedBytes=0,queueLimit=MaxQueue;bool stopping=false;uint64_t durable=0;std::string failure;Model model;
    Digest chain{};size_t journalBytes=0,events=0;bool resume=false;size_t validBytes=0;
    Worker(std::string p,std::string id,Model m):path(std::move(p)),identity(std::move(id)),model(std::move(m)){}
    ~Worker(){stop();if(lock>=0)::close(lock);}
    void start(){thread=std::thread([this]{run();});}
    void stop(){if(thread.joinable()){{std::lock_guard<std::mutex> g(mutex);stopping=true;}cv.notify_all();thread.join();}}
    void reserve(size_t bytes){std::lock_guard<std::mutex>g(mutex);if(!failure.empty())throw Error("History persistence failed: "+failure);if(bytes>queueLimit||queuedBytes>queueLimit-bytes||queue.size()>=8192)throw Error("History persistence queue is full; wait for durable writes before submitting again");}
    void enqueue(Job j){std::lock_guard<std::mutex>g(mutex);if(!failure.empty())throw Error("History persistence failed: "+failure);if(j.bytes>queueLimit||queuedBytes>queueLimit-j.bytes||queue.size()>=8192)throw Error("History persistence queue is full");size_t bytes=j.bytes;queue.push_back(std::move(j));queuedBytes+=bytes;cv.notify_all();}
    void checkpoint(uint64_t revision,int& fd){
        std::string target=path+".checkpoint",tmp=target+".pending."+std::to_string(::getpid());
        std::string journalTmp=path+".pending."+std::to_string(::getpid());
        Digest hash{};std::string b=header(identity),payload=event("snapshot_bundle",model.bundle());b+=frame(revision,payload,Digest{},hash);
        int cf=-1,jf=-1;
        try{
            cf=safeOpen(tmp,O_CREAT|O_EXCL|O_WRONLY);writeAll(cf,b.data(),b.size());syncFd(cf);::close(cf);cf=-1;
            if(::rename(tmp.c_str(),target.c_str()))throw Error(sys("History checkpoint publication failed"));
            syncDir(target);
            // Publish the empty suffix atomically. An interrupted checkpoint
            // leaves either the old complete suffix (covered by the newer
            // checkpoint) or the new complete header; never a torn header.
            jf=safeOpen(journalTmp,O_CREAT|O_EXCL|O_WRONLY);std::string h=header(identity);writeAll(jf,h.data(),h.size());syncFd(jf);
            if(::rename(journalTmp.c_str(),path.c_str()))throw Error(sys("History suffix publication failed"));
            syncDir(path);
            if(fd>=0)::close(fd);
            fd=jf;jf=-1;chain={};journalBytes=h.size();events=0;
        }catch(...){if(cf>=0)::close(cf);if(jf>=0)::close(jf);::unlink(tmp.c_str());::unlink(journalTmp.c_str());throw;}
    }
    void run(){
        int fd=-1;
        try{
            if(resume){
                fd=safeOpen(path,O_CREAT|O_WRONLY);
                if(ftruncate(fd,static_cast<off_t>(validBytes)))throw Error(sys("History torn-tail repair failed"));
                if(validBytes==0){std::string h=header(identity);writeAll(fd,h.data(),h.size());syncFd(fd);validBytes=h.size();chain={};}
                if(lseek(fd,0,SEEK_END)<0)throw Error(sys("History seek failed"));
                journalBytes=validBytes;
            }
            while(true){
                std::vector<Job> batch;batch.reserve(64);size_t bytes=0;
                {
                    std::unique_lock<std::mutex>g(mutex);cv.wait(g,[this]{return stopping||!queue.empty();});
                    if(queue.empty()){if(stopping)break;continue;}
                    while(!queue.empty()&&batch.size()<64&&bytes<1024*1024){bytes+=queue.front().bytes;batch.push_back(std::move(queue.front()));queue.pop_front();}
                }
                uint64_t completed=0;bool dirty=false;
                for(auto& j:batch){
                    if(j.kind!="snapshot"&&j.kind!="snapshot_bundle")model.update(j.kind,j.value);
                    if(j.checkpoint||fd<0){checkpoint(j.revision,fd);dirty=false;}
                    else{
                        Digest next{};std::string b=frame(j.revision,j.payload,chain,next);writeAll(fd,b.data(),b.size());chain=next;journalBytes+=b.size();++events;dirty=true;
                        if(events>=1024||journalBytes>8*1024*1024){checkpoint(j.revision,fd);dirty=false;}
                    }
                    completed=j.revision;
                }
                if(dirty)syncFd(fd);
                {std::lock_guard<std::mutex>g(mutex);durable=completed;queuedBytes-=bytes;}
                cv.notify_all();
            }
        }catch(const std::exception& e){std::lock_guard<std::mutex>g(mutex);failure=e.what();cv.notify_all();}
        if(fd>=0)::close(fd);
    }
    void flush(uint64_t revision,int timeout){
        std::unique_lock<std::mutex>g(mutex);if(!cv.wait_for(g,std::chrono::milliseconds(timeout),[&]{return durable>=revision||!failure.empty();}))throw Error("History flush timed out; accepted operations remain pending");
        if(!failure.empty())throw Error("History persistence failed: "+failure);
    }
};
struct Engine {
    Tcl_Interp* interp;std::string owner;Ref metadata,base,current,auxiliary{Tcl_NewDictObj()};std::vector<Step> steps;size_t cursor=0,sizeBytes=0,auxiliaryBytes=0;bool legacyImport=false;uint64_t revision=0;std::unique_ptr<Worker> worker;
    Engine(Tcl_Interp* i,std::string o,Tcl_Obj* record):interp(i),owner(std::move(o)){load(record);}
    void load(Tcl_Obj* record){
        dict(interp,record);if(str(get(interp,record,"workbench_id"))!=owner)throw Error("History scientific owner mismatch");
        if(Tcl_Obj* format=get(interp,record,"format",false)){if(str(format)!="gxtxt.scientific_recipe.v1")throw Error("Unsupported scientific History format");}
        if(Tcl_Obj* flag=get(interp,record,"legacy_import",false)){long long n=number(interp,flag);if(n!=0&&n!=1)throw Error("Invalid legacy History import flag");legacyImport=n==1;}
        base=Ref(get(interp,record,"base"));dict(interp,base);current=base;metadata=Ref(Tcl_DuplicateObj(record));
        for(auto key:{"base","steps","cursor"}){Ref k(Tcl_NewStringObj(key,-1));ok(Tcl_DictObjRemove(interp,metadata,k),interp);}
        auto input=list(interp,get(interp,record,"steps"));if(input.size()>MaxSteps)throw Error("History exceeds 4096 retained steps");
        for(auto& s:input){Step step=makeStep(s);current=apply(interp,current,get(interp,s,"patch"),&step.inverse);steps.push_back(std::move(step));}
        cursor=steps.size();long long n=number(interp,get(interp,record,"cursor"));if(n<0||static_cast<size_t>(n)>steps.size())throw Error("Invalid History cursor");setCursor(static_cast<size_t>(n));
        sizeBytes=recordSize();if(sizeBytes>importLimit())throw Error("History exceeds the 8 MiB retained record limit (legacy envelope allowance is limited to 4096 bytes)");
    }
    Step makeStep(Tcl_Obj* value){
        dict(interp,value);for(auto key:{"api_id","api_version","operation","parameters","targets","result_ids","working_unit","patch"})get(interp,value,key);
        if(number(interp,get(interp,value,"api_version"))!=1)throw Error("Invalid History API version");
        const std::string api=str(get(interp,value,"api_id"));
        if(api!="SCIENTIFIC_RECIPE_API_v1"&&api!="NATIVE_2D_GEOMETRY_API_v1"&&api!="NATIVE_3D_GEOMETRY_API_v1")throw Error("Unsupported History semantic API");
        dict(interp,get(interp,value,"patch"));
        Step s;s.semantic=Ref(value);s.summary=Ref(Tcl_NewDictObj());
        for(auto key:{"description","timestamp","operation","api_id","api_version","group","group_id","group_label"}){if(Tcl_Obj* v=get(interp,value,key,false))put(interp,s.summary,key,v);}
        // Old scientific recipes have no display fields. Preserve their exact
        // semantic record; synthesize presentation only in this small summary.
        if(!get(interp,s.summary,"description",false)){Tcl_Obj* text=get(interp,value,"semantic_operation",false);put(interp,s.summary,"description",text?text:get(interp,value,"operation"));}
        if(!get(interp,s.summary,"timestamp",false))putN(interp,s.summary,"timestamp",0);
        put(interp,s.summary,"patch",Tcl_NewDictObj());s.bytes=str(value);s.encoded=element(s.bytes).size();return s;
    }
    size_t importLimit()const{return MaxRecord+(legacyImport?4096:0);}
    size_t recordSize()const{size_t n=str(metadata).size()+element(str(base)).size()+40;for(auto& s:steps)n+=s.encoded+1;return n;}
    Model model()const{Model m;m.metadata=str(metadata);m.base=str(base);m.auxiliary=str(auxiliary);m.cursor=cursor;for(auto& s:steps)m.steps.push_back(s.bytes);return m;}
    void importAuxiliary(Tcl_Obj* value){size_t n=auxiliarySize(interp,value);auxiliary=Ref(value);auxiliaryBytes=n;}
    void setAuxiliary(Tcl_Obj* value){
        size_t n=auxiliarySize(interp,value);
        if(str(value)==str(auxiliary))return;
        Ref delta=difference(interp,auxiliary,value);int changed=0;ok(Tcl_DictObjSize(interp,delta,&changed),interp);if(!changed)return;
        Ref candidate(value);Job j=prepare("auxiliary",str(value));
        submit(std::move(j));auxiliary=std::move(candidate);auxiliaryBytes=n;
    }
    Ref record(bool summary=false)const{
        Ref r(Tcl_DuplicateObj(metadata));put(interp,r,"base",base);Ref l(Tcl_NewListObj(0,nullptr));for(auto& s:steps)ok(Tcl_ListObjAppendElement(interp,l,summary?s.summary.p:s.semantic.p),interp);put(interp,r,"steps",l);putN(interp,r,"cursor",cursor);return r;
    }
    Ref state(size_t target)const{
        if(target>steps.size())throw Error("History index is outside retained timeline");
        Ref s=current;
        for(size_t n=cursor;n>target;--n)s=apply(interp,s,steps[n-1].inverse);
        for(size_t n=cursor;n<target;++n)s=apply(interp,s,get(interp,steps[n].semantic,"patch"));
        return s;
    }
    void setCursor(size_t target){current=state(target);cursor=target;}
    Job prepare(const std::string& kind,const std::string& value,bool cp=false){
        Job j;j.revision=revision+1;j.kind=kind;j.value=value;j.payload=event(kind,value);j.bytes=j.payload.size()+108;j.checkpoint=cp;
        if(worker)worker->reserve(j.bytes);
        return j;
    }
    void submit(Job j){if(worker)worker->enqueue(j);revision=j.revision;}
    Ref status()const{
        Ref s(Tcl_NewDictObj());putN(interp,s,"count",steps.size());putN(interp,s,"cursor",cursor);putN(interp,s,"revision",revision);putN(interp,s,"accepted_revision",revision);putN(interp,s,"record_bytes",sizeBytes);putN(interp,s,"auxiliary_bytes",auxiliaryBytes);
        uint64_t durable=0;size_t pending=0,bytes=0,queueLimit=MaxQueue;std::string error;
        if(worker){std::lock_guard<std::mutex>g(worker->mutex);durable=worker->durable;bytes=worker->queuedBytes;queueLimit=worker->queueLimit;error=worker->failure;pending=revision>durable?revision-durable:0;}
        putN(interp,s,"durable_revision",durable);putN(interp,s,"pending",pending);putN(interp,s,"queued_bytes",bytes);putN(interp,s,"queue_limit",queueLimit);putN(interp,s,"failed",!error.empty());putN(interp,s,"accepted",1);
        putS(interp,s,"status",!error.empty()?"failed":!worker?"ram":pending?"pending":"durable");putS(interp,s,"error",error);return s;
    }
    void append(Tcl_Obj* snapshot,Tcl_Obj* patch,const std::string& description,Tcl_Obj* semantic){
        if(cursor!=steps.size())throw Error("Confirm an explicit History branch before editing an older state");
        Ref delta=patch?Ref(patch):difference(interp,current,snapshot);dict(interp,delta);int n;ok(Tcl_DictObjSize(interp,delta,&n),interp);if(!n)return;
        if(steps.size()>=MaxSteps)throw Error("History limit reached (4096 steps); save/export and explicitly clear before further edits");
        Ref data(semantic?Tcl_DuplicateObj(semantic):Tcl_NewDictObj());dict(interp,data);
        if(!get(interp,data,"api_id",false))putS(interp,data,"api_id","SCIENTIFIC_RECIPE_API_v1");
        if(!get(interp,data,"api_version",false))putN(interp,data,"api_version",1);
        if(!get(interp,data,"operation",false))putS(interp,data,"operation","workspace_state");
        for(auto key:{"parameters","targets","result_ids","working_unit"})if(!get(interp,data,key,false))putS(interp,data,key,"");
        putS(interp,data,"description",description);putN(interp,data,"timestamp",std::chrono::system_clock::to_time_t(std::chrono::system_clock::now()));put(interp,data,"patch",delta);
        Step step=makeStep(data);size_t proposed=sizeBytes+step.encoded+1;if(proposed>MaxRecord)throw Error("History exceeds the 8 MiB limit; save/export and explicitly clear before further edits");
        Ref next=apply(interp,current,delta,&step.inverse);Job j=prepare("append",step.bytes);
        // Reserve all allocations before accepting a worker job. The main thread
        // owns steps/current and can publish immediately after successful enqueue.
        if(steps.size()==steps.capacity())steps.reserve(std::max<size_t>(16,steps.capacity()*2));
        submit(std::move(j));steps.push_back(std::move(step));current=std::move(next);cursor=steps.size();sizeBytes=proposed;
    }
    void navigate(size_t target){if(target>steps.size())throw Error("History index is outside retained timeline");if(target==cursor)return;Ref next=state(target);Job j=prepare("navigate",std::to_string(target));submit(std::move(j));current=std::move(next);cursor=target;}
    void branch(size_t target){if(target>steps.size())throw Error("History branch index is outside retained timeline");if(target==steps.size()&&target==cursor)return;Ref next=state(target);Job j=prepare("branch",std::to_string(target));submit(std::move(j));steps.resize(target);current=std::move(next);cursor=target;sizeBytes=recordSize();}
    void clear(Tcl_Obj* snapshot){dict(interp,snapshot);size_t bytes=str(metadata).size()+element(str(snapshot)).size()+40;if(bytes>MaxRecord)throw Error("History base exceeds 8 MiB");Job j=prepare("clear",str(snapshot));submit(std::move(j));base=Ref(snapshot);current=base;steps.clear();cursor=0;sizeBytes=bytes;}
};
struct Recovered {Ref record,auxiliary{Tcl_NewDictObj()};uint64_t revision=0;bool torn=false;size_t validBytes=0;Digest chain{};};
Recovered recover(Tcl_Interp* i,const std::string& path,const std::string& identity){
    Scan cp=scan(path+".checkpoint",identity,true),log=scan(path,identity,false);Recovered result;std::unique_ptr<Engine> e;
    auto consume=[&](const Frame& f){
        if(e&&f.revision<=result.revision)return;
        Ref payload(obj(f.payload));auto fields=list(i,payload);if(fields.size()!=2)throw Error("History frame event is malformed");std::string kind=str(fields[0]);
        if(kind=="snapshot"||kind=="snapshot_bundle"){
            Tcl_Obj* record=kind=="snapshot"?fields[1].p:get(i,fields[1],"record");
            std::string owner=str(get(i,record,"workbench_id"));e=std::make_unique<Engine>(i,owner,record);
            if(kind=="snapshot_bundle")e->importAuxiliary(get(i,fields[1],"auxiliary"));
        }
        else{
            if(!e)throw Error("History journal has no checkpoint");
            if(f.revision!=result.revision+1)throw Error("History recovery revision gap");
            if(kind=="append"){Step s=e->makeStep(fields[1]);e->current=apply(i,e->current,get(i,s.semantic,"patch"),&s.inverse);e->steps.push_back(std::move(s));e->cursor=e->steps.size();}
            else if(kind=="navigate")e->setCursor(static_cast<size_t>(number(i,fields[1])));
            else if(kind=="branch"){size_t n=static_cast<size_t>(number(i,fields[1]));e->setCursor(n);e->steps.resize(n);}
            else if(kind=="clear"){dict(i,fields[1]);e->base=fields[1];e->current=e->base;e->steps.clear();e->cursor=0;}
            else if(kind=="auxiliary")e->importAuxiliary(fields[1]);
            else throw Error("Unknown History journal event");
        }
        result.revision=f.revision;
    };
    for(auto& f:cp.frames)consume(f);
    for(auto& f:log.frames)consume(f);
    if(!e)throw Error("No recoverable History checkpoint exists");
    if(e->steps.size()>MaxSteps||e->recordSize()>e->importLimit())throw Error("Recovered History exceeds its limits");
    syncDir(path);
    result.record=e->record();result.auxiliary=e->auxiliary;result.torn=log.torn;result.validBytes=log.validBytes;result.chain=log.last;return result;
}
struct Context {Tcl_Interp* interp;unsigned long serial=0;std::map<std::string,std::unique_ptr<Engine>> engines;};
void shutdown(ClientData data){
    // Tclsh can exit without deleting its interpreter. Stop/drain owned writers
    // before Tcl unloads extension libraries; do not touch Tcl objects here.
    auto* context=static_cast<Context*>(data);
    for(auto& item:context->engines){
        Worker* worker=item.second->worker.get();if(!worker)continue;
        try{
            worker->stop();
            std::string failure;{std::lock_guard<std::mutex>g(worker->mutex);failure=worker->failure;}
            if(!failure.empty()){std::string message="GX History persistence failed during process exit: "+failure+"\n";::write(STDERR_FILENO,message.data(),message.size());}
        }catch(const std::exception& error){std::string message="GX History writer shutdown failed: "+std::string(error.what())+"\n";::write(STDERR_FILENO,message.data(),message.size());}
    }
}
void cleanup(ClientData p,Tcl_Interp*){Tcl_DeleteExitHandler(shutdown,p);delete static_cast<Context*>(p);}
void args(int n,int min,int max,const char* help){if(n<min||n>max)throw Error(std::string("usage: ::GX::historyNative ")+help);}
int command(ClientData data,Tcl_Interp* i,int argc,Tcl_Obj*const argv[]){
    auto* ctx=static_cast<Context*>(data);
    try{
        args(argc,2,100,"subcommand ...");std::string cmd=str(argv[1]);
        if(cmd=="open"){
            args(argc,6,7,"open owner record journalPath identity ?initialAuxiliary?");if(ctx->engines.size()>=MaxEngines)throw Error("Too many active native History engines");std::string owner=str(argv[2]),path=str(argv[4]),identity=str(argv[5]);
            auto e=std::make_unique<Engine>(i,owner,argv[3]);
            if(argc==7)e->importAuxiliary(argv[6]);
            if(!path.empty()){
                if(identity.empty()||identity.size()>65536)throw Error("History requires a bounded Session/Document identity");
                e->worker=std::make_unique<Worker>(path,identity,e->model());e->worker->lock=safeOpen(path+".lock",O_CREAT|O_RDWR);
                if(flock(e->worker->lock,LOCK_EX|LOCK_NB))throw Error("History already has an active writer for this Document");
                bool old=exists(path)||exists(path+".checkpoint");
                if(old){auto recovered=recover(i,path,identity);Ref supplied=e->record();if(str(supplied)!=str(recovered.record))throw Error("History journal differs from supplied record; explicitly recover or retire it before opening");if(argc==7&&str(e->auxiliary)!=str(recovered.auxiliary))throw Error("History journal auxiliary state differs from supplied initial auxiliary state");e->importAuxiliary(recovered.auxiliary);e->worker->model=e->model();e->revision=recovered.revision;e->worker->durable=recovered.revision;e->worker->resume=true;e->worker->validBytes=recovered.validBytes;e->worker->chain=recovered.chain;}
                else{Job j;j.revision=1;j.kind="snapshot_bundle";j.value=e->model().bundle();j.payload=event("snapshot_bundle",j.value);j.bytes=j.payload.size()+108;j.checkpoint=true;e->submit(std::move(j));}
                e->worker->start();
            }
            std::string h="history#"+std::to_string(++ctx->serial);ctx->engines.emplace(h,std::move(e));Tcl_SetObjResult(i,obj(h));return TCL_OK;
        }
        if(cmd=="recover"){
            args(argc,4,4,"recover journalPath identity");std::string path=str(argv[2]);int lock=safeOpen(path+".lock",O_CREAT|O_RDWR);if(flock(lock,LOCK_SH|LOCK_NB)){::close(lock);throw Error("History recovery requires the active writer to close first");}Recovered r;try{r=recover(i,path,str(argv[3]));}catch(...){::close(lock);throw;}::close(lock);Ref value(Tcl_NewDictObj());put(i,value,"record",r.record);put(i,value,"auxiliary",r.auxiliary);putN(i,value,"revision",r.revision);putN(i,value,"durable_revision",r.revision);putN(i,value,"torn_tail",r.torn);putS(i,value,"status","recovered");Tcl_SetObjResult(i,value);return TCL_OK;
        }
        args(argc,3,8,"subcommand handle ...");auto it=ctx->engines.find(str(argv[2]));if(it==ctx->engines.end())throw Error("Unknown or closed native History handle");Engine& e=*it->second;
        if(cmd=="append"||cmd=="appendPatch"){args(argc,5,6,"append[Patch] handle snapshotOrPatch description ?semantic?");e.append(cmd=="append"?argv[3]:nullptr,cmd=="appendPatch"?argv[3]:nullptr,str(argv[4]),argc==6?argv[5]:nullptr);Tcl_SetObjResult(i,e.status());}
        else if(cmd=="auxiliary"){args(argc,3,4,"auxiliary handle ?dictionary?");if(argc==4){e.setAuxiliary(argv[3]);Tcl_SetObjResult(i,e.status());}else Tcl_SetObjResult(i,e.auxiliary);}
        else if(cmd=="status"){args(argc,3,3,"status handle");Tcl_SetObjResult(i,e.status());}
        else if(cmd=="entry"){args(argc,4,4,"entry handle oneBasedIndex");long long index=number(i,argv[3]);if(index<1||static_cast<size_t>(index)>e.steps.size())throw Error("History entry index is outside retained timeline");Tcl_SetObjResult(i,e.steps[static_cast<size_t>(index)-1].semantic);}
        else if(cmd=="record"||cmd=="summary"){args(argc,3,3,"record|summary handle");Tcl_SetObjResult(i,e.record(cmd=="summary"));}
        else if(cmd=="state"){args(argc,3,4,"state handle ?index?");long long n=argc==4?number(i,argv[3]):-1;if(n< -1)throw Error("Invalid History state index");Tcl_SetObjResult(i,e.state(n==-1?e.cursor:static_cast<size_t>(n)));}
        else if(cmd=="navigate"||cmd=="branch"){args(argc,4,4,"navigate|branch handle index");long long n=number(i,argv[3]);if(n<0)throw Error("Invalid History index");if(cmd=="navigate")e.navigate(n);else e.branch(n);Tcl_SetObjResult(i,e.status());}
        else if(cmd=="clear"){args(argc,4,4,"clear handle snapshot");e.clear(argv[3]);Tcl_SetObjResult(i,e.status());}
        else if(cmd=="rows"){
            args(argc,3,5,"rows handle ?start? ?count?");long long start=argc>=4?number(i,argv[3]):0,count=argc==5?number(i,argv[4]):static_cast<long long>(e.steps.size());if(start<0||count<0)throw Error("Invalid History rows range");Ref rows(Tcl_NewListObj(0,nullptr));
            size_t end=std::min(e.steps.size(),static_cast<size_t>(start)+static_cast<size_t>(count));for(size_t n=start;n<end;++n){Ref row(Tcl_DuplicateObj(e.steps[n].summary));putN(i,row,"index",n+1);ok(Tcl_ListObjAppendElement(i,rows,row),i);}Tcl_SetObjResult(i,rows);
        }
        else if(cmd=="queueLimit"){args(argc,4,4,"queueLimit handle bytes");long long bytes=number(i,argv[3]);if(bytes<1024||static_cast<size_t>(bytes)>MaxQueue)throw Error("History queue limit must be 1024..33554432 bytes");if(e.worker){std::lock_guard<std::mutex>g(e.worker->mutex);if(static_cast<size_t>(bytes)<e.worker->queuedBytes)throw Error("History queue limit cannot be lower than outstanding bytes");e.worker->queueLimit=static_cast<size_t>(bytes);}Tcl_SetObjResult(i,e.status());}
        else if(cmd=="checkpoint"){args(argc,3,3,"checkpoint handle");if(e.worker){Job j=e.prepare("navigate",std::to_string(e.cursor),true);e.submit(std::move(j));}Tcl_SetObjResult(i,e.status());}
        else if(cmd=="flush"){args(argc,3,4,"flush handle ?timeoutMilliseconds?");int t=argc==4?static_cast<int>(number(i,argv[3])):30000;if(t<0||t>600000)throw Error("Invalid History flush timeout");if(e.worker)e.worker->flush(e.revision,t);Tcl_SetObjResult(i,e.status());}
        else if(cmd=="close"){args(argc,3,3,"close handle");if(e.worker)e.worker->flush(e.revision,30000);Ref s=e.status();ctx->engines.erase(it);Tcl_SetObjResult(i,s);}
        else throw Error("Unknown native History subcommand");
        return TCL_OK;
    }catch(const std::exception& error){Tcl_SetObjResult(i,Tcl_NewStringObj(error.what(),-1));Tcl_SetErrorCode(i,"GX","HISTORY","NATIVE",nullptr);return TCL_ERROR;}
}
}
extern "C" int Gxtxt_history_Init(Tcl_Interp* interp){
    if(!Tcl_InitStubs(interp,"8.6",0))return TCL_ERROR;
    if(!Tcl_FindNamespace(interp,"::GX",nullptr,0))Tcl_CreateNamespace(interp,"::GX",nullptr,nullptr);
    auto* context=new Context;context->interp=interp;Tcl_CreateExitHandler(shutdown,context);Tcl_SetAssocData(interp,"GX.P017.history",cleanup,context);Tcl_CreateObjCommand(interp,"::GX::historyNative",command,context,nullptr);return Tcl_PkgProvide(interp,"gxtxt_history","1.0");
}
