/* SPDX-License-Identifier: GPL-3.0-or-later
 * TASK210 isolated DEVELOPMENT candidate. Not registered by the normal adapter.
 * Existing canonical/Graph/CurveSource/coordinate/common-engine owners retain
 * authority. MAIN must review exact bytes and install package admission hooks.
 */
#include "gx2d_preview_provider_v1.h"
#include <tcl.h>
#include <dlfcn.h>
#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstring>
#include <deque>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>
#ifndef GXTXT_PREVIEW_BRIDGE_BUILD_ID
#define GXTXT_PREVIEW_BRIDGE_BUILD_ID "task210-provider-bridge-unwired-v1"
#endif
namespace {
namespace abi = gx::preview::v1;
using abi::Status;
struct Error : std::runtime_error {
    Status status;
    std::string message; // explicit length preserves embedded NUL in ABI Text
    explicit Error(const std::string &s, Status code=Status::invalid):std::runtime_error(s),status(code),message(s){}
};
struct Obj {
    Tcl_Obj *p=nullptr;
    Obj()=default;
    explicit Obj(Tcl_Obj *v):p(v){if(p)Tcl_IncrRefCount(p);}
    Obj(const Obj &v):Obj(v.p){}
    Obj(Obj &&v) noexcept:p(v.p){v.p=nullptr;}
    Obj &operator=(Obj v) noexcept {std::swap(p,v.p);return *this;}
    ~Obj(){if(p)Tcl_DecrRefCount(p);}
};
std::string str(Tcl_Obj *v){int n;const char *p=Tcl_GetStringFromObj(v,&n);return {p,static_cast<size_t>(n)};}
Obj word(const char *s){return Obj(Tcl_NewStringObj(s,-1));}
Obj word(const std::string &s){return Obj(Tcl_NewStringObj(s.data(),static_cast<int>(s.size())));}
Obj dict(){return Obj(Tcl_NewDictObj());}
void put(Tcl_Obj *d,const char *key,Tcl_Obj *v){Obj k=word(key);if(Tcl_DictObjPut(nullptr,d,k.p,v)!=TCL_OK)throw Error("Cannot build bridge dictionary",Status::internal);}
void put(Tcl_Obj *d,const char *key,const std::string &s){Obj v=word(s);put(d,key,v.p);}
void number(Tcl_Obj *d,const char *key,uint64_t n){if(n>INT64_MAX)throw Error("Bridge Tcl counter overflow");put(d,key,Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(n)));}
Tcl_Obj *get(Tcl_Interp *ip,Tcl_Obj *d,const char *key,bool required=true){Obj k=word(key);Tcl_Obj *v=nullptr;if(Tcl_DictObjGet(ip,d,k.p,&v)!=TCL_OK)throw Error("Invalid bridge dictionary");if(!v&&required)throw Error(std::string("Missing bridge field: ")+key);return v;}
std::vector<Tcl_Obj*> list(Tcl_Interp *ip,Tcl_Obj *v){int n;Tcl_Obj **items;if(Tcl_ListObjGetElements(ip,v,&n,&items)!=TCL_OK)throw Error("Invalid bridge list");return n?std::vector<Tcl_Obj*>(items,items+n):std::vector<Tcl_Obj*>{};}
uint64_t unsigned_value(Tcl_Interp *ip,Tcl_Obj *v){(void)ip;std::string s=str(v);uint64_t n;auto r=std::from_chars(s.data(),s.data()+s.size(),n);if(r.ec!=std::errc()||r.ptr!=s.data()+s.size())throw Error("Expected canonical unsigned bridge integer");return n;}
uint64_t integer(Tcl_Interp *ip,Tcl_Obj *d,const char *key,uint64_t lo,uint64_t hi){uint64_t n=unsigned_value(ip,get(ip,d,key));if(n<lo||n>hi)throw Error(std::string("Bridge bound: ")+key,Status::limit);return n;}
Tcl_WideInt owner_integer(Tcl_Interp *ip,Tcl_Obj *d,const char *key,Tcl_WideInt lo,Tcl_WideInt hi){Tcl_WideInt n;if(Tcl_GetWideIntFromObj(ip,get(ip,d,key),&n)!=TCL_OK||n<lo||n>hi)throw Error(std::string("Existing batch config bound: ")+key);return n;}
bool boolean(Tcl_Interp *ip,Tcl_Obj *d,const char *key){int value;if(Tcl_GetBooleanFromObj(ip,get(ip,d,key),&value)!=TCL_OK)throw Error("Invalid bridge boolean");return value!=0;}
std::string tcl_error_text(Tcl_Interp *ip);
Obj invoke(Tcl_Interp *ip,const char *name,std::initializer_list<Tcl_Obj*> args){Obj command=word(name);std::vector<Tcl_Obj*> v{command.p};v.insert(v.end(),args.begin(),args.end());if(Tcl_EvalObjv(ip,static_cast<int>(v.size()),v.data(),TCL_EVAL_GLOBAL)!=TCL_OK)throw Error(tcl_error_text(ip),Status::invalid);return Obj(Tcl_GetObjResult(ip));}
std::string bounded_text(Tcl_Obj *v,size_t max,const char *what){std::string s=str(v);if(s.size()>max)throw Error(std::string("Bridge text bound: ")+what,Status::limit);return s;}
bool standard_utf8(const std::string &s){
    for(size_t i=0;i<s.size();){unsigned char a=static_cast<unsigned char>(s[i++]);if(a<0x80)continue;unsigned n;if(a>=0xc2&&a<=0xdf)n=1;else if(a>=0xe0&&a<=0xef)n=2;else if(a>=0xf0&&a<=0xf4)n=3;else return false;if(n>s.size()-i)return false;unsigned char b=static_cast<unsigned char>(s[i]);if((a==0xe0&&b<0xa0)||(a==0xed&&b>=0xa0)||(a==0xf0&&b<0x90)||(a==0xf4&&b>=0x90))return false;for(unsigned k=0;k<n;++k){unsigned char c=static_cast<unsigned char>(s[i++]);if(c<0x80||c>0xbf)return false;}}
    return true;
}
// Tcl's internal modified UTF-8 is not the provider's standard UTF-8.
// Convert losslessly through the actual Tcl encoding owner. Reject a value
// that cannot round-trip (for example an isolated surrogate), never replace it.
std::string utf8_text(Tcl_Interp *ip,Tcl_Obj *value){
    Tcl_Encoding encoding=Tcl_GetEncoding(ip,"utf-8");if(!encoding)throw Error("UTF-8 encoding owner unavailable",Status::unsupported);
    Tcl_DString external,internal;Tcl_DStringInit(&external);Tcl_DStringInit(&internal);
    struct Cleanup{Tcl_Encoding e;Tcl_DString *a,*b;~Cleanup(){Tcl_DStringFree(a);Tcl_DStringFree(b);Tcl_FreeEncoding(e);}} cleanup{encoding,&external,&internal};
    int n;const char *source=Tcl_GetStringFromObj(value,&n);Tcl_UtfToExternalDString(encoding,source,n,&external);
    std::string encoded(Tcl_DStringValue(&external),static_cast<size_t>(Tcl_DStringLength(&external)));
    if(!standard_utf8(encoded))throw Error("Owner text is not representable as standard UTF-8",Status::unsupported);
    Tcl_ExternalToUtfDString(encoding,Tcl_DStringValue(&external),Tcl_DStringLength(&external),&internal);
    Obj roundtrip(Tcl_NewStringObj(Tcl_DStringValue(&internal),Tcl_DStringLength(&internal)));
    int a,b;const Tcl_UniChar *x=Tcl_GetUnicodeFromObj(value,&a),*y=Tcl_GetUnicodeFromObj(roundtrip.p,&b);
    if(a!=b||(a&&std::memcmp(x,y,static_cast<size_t>(a)*sizeof(*x))))throw Error("Owner text cannot round-trip through standard UTF-8",Status::unsupported);
    return encoded;
}
constexpr char kDiagnosticFallback[]="Preview diagnostic is unavailable";
std::string tcl_error_text(Tcl_Interp *ip){
    Obj original(Tcl_GetObjResult(ip));
    struct Restore{Tcl_Interp *ip;Tcl_InterpState state;~Restore(){Tcl_RestoreInterpState(ip,state);}} restore{ip,Tcl_SaveInterpState(ip,TCL_ERROR)};
    try{return utf8_text(ip,original.p);}catch(...){return kDiagnosticFallback;}
}
std::string bounded_diagnostic(const std::string &message){
    if(!standard_utf8(message))return kDiagnosticFallback;
    size_t end=std::min(size_t(4096),message.size());
    // With a valid full string, continuation bytes at the first excluded
    // position identify a partial character; exclude its leading byte too.
    if(end<message.size())while(end&&(static_cast<unsigned char>(message[end])&0xc0)==0x80)--end;
    return message.substr(0,end);
}
abi::Text view(const std::string &s){return {s.empty()?nullptr:s.data(),s.size()};}
bool eq(abi::Text a,abi::Text b){return a.bytes==b.bytes&&(!a.bytes||(a.data&&b.data&&std::memcmp(a.data,b.data,static_cast<size_t>(a.bytes))==0));}
std::string copy_text(abi::Text v,size_t max){if(v.bytes>max||(!v.data&&v.bytes))throw Error("Invalid or oversized ABI text",Status::limit);std::string result=v.bytes?std::string(v.data,static_cast<size_t>(v.bytes)):std::string{};if(!standard_utf8(result))throw Error("ABI text is not standard UTF-8");return result;}
uint64_t add(uint64_t a,uint64_t b,uint64_t max,const char *what){if(b>max||a>max-b)throw Error(what,Status::limit);return a+b;}
uint64_t product(uint64_t a,uint64_t b,uint64_t max,const char *what){if(b&&a>max/b)throw Error(what,Status::limit);return a*b;}
abi::DType dtype(const std::string &s){static const char *names[]={"bool","int8","int16","int32","int64","uint8","uint16","uint32","uint64","float16","float32","float64","string"};for(unsigned i=0;i<13;++i)if(s==names[i])return static_cast<abi::DType>(i+1);throw Error("Unsupported canonical bridge dtype",Status::unsupported);}
const char *dtype_name(abi::DType d){static const char *names[]={"","bool","int8","int16","int32","int64","uint8","uint16","uint32","uint64","float16","float32","float64","string"};unsigned n=static_cast<unsigned>(d);if(n<1||n>13)throw Error("Invalid ABI dtype");return names[n];}
size_t width(abi::DType d){switch(d){case abi::DType::boolean:case abi::DType::i8:case abi::DType::u8:return 1;case abi::DType::i16:case abi::DType::u16:case abi::DType::f16:return 2;case abi::DType::i32:case abi::DType::u32:case abi::DType::f32:return 4;case abi::DType::i64:case abi::DType::u64:case abi::DType::f64:return 8;default:throw Error("UTF8 is not fixed numeric");}}
bool signed_type(abi::DType d){return d>=abi::DType::i8&&d<=abi::DType::i64;}
bool unsigned_type(abi::DType d){return d==abi::DType::boolean||(d>=abi::DType::u8&&d<=abi::DType::u64);}
struct Strings {
    std::deque<std::string> values;
    uint64_t bytes=0,limit=UINT64_MAX;
    abi::Text keep(std::string s){bytes=add(bytes,s.size(),limit,"Retained plan/result text budget");values.push_back(std::move(s));return view(values.back());}
};
abi::Scalar scalar(Tcl_Interp *ip,Strings &strings,abi::DType type,Tcl_Obj *value,bool common_plane_label=false){
    // Call the current Graph owner; this is ABI representation, not validation.
    Obj name=word(dtype_name(type));Obj bool_value;
    if(type==abi::DType::boolean&&common_plane_label){double n;if(Tcl_GetDoubleFromObj(ip,value,&n)!=TCL_OK||(n!=0&&n!=1))throw Error("Invalid common bool scalar");bool_value=Obj(Tcl_NewIntObj(n!=0));value=bool_value.p;}
    Obj normalized=invoke(ip,"::GX::graphSeriesCanonicalMember",{name.p,value});
    abi::Scalar s{};s.struct_bytes=sizeof s;s.dtype=type;s.state=abi::CellState::present;std::string token=str(normalized.p);
    if(type==abi::DType::utf8)s.text_value=strings.keep(utf8_text(ip,normalized.p));
    else if(unsigned_type(type))s.unsigned_value=unsigned_value(ip,normalized.p);
    else if(signed_type(type)){auto r=std::from_chars(token.data(),token.data()+token.size(),s.signed_value);if(r.ec!=std::errc()||r.ptr!=token.data()+token.size())throw Error("Invalid canonical signed identity");}
    else if(Tcl_GetDoubleFromObj(ip,normalized.p,&s.float_value)!=TCL_OK||!std::isfinite(s.float_value))throw Error("Invalid finite canonical identity");
    return s;
}
const abi::AbiIdentity &host_identity(){static const std::string platform=abi::kPlatform,layout=abi::kValueLayoutId,build=GXTXT_PREVIEW_BRIDGE_BUILD_ID;static const abi::AbiIdentity identity{sizeof(abi::AbiIdentity),abi::kAbiMajor,abi::kAbiMinor,sizeof(void*),abi::Endian::little,abi::FloatFormat::ieee754_binary64,{0,0},view(platform),view(layout),view(build)};return identity;}
struct Input {
    Obj canonical;
    std::vector<abi::Column> columns;
    std::deque<std::string> texts;
    std::vector<std::vector<uint64_t>> offsets;
    abi::Chunk chunk{};
    uint64_t payload_bytes=0,text_bytes=0;
    explicit Input(Tcl_Interp *ip,Tcl_Obj *source,uint64_t start,uint64_t cap,uint64_t text_cap):canonical(source){
        Tcl_DictSearch search;Tcl_Obj *key,*value;int done;
        if(Tcl_DictObjFirst(ip,source,&search,&key,&value,&done)!=TCL_OK)throw Error("Invalid canonical projected columns");
        struct End {Tcl_DictSearch *s;~End(){Tcl_DictObjDone(s);}} end{&search};
        int size;if(Tcl_DictObjSize(ip,source,&size)!=TCL_OK||size<1||size>128)throw Error("Bridge projection needs1..128 unique columns");
        columns.reserve(static_cast<size_t>(size));offsets.reserve(static_cast<size_t>(size));uint64_t rows=0;
        while(!done){
            abi::Column c{};c.struct_bytes=sizeof c;c.dtype=dtype(str(get(ip,value,"dtype")));c.endian=abi::Endian::little;
            texts.push_back(bounded_text(key,1024,"variable_id"));c.variable_id=view(texts.back());
            Tcl_Obj *values=get(ip,value,"values",false);
            if(values){
                auto cells=list(ip,values);c.row_count=cells.size();if(c.row_count>cap)throw Error("Bridge input chunk row limit",Status::limit);
                c.transport=c.dtype==abi::DType::utf8?abi::ColumnTransport::utf8:abi::ColumnTransport::owner_lexemes;
                offsets.emplace_back();auto &o=offsets.back();o.reserve(cells.size()+1);o.push_back(0);std::string bytes;
                for(auto *cell:cells){std::string token=utf8_text(ip,cell);text_bytes=add(text_bytes,token.size(),text_cap,"Bridge input text budget");bytes+=token;o.push_back(bytes.size());}
                texts.push_back(std::move(bytes));c.bytes={reinterpret_cast<const uint8_t*>(texts.back().data()),texts.back().size()};c.offsets=o.data();c.offset_count=o.size();
            }else{
                if(c.dtype==abi::DType::utf8)throw Error("String columns require canonical values");
                int n;auto *raw=Tcl_GetByteArrayFromObj(get(ip,value,"raw"),&n);size_t w=width(c.dtype);if(static_cast<size_t>(n)%w)throw Error("Canonical raw byte count mismatch");
                c.row_count=static_cast<size_t>(n)/w;if(c.row_count>cap)throw Error("Bridge input chunk row limit",Status::limit);
                std::string endian=str(get(ip,value,"endian"));if(endian=="big")c.endian=abi::Endian::big;else if(endian!="little")throw Error("Invalid canonical endian");
                c.transport=abi::ColumnTransport::fixed_numeric;c.bytes={raw,static_cast<uint64_t>(n)};
            }
            if(!columns.empty()&&rows!=c.row_count)throw Error("Canonical projected row count mismatch");rows=c.row_count;
            payload_bytes=add(payload_bytes,c.bytes.bytes,UINT64_MAX,"Input payload overflow");payload_bytes=add(payload_bytes,c.offset_count*8,UINT64_MAX,"Input offset overflow");columns.push_back(c);
            Tcl_DictObjNext(&search,&key,&value,&done);
        }
        chunk={sizeof(abi::Chunk),static_cast<uint32_t>(columns.size()),start,rows,columns.data()};
    }
    bool same(const abi::Chunk *other)const{
        if(!other||other->struct_bytes!=sizeof(abi::Chunk)||other->column_count!=chunk.column_count||other->source_row_start!=chunk.source_row_start||other->row_count!=chunk.row_count||!other->columns)return false;
        std::vector<bool> seen(columns.size(),false);
        for(size_t i=0;i<columns.size();++i){const auto &b=other->columns[i];size_t match=0;for(;match<columns.size()&&!eq(columns[match].variable_id,b.variable_id);++match){}if(match==columns.size()||seen[match])return false;seen[match]=true;const auto &a=columns[match];if(b.struct_bytes!=sizeof(abi::Column)||a.dtype!=b.dtype||a.endian!=b.endian||a.transport!=b.transport||a.row_count!=b.row_count||!eq(a.variable_id,b.variable_id)||a.bytes.bytes!=b.bytes.bytes||a.offset_count!=b.offset_count||(!a.offset_count&&b.offsets)||b.present.bit_count||b.present.bits)return false;
            if(a.bytes.bytes&&(!b.bytes.data||std::memcmp(a.bytes.data,b.bytes.data,static_cast<size_t>(a.bytes.bytes))))return false;
            if(a.offset_count&&(!b.offsets||std::memcmp(a.offsets,b.offsets,static_cast<size_t>(a.offset_count)*8)))return false;
        }return true;
    }
};
struct Trace {
    std::vector<abi::Scalar> identity;
    std::vector<abi::Point> canonical,display;
    std::vector<uint64_t> rows,breaks;
    abi::TraceView value{};
};
struct Raster {std::vector<abi::RasterPoint> points;abi::RasterView value{};};
struct Invocation;
Status core_create(void*,abi::CoreHandle*,abi::Diagnostic*) noexcept;
Status core_push(void*,abi::CoreHandle,const abi::Chunk*,abi::Progress*,abi::Diagnostic*) noexcept;
Status core_seal(void*,abi::CoreHandle,abi::Progress*,abi::Diagnostic*) noexcept;
Status core_result(void*,abi::CoreHandle,abi::ResultToken*,abi::Diagnostic*) noexcept;
Status core_inspect(void*,abi::ResultToken,abi::ResultInfo*,abi::Diagnostic*) noexcept;
Status core_trace(void*,abi::ResultToken,uint64_t,abi::TraceView*,abi::Diagnostic*) noexcept;
Status core_raster(void*,abi::ResultToken,uint64_t,abi::RasterView*,abi::Diagnostic*) noexcept;
Status core_plane(void*,abi::ResultToken,abi::PlaneView*,abi::Diagnostic*) noexcept;
Status core_cancel(void*,abi::CoreHandle,abi::Diagnostic*) noexcept;
struct Invocation {
    Tcl_Interp *ip;
    Obj context,batch_config,coordinate_context,overlay_config,plane_config,source_receipt,provider_binding;
    Obj batch,overlay,plane_column,raw_result,overlay_result,plane_result,package_admission,package_lease;
    Strings strings;abi::Plan plan{};abi::PlanePlan plane_plan{};
    std::vector<abi::Text> groups;std::vector<abi::DType> group_types;
    std::vector<abi::Predicate> predicates;std::vector<std::vector<abi::Scalar>> operands;
    std::vector<uint64_t> starts,counts;
    std::vector<Trace> traces;std::vector<Raster> rasters;
    std::vector<uint8_t> rgb;abi::PlaneView plane_view{};
    abi::CoreApi core{};const abi::ProviderApi *provider=nullptr;abi::ProviderHandle provider_handle=nullptr;
    std::unique_ptr<Input> input;
    void *library=nullptr;
    uint64_t handle=0,result_token=0,input_rows=0,accepted_rows=0,next_handle=0,input_text_bytes=0;
    bool busy=false,inside_core=false,admitted=false,created=false,consumed=false,sealed=false,failed=false,cancelled=false,closed=false,unload_failed=false,cleanup_failed=false;
    std::string diagnostic_code,diagnostic_message,component_id,provider_version,cleanup_message;
    explicit Invocation(Tcl_Interp *interp,Tcl_Obj *captured,uint64_t serial):ip(interp),context(captured),next_handle(serial){capture();core={sizeof(abi::CoreApi),abi::kAbiMajor,abi::kAbiMinor,0,this,&host_identity(),capabilities(),core_create,core_push,core_seal,core_result,core_inspect,core_trace,core_raster,core_plane,core_cancel};}
    ~Invocation(){close();}
    abi::Text text(Tcl_Obj *v,size_t max=1024){std::string s=utf8_text(ip,v);if(s.size()>max)throw Error("Plan/result text bound",Status::limit);return strings.keep(std::move(s));}
    uint64_t capabilities()const{return plan.mode==abi::PlanMode::bounded_array_plane?abi::kCapBoundedArrayPlane:abi::kCapGroupedCurves|(overlay_config.p?abi::kCapRasterOverlay:0);}
    void capture();void begin();void push();void finish();void make_traces();void make_rasters();void make_plane();void close() noexcept;
    void require_handle(uint64_t value){if(!value||value!=handle||!created||closed)throw Error("Unknown or foreign CORE handle");if(cancelled)throw Error("CORE preparation cancelled",Status::cancelled);if(failed)throw Error("CORE preparation failed");}
    void require_result(uint64_t value){if(!value||value!=result_token||!sealed||failed||cancelled||closed)throw Error("Unknown, stale or incomplete CORE result token");}
    void progress(abi::Progress *out){if(!out||out->struct_bytes!=sizeof(*out))throw Error("Invalid Progress size");*out={sizeof(*out),cancelled?abi::Stage::cancelled:failed?abi::Stage::failed:sealed?abi::Stage::complete:created?abi::Stage::ingest:abi::Stage::created,input_rows,accepted_rows,traces.size(),0,0,input_text_bytes};if(batch.p){Obj inspect=word("inspect");Obj stats=invoke(ip,"::gx::native2d::_preview_batch",{inspect.p,batch.p});out->accepted_rows=unsigned_value(ip,get(ip,stats.p,"selected_rows"));out->series=unsigned_value(ip,get(ip,stats.p,"series"));out->retained_row_capacity=unsigned_value(ip,get(ip,stats.p,"retained_row_capacity"));}}
};
void Invocation::capture(){
    if(str(get(ip,context.p,"schema"))!="gxtxt.preview_native_invocation.v1")throw Error("Unknown captured Preview context schema");
    auto *limits=get(ip,context.p,"limits");
    plan.struct_bytes=sizeof plan;plan.raster.struct_bytes=sizeof plan.raster;plan.x_display.struct_bytes=sizeof plan.x_display;plan.y_display.struct_bytes=sizeof plan.y_display;
    auto &l=plan.limits;l.struct_bytes=sizeof l;
    l.max_native_bytes=integer(ip,limits,"max_native_bytes",0,UINT64_MAX);
    if(l.max_native_bytes)throw Error("aggregate_native_budget_supported=0: common engines do not reserve aggregate bytes",Status::unsupported);
    l.max_input_rows=integer(ip,limits,"max_input_rows",1,INT64_MAX);
    l.max_text_bytes=integer(ip,limits,"max_text_bytes",1,INT32_MAX);
    // Bound metadata before copying it. Aggregate allocation accounting is not
    // claimed; this is a payload cap in addition to the common hard caps.
    if(str(context.p).size()>l.max_text_bytes)throw Error("Captured context exceeds text budget",Status::limit);
    strings.limit=l.max_text_bytes;strings.bytes=str(context.p).size();
    provider_binding=Obj(get(ip,context.p,"provider_binding"));
    source_receipt=Obj(get(ip,context.p,"source_receipt"));if(str(source_receipt.p).empty())throw Error("Empty captured source/Session/key receipt");
    plan.dataset_id=text(get(ip,context.p,"dataset_id"));
    std::string mode=str(get(ip,context.p,"mode"));
    if(mode=="bounded_array_plane"){
        plan.mode=abi::PlanMode::bounded_array_plane;plane_config=Obj(get(ip,context.p,"plane"));
        plane_plan.struct_bytes=sizeof plane_plan;plane_plan.dataset_id=plan.dataset_id;plane_plan.variable_id=text(get(ip,plane_config.p,"variable_id"));
        if(str(get(ip,plane_config.p,"storage_order"))!="last_dimension_fastest")throw Error("Unsupported canonical plane storage order",Status::unsupported);
        plane_plan.storage_order=abi::StorageOrder::last_dimension_fastest;plane_plan.policy=abi::PlanePolicy::existing_nearest_cell_rgb_v1;
        for(auto *v:list(ip,get(ip,plane_config.p,"starts")))starts.push_back(unsigned_value(ip,v));
        for(auto *v:list(ip,get(ip,plane_config.p,"counts")))counts.push_back(unsigned_value(ip,v));
        if(starts.size()<2||starts.size()>32||starts.size()!=counts.size())throw Error("Invalid canonical plane rank");
        for(size_t i=0;i<counts.size();++i){if(!counts[i]||counts[i]>UINT64_MAX-starts[i])throw Error("Invalid plane hyperslab extent");if(i+2<counts.size()&&counts[i]!=1)throw Error("Leading plane counts must be1");}
        plane_plan.rank=static_cast<uint32_t>(counts.size());plane_plan.starts=starts.data();plane_plan.counts=counts.data();
        plane_plan.source_width=counts.back();plane_plan.source_height=counts[counts.size()-2];
        if(plane_plan.source_width>128||plane_plan.source_height>128)throw Error("Plane edge exceeds128",Status::limit);
        if(product(plane_plan.source_width,plane_plan.source_height,16384,"Plane cell limit")>l.max_input_rows)throw Error("Plane input row budget",Status::limit);
        plane_plan.max_output_width=integer(ip,plane_config.p,"max_output_width",1,640);plane_plan.max_output_height=integer(ip,plane_config.p,"max_output_height",1,420);
        uint64_t scale=std::max(UINT64_C(1),std::min({UINT64_C(8),640/plane_plan.source_width,420/plane_plan.source_height}));
        if(plane_plan.source_width*scale>plane_plan.max_output_width||plane_plan.source_height*scale>plane_plan.max_output_height)throw Error("Output budget cannot retain existing nearest-cell policy",Status::unsupported);
        l.max_rgb_bytes=integer(ip,limits,"max_rgb_bytes",1,abi::kPlaneRgbBytesMax);
        if(product(plane_plan.source_width*scale,plane_plan.source_height*scale,abi::kPlaneRgbBytesMax/3,"Plane RGB bound")*3>l.max_rgb_bytes)throw Error("Plane RGB byte budget",Status::limit);
        plan.plane=&plane_plan;l.max_chunk_rows=16384;
    }else if(mode=="grouped_curves"){
        plan.mode=abi::PlanMode::grouped_curves;batch_config=Obj(get(ip,context.p,"batch_config"));coordinate_context=Obj(get(ip,context.p,"coordinate_context"));
        plan.x_variable_id=text(get(ip,batch_config.p,"x_variable_id"));plan.y_variable_id=text(get(ip,batch_config.p,"y_variable_id"));
        l.max_chunk_rows=integer(ip,limits,"max_chunk_rows",1,4096);
        // These limits are owned by the existing common adapters. Lower host
        // values are unsupported rather than checked only after allocation.
        l.max_selected_rows=integer(ip,limits,"max_selected_rows",2000000,2000000);l.max_retained_row_capacity=integer(ip,limits,"max_retained_row_capacity",4000000,4000000);
        l.max_series=static_cast<uint32_t>(owner_integer(ip,batch_config.p,"max_series",1,512));
        l.per_series_display_points=owner_integer(ip,batch_config.p,"display_budget",6,4096);l.total_display_points=owner_integer(ip,batch_config.p,"total_display_points",6,100000);
        for(auto *g:list(ip,get(ip,batch_config.p,"groups"))){groups.push_back(text(get(ip,g,"variable_id")));group_types.push_back(dtype(str(get(ip,g,"dtype"))));}
        if(groups.size()>16)throw Error("More than16 grouping roles",Status::limit);
        std::unordered_set<std::string> unique;for(auto g:groups)if(!unique.insert(copy_text(g,1024)).second)throw Error("Duplicate grouping roles");
        plan.group_count=static_cast<uint32_t>(groups.size());plan.group_variable_ids=groups.empty()?nullptr:groups.data();
        Tcl_Obj *order=get(ip,batch_config.p,"order");if(!str(order).empty())plan.order_variable_id=text(get(ip,order,"variable_id"));
        Tcl_Obj *continuity=get(ip,batch_config.p,"continuity");if(!str(continuity).empty()){plan.continuity_policy=abi::ContinuityPolicy::source_row_adjacency;plan.continuity_variable_id=text(get(ip,continuity,"variable_id"));}
        plan.range.start=owner_integer(ip,batch_config.p,"start",0,2000000);Tcl_WideInt count=owner_integer(ip,batch_config.p,"count",-1,2000000);
        if(count>=0){plan.range.count_is_bounded=1;plan.range.count=static_cast<uint64_t>(count);}
        static const char *names[]={"exact_equal","not_equal","less_than","less_equal","greater_than","greater_equal","between_inclusive","in_set","is_finite","is_nonfinite"};
        auto filters=list(ip,get(ip,batch_config.p,"filters"));if(filters.size()>64)throw Error("More than64 filters",Status::limit);
        predicates.reserve(filters.size());operands.reserve(filters.size());
        for(auto *f:filters){abi::Predicate p{};p.struct_bytes=sizeof p;p.variable_id=text(get(ip,f,"filter_variable_id"));std::string name=str(get(ip,f,"predicate"));unsigned index=0;for(;index<10&&name!=names[index];++index){}if(index==10)throw Error("Unknown normalized predicate");p.kind=static_cast<abi::PredicateKind>(index+1);abi::DType type=dtype(str(get(ip,f,"dtype")));operands.emplace_back();auto &o=operands.back();
            if(index<6)o.push_back(scalar(ip,strings,type,get(ip,f,"value")));
            else if(index==6){o.push_back(scalar(ip,strings,type,get(ip,f,"lower")));o.push_back(scalar(ip,strings,type,get(ip,f,"upper")));}
            else if(index==7){for(auto *v:list(ip,get(ip,f,"values")))o.push_back(scalar(ip,strings,type,v));if(o.empty())throw Error("Empty normalized in_set");}
            p.operands=o.empty()?nullptr:o.data();p.operand_count=o.size();predicates.push_back(p);
        }
        plan.predicates=predicates.empty()?nullptr:predicates.data();plan.predicate_count=predicates.size();
        // The full actual coordinate owner receives this invocation's captured
        // context. Do not reconstruct or condense units/calibration expressions.
        plan.x_display.policy=abi::CoordinatePolicy::owner_pointwise;plan.y_display.policy=abi::CoordinatePolicy::owner_pointwise;
        auto *o=get(ip,context.p,"overlay",false);
        if(o&&boolean(ip,o,"enabled")){
            overlay_config=Obj(o);auto *columns=get(ip,o,"columns");plan.raster.curve_variable_id=text(get(ip,columns,"curve_key"));plan.raster.curve_label_variable_id=text(get(ip,columns,"curve_name"));plan.raster.point_order_variable_id=text(get(ip,columns,"point_order"));
            if(!boolean(ip,o,"raster"))throw Error("ABI raster view requires actual raster coordinates",Status::unsupported);
            plan.raster.raster_x_variable_id=text(get(ip,columns,"raster_x"));plan.raster.raster_y_variable_id=text(get(ip,columns,"raster_y"));
            // Overlay must use the exact same normalized predicates, never a
            // hidden second request accepted by a provider.
            if(str(get(ip,o,"filters"))!=str(get(ip,batch_config.p,"filters")))throw Error("Overlay/batch predicate receipts differ");
            l.max_unique_raster_points=integer(ip,limits,"max_unique_raster_points",65536,65536);
        }
    }else throw Error("Unknown Preview plan mode",Status::unsupported);
    l.max_core_handles=1;l.max_result_tokens=1;
}
void Invocation::begin(){
    if(created||failed||cancelled||closed)throw Error("CORE create is allowed once");
    // Track before calling owners so a partial begin is still host-cleaned.
    created=true;handle=next_handle;
    if(plan.mode==abi::PlanMode::grouped_curves){Obj op=word("begin");batch=invoke(ip,"::gx::native2d::_preview_batch",{op.p,batch_config.p});if(overlay_config.p){Obj raster(Tcl_NewBooleanObj(1));overlay=invoke(ip,"::gx::native2d::_preview_overlay",{op.p,get(ip,overlay_config.p,"columns"),raster.p,get(ip,overlay_config.p,"filters")});}}
}
void Invocation::push(){
    if(sealed||!input||consumed)throw Error("CORE push requires the one current unconsumed canonical chunk");
    if(input->chunk.source_row_start!=input_rows)throw Error("Noncontiguous source ordinal");
    uint64_t next=add(input_rows,input->chunk.row_count,plan.limits.max_input_rows,"Input row budget");
    uint64_t text=add(input_text_bytes,input->text_bytes,plan.limits.max_text_bytes,"Input text budget");
    add(text,strings.bytes,plan.limits.max_text_bytes,"Combined invocation text budget");
    if(plan.mode==abi::PlanMode::bounded_array_plane){if(input_rows||input->columns.size()!=1||!eq(input->columns[0].variable_id,plane_plan.variable_id)||input->chunk.row_count!=plane_plan.source_width*plane_plan.source_height)throw Error("Plane needs one exact canonical hyperslab chunk");Obj key=word(copy_text(plane_plan.variable_id,1024));plane_column=Obj(get(ip,input->canonical.p,str(key.p).c_str()));}
    else{
        Obj op=word("push");
        // The overlay owner requires lexical roles. Do not derive them from
        // numeric raw bytes, lose bignums, or normalize 01/1 collision receipts.
        if(overlay.p){for(auto role:{plan.raster.curve_variable_id,plan.raster.curve_label_variable_id,plan.raster.point_order_variable_id,plan.raster.raster_x_variable_id,plan.raster.raster_y_variable_id}){Obj key=word(copy_text(role,1024));if(!get(ip,get(ip,input->canonical.p,str(key.p).c_str()),"values",false))throw Error("Overlay role lacks authoritative original owner lexemes",Status::unsupported);}}
        invoke(ip,"::gx::native2d::_preview_batch",{op.p,batch.p,input->canonical.p});
        if(overlay.p){
            for(uint64_t begin=0;begin<input->chunk.row_count;begin+=2048){uint64_t n=std::min(UINT64_C(2048),input->chunk.row_count-begin);Obj values=dict();
                for(const auto &c:input->columns){std::string id=copy_text(c.variable_id,1024);auto *column=get(ip,input->canonical.p,id.c_str());auto *source=get(ip,column,"values",false);if(!source)continue;auto cells=list(ip,source);Obj part(Tcl_NewListObj(static_cast<int>(n),cells.data()+begin));put(values.p,id.c_str(),part.p);}
                Obj rows(Tcl_NewIntObj(static_cast<int>(n)));invoke(ip,"::gx::native2d::_preview_overlay",{op.p,overlay.p,values.p,rows.p});
            }
        }
    }
    input_rows=next;input_text_bytes=text;consumed=true;
}
std::vector<abi::Point> points(Tcl_Interp *ip,Tcl_Obj *v){std::vector<abi::Point> out;auto rows=list(ip,v);if(rows.size()>4096)throw Error("Common owner point cap violated",Status::internal);out.reserve(rows.size());for(auto *row:rows){auto pair=list(ip,row);abi::Point point;if(pair.size()!=2||Tcl_GetDoubleFromObj(ip,pair[0],&point.x)!=TCL_OK||Tcl_GetDoubleFromObj(ip,pair[1],&point.y)!=TCL_OK||!std::isfinite(point.x)||!std::isfinite(point.y))throw Error("Invalid common owner finite point",Status::internal);out.push_back(point);}return out;}
void bounds(Tcl_Interp *ip,Tcl_Obj *source,double *out){auto v=list(ip,source);if(v.size()!=4)throw Error("Invalid common owner bounds",Status::internal);for(size_t i=0;i<4;++i)if(Tcl_GetDoubleFromObj(ip,v[i],out+i)!=TCL_OK||!std::isfinite(out[i]))throw Error("Nonfinite common owner bounds",Status::internal);}
void Invocation::make_traces(){
    auto items=list(ip,raw_result.p);if(items.empty()||items.size()>plan.limits.max_series)throw Error("Invalid common owner series count",Status::internal);traces.reserve(items.size());
    uint64_t total=0;Obj xid=word(copy_text(plan.x_variable_id,1024)),yid=word(copy_text(plan.y_variable_id,1024));
    for(auto *item:items){Obj shown=invoke(ip,"::GX::scientificDatasetCoordinateDisplay",{coordinate_context.p,xid.p,yid.p,item});Trace t;t.value.struct_bytes=sizeof t.value;t.value.group_count=plan.group_count;auto identities=list(ip,get(ip,item,"group_key"));if(identities.size()!=group_types.size())throw Error("Common owner group identity count",Status::internal);for(size_t j=0;j<identities.size();++j)t.identity.push_back(scalar(ip,strings,group_types[j],identities[j]));
        t.canonical=points(ip,get(ip,shown.p,"canonical_points"));t.display=points(ip,get(ip,shown.p,"points"));if(t.canonical.size()!=t.display.size())throw Error("Coordinate owner point count",Status::internal);
        for(auto *v:list(ip,get(ip,item,"source_rows"))){uint64_t row=unsigned_value(ip,v);if(row>=input_rows)throw Error("Common source ordinal outside input",Status::internal);t.rows.push_back(row);}
        if(t.rows.size()!=t.canonical.size())throw Error("Common source mapping count",Status::internal);
        for(auto *v:list(ip,get(ip,item,"breaks"))){uint64_t n=unsigned_value(ip,v);if(n+1>=t.canonical.size()||(!t.breaks.empty()&&n<=t.breaks.back()))throw Error("Invalid common continuity break",Status::internal);t.breaks.push_back(n);}
        bounds(ip,get(ip,shown.p,"canonical_full_bounds"),t.value.canonical_bounds);bounds(ip,get(ip,shown.p,"full_bounds"),t.value.display_bounds);
        t.value.row_count=unsigned_value(ip,get(ip,item,"row_count"));t.value.finite_rows=unsigned_value(ip,get(ip,item,"finite_rows"));t.value.display_rows=t.canonical.size();if(t.value.finite_rows>t.value.row_count||t.value.display_rows>t.value.finite_rows)throw Error("Invalid common row counts",Status::internal);total=add(total,t.value.display_rows,plan.limits.total_display_points,"Aggregate display point budget");traces.push_back(std::move(t));
    }
    for(auto &t:traces){t.value.group_identity=t.identity.empty()?nullptr:t.identity.data();t.value.canonical_points=t.canonical.data();t.value.display_points=t.display.data();t.value.source_rows=t.rows.data();t.value.breaks=t.breaks.empty()?nullptr:t.breaks.data();t.value.break_count=t.breaks.size();}
}
void Invocation::make_rasters(){
    auto *curves=get(ip,overlay_result.p,"curves");Tcl_DictSearch search;Tcl_Obj *key,*value;int done;if(Tcl_DictObjFirst(ip,curves,&search,&key,&value,&done)!=TCL_OK)throw Error("Invalid common raster result",Status::internal);struct End{Tcl_DictSearch*s;~End(){Tcl_DictObjDone(s);}} end{&search};uint64_t total=0,bytes=0;
    while(!done){Raster r;r.value.struct_bytes=sizeof r.value;r.value.curve_identity_lexeme=text(key,plan.limits.max_text_bytes);r.value.curve_label=text(get(ip,value,"label"),plan.limits.max_text_bytes);bytes=add(bytes,r.value.curve_identity_lexeme.bytes+r.value.curve_label.bytes,plan.limits.max_text_bytes,"Raster result text budget");
        for(auto *point:list(ip,get(ip,value,"points"))){auto v=list(ip,point);if(v.size()!=3)throw Error("Invalid common raster point",Status::internal);abi::RasterPoint p{};p.point_order_lexeme=text(v[0],plan.limits.max_text_bytes);p.x_lexeme=text(v[1],plan.limits.max_text_bytes);p.y_lexeme=text(v[2],plan.limits.max_text_bytes);bytes=add(bytes,p.point_order_lexeme.bytes+p.x_lexeme.bytes+p.y_lexeme.bytes,plan.limits.max_text_bytes,"Raster result text budget");if(Tcl_GetDoubleFromObj(ip,v[1],&p.x)!=TCL_OK||Tcl_GetDoubleFromObj(ip,v[2],&p.y)!=TCL_OK||!std::isfinite(p.x)||!std::isfinite(p.y))throw Error("Invalid common raster coordinate",Status::internal);r.points.push_back(p);}
        total=add(total,r.points.size(),plan.limits.max_unique_raster_points,"Raster point cap");rasters.push_back(std::move(r));Tcl_DictObjNext(&search,&key,&value,&done);
    }
    for(auto &r:rasters){r.value.points=r.points.data();r.value.point_count=r.points.size();}
}
void Invocation::make_plane(){
    Obj w(Tcl_NewIntObj(static_cast<int>(plane_plan.source_width))),h(Tcl_NewIntObj(static_cast<int>(plane_plan.source_height)));plane_result=invoke(ip,"::gx::native2d::_preview_plane",{plane_column.p,w.p,h.p});
    plane_view.struct_bytes=sizeof plane_view;plane_view.channels=3;plane_view.width=unsigned_value(ip,get(ip,plane_result.p,"width"));plane_view.height=unsigned_value(ip,get(ip,plane_result.p,"height"));plane_view.row_stride=product(plane_view.width,3,UINT64_MAX,"Plane stride overflow");uint64_t bytes=product(plane_view.row_stride,plane_view.height,plan.limits.max_rgb_bytes,"Plane RGB budget");
    std::string header="P6\n"+std::to_string(plane_view.width)+" "+std::to_string(plane_view.height)+"\n255\n";int n;auto *ppm=Tcl_GetByteArrayFromObj(get(ip,plane_result.p,"ppm"),&n);if(static_cast<uint64_t>(n)!=header.size()+bytes||std::memcmp(ppm,header.data(),header.size()))throw Error("Common plane P6 framing differs",Status::internal);rgb.assign(ppm+header.size(),ppm+n);plane_view.rgb={rgb.data(),rgb.size()};
    auto type=dtype(str(get(ip,plane_column.p,"dtype")));plane_view.finite_minimum=scalar(ip,strings,type,get(ip,plane_result.p,"minimum"),true);plane_view.finite_maximum=scalar(ip,strings,type,get(ip,plane_result.p,"maximum"),true);plane_view.finite_count=unsigned_value(ip,get(ip,plane_result.p,"finite_count"));if(plane_view.finite_count>input_rows)throw Error("Common plane finite count",Status::internal);plane_view.nonfinite_count=input_rows-plane_view.finite_count;plane_view.nearest_cell_scale=plane_view.width/plane_plan.source_width;
}
void Invocation::finish(){if(sealed||!input_rows||(input&&!consumed))throw Error("CORE seal requires complete canonical input");strings.limit=plan.limits.max_text_bytes-input_text_bytes;Obj op=word("finish");if(plan.mode==abi::PlanMode::grouped_curves){raw_result=invoke(ip,"::gx::native2d::_preview_batch",{op.p,batch.p});make_traces();if(overlay.p){overlay_result=invoke(ip,"::gx::native2d::_preview_overlay",{op.p,overlay.p});make_rasters();}}else make_plane();sealed=true;result_token=handle;}
void Invocation::close() noexcept{
    if(closed)return;closed=true;
    // Keep CORE/results alive until provider close returns, even partial open.
    if(provider_handle&&provider&&provider->close){auto handle_to_close=provider_handle;provider_handle=nullptr;provider->close(handle_to_close);}
    auto cleanup=[&](const char *name,Obj &token){if(!token.p)return;bool destroyed=false;Tcl_InterpState saved=Tcl_SaveInterpState(ip,TCL_OK);try{Obj destroy=word("destroy");invoke(ip,name,{destroy.p,token.p});destroyed=true;}catch(const Error &e){cleanup_failed=true;try{cleanup_message=bounded_diagnostic(e.message);}catch(...){}}catch(const std::exception &e){cleanup_failed=true;try{cleanup_message=bounded_diagnostic(e.what());}catch(...){}}catch(...){cleanup_failed=true;}Tcl_RestoreInterpState(ip,saved);if(destroyed)token=Obj();};
    cleanup("::gx::native2d::_preview_overlay",overlay);cleanup("::gx::native2d::_preview_batch",batch);result_token=0;handle=0;
    if(library&&!cleanup_failed){if(dlclose(library)==0)library=nullptr;else unload_failed=true;}provider=nullptr;
}
thread_local std::unordered_set<Invocation*> invocations;
abi::Text diagnostic_code(Status status) noexcept {
    static constexpr char unsupported[]="unsupported",error[]="preview_bridge_error";
    return status==Status::unsupported?abi::Text{unsupported,sizeof(unsupported)-1}:abi::Text{error,sizeof(error)-1};
}
void diagnostic_fallback(abi::Diagnostic *out,Status status) noexcept {
    if(out&&out->struct_bytes==sizeof(*out))*out={sizeof(*out),status,diagnostic_code(status),{kDiagnosticFallback,sizeof(kDiagnosticFallback)-1}};
}
void diagnose(Invocation &i,abi::Diagnostic *out,Status status,const std::string &message) noexcept{
    if(!out||out->struct_bytes!=sizeof(*out))return;
    try{i.diagnostic_message=bounded_diagnostic(message);*out={sizeof(*out),status,diagnostic_code(status),view(i.diagnostic_message)};}catch(...){diagnostic_fallback(out,status);}
}
void diagnose(Invocation &i,abi::Diagnostic *out,Status status,const char *message) noexcept{
    if(!out||out->struct_bytes!=sizeof(*out))return;
    try{diagnose(i,out,status,std::string(message?message:kDiagnosticFallback));}catch(...){diagnostic_fallback(out,status);}
}
template<class F>Status protect(void *raw,abi::Diagnostic *diag,F &&function) noexcept{
    auto *i=static_cast<Invocation*>(raw);
    if(!i||!invocations.count(i)||(diag&&diag->struct_bytes!=sizeof(*diag)))return Status::invalid;
    if(i->inside_core){diagnose(*i,diag,Status::invalid,"Reentrant CORE call is forbidden");return Status::invalid;}
    struct Guard{Invocation &i;explicit Guard(Invocation &v):i(v){i.inside_core=true;}~Guard(){i.inside_core=false;}} guard(*i);
    try{Status result=function(*i);if(diag)*diag={sizeof(*diag),result,{nullptr,0},{nullptr,0}};return result;}
    catch(const Error &e){i->failed=true;diagnose(*i,diag,e.status,e.message);return e.status;}
    catch(const std::bad_alloc &){i->failed=true;diagnose(*i,diag,Status::out_of_memory,"Preview bridge allocation failed");return Status::out_of_memory;}
    catch(const std::exception &e){i->failed=true;diagnose(*i,diag,Status::internal,e.what());return Status::internal;}
    catch(...){i->failed=true;diagnose(*i,diag,Status::internal,"Unknown Preview bridge failure");return Status::internal;}
}
Status core_create(void *v,abi::CoreHandle *out,abi::Diagnostic *d) noexcept{if(out)*out=0;return protect(v,d,[&](Invocation &i){if(!out)throw Error("Missing CORE handle output");i.begin();*out=i.handle;return Status::ok;});}
Status core_push(void *v,abi::CoreHandle h,const abi::Chunk *chunk,abi::Progress *p,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!p||p->struct_bytes!=sizeof(*p))throw Error("Invalid Progress size");i.require_handle(h);if(!i.input||!i.input->same(chunk))throw Error("Provider changed canonical input or supplied a foreign chunk");i.push();i.progress(p);return Status::ok;});}
Status core_seal(void *v,abi::CoreHandle h,abi::Progress *p,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!p||p->struct_bytes!=sizeof(*p))throw Error("Invalid Progress size");i.require_handle(h);i.finish();i.progress(p);return Status::done;});}
Status core_result(void *v,abi::CoreHandle h,abi::ResultToken *out,abi::Diagnostic *d) noexcept{if(out)*out=0;return protect(v,d,[&](Invocation &i){if(!out)throw Error("Missing CORE result output");i.require_handle(h);i.require_result(i.result_token);*out=i.result_token;return Status::done;});}
Status core_inspect(void *v,abi::ResultToken token,abi::ResultInfo *out,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!out||out->struct_bytes!=sizeof(*out))throw Error("Invalid ResultInfo size");i.require_result(token);*out={sizeof(*out),i.plan.mode,i.handle,i.traces.size(),i.rasters.size(),i.plan.mode==abi::PlanMode::bounded_array_plane?1U:0U,0,i.capabilities()};return Status::ok;});}
Status core_trace(void *v,abi::ResultToken token,uint64_t n,abi::TraceView *out,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!out||out->struct_bytes!=sizeof(*out))throw Error("Invalid TraceView size");i.require_result(token);if(n>=i.traces.size())throw Error("Trace view index outside result");*out=i.traces[static_cast<size_t>(n)].value;return Status::ok;});}
Status core_raster(void *v,abi::ResultToken token,uint64_t n,abi::RasterView *out,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!out||out->struct_bytes!=sizeof(*out))throw Error("Invalid RasterView size");i.require_result(token);if(n>=i.rasters.size())throw Error("Raster view index outside result");*out=i.rasters[static_cast<size_t>(n)].value;return Status::ok;});}
Status core_plane(void *v,abi::ResultToken token,abi::PlaneView *out,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!out||out->struct_bytes!=sizeof(*out))throw Error("Invalid PlaneView size");i.require_result(token);if(i.plan.mode!=abi::PlanMode::bounded_array_plane)throw Error("Result has no plane",Status::unsupported);*out=i.plane_view;return Status::ok;});}
Status core_cancel(void *v,abi::CoreHandle h,abi::Diagnostic *d) noexcept{return protect(v,d,[&](Invocation &i){if(!h||h!=i.handle||!i.created||i.closed)throw Error("Unknown CORE cancellation handle");i.cancelled=true;return Status::cancelled;});}
void require_ok(Status status,Invocation &i,const abi::Diagnostic &d,bool done=false){if(status!=(done?Status::done:Status::ok)){std::string message=copy_text(d.message,4096);throw Error(message.empty()?"Provider returned a failed status":message,status);}if(i.failed||i.cancelled)throw Error("Provider ignored a failed/cancelled CORE call",i.cancelled?Status::cancelled:Status::invalid);}
void validate_identity(const abi::AbiIdentity *identity){
    if(!identity||identity->struct_bytes!=sizeof(*identity)||identity->abi_major!=abi::kAbiMajor||identity->pointer_bytes!=sizeof(void*)||identity->native_endian!=abi::Endian::little||identity->float_format!=abi::FloatFormat::ieee754_binary64||identity->reserved[0]||identity->reserved[1]||!eq(identity->platform,host_identity().platform)||!eq(identity->value_layout_id,host_identity().value_layout_id)||copy_text(identity->build_id,256).empty())throw Error("Incompatible provider ABI/platform/value layout",Status::incompatible);
}
void validate_provider(Invocation &i,const abi::ProviderApi *table){
    if(!table||table->struct_bytes<abi::kProviderApiV1Bytes||table->abi_major!=abi::kAbiMajor||table->reserved||!table->probe||!table->open||!table->push||!table->seal||!table->result||!table->cancel||!table->close)throw Error("Provider table lacks mandatory ABI1 prefix",Status::incompatible);
    validate_identity(table->identity);if(table->abi_minor!=table->identity->abi_minor)throw Error("Provider table/identity minor disagree",Status::incompatible);
    if(copy_text(table->provider_id,256)!=i.component_id||copy_text(table->provider_version,128)!=i.provider_version)throw Error("Provider table differs from admitted ordinary module identity",Status::incompatible);
    if((table->capabilities&i.capabilities())!=i.capabilities()||(table->capabilities&abi::kCapRasterOverlay&&!(table->capabilities&abi::kCapGroupedCurves)))throw Error("Provider cannot prepare the full captured owner plan",Status::unsupported);
}
struct State {
    Tcl_Interp *ip;uint64_t serial=0;bool host_authority_enabled=false,constructing=false,disposing=false;
    std::unordered_map<std::string,std::shared_ptr<Invocation>> entries;
    explicit State(Tcl_Interp *v):ip(v){}
};
// MAIN-only integration contract. Merely defining procedures or supplying an
// admission dictionary cannot enable this compiled gate. MAIN must call the
// dedicated C initializer only from its fixed managed worker bootstrap.
// All names below are fixed, never copied from a render option/package field.
constexpr char kAuthorityAdmit[]="::GX::_pluginPreviewProviderAdmit";
constexpr char kAuthorityLoaded[]="::GX::_pluginPreviewProviderNoteLoaded";
constexpr char kAuthorityRetire[]="::GX::_pluginPreviewProviderRetire";
void admit(State &state,Invocation &i,Tcl_Obj *request){
    if(!state.host_authority_enabled||Tcl_FindCommand(i.ip,"::tk",nullptr,TCL_GLOBAL_ONLY))throw Error("MAIN fixed managed-worker package/lifecycle authority is not installed; native admission unavailable",Status::unsupported);
    if(i.admitted||i.provider||i.library||i.created)throw Error("Provider admission is allowed once");
    // The fixed owner must check actual worker identity, enabled/pending Module
    // state, all exact native/design bytes and GuardNewLoad BEFORE returning.
    for(const char *key:{"component_id","version","generation","native_abi","native_platform","native_layout_id","native_build_id","native_sha256","gui_design_sha256","host_build_id"})if(str(get(i.ip,request,key))!=str(get(i.ip,i.provider_binding.p,key)))throw Error("Admission request differs from captured provider/cache binding",Status::stale);
    i.package_admission=Obj(request);i.package_lease=invoke(i.ip,kAuthorityAdmit,{request});
    if(str(get(i.ip,i.package_lease.p,"schema"))!="gxtxt.preview_native_lease.v1")throw Error("Invalid MAIN package admission lease",Status::incompatible);
    i.component_id=bounded_text(get(i.ip,i.package_lease.p,"component_id"),256,"component_id");i.provider_version=bounded_text(get(i.ip,i.package_lease.p,"version"),128,"version");
    std::string path=bounded_text(get(i.ip,i.package_lease.p,"native_path"),4096,"native_path");if(path.empty()||path.front()!='/')throw Error("Package owner did not return an absolute admitted native path");
    for(const char *key:{"component_id","version","generation","native_abi","native_platform","native_layout_id","native_build_id","native_sha256","gui_design_sha256","host_build_id"})if(str(get(i.ip,i.package_lease.p,key))!=str(get(i.ip,i.provider_binding.p,key)))throw Error("MAIN lease differs from captured provider/cache binding",Status::stale);
    if(str(get(i.ip,i.package_lease.p,"native_abi"))!="gxtxt.preview.provider.v1"||str(get(i.ip,i.package_lease.p,"native_platform"))!=abi::kPlatform||str(get(i.ip,i.package_lease.p,"native_layout_id"))!=abi::kValueLayoutId||str(get(i.ip,i.package_lease.p,"host_build_id"))!=GXTXT_PREVIEW_BRIDGE_BUILD_ID)throw Error("Admission lease has incompatible current host identity",Status::incompatible);
    // Lease must include these exact bound receipts; only the MAIN owner may
    // verify their current bytes/generation. The bridge never treats strings
    // from the caller as their own certificate or a global unload permission.
    for(const char *key:{"native_sha256","gui_design_sha256","native_build_id","generation","lease_id","fingerprint"})if(str(get(i.ip,i.package_lease.p,key)).empty())throw Error("Incomplete package admission lease");
    for(const char *key:{"native_sha256","gui_design_sha256","fingerprint"}){auto digest=str(get(i.ip,i.package_lease.p,key));if(digest.size()!=64||digest.find_first_not_of("0123456789abcdef")!=std::string::npos)throw Error("Invalid package digest/fingerprint receipt");}
    auto verified=list(i.ip,get(i.ip,i.package_lease.p,"verified_capabilities"));if(verified.empty()||verified.size()>3)throw Error("Invalid admitted capability receipt");std::unordered_set<std::string> seen;uint64_t admitted_caps=0;for(auto *v:verified){auto name=str(v);if(!seen.insert(name).second)throw Error("Duplicate admitted capability");if(name=="grouped_curves")admitted_caps|=abi::kCapGroupedCurves;else if(name=="bounded_array_plane")admitted_caps|=abi::kCapBoundedArrayPlane;else if(name=="raster_overlay")admitted_caps|=abi::kCapRasterOverlay;else throw Error("Unknown admitted capability");}if((admitted_caps&i.capabilities())!=i.capabilities())throw Error("MAIN lease does not admit the full actual plan capabilities",Status::unsupported);
    i.library=dlopen(path.c_str(),RTLD_NOW|RTLD_LOCAL);if(!i.library)throw Error("Admitted native provider could not be loaded",Status::incompatible);
    // Record loading even if entry/table/open later fail. MAIN owns generation
    // quiescence. A failure here keeps the lease until host normal retirement.
    invoke(i.ip,kAuthorityLoaded,{i.package_lease.p});
    void *symbol=dlsym(i.library,"gxtxt_preview_provider_v1");if(!symbol)throw Error("Admitted provider lacks fixed ABI1 entry",Status::incompatible);
    abi::ProviderEntryV1 entry;static_assert(sizeof entry==sizeof symbol,"POSIX function pointer profile");std::memcpy(&entry,&symbol,sizeof entry);
    abi::Diagnostic d{};d.struct_bytes=sizeof d;const abi::ProviderApi *table=nullptr;Status status=entry(&host_identity(),abi::kCoreApiV1Bytes,abi::kProviderApiV1Bytes,&table,&d);if(status!=Status::ok){std::string message=copy_text(d.message,4096);throw Error(message.empty()?"Provider rejected host ABI":message,status);}validate_provider(i,table);i.provider=table;
    if(copy_text(table->identity->build_id,256)!=str(get(i.ip,i.package_lease.p,"native_build_id")))throw Error("Provider build differs from admitted build",Status::incompatible);
    // No independent contract string matching: MAIN Module owner supplies the
    // registry-compatible actual contract receipt, including curve_family.table.
    std::vector<std::string> contract_storage;for(auto *v:list(i.ip,get(i.ip,i.context.p,"contracts")))contract_storage.push_back(bounded_text(v,256,"contract"));std::vector<abi::Text> contracts;for(auto &s:contract_storage)contracts.push_back(view(s));
    std::string kind=bounded_text(get(i.ip,i.context.p,"dataset_kind"),128,"dataset_kind");abi::Probe probe{sizeof probe,static_cast<uint32_t>(contracts.size()),contracts.data(),view(kind),i.capabilities(),i.plan.mode,0};abi::Admission admission{};admission.struct_bytes=sizeof admission;d={};d.struct_bytes=sizeof d;status=table->probe(&probe,&admission,&d);require_ok(status,i,d);if(admission.struct_bytes!=sizeof admission||admission.supported!=1||(admission.capabilities&i.capabilities())!=i.capabilities())throw Error("Provider declined actual captured owner plan",Status::unsupported);
    d={};d.struct_bytes=sizeof d;status=table->open(&i.core,&i.plan,&i.provider_handle,&d);require_ok(status,i,d);if(!i.provider_handle||!i.created)throw Error("Provider open did not create its invocation-bound CORE preparation");i.admitted=true;
}
void retire(Invocation &i,const char *reason) {
    if(!i.package_lease.p)return;
    Obj why=word(reason);invoke(i.ip,kAuthorityRetire,{i.package_lease.p,why.p});
    // A failed owner retirement keeps the lease and reports the error. It is
    // never converted into a false quiescence/normal-close certificate.
    i.package_lease=Obj();
}
Obj receipt(Invocation &i){Obj d=dict();put(d.p,"native_abi","gxtxt.preview.provider.v1");number(d.p,"abi_major",1);put(d.p,"native_platform",abi::kPlatform);put(d.p,"native_layout_id",abi::kValueLayoutId);put(d.p,"host_build_id",GXTXT_PREVIEW_BRIDGE_BUILD_ID);if(i.admitted&&i.package_lease.p)put(d.p,"native_build_id",get(i.ip,i.package_lease.p,"native_build_id"));else put(d.p,"native_build_id","");number(d.p,"aggregate_native_budget_supported",0);put(d.p,"provider_id",i.component_id);put(d.p,"provider_version",i.provider_version);if(i.package_lease.p)put(d.p,"package_lease",i.package_lease.p);put(d.p,"source_receipt",i.source_receipt.p);return d;}
int command(ClientData client,Tcl_Interp *ip,int objc,Tcl_Obj *const objv[]){
    auto &state=*static_cast<State*>(client);std::shared_ptr<Invocation> owned;
    try{
        if(state.disposing)throw Error("Private provider owner is disposing");
        if(objc<2)throw Error("Expected private Preview provider operation");std::string op=str(objv[1]);
        if(op=="info"&&objc==2){Obj info=dict();put(info.p,"native_abi","gxtxt.preview.provider.v1");number(info.p,"abi_major",1);put(info.p,"native_platform",abi::kPlatform);put(info.p,"native_layout_id",abi::kValueLayoutId);put(info.p,"native_build_id",GXTXT_PREVIEW_BRIDGE_BUILD_ID);number(info.p,"aggregate_native_budget_supported",0);Tcl_SetObjResult(ip,info.p);return TCL_OK;}
        if(op=="open"&&objc==3){if(state.constructing)throw Error("Reentrant provider construction is forbidden");if(state.entries.size()>=4||state.serial==UINT64_MAX)throw Error("Private provider invocation limit",Status::limit);struct Construction{State&s;explicit Construction(State&v):s(v){s.constructing=true;}~Construction(){s.constructing=false;}} construction(state);auto i=std::make_shared<Invocation>(ip,objv[2],++state.serial);std::string token="preview-provider#"+std::to_string(state.serial);invocations.insert(i.get());try{state.entries.emplace(token,i);}catch(...){invocations.erase(i.get());throw;}Tcl_SetObjResult(ip,Tcl_NewStringObj(token.c_str(),-1));return TCL_OK;}
        if(objc<3)throw Error("Missing private invocation token");std::string token_key=str(objv[2]);auto found=state.entries.find(token_key);if(found==state.entries.end())throw Error("Unknown or closed private invocation");owned=found->second;auto &i=*owned;
        if(i.busy||i.inside_core)throw Error("Reentrant provider operation is forbidden");
        struct Busy{Invocation&i;explicit Busy(Invocation&v):i(v){i.busy=true;}~Busy(){i.busy=false;}} busy(i);
        if(op=="close"&&objc==3){i.close();if(i.cleanup_failed)throw Error("Common CORE cleanup failed; managed worker retirement required",Status::internal);if(i.unload_failed)throw Error("Native unload failed; managed worker retirement required",Status::internal);retire(i,i.admitted?"normal_close":"admission_failed");invocations.erase(&i);state.entries.erase(token_key);Tcl_ResetResult(ip);return TCL_OK;}
        if(op=="admit"&&objc==4){admit(state,i,objv[3]);Obj value=receipt(i);Tcl_SetObjResult(ip,value.p);return TCL_OK;}
        if(op=="inspect"&&objc==3){Obj value=receipt(i);number(value.p,"input_rows",i.input_rows);number(value.p,"admitted",i.admitted);number(value.p,"sealed",i.sealed);number(value.p,"failed",i.failed);number(value.p,"cancelled",i.cancelled);number(value.p,"cleanup_failed",i.cleanup_failed);number(value.p,"unload_failed",i.unload_failed);put(value.p,"cleanup_message",i.cleanup_message);Tcl_SetObjResult(ip,value.p);return TCL_OK;}
        if(!i.admitted||!i.provider||!i.provider_handle)throw Error("No admitted native provider",Status::unsupported);
        abi::Diagnostic d{};d.struct_bytes=sizeof d;
        if(op=="cancel"&&objc==3){Status status=i.provider->cancel(i.provider_handle,&d);if(status!=Status::cancelled&&status!=Status::ok)require_ok(status,i,d);i.cancelled=true;Tcl_ResetResult(ip);return TCL_OK;}
        i.require_handle(i.handle);
        if(op=="push"&&objc==4){if(i.sealed)throw Error("Invocation is already sealed");i.input=std::make_unique<Input>(ip,objv[3],i.input_rows,i.plan.limits.max_chunk_rows,i.plan.limits.max_text_bytes);i.consumed=false;abi::Progress p{};p.struct_bytes=sizeof p;Status status=i.provider->push(i.provider_handle,&i.input->chunk,&p,&d);require_ok(status,i,d);if(!i.consumed)throw Error("Provider omitted actual CORE push");i.input.reset();Obj out=dict();number(out.p,"input_rows",i.input_rows);number(out.p,"aggregate_native_budget_supported",0);Tcl_SetObjResult(ip,out.p);return TCL_OK;}
        if(op=="seal"&&objc==3){i.input.reset();abi::Progress p{};p.struct_bytes=sizeof p;Status status=i.provider->seal(i.provider_handle,&p,&d);require_ok(status,i,d,true);i.require_result(i.result_token);Tcl_ResetResult(ip);return TCL_OK;}
        if(op=="result"&&objc==3){abi::ResultToken token=0;Status status=i.provider->result(i.provider_handle,&token,&d);require_ok(status,i,d,true);i.require_result(token);Obj out=dict(),r=receipt(i);put(out.p,"receipt",r.p);put(out.p,"mode",i.plan.mode==abi::PlanMode::grouped_curves?"grouped_curves":"bounded_array_plane");if(i.raw_result.p)put(out.p,"native_series",i.raw_result.p);if(i.overlay_result.p)put(out.p,"overlay",i.overlay_result.p);if(i.plane_result.p)put(out.p,"plane",i.plane_result.p);put(out.p,"publication_requires_owner_source_session_key_guard","1");Tcl_SetObjResult(ip,out.p);return TCL_OK;}
        throw Error("Unknown private provider operation/argument count");
    }catch(const Error &e){if(owned)owned->failed=true;Tcl_SetObjResult(ip,Tcl_NewStringObj(e.message.data(),static_cast<int>(e.message.size())));Tcl_SetErrorCode(ip,"GXTXT","PREVIEW_PROVIDER",e.status==Status::unsupported?"UNSUPPORTED":"FAILED",nullptr);return TCL_ERROR;}
    catch(const std::exception &e){if(owned)owned->failed=true;Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
    catch(...){if(owned)owned->failed=true;Tcl_SetObjResult(ip,Tcl_NewStringObj("Unknown private Preview bridge failure",-1));return TCL_ERROR;}
}
void dispose(ClientData data,Tcl_Interp *){
    auto *state=static_cast<State*>(data);state->disposing=true;
    for(auto &entry:state->entries){entry.second->busy=true;entry.second->close();try{retire(*entry.second,entry.second->cleanup_failed?"worker_dispose_cleanup_failed":entry.second->unload_failed?"worker_dispose_unload_failed":"interpreter_dispose");}catch(...){
        // Interpreter destruction cannot return an error to its caller. Keep
        // failure explicit in the worker's ordinary diagnostic stream; MAIN's
        // process owner still owns emergency lease/quiescence retirement.
        Tcl_Channel channel=Tcl_GetStdChannel(TCL_STDERR);if(channel)Tcl_WriteChars(channel,"Preview package retirement failed during interpreter disposal; worker retirement required\n",-1);
    }invocations.erase(entry.second.get());}
    delete state;
}
} // namespace
// Neither function is a provider entry/export. Shared normal init is MAIN-owned.
extern "C" int gx2d_preview_provider_v1_init(Tcl_Interp *ip){
    try{
        if(Tcl_GetAssocData(ip,"gx2d.preview.provider.v1",nullptr))return TCL_OK;
        if(!Tcl_FindNamespace(ip,"::gx::native2d",nullptr,0)&&!Tcl_CreateNamespace(ip,"::gx::native2d",nullptr,nullptr))return TCL_ERROR;
        auto *state=new State(ip);Tcl_SetAssocData(ip,"gx2d.preview.provider.v1",dispose,state);
        if(!Tcl_CreateObjCommand(ip,"::gx::native2d::_preview_provider",command,state,nullptr)){Tcl_DeleteAssocData(ip,"gx2d.preview.provider.v1");return TCL_ERROR;}
        return TCL_OK;
    }catch(const std::exception &e){Tcl_SetObjResult(ip,Tcl_NewStringObj(e.what(),-1));return TCL_ERROR;}
    catch(...){Tcl_SetObjResult(ip,Tcl_NewStringObj("Preview bridge initialization failed",-1));return TCL_ERROR;}
}
extern "C" int gx2d_preview_provider_v1_enable_host_authority(Tcl_Interp *ip){
    auto *state=static_cast<State*>(Tcl_GetAssocData(ip,"gx2d.preview.provider.v1",nullptr));
    if(!state||Tcl_FindCommand(ip,"::tk",nullptr,TCL_GLOBAL_ONLY)){Tcl_SetObjResult(ip,Tcl_NewStringObj("Preview native admission requires fixed non-Tk managed worker",-1));return TCL_ERROR;}
    for(const char *name:{kAuthorityAdmit,kAuthorityLoaded,kAuthorityRetire})if(!Tcl_FindCommand(ip,name,nullptr,TCL_GLOBAL_ONLY)){Tcl_SetObjResult(ip,Tcl_NewStringObj("MAIN package/lifecycle hooks unavailable",-1));return TCL_ERROR;}
    state->host_authority_enabled=true;return TCL_OK;
}
