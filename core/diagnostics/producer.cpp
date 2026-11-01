// SPDX-License-Identifier: GPL-3.0-or-later
#include "gxtxt_diagnostics_producer_v1.h"
#include "protocol.h"
#include <algorithm>
#include <chrono>
#include <memory>
#include <sstream>
#include <cstdlib>
#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
using namespace gxdiag;
struct gxdiag_producer_v1 {
    Fd socket;
    Shared* shared=nullptr;
    uint64_t generation=0;
    ~gxdiag_producer_v1(){if(shared)munmap(shared,sizeof(Shared));}
};
namespace {
struct Emitting {
    Shared* shared;
    explicit Emitting(Shared* value):shared(value){shared->producer_inflight.fetch_add(1);}
    ~Emitting(){shared->producer_inflight.fetch_sub(1);}
};
void report(char* out,size_t capacity,const std::string& message) {
    if(!out||!capacity)return;
    auto n=std::min(capacity-1,message.size());memcpy(out,message.data(),n);out[n]=0;
}
}
extern "C" int gxdiag_producer_attach_v1(const char* descriptor,gxdiag_producer_v1** out,char* message,size_t capacity) {
    if(out)*out=nullptr;
    report(message,capacity,"");
    try {
        if(!descriptor||!out||strnlen(descriptor,512)>=512)throw std::runtime_error("Invalid diagnostics producer descriptor");
        std::istringstream input(descriptor);std::string version,endpoint,name,generation,extra;
        if(!std::getline(input,version,':')||!std::getline(input,endpoint,':')||!std::getline(input,name,':')||!std::getline(input,generation,':')||std::getline(input,extra,':')||version!="gxdiag1")throw std::runtime_error("Invalid diagnostics producer descriptor version/shape");
        auto identity=std::to_string(getuid())+"."+generation;
        if(generation.empty()||generation.size()>19||generation.find_first_not_of("0123456789")!=std::string::npos||endpoint!="gxtxt.diag."+identity||name!="/gxtxt-diag-"+identity)throw std::runtime_error("Invalid diagnostics producer capability identities");
        uint64_t expected=std::stoull(generation);if(!expected||expected>0x7fffffffffffffffULL)throw std::runtime_error("Invalid diagnostics producer generation");
        Fd page(shm_open(name.c_str(),O_RDWR|O_CLOEXEC,0));
        if(page.n<0){report(message,capacity,systemError("Attach diagnostics status"));return errno==ENOENT?GXDIAG_OFF_V1:GXDIAG_INVALID_V1;}
        struct stat st{};
        if(fstat(page.n,&st)||!S_ISREG(st.st_mode)||st.st_uid!=getuid()||st.st_nlink!=1||(st.st_mode&0077)||st.st_size!=off_t(sizeof(Shared)))throw std::runtime_error("Unsafe diagnostics producer status page");
        auto producer=std::make_unique<gxdiag_producer_v1>();
        producer->shared=static_cast<Shared*>(mmap(nullptr,sizeof(Shared),PROT_READ|PROT_WRITE,MAP_SHARED,page.n,0));
        if(producer->shared==MAP_FAILED){producer->shared=nullptr;throw std::runtime_error(systemError("Map producer status"));}
        if(producer->shared->magic.load()!=sharedMagic||producer->shared->generation.load()!=expected)throw std::runtime_error("Diagnostics producer ABI/generation mismatch");
        Emitting attachment(producer->shared);
        if(!producer->shared->accepting.load()||producer->shared->phase.load()!=Running){report(message,capacity,"Diagnostics producer generation is OFF");return GXDIAG_OFF_V1;}
        producer->socket=Fd(::socket(AF_UNIX,SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC,0));if(producer->socket.n<0)throw std::runtime_error(systemError("Create producer endpoint"));
        sockaddr_un address{};address.sun_family=AF_UNIX;
        if(endpoint.size()+1>sizeof address.sun_path)throw std::runtime_error("Diagnostics producer endpoint exceeds UNIX bound");
        memcpy(address.sun_path+1,endpoint.data(),endpoint.size());
        if(connect(producer->socket.n,reinterpret_cast<sockaddr*>(&address),socklen_t(offsetof(sockaddr_un,sun_path)+1+endpoint.size()))){report(message,capacity,systemError("Connect diagnostics producer endpoint"));return errno==ECONNREFUSED||errno==ENOENT?GXDIAG_OFF_V1:GXDIAG_INVALID_V1;}
        producer->generation=expected;producer->shared->producer_attachments.fetch_add(1);*out=producer.release();return GXDIAG_QUEUED_V1;
    }catch(const std::exception& e){report(message,capacity,e.what());return GXDIAG_INVALID_V1;}
    catch(...){report(message,capacity,"Unexpected diagnostics producer attachment failure");return GXDIAG_INVALID_V1;}
}
extern "C" int gxdiag_producer_emit_v1(gxdiag_producer_v1* producer,const gxdiag_origin_v1* origin,const void* payload,size_t size) {
    if(!producer||!producer->shared||(!payload&&size))return GXDIAG_INVALID_V1;
    auto shared=producer->shared;
    Emitting emission(shared);
    bool countedDrop=false;
    auto failure=[&](const char* message) noexcept {
        if(!countedDrop){shared->transport_dropped_records.fetch_add(1);shared->transport_dropped_bytes.fetch_add(size);}
        shared->producer_failed_records.fetch_add(1);shared->producer_failed_bytes.fetch_add(size);
        errorLiteral(shared,message);return GXDIAG_INVALID_V1;
    };
    try {
        if(!shared->accepting.load()||shared->phase.load()!=Running||shared->generation.load()!=producer->generation)return GXDIAG_OFF_V1;
#ifdef GXDIAG_PRIVATE_FIXTURES
        if(getenv("GXTXT_DIAG_FIXTURE_EMIT_PAUSE"))raise(SIGSTOP);
        if(getenv("GXTXT_DIAG_FIXTURE_EMIT_THROW"))throw std::runtime_error("Private fixture native producer exception");
#endif
        if(size>maxPayload){shared->transport_dropped_records.fetch_add(1);shared->transport_dropped_bytes.fetch_add(size);return GXDIAG_OVERSIZE_V1;}
        const char* fields[12]{};
        if(origin){fields[0]=origin->source;fields[1]=origin->component;fields[2]=origin->module_id;fields[3]=origin->viewer_id;fields[4]=origin->job_id;fields[5]=origin->api_id;fields[6]=origin->operation;fields[7]=origin->process_id;fields[8]=origin->stream;fields[9]=origin->severity;fields[10]=origin->chunk_id;fields[11]=origin->chunk_index;}
        auto time=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        std::string body="\"timestamp_us\":"+std::to_string(time)+",\"pid\":"+std::to_string(getpid())+",\"capture_pid\":"+std::to_string(getpid())+",\"origin\":{";
        size_t total=0;
        for(size_t n=0;n<12;++n){const char* field=fields[n]?fields[n]:"unknown";size_t length=strnlen(field,513);total+=length;if(length>512||total>2048)return GXDIAG_INVALID_V1;if(n)body+=',';body+=json(originKeys[n])+":"+json(std::string(field,length));}
        body+="},\"payload_bytes\":"+std::to_string(size)+",\"payload_base64\":"+json(b64(static_cast<const unsigned char*>(payload),size));
        PacketHeader header;header.payload_bytes=uint32_t(size);std::string packet(sizeof header,'\0');memcpy(packet.data(),&header,sizeof header);packet+=body;
        auto sent=send(producer->socket.n,packet.data(),packet.size(),MSG_DONTWAIT|MSG_NOSIGNAL);
        if(sent==ssize_t(packet.size())){shared->accepted_records.fetch_add(1);shared->accepted_bytes.fetch_add(size);return GXDIAG_QUEUED_V1;}
        auto code=errno;countedDrop=true;shared->transport_dropped_records.fetch_add(1);shared->transport_dropped_bytes.fetch_add(size);
        if(code==EAGAIN||code==EWOULDBLOCK||code==ENOBUFS)return GXDIAG_OVERLOAD_V1;
        error(shared,"External producer IPC send failed: "+std::string(strerror(code)));return GXDIAG_BROKEN_IPC_V1;
    }catch(const std::exception& e){return failure(e.what());}
    catch(...){return failure("Unexpected native diagnostics producer failure");}
}
extern "C" void gxdiag_producer_close_v1(gxdiag_producer_v1* producer){delete producer;}
