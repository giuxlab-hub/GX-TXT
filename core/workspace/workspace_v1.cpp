// SPDX-License-Identifier: GPL-3.0-or-later
#include "workspace_v1.hpp"
#include <sqlite3.h>
#include <openssl/rand.h>
#include <openssl/evp.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cerrno>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <filesystem>
#include <future>
#include <functional>
#include <iomanip>
#include <mutex>
#include <set>
#include <sstream>
#include <thread>

namespace gx::workspace::v1 {
Error::Error(std::string c, std::string m):std::runtime_error(std::move(m)),code(std::move(c)){}
Value Value::string(std::string s){Value v;v.kind=Kind::text;v.text=std::move(s);return v;}
Value Value::number(std::int64_t n){Value v;v.kind=Kind::integer;v.integer=n;return v;}
Value Value::floating(double n){Value v;v.kind=Kind::real;v.real=n;return v;}
Value Value::boolean(bool n){Value v;v.kind=Kind::boolean;v.integer=n;return v;}
Value Value::object(std::map<std::string,Value> f){Value v;v.kind=Kind::object;v.fields=std::move(f);return v;}
Value Value::array(std::vector<Value> a){Value v;v.kind=Kind::array;v.elements=std::move(a);return v;}
bool Value::operator==(const Value& v)const{return kind==v.kind && text==v.text && integer==v.integer && real==v.real && (real!=0||std::signbit(real)==std::signbit(v.real)) && fields==v.fields && elements==v.elements && field_order==v.field_order;}
namespace {
constexpr std::size_t MaxBytes=16*1024*1024, MaxNodes=262144, MaxQueue=32*1024*1024;
[[noreturn]] void fail(const char* c,const std::string& m){throw Error(c,m);}
std::string now(){auto n=std::chrono::system_clock::now().time_since_epoch();return std::to_string(std::chrono::duration_cast<std::chrono::microseconds>(n).count());}
std::string random_hex(){unsigned char b[16];if(RAND_bytes(b,sizeof b)!=1)fail("RANDOM","Workspace identity generation failed");std::ostringstream o;for(auto c:b)o<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(c);return o.str();}
std::string id(){unsigned char b[8];if(RAND_bytes(b,sizeof b)!=1)fail("RANDOM","Workspace identity generation failed");std::uint64_t n=0;for(auto c:b)n=(n<<8)|c;return "idoc_"+std::to_string(1000000000000000ULL+n%8000000000000000ULL);}
void token(const std::string& s,const char* label){if(s.empty()||s.size()>256||!std::all_of(s.begin(),s.end(),[](unsigned char c){return std::isalnum(c)||c=='.'||c=='_'||c=='-';}))fail("INVALID",std::string("Invalid ")+label);}
void name_valid(const std::string& n){if(n.empty()||n.size()>640||n.find_first_of("\r\n\0",0,3)!=std::string::npos)fail("NAME","Workspace name must be nonempty, bounded single-line text");}
std::size_t value_size(const Value& v,unsigned depth=0,std::size_t* nodes=nullptr){
    std::size_t local=0;if(!nodes)nodes=&local;
    if(depth>64||++*nodes>MaxNodes)fail("LIMIT","Workspace typed graph exceeds nesting/node bound");
    if(v.kind<Kind::null||v.kind>Kind::resource)fail("TYPE","Invalid native Workspace value kind");
    if(v.kind!=Kind::object&&v.kind!=Kind::resource&&!v.fields.empty())fail("TYPE","Scalar/array value cannot own object fields");
    if(!v.field_order.empty()){
        std::set<std::string> keys(v.field_order.begin(),v.field_order.end());
        if(keys.size()!=v.fields.size()||keys.size()!=v.field_order.size())fail("TYPE","Object field order must name each field exactly once");
        for(const auto& k:keys)if(!v.fields.count(k))fail("TYPE","Object field order names an unknown field");
    }
    if(v.kind!=Kind::array&&!v.elements.empty())fail("TYPE","Only arrays own elements");
    if(v.kind==Kind::real&&!std::isfinite(v.real))fail("TYPE","Use an explicit scientific missing/nonfinite descriptor");
    if(v.kind==Kind::real&&v.integer!=0)fail("TYPE","Real values cannot carry an unrelated integer scalar");
    if(v.kind==Kind::boolean&&v.integer!=0&&v.integer!=1)fail("TYPE","Boolean must be zero or one");
    std::size_t bytes=48+v.text.size();
    for(const auto& [k,x]:v.fields){if(k.size()>4096||k.find('\0')!=std::string::npos)fail("TYPE","Invalid property key");bytes+=k.size()+value_size(x,depth+1,nodes);if(bytes>MaxBytes)fail("LIMIT","Workspace state exceeds 16 MiB; use managed resources");}
    for(const auto& x:v.elements){bytes+=value_size(x,depth+1,nodes);if(bytes>MaxBytes)fail("LIMIT","Workspace state exceeds 16 MiB; use managed resources");}
    if(bytes>MaxBytes)fail("LIMIT","Workspace state exceeds 16 MiB; use managed resources");
    if(v.kind==Kind::resource){
        for(const auto* field:{"document_id","owner_generation","sha256","size_bytes"})if(!v.fields.count(field))fail("RESOURCE",std::string("Managed reference requires ")+field);
        const auto& hash=v.fields.at("sha256");const auto& count=v.fields.at("size_bytes");
        if(hash.kind!=Kind::text||hash.text.size()!=64||!std::all_of(hash.text.begin(),hash.text.end(),[](unsigned char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');})||count.kind!=Kind::integer||count.integer<0)fail("RESOURCE","Invalid managed reference digest/size");
        for(const auto* field:{"document_id","owner_generation"})if(v.fields.at(field).kind!=Kind::text||v.fields.at(field).text.empty())fail("RESOURCE","Managed reference needs stable owner identity");
    }
    return bytes;
}
std::size_t workspace_size(const Workspace& w){
    if(w.state.kind!=Kind::object||w.properties.kind!=Kind::object||w.provenance.kind!=Kind::object)fail("TYPE","Workspace state, properties and provenance must be typed objects");
    if(w.notes.size()>1048576)fail("LIMIT","Workspace notes exceed 1 MiB");
    auto n=value_size(w.state)+value_size(w.properties)+value_size(w.provenance)+w.notes.size()+2048;
    if(n>MaxBytes)fail("LIMIT","Workspace aggregate exceeds 16 MiB; use managed resources");
    return n;
}
Summary summary(const Workspace& w){auto preview=w.properties.fields.find("preview");return {w.identity,w.owner,w.provider,w.schema,w.schema_version,w.name,w.created_at,w.updated_at,w.content_sha256,!w.notes.empty(),preview!=w.properties.fields.end()&&preview->second.kind==Kind::resource};}
Workspace metadata_copy(const Workspace& source){
    Workspace result;result.identity=source.identity;result.owner=source.owner;result.provider=source.provider;result.schema=source.schema;result.schema_version=source.schema_version;
    result.name=source.name;result.notes=source.notes;result.created_at=source.created_at;result.updated_at=source.updated_at;result.content_sha256=source.content_sha256;return result;
}
std::string content_hash(const Workspace& w){
    // Length-prefixed native values define this digest, independently of Tcl
    // object ordering, string quoting or a Viewer's display serialization.
    auto ctx=std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)>(EVP_MD_CTX_new(),EVP_MD_CTX_free);
    if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)fail("HASH","Cannot initialize Workspace content digest");
    auto bytes=[&](const void* data,std::size_t n){if(EVP_DigestUpdate(ctx.get(),data,n)!=1)fail("HASH","Workspace content digest failed");};
    auto integer=[&](std::uint64_t n){unsigned char b[8];for(unsigned j=0;j<8;++j)b[j]=static_cast<unsigned char>(n>>(j*8));bytes(b,sizeof b);};
    auto text=[&](const std::string& s){integer(s.size());bytes(s.data(),s.size());};
    std::function<void(const Value&)> value=[&](const Value& v){
        integer(static_cast<unsigned>(v.kind));text(v.text);integer(static_cast<std::uint64_t>(v.integer));
        static_assert(sizeof(double)==8);std::uint64_t bits;std::memcpy(&bits,&v.real,8);integer(bits);
        integer(v.fields.size());for(const auto& [k,x]:v.fields){text(k);value(x);}
        integer(v.field_order.size());for(const auto& key:v.field_order)text(key);
        integer(v.elements.size());for(const auto& x:v.elements)value(x);
    };
    text("GXWorkspaceNative.v1");text(w.owner);text(w.provider);text(w.schema);text(w.schema_version);value(w.state);value(w.properties);value(w.provenance);
    unsigned char result[EVP_MAX_MD_SIZE];unsigned count=0;if(EVP_DigestFinal_ex(ctx.get(),result,&count)!=1)fail("HASH","Workspace content digest failed");std::ostringstream out;for(unsigned j=0;j<count;++j)out<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(result[j]);return out.str();
}
std::string archive_hash(const Value& content){Workspace wrapper;wrapper.schema="gxtxt.history_archive";wrapper.schema_version="1";wrapper.state=content;return content_hash(wrapper);}
void sql(sqlite3* db,const char* s){char* msg=nullptr;if(sqlite3_exec(db,s,nullptr,nullptr,&msg)!=SQLITE_OK){std::string m=msg?msg:sqlite3_errmsg(db);sqlite3_free(msg);fail("STORAGE",m);}}
struct Statement {
    sqlite3* db;sqlite3_stmt* s=nullptr;
    Statement(sqlite3* d,const char* q):db(d){if(sqlite3_prepare_v2(db,q,-1,&s,nullptr)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));}
    ~Statement(){sqlite3_finalize(s);}
    void reset(){sqlite3_reset(s);sqlite3_clear_bindings(s);}
    void bind(int n,const std::string& v){if(sqlite3_bind_text(s,n,v.data(),static_cast<int>(v.size()),SQLITE_TRANSIENT)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));}
    void bind(int n,std::int64_t v){if(sqlite3_bind_int64(s,n,v)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));}
    void bind(int n,double v){if(sqlite3_bind_double(s,n,v)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));}
    bool row(){int r=sqlite3_step(s);if(r==SQLITE_ROW)return true;if(r==SQLITE_DONE)return false;fail("STORAGE",sqlite3_errmsg(db));}
    std::string text(int n){auto* c=sqlite3_column_text(s,n);int b=sqlite3_column_bytes(s,n);return c?std::string(reinterpret_cast<const char*>(c),b):std::string();}
    std::int64_t integer(int n){return sqlite3_column_int64(s,n);}
};
struct Node {std::string parent,key,text;Kind kind;std::int64_t ordinal=0,integer=0;double real=0;bool operator==(const Node& n)const{return parent==n.parent&&key==n.key&&text==n.text&&kind==n.kind&&ordinal==n.ordinal&&integer==n.integer&&real==n.real;}};
using Nodes=std::map<std::string,Node>;
std::string hex(const std::string& key){static const char* h="0123456789abcdef";std::string r;for(unsigned char c:key){r+=h[c>>4];r+=h[c&15];}return r;}
void flatten(Nodes& n,const Value& v,const std::string& path,const std::string& parent={},const std::string& key={},std::int64_t order=0){
    // SQLite may store an integral REAL as an integer, losing the -0 sign.
    // Retain the exact finite IEEE bits in this kind's unused integer column.
    auto integer=v.integer;
    if(v.kind==Kind::real)std::memcpy(&integer,&v.real,sizeof integer);
    n.emplace(path,Node{parent,key,v.text,v.kind,order,integer,v.real});
    std::int64_t ordinal=0;
    if(v.field_order.empty()){for(const auto& [k,x]:v.fields)flatten(n,x,path+"/k"+hex(k),path,k,-1);}
    else for(const auto& k:v.field_order)flatten(n,v.fields.at(k),path+"/k"+hex(k),path,k,ordinal++);
    for(std::size_t j=0;j<v.elements.size();++j)flatten(n,v.elements[j],path+"/i"+std::to_string(j),path,{},j);
}
Nodes flatten(const Workspace& w){Nodes n;flatten(n,w.state,"state");flatten(n,w.properties,"properties");flatten(n,w.provenance,"provenance");return n;}
Value expand(const Nodes& n,const std::map<std::string,std::vector<std::string>>& children,const std::string& path,std::set<std::string>& visited,unsigned depth=0){
    if(depth>64||!visited.insert(path).second)fail("CORRUPT","Invalid persisted Workspace graph");
    const Node& node=n.at(path);Value v;v.kind=node.kind;v.text=node.text;v.integer=node.integer;v.real=node.real;
    if(v.kind==Kind::real){
        // A zero bits column also reads prior finite REAL nodes directly;
        // no old Workspace parsing or persisted-data conversion is involved.
        if(node.integer!=0){std::memcpy(&v.real,&node.integer,sizeof v.real);if(!std::isfinite(v.real)||v.real!=node.real)fail("CORRUPT","Persisted real bits differ from numeric value");}
        v.integer=0;
    }
    auto it=children.find(path);if(it==children.end())return v;
    auto paths=it->second;
    if(v.kind==Kind::array){std::sort(paths.begin(),paths.end(),[&](const auto& a,const auto& b){return n.at(a).ordinal<n.at(b).ordinal;});for(const auto& child:paths){if(n.at(child).ordinal!=static_cast<std::int64_t>(v.elements.size()))fail("CORRUPT","Invalid array order");v.elements.push_back(expand(n,children,child,visited,depth+1));}}
    else if(v.kind==Kind::object||v.kind==Kind::resource){
        bool ordered=n.at(paths.front()).ordinal>=0;
        if(ordered)std::sort(paths.begin(),paths.end(),[&](const auto& a,const auto& b){return n.at(a).ordinal<n.at(b).ordinal;});
        for(const auto& child:paths){
            const auto& node=n.at(child);
            if(ordered){if(node.ordinal!=static_cast<std::int64_t>(v.field_order.size()))fail("CORRUPT","Invalid object field order");v.field_order.push_back(node.key);}
            else if(node.ordinal!=-1)fail("CORRUPT","Mixed object field ordering");
            if(!v.fields.emplace(node.key,expand(n,children,child,visited,depth+1)).second)fail("CORRUPT","Duplicate object key");
        }
    }
    else fail("CORRUPT","Persisted scalar has children");
    return v;
}
// All graph reads run on the store worker, only for an explicit cold Open.
Nodes read_nodes(sqlite3* db,const std::string& workspace,const std::string& prefix={}){
    Statement q(db,prefix.empty()?"SELECT path,parent,key,kind,text_value,integer_value,real_value,ordinal FROM values_v1 WHERE workspace=? AND path NOT LIKE 'archive/%' ORDER BY path":"SELECT path,parent,key,kind,text_value,integer_value,real_value,ordinal FROM values_v1 WHERE workspace=? AND (path=? OR (path>=? AND path<?)) ORDER BY path");
    q.bind(1,workspace);if(!prefix.empty()){q.bind(2,prefix);q.bind(3,prefix+"/");q.bind(4,prefix+"0");}
    Nodes nodes;std::size_t bytes=0;
    while(q.row()){
        auto key=q.text(0);Node node{q.text(1),q.text(2),q.text(4),static_cast<Kind>(q.integer(3)),q.integer(7),q.integer(5),sqlite3_column_double(q.s,6)};
        bytes+=key.size()+node.text.size()+node.key.size()+64;
        if(nodes.size()>=MaxNodes||bytes>MaxBytes*4)fail("CORRUPT","Persisted native graph exceeds bounds");
        nodes.emplace(std::move(key),std::move(node));
    }
    return nodes;
}
std::map<std::string,std::vector<std::string>> child_index(const Nodes& nodes){
    std::map<std::string,std::vector<std::string>> children;
    for(const auto& [path,node]:nodes)if(!node.parent.empty())children[node.parent].push_back(path);
    return children;
}
Workspace read_workspace(sqlite3* db,Workspace metadata){
    auto nodes=read_nodes(db,metadata.identity.id);auto children=child_index(nodes);std::set<std::string> visited;
    for(const auto* root:{"state","properties","provenance"})if(!nodes.count(root))fail("CORRUPT","Missing Workspace graph root");
    metadata.state=expand(nodes,children,"state",visited);metadata.properties=expand(nodes,children,"properties",visited);metadata.provenance=expand(nodes,children,"provenance",visited);
    if(visited.size()!=nodes.size())fail("CORRUPT","Unreachable persisted Workspace nodes");
    workspace_size(metadata);if(content_hash(metadata)!=metadata.content_sha256)fail("CORRUPT","Native Workspace typed content digest differs");return metadata;
}
Value read_archive(sqlite3* db,const std::string& workspace,const std::string& id,const std::string& sha){
    auto root="archive/"+id;auto nodes=read_nodes(db,workspace,root);if(!nodes.count(root))fail("CORRUPT","Missing History archive graph");
    auto children=child_index(nodes);std::set<std::string> visited;auto value=expand(nodes,children,root,visited);
    if(visited.size()!=nodes.size())fail("CORRUPT","Unreachable History archive graph nodes");
    value_size(value);if(archive_hash(value)!=sha)fail("CORRUPT","Named History archive content digest differs");return value;
}
Value archive_listing(const std::string& id,const std::string& name,const Value& content){
    const auto& record=content.fields.at("record");return Value::object({{"id",Value::string(id)},{"name",Value::string(name)},{"saved_at",content.fields.at("saved_at")},{"source_revision",content.fields.at("source_revision")},{"count",Value::number(static_cast<std::int64_t>(record.fields.at("steps").elements.size()))},{"cursor",record.fields.at("cursor")}});
}
void sync_dir(const std::filesystem::path& path){int fd=::open(path.c_str(),O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(fd<0)fail("STORAGE","Cannot open Workspace database directory");int r=::fsync(fd);::close(fd);if(r)fail("STORAGE","Cannot synchronize Workspace database directory");}
using References=std::map<std::string,const Value*>;
void references(const Value& v,References& refs){
    if(v.kind==Kind::resource){
        auto key=v.fields.at("document_id").text+":"+v.fields.at("owner_generation").text+":"+v.fields.at("sha256").text;
        refs.emplace(key,&v);
    }
    for(const auto& [key,value]:v.fields)references(value,refs);
    for(const auto& value:v.elements)references(value,refs);
}
References references(const Workspace& w){References r;references(w.state,r);references(w.properties,r);references(w.provenance,r);return r;}
// Derived, compact retention pins are committed with the authoritative graph.
// Their digest and source hash let GC fail closed without opening scientific
// state or complete named workflows. Mixed cache/scientific uses stay scientific.
using Pins=std::map<std::string,Value>;
void retention_collect(const Value& value,Pins& pins){
    if(value.kind==Kind::resource){
        const auto& f=value.fields;auto key=f.at("document_id").text+":"+f.at("owner_generation").text+":"+f.at("sha256").text;
        bool disposable=false;auto metadata=f.find("metadata");
        if(metadata!=f.end()){
            auto truth=[](const Value& v){return (v.kind==Kind::boolean||v.kind==Kind::integer)?v.integer==1:v.kind==Kind::text&&v.text=="1";};
            auto zero=[](const Value& v){return (v.kind==Kind::boolean||v.kind==Kind::integer)?v.integer==0:v.kind==Kind::text&&v.text=="0";};
            auto d=metadata->second.fields.find("disposable"),a=metadata->second.fields.find("scientific_authority");
            disposable=d!=metadata->second.fields.end()&&a!=metadata->second.fields.end()&&truth(d->second)&&zero(a->second);
        }
        auto existing=pins.find(key);if(existing!=pins.end()){
            if(existing->second.fields.at("size_bytes").integer!=f.at("size_bytes").integer)fail("RESOURCE","Conflicting retained resource sizes");
            disposable=disposable&&existing->second.fields.at("metadata").fields.at("disposable").integer;
        }
        Value pin;pin.kind=Kind::resource;pin.fields={{"api_id",Value::string("INTERACTIVE_DOCUMENT_RESOURCE_API_v1")},{"document_id",f.at("document_id")},{"owner_generation",f.at("owner_generation")},{"sha256",f.at("sha256")},{"size_bytes",Value::number(f.at("size_bytes").integer)},{"metadata",Value::object({{"disposable",Value::boolean(disposable)},{"scientific_authority",Value::boolean(!disposable)}})}};pins[key]=std::move(pin);
    }
    for(const auto& [key,child]:value.fields)retention_collect(child,pins);
    for(const auto& child:value.elements)retention_collect(child,pins);
}
Value pin_array(const Pins& pins){std::vector<Value> values;for(const auto& [key,value]:pins)values.push_back(value);return Value::array(std::move(values));}
void persist_pins(sqlite3* db,const std::string& workspace,const std::string& scope,const std::string& sha,const Pins& pins){
    Statement root(db,"INSERT INTO retention_roots(workspace,scope,source_sha256,refs_sha256) VALUES(?,?,?,?) ON CONFLICT(workspace,scope) DO UPDATE SET source_sha256=excluded.source_sha256,refs_sha256=excluded.refs_sha256");root.bind(1,workspace);root.bind(2,scope);root.bind(3,sha);root.bind(4,archive_hash(pin_array(pins)));root.row();
    Statement remove(db,"DELETE FROM retention_pins WHERE workspace=? AND scope=?");remove.bind(1,workspace);remove.bind(2,scope);remove.row();
    Statement put(db,"INSERT INTO retention_pins(workspace,scope,document_id,generation,sha256,size_bytes,disposable) VALUES(?,?,?,?,?,?,?)");
    for(const auto& [key,value]:pins){const auto& f=value.fields;put.reset();put.bind(1,workspace);put.bind(2,scope);put.bind(3,f.at("document_id").text);put.bind(4,f.at("owner_generation").text);put.bind(5,f.at("sha256").text);put.bind(6,f.at("size_bytes").integer);put.bind(7,f.at("metadata").fields.at("disposable").integer);put.row();}
}
Pins read_pins(sqlite3* db,const std::string& workspace,const std::string& scope,const std::string& sha){
    Statement root(db,"SELECT source_sha256,refs_sha256 FROM retention_roots WHERE workspace=? AND scope=?");root.bind(1,workspace);root.bind(2,scope);
    if(!root.row())fail("RETENTION","Native retention index is absent; explicitly Open/validate this native graph before resource collection");
    if(root.text(0)!=sha)fail("CORRUPT","Retention index source digest differs");
    Statement rows(db,"SELECT document_id,generation,sha256,size_bytes,disposable FROM retention_pins WHERE workspace=? AND scope=? ORDER BY document_id,generation,sha256");rows.bind(1,workspace);rows.bind(2,scope);Pins pins;
    while(rows.row()){
        auto disposable=rows.integer(4);if(disposable!=0&&disposable!=1)fail("CORRUPT","Invalid retention pin disposition");
        Value pin;pin.kind=Kind::resource;pin.fields={{"api_id",Value::string("INTERACTIVE_DOCUMENT_RESOURCE_API_v1")},{"document_id",Value::string(rows.text(0))},{"owner_generation",Value::string(rows.text(1))},{"sha256",Value::string(rows.text(2))},{"size_bytes",Value::number(rows.integer(3))},{"metadata",Value::object({{"disposable",Value::boolean(disposable)},{"scientific_authority",Value::boolean(!disposable)}})}};
        value_size(pin);retention_collect(pin,pins);
    }
    if(archive_hash(pin_array(pins))!=root.text(1))fail("CORRUPT","Retention pin digest differs");
    return pins;
}
void resource_sync(const std::filesystem::path& metadata,const Value& reference){
    const auto& f=reference.fields;const auto& owner=f.at("document_id").text;const auto& sha=f.at("sha256").text;
    if(owner.compare(0,5,"idoc_")!=0||owner.size()<=5||owner.size()>32||!std::all_of(owner.begin()+5,owner.end(),[](unsigned char c){return c>='0'&&c<='9';}))fail("RESOURCE","Invalid managed resource owner ID");
    auto root=metadata/"interactive_document_resources"/owner;
    for(auto part=root;!part.empty()&&part!=part.root_path();part=part.parent_path())if(std::filesystem::is_symlink(std::filesystem::symlink_status(part)))fail("RESOURCE","Managed resource path contains a symlink");
    auto path=root/(sha+".blob");int fd=::open(path.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0)fail("RESOURCE","Managed resource bytes are unavailable");
    try{
        struct stat before{},after{};
        if(fstat(fd,&before)||!S_ISREG(before.st_mode)||before.st_size!=f.at("size_bytes").integer)fail("RESOURCE","Managed resource size/type differs");
        auto ctx=std::unique_ptr<EVP_MD_CTX,decltype(&EVP_MD_CTX_free)>(EVP_MD_CTX_new(),EVP_MD_CTX_free);
        if(!ctx||EVP_DigestInit_ex(ctx.get(),EVP_sha256(),nullptr)!=1)fail("HASH","Resource digest initialization failed");
        char buffer[65536];for(;;){ssize_t n=::read(fd,buffer,sizeof buffer);if(n<0){if(errno==EINTR)continue;fail("RESOURCE","Managed resource read failed");}if(!n)break;if(EVP_DigestUpdate(ctx.get(),buffer,n)!=1)fail("HASH","Managed resource digest failed");}
        unsigned char digest[EVP_MAX_MD_SIZE];unsigned n=0;if(EVP_DigestFinal_ex(ctx.get(),digest,&n)!=1)fail("HASH","Managed resource digest failed");std::ostringstream hex;for(unsigned j=0;j<n;++j)hex<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(digest[j]);
        if(fstat(fd,&after)||before.st_dev!=after.st_dev||before.st_ino!=after.st_ino||before.st_size!=after.st_size||before.st_mtim.tv_sec!=after.st_mtim.tv_sec||before.st_mtim.tv_nsec!=after.st_mtim.tv_nsec||hex.str()!=sha)fail("RESOURCE","Managed scientific resource content changed");
        if(::fsync(fd))fail("RESOURCE","Managed resource durability failed");
        sync_dir(root);sync_dir(root.parent_path());sync_dir(metadata);
    }catch(...){::close(fd);throw;}
    ::close(fd);
}
}

struct Store::Impl {
    struct Entry {Workspace value;std::uint64_t durable=0;bool deleted=false;std::size_t total_bytes=0;bool loaded=true,preview=false;std::shared_future<std::shared_ptr<Workspace>> loading;};
    struct Archive {std::string name;Value content;std::string sha256;Value listing;bool loaded=true;std::shared_future<std::shared_ptr<Value>> loading;};
    struct Job {
        Workspace next;bool deleted=false,metadata_only=false;std::size_t bytes=0;
        std::function<void(sqlite3*)> read;std::function<void(std::exception_ptr)> abort_read;
        // Archives are separate immutable graphs. Ordinary Save/Close never
        // materializes, copies, hashes or replays a retained History archive.
        unsigned archive_action=0;
        std::string archive_id,archive_name,transition_token;
        Value archive;
    };
    mutable std::mutex mutex;
    std::condition_variable wake,finished;
    std::map<std::string,Entry> entries;
    std::map<std::string,std::map<std::string,Archive>> archives;
    std::map<std::string,Schema> schemas;
    struct Origin {Identity identity;std::string sha256;};
    std::map<std::string,std::vector<Origin>> lineage;
    std::set<std::string> pending_names,pending_ids;
    std::map<std::string,std::string> scientific_owners;
    std::map<std::string,std::string> names;
    std::map<std::string,std::map<std::string,std::string>> providers,owners;
    std::deque<Job> queue;
    std::thread worker;
    std::string path,error;
    std::size_t queued=0;
    bool stopping=false,closed=false,recovery_pending=false;
    int lock=-1;
    explicit Impl(std::string file):path(std::filesystem::absolute(file).string()){
        auto parent=std::filesystem::path(path).parent_path();
        if(!std::filesystem::exists(parent))std::filesystem::create_directories(parent);
        for(auto p=std::filesystem::path(path);!p.empty()&&p!=p.root_path();p=p.parent_path())if(std::filesystem::is_symlink(std::filesystem::symlink_status(p)))fail("PATH","Workspace symlink paths are forbidden");
        lock=::open((path+".lock").c_str(),O_RDWR|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600);
        if(lock<0)fail("STORAGE","Cannot open Workspace writer lock");
        struct stat st{};if(fstat(lock,&st)||!S_ISREG(st.st_mode)||flock(lock,LOCK_EX|LOCK_NB)){::close(lock);lock=-1;fail("BUSY","Session Workspace database already has an active writer or invalid lock");}
        std::promise<void> ready;auto future=ready.get_future();
        worker=std::thread([this,r=std::move(ready)]()mutable{run(std::move(r));});
        try{future.get();}catch(...){worker.join();::close(lock);lock=-1;throw;}
    }
    ~Impl(){
        {std::lock_guard<std::mutex> g(mutex);stopping=true;wake.notify_one();}
        if(worker.joinable())worker.join();
        if(lock>=0)::close(lock);
    }
    void load(sqlite3* db){
        {Statement retired(db,"SELECT id,generation,revision,owner,provider FROM retired_owners");
        while(retired.row()){
            Workspace w;w.identity={retired.text(0),retired.text(1),static_cast<std::uint64_t>(retired.integer(2))};w.owner=retired.text(3);w.provider=retired.text(4);
            auto key=w.identity.id;auto revision=w.identity.revision;
            entries.emplace(key,Entry{std::move(w),revision,true,0,true,false,{}});
        }}
        Statement q(db,"SELECT id,generation,revision,owner,provider,schema_id,schema_version,name,notes,created_at,updated_at,content_sha256 FROM workspaces ORDER BY id");
        while(q.row()){
            Workspace w;w.identity={q.text(0),q.text(1),static_cast<std::uint64_t>(q.integer(2))};w.owner=q.text(3);w.provider=q.text(4);w.schema=q.text(5);w.schema_version=q.text(6);w.name=q.text(7);w.notes=q.text(8);w.created_at=q.text(9);w.updated_at=q.text(10);w.content_sha256=q.text(11);
            if(w.identity.revision<1||w.identity.generation.empty())fail("CORRUPT","Invalid Workspace identity");
            name_valid(w.name);
            // The preview flag is an indexed single-node probe; never Open a body.
            Statement preview(db,"SELECT 1 FROM values_v1 WHERE workspace=? AND path='properties/k70726576696577' AND kind=7");preview.bind(1,w.identity.id);bool has_preview=preview.row();
            std::size_t total_bytes=0;
            if(!names.emplace(w.name,w.identity.id).second)fail("CORRUPT","Duplicate persisted Workspace name");
            providers[w.provider][w.name]=w.identity.id;owners[w.owner][w.name]=w.identity.id;
            auto revision=w.identity.revision;auto key=w.identity.id;
            if(!entries.emplace(key,Entry{std::move(w),revision,false,total_bytes,false,has_preview,{}}).second)fail("CORRUPT","Retired/live Workspace identity collision");
        }
        {Statement sources(db,"SELECT workspace,source_id,source_generation,source_revision,source_sha256 FROM workspace_lineage ORDER BY workspace,source_id,source_generation");while(sources.row()){auto workspace=sources.text(0);if(!entries.count(workspace)||entries.at(workspace).deleted)fail("CORRUPT","Workspace lineage owner unavailable");lineage[workspace].push_back({{sources.text(1),sources.text(2),static_cast<std::uint64_t>(sources.integer(3))},sources.text(4)});}}
        Statement saved(db,"SELECT workspace,archive_id,name,sha256 FROM history_archives ORDER BY workspace,archive_id");
        while(saved.row()){
            auto workspace=saved.text(0),archive=saved.text(1),name=saved.text(2),sha=saved.text(3),prefix="archive/"+archive;
            if(!entries.count(workspace)||entries.at(workspace).deleted)fail("CORRUPT","History archive owner unavailable");
            name_valid(name);token(archive,"History archive identity");
            auto scalar=[&](const std::string& suffix,Kind kind){Statement field(db,"SELECT kind,text_value,integer_value FROM values_v1 WHERE workspace=? AND path=?");field.bind(1,workspace);field.bind(2,prefix+suffix);if(!field.row()||field.integer(0)!=static_cast<std::int64_t>(kind))fail("CORRUPT","Invalid archive metadata");return kind==Kind::text?Value::string(field.text(1)):Value::number(field.integer(2));};
            Statement count(db,"SELECT count(*) FROM values_v1 WHERE workspace=? AND parent=?");count.bind(1,workspace);count.bind(2,prefix+"/k7265636f7264/k7374657073");count.row();
            auto listing=Value::object({{"id",Value::string(archive)},{"name",Value::string(name)},{"saved_at",scalar("/k73617665645f6174",Kind::text)},{"source_revision",scalar("/k736f757263655f7265766973696f6e",Kind::integer)},{"count",Value::number(count.integer(0))},{"cursor",scalar("/k7265636f7264/k637572736f72",Kind::integer)}});
            archives[workspace].emplace(archive,Archive{name,Value::object(),sha,std::move(listing),false,{}});
        }
    }
    void persist(sqlite3* db,const Job& j,std::map<std::string,Nodes>& persisted){
        sql(db,"BEGIN IMMEDIATE");
        try{
            const auto& w=j.next;
            if(j.deleted){
                // A deleted editor object may still own published science.
                // Retain only its identity, never a second active Workspace.
                Statement tombstone(db,"INSERT INTO retired_owners(id,generation,revision,owner,provider) VALUES(?,?,?,?,?)");
                tombstone.bind(1,w.identity.id);tombstone.bind(2,w.identity.generation);tombstone.bind(3,static_cast<std::int64_t>(w.identity.revision));tombstone.bind(4,w.owner);tombstone.bind(5,w.provider);tombstone.row();
                Statement d(db,"DELETE FROM workspaces WHERE id=? AND generation=?");d.bind(1,w.identity.id);d.bind(2,w.identity.generation);d.row();persisted.erase(w.identity.id);
            }
            else{
                Statement s(db,"INSERT INTO workspaces(id,generation,revision,owner,provider,schema_id,schema_version,name,notes,created_at,updated_at,content_sha256) VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,name=excluded.name,notes=excluded.notes,updated_at=excluded.updated_at,content_sha256=excluded.content_sha256");
                s.bind(1,w.identity.id);s.bind(2,w.identity.generation);s.bind(3,static_cast<std::int64_t>(w.identity.revision));s.bind(4,w.owner);s.bind(5,w.provider);s.bind(6,w.schema);s.bind(7,w.schema_version);s.bind(8,w.name);s.bind(9,w.notes);s.bind(10,w.created_at);s.bind(11,w.updated_at);s.bind(12,w.content_sha256);s.row();
                if(j.archive_action){
                    if(j.archive_action==1){
                        Pins pins;retention_collect(j.archive,pins);persist_pins(db,w.identity.id,j.archive_id,archive_hash(j.archive),pins);
                        Statement archive(db,"INSERT INTO history_archives(workspace,archive_id,name,sha256) VALUES(?,?,?,?)");archive.bind(1,w.identity.id);archive.bind(2,j.archive_id);archive.bind(3,j.archive_name);archive.bind(4,archive_hash(j.archive));archive.row();
                        Nodes nodes;flatten(nodes,j.archive,"archive/"+j.archive_id);
                        Statement put(db,"INSERT INTO values_v1(workspace,path,parent,key,kind,text_value,integer_value,real_value,ordinal) VALUES(?,?,?,?,?,?,?,?,?)");
                        for(const auto& [key,node]:nodes){put.reset();put.bind(1,w.identity.id);put.bind(2,key);put.bind(3,node.parent);put.bind(4,node.key);put.bind(5,static_cast<std::int64_t>(node.kind));put.bind(6,node.text);put.bind(7,node.integer);put.bind(8,node.real);put.bind(9,node.ordinal);put.row();}
                    }else if(j.archive_action==2){Statement rename(db,"UPDATE history_archives SET name=? WHERE workspace=? AND archive_id=?");rename.bind(1,j.archive_name);rename.bind(2,w.identity.id);rename.bind(3,j.archive_id);rename.row();}
                    else{
                        Statement pins(db,"DELETE FROM retention_roots WHERE workspace=? AND scope=?");pins.bind(1,w.identity.id);pins.bind(2,j.archive_id);pins.row();
                        Statement remove(db,"DELETE FROM history_archives WHERE workspace=? AND archive_id=?");remove.bind(1,w.identity.id);remove.bind(2,j.archive_id);remove.row();
                        Statement nodes(db,"DELETE FROM values_v1 WHERE workspace=? AND (path=? OR path LIKE ?)");nodes.bind(1,w.identity.id);nodes.bind(2,"archive/"+j.archive_id);nodes.bind(3,"archive/"+j.archive_id+"/%");nodes.row();
                    }
                    sql(db,"COMMIT");return;
                }
                if(j.metadata_only){sql(db,"COMMIT");return;}
                Nodes next=flatten(w);if(!persisted.count(w.identity.id))persisted.emplace(w.identity.id,read_nodes(db,w.identity.id));const auto& old=persisted.at(w.identity.id);
                Statement remove(db,"DELETE FROM values_v1 WHERE workspace=? AND path=?");
                for(const auto& [key,node]:old)if(!next.count(key)){remove.reset();remove.bind(1,w.identity.id);remove.bind(2,key);remove.row();}
                Statement put(db,"INSERT INTO values_v1(workspace,path,parent,key,kind,text_value,integer_value,real_value,ordinal) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(workspace,path) DO UPDATE SET parent=excluded.parent,key=excluded.key,kind=excluded.kind,text_value=excluded.text_value,integer_value=excluded.integer_value,real_value=excluded.real_value,ordinal=excluded.ordinal");
                for(const auto& [key,node]:next){auto it=old.find(key);if(it!=old.end()&&it->second==node)continue;put.reset();put.bind(1,w.identity.id);put.bind(2,key);put.bind(3,node.parent);put.bind(4,node.key);put.bind(5,static_cast<std::int64_t>(node.kind));put.bind(6,node.text);put.bind(7,node.integer);put.bind(8,node.real);put.bind(9,node.ordinal);put.row();}
                Pins pins;retention_collect(w.state,pins);retention_collect(w.properties,pins);retention_collect(w.provenance,pins);persist_pins(db,w.identity.id,"active",w.content_sha256,pins);
                // Move into the derived worker cache only after COMMIT succeeds.
                if(!j.transition_token.empty()){Statement commit(db,"UPDATE transitions SET phase='committed' WHERE token=? AND phase='prepared'");commit.bind(1,j.transition_token);commit.row();if(sqlite3_changes(db)!=1)fail("CONFLICT","Workspace transition intent changed");}
                sql(db,"COMMIT");persisted[w.identity.id]=std::move(next);return;
            }
            sql(db,"COMMIT");
        }catch(...){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);throw;}
    }
    void run(std::promise<void> ready){
        sqlite3* db=nullptr;bool announced=false;
        try{
            if(sqlite3_open_v2(path.c_str(),&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_NOMUTEX,nullptr)!=SQLITE_OK)fail("STORAGE",db?sqlite3_errmsg(db):"Cannot open Workspace database");
            sqlite3_busy_timeout(db,5000);sql(db,"PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA wal_autocheckpoint=128;");
            std::int64_t v;
            {Statement version(db,"PRAGMA user_version");version.row();v=version.integer(0);}
            if(v!=0&&v!=1)fail("VERSION","Unsupported native Workspace database contract");
            if(v==0){
                {Statement present(db,"SELECT count(*) FROM sqlite_master WHERE type='table'");present.row();if(present.integer(0)!=0)fail("VERSION","Unidentified database cannot become a Workspace store");}
                sql(db,"BEGIN IMMEDIATE; CREATE TABLE workspaces(id TEXT PRIMARY KEY,generation TEXT NOT NULL,revision INTEGER NOT NULL CHECK(revision>0),owner TEXT NOT NULL,provider TEXT NOT NULL,schema_id TEXT NOT NULL,schema_version TEXT NOT NULL,name TEXT NOT NULL UNIQUE,notes TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,content_sha256 TEXT NOT NULL); CREATE TABLE retired_owners(id TEXT PRIMARY KEY,generation TEXT NOT NULL,revision INTEGER NOT NULL,owner TEXT NOT NULL,provider TEXT NOT NULL); CREATE TABLE history_archives(workspace TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,archive_id TEXT NOT NULL,name TEXT NOT NULL,sha256 TEXT NOT NULL,PRIMARY KEY(workspace,archive_id),UNIQUE(workspace,name)); CREATE TABLE values_v1(workspace TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,path TEXT NOT NULL,parent TEXT NOT NULL,key TEXT NOT NULL,kind INTEGER NOT NULL CHECK(kind BETWEEN 0 AND 7),text_value TEXT NOT NULL,integer_value INTEGER NOT NULL,real_value REAL NOT NULL,ordinal INTEGER NOT NULL,PRIMARY KEY(workspace,path)); CREATE INDEX workspace_provider_name ON workspaces(provider,name); CREATE INDEX workspace_owner_name ON workspaces(owner,name); PRAGMA user_version=1; COMMIT;");sync_dir(std::filesystem::path(path).parent_path());}
            sql(db,"CREATE INDEX IF NOT EXISTS workspace_values_parent ON values_v1(workspace,parent)");
            sql(db,"CREATE TABLE IF NOT EXISTS retention_roots(workspace TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,scope TEXT NOT NULL,source_sha256 TEXT NOT NULL,refs_sha256 TEXT NOT NULL,PRIMARY KEY(workspace,scope)); CREATE TABLE IF NOT EXISTS retention_pins(workspace TEXT NOT NULL,scope TEXT NOT NULL,document_id TEXT NOT NULL,generation TEXT NOT NULL,sha256 TEXT NOT NULL,size_bytes INTEGER NOT NULL,disposable INTEGER NOT NULL CHECK(disposable IN (0,1)),PRIMARY KEY(workspace,scope,document_id,generation,sha256),FOREIGN KEY(workspace,scope) REFERENCES retention_roots(workspace,scope) ON DELETE CASCADE)");
            sql(db,"CREATE TABLE IF NOT EXISTS workspace_lineage(workspace TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,source_id TEXT NOT NULL,source_generation TEXT NOT NULL,source_revision INTEGER NOT NULL,source_sha256 TEXT NOT NULL,PRIMARY KEY(workspace,source_id,source_generation))");
            sql(db,"CREATE TABLE IF NOT EXISTS transitions(token TEXT PRIMARY KEY,workspace TEXT NOT NULL,generation TEXT NOT NULL,revision INTEGER NOT NULL,phase TEXT NOT NULL,sha256 TEXT NOT NULL); CREATE TABLE IF NOT EXISTS transition_nodes(token TEXT NOT NULL REFERENCES transitions(token) ON DELETE CASCADE,path TEXT NOT NULL,parent TEXT NOT NULL,key TEXT NOT NULL,kind INTEGER NOT NULL,text_value TEXT NOT NULL,integer_value INTEGER NOT NULL,real_value REAL NOT NULL,ordinal INTEGER NOT NULL,PRIMARY KEY(token,path))");
            {Statement pending(db,"SELECT count(*) FROM transitions");pending.row();recovery_pending=pending.integer(0)!=0;}
            load(db);std::map<std::string,Nodes> persisted;
            std::set<std::string> durableResources;
            ready.set_value();announced=true;
            for(;;){
                Job j;
                {std::unique_lock<std::mutex> g(mutex);wake.wait(g,[&]{return stopping||!queue.empty();});if(queue.empty()&&stopping)break;j=std::move(queue.front());queue.pop_front();}
                if(j.read){j.read(db);continue;}
                if(!j.deleted && (!j.metadata_only || j.archive_action==1)){
                    auto refs=references(j.next);if(j.archive_action==1)references(j.archive,refs);
                    for(const auto& [key,reference]:refs)if(!durableResources.count(key)){
                        resource_sync(std::filesystem::path(path).parent_path(),*reference);
                        durableResources.insert(key);
                    }
                }
                persist(db,j,persisted);
                {std::lock_guard<std::mutex> g(mutex);entries.at(j.next.identity.id).durable=j.next.identity.revision;queued-=j.bytes;finished.notify_all();}
            }
            if(sqlite3_wal_checkpoint_v2(db,nullptr,SQLITE_CHECKPOINT_TRUNCATE,nullptr,nullptr)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));
            sync_dir(std::filesystem::path(path).parent_path());
        }catch(...){
            if(!announced)ready.set_exception(std::current_exception());
            else{try{throw;}catch(const std::exception& e){std::lock_guard<std::mutex> g(mutex);error=e.what();for(auto& job:queue)if(job.abort_read)job.abort_read(std::current_exception());queue.clear();finished.notify_all();}}
        }
        if(db)sqlite3_close(db);
    }
    template<class T,class F> std::shared_future<std::shared_ptr<T>> read_submit(F operation){
        writable(true);auto promise=std::make_shared<std::promise<std::shared_ptr<T>>>();auto result=promise->get_future().share();Job job;
        job.read=[promise,operation=std::move(operation)](sqlite3* db)mutable{try{promise->set_value(std::make_shared<T>(operation(db)));}catch(...){promise->set_exception(std::current_exception());}};
        job.abort_read=[promise](std::exception_ptr error){promise->set_exception(error);};queue.push_back(std::move(job));wake.notify_one();return result;
    }
    Entry& live(const std::string& id){auto found=entries.find(id);if(found==entries.end()||found->second.deleted)fail("MISSING","Workspace is unavailable");return found->second;}
    Summary describe(const Entry& entry)const{auto result=summary(entry.value);if(!entry.loaded)result.has_preview=entry.preview;return result;}
    void ensure_loaded(const std::string& id){
        std::unique_lock<std::mutex> lock(mutex);auto& entry=live(id);if(entry.loaded)return;
        if(!entry.loading.valid()){auto metadata=metadata_copy(entry.value);entry.loading=read_submit<Workspace>([metadata=std::move(metadata)](sqlite3* db){auto result=read_workspace(db,metadata);Statement present(db,"SELECT 1 FROM retention_roots WHERE workspace=? AND scope='active'");present.bind(1,metadata.identity.id);if(!present.row()){Pins pins;retention_collect(result.state,pins);retention_collect(result.properties,pins);retention_collect(result.provenance,pins);sql(db,"BEGIN IMMEDIATE");try{persist_pins(db,metadata.identity.id,"active",metadata.content_sha256,pins);sql(db,"COMMIT");}catch(...){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);throw;}}return result;});}
        auto future=entry.loading;lock.unlock();auto result=future.get();lock.lock();auto& current=live(id);if(current.loaded)return;
        if(current.value.identity.generation!=result->identity.generation||current.value.content_sha256!=result->content_sha256)fail("CONFLICT","Workspace changed during Open");
        current.value.state=std::move(result->state);current.value.properties=std::move(result->properties);current.value.provenance=std::move(result->provenance);
        current.total_bytes=workspace_size(current.value);current.loaded=true;current.loading={};
    }
    void ensure_size(const Identity& expected_id){
        std::unique_lock<std::mutex> lock(mutex);auto& entry=expected(expected_id);if(entry.total_bytes)return;
        auto future=read_submit<std::size_t>([id=expected_id.id](sqlite3* db){Statement size(db,"SELECT coalesce(sum(48+length(CAST(text_value AS BLOB))+length(CAST(key AS BLOB))),0) FROM values_v1 WHERE workspace=? AND path NOT LIKE 'archive/%'");size.bind(1,id);size.row();return static_cast<std::size_t>(size.integer(0))+2048;});
        lock.unlock();auto result=future.get();lock.lock();auto& current=expected(expected_id);if(!current.total_bytes)current.total_bytes=*result+current.value.notes.size();
    }
    void ensure_archive(const std::string& workspace,const std::string& archive){
        std::unique_lock<std::mutex> lock(mutex);live(workspace);auto owner=archives.find(workspace);if(owner==archives.end()||!owner->second.count(archive))fail("MISSING","Named History archive is unavailable");
        auto& entry=owner->second.at(archive);if(entry.loaded)return;
        if(!entry.loading.valid()){auto sha=entry.sha256;entry.loading=read_submit<Value>([workspace,archive,sha](sqlite3* db){auto result=read_archive(db,workspace,archive,sha);Statement present(db,"SELECT 1 FROM retention_roots WHERE workspace=? AND scope=?");present.bind(1,workspace);present.bind(2,archive);if(!present.row()){Pins pins;retention_collect(result,pins);sql(db,"BEGIN IMMEDIATE");try{persist_pins(db,workspace,archive,sha,pins);sql(db,"COMMIT");}catch(...){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);throw;}}return result;});}
        auto future=entry.loading;lock.unlock();auto result=future.get();lock.lock();live(workspace);owner=archives.find(workspace);if(owner==archives.end()||!owner->second.count(archive))fail("MISSING","Named History archive was deleted");
        auto& current=owner->second.at(archive);if(!current.loaded){current.content=std::move(*result);current.loaded=true;current.loading={};}
    }
    void writable(bool recovering=false)const{if(recovery_pending&&!recovering)fail("RECOVERY_REQUIRED","An interrupted Workspace/History transition must be recovered before writing");if(closed||stopping)fail("CLOSED","Workspace Session store is closed");if(!error.empty())fail("STORAGE","Workspace persistence failed: "+error);}
    Entry& expected(const Identity& identity){writable();auto it=entries.find(identity.id);if(it==entries.end()||it->second.deleted)fail("MISSING","Workspace is unavailable");if(it->second.value.identity.generation!=identity.generation||it->second.value.identity.revision!=identity.revision)fail("CONFLICT","Workspace generation/revision changed; reopen before saving");return it->second;}
    Receipt receipt(const Entry& e)const{return {e.value.identity,e.durable,true,e.durable<e.value.identity.revision,!error.empty(),queued,error};}
    void unique_name(const std::string& n,const std::string& except={})const{name_valid(n);auto it=names.find(n);if((it!=names.end()&&it->second!=except)||pending_names.count(n))fail("NAME_EXISTS","Workspace name already exists or is being duplicated");}
    void validate_references(const References& refs,const Workspace& w)const{
        for(const auto& [key,reference]:refs){
            const auto& owner=reference->fields.at("document_id").text;
            const auto& generation=reference->fields.at("owner_generation").text;
            auto found=entries.find(owner);
            if(owner==w.identity.id&&generation==w.identity.generation)continue;
            auto scientific=scientific_owners.find(owner);
            if(found==entries.end()&&scientific!=scientific_owners.end()&&scientific->second==generation)continue;
            if(found==entries.end()||found->second.value.identity.generation!=generation)fail("RESOURCE","Managed reference has a stale or foreign scientific owner");
        }
    }
    void validate(const Workspace& w)const{
        auto schema=schemas.find(w.provider);if(schema==schemas.end())fail("PROVIDER","Workspace provider is not registered with the native contract");
        const auto& s=schema->second;if(s.owner!=w.owner||s.id!=w.schema||s.version!=w.schema_version)fail("SCHEMA","Workspace provider/schema contract differs");
        for(const auto& [field,kind]:s.required){auto x=w.state.fields.find(field);if(x==w.state.fields.end()||x->second.kind!=kind)fail("SCHEMA","Workspace state requires typed field "+field);}
        workspace_size(w);validate_references(references(w),w);
    }
    Receipt submit(Workspace w,bool deleted=false,bool contentChanged=true){
        std::size_t bytes=workspace_size(w);if(bytes>MaxQueue-queued)fail("QUEUE_FULL","Workspace persistence queue is full; wait for durability");
        if(contentChanged)w.content_sha256=content_hash(w);
        auto key=w.identity.id;Job j;j.next=w;j.deleted=deleted;j.bytes=bytes;queue.push_back(std::move(j));
        auto old=entries.find(key);std::uint64_t durable=old==entries.end()?0:old->second.durable;
        if(old!=entries.end()){names.erase(old->second.value.name);providers[old->second.value.provider].erase(old->second.value.name);owners[old->second.value.owner].erase(old->second.value.name);}
        if(!deleted){names[w.name]=key;providers[w.provider][w.name]=key;owners[w.owner][w.name]=key;}
        entries[key]={std::move(w),durable,deleted,bytes,true,false,{}};queued+=bytes;wake.notify_one();return receipt(entries.at(key));
    }
    void metadata_apply(Entry& entry,Workspace next){
        if(entry.total_bytes)entry.total_bytes=entry.total_bytes-entry.value.notes.size()+next.notes.size();
        entry.value.identity=std::move(next.identity);entry.value.name=std::move(next.name);entry.value.notes=std::move(next.notes);entry.value.updated_at=std::move(next.updated_at);
    }
    Receipt metadata_submit(Workspace next,bool deleted=false){
        auto& entry=entries.at(next.identity.id);
        if(next.notes.size()>1048576 || (entry.total_bytes&&entry.total_bytes-entry.value.notes.size()+next.notes.size()>MaxBytes))fail("LIMIT","Workspace notes exceed native size bounds");
        auto bytes=workspace_size(next);if(bytes>MaxQueue-queued)fail("QUEUE_FULL","Workspace persistence queue is full; wait for durability");
        auto key=next.identity.id;Job job;job.next=next;job.deleted=deleted;job.metadata_only=true;job.bytes=bytes;queue.push_back(std::move(job));
        if(deleted||entry.value.name!=next.name){
            names.erase(entry.value.name);providers[entry.value.provider].erase(entry.value.name);owners[entry.value.owner].erase(entry.value.name);
            if(!deleted){names[next.name]=key;providers[next.provider][next.name]=key;owners[next.owner][next.name]=key;}
        }
        if(deleted){entry.value=std::move(next);entry.deleted=true;entry.total_bytes=bytes;archives.erase(key);}else metadata_apply(entry,std::move(next));
        queued+=bytes;wake.notify_one();return receipt(entry);
    }
    Receipt archive_submit(Workspace w,unsigned action,const std::string& archive,const std::string& name,Value content=Value::object()){
        auto bytes=value_size(content)+2048;
        if(bytes>MaxQueue-queued)fail("QUEUE_FULL","Workspace persistence queue is full");
        Job j;j.next=w;j.bytes=bytes;j.metadata_only=true;j.archive_action=action;j.archive_id=archive;j.archive_name=name;j.archive=std::move(content);
        auto key=w.identity.id;
        queue.push_back(std::move(j));metadata_apply(entries.at(key),std::move(w));queued+=bytes;wake.notify_one();return receipt(entries.at(key));
    }
};

Store::Store(const std::string& file):p(std::make_unique<Impl>(file)){}
Store::~Store()=default;
void Store::register_schema(Schema s){
    token(s.provider,"Workspace provider");token(s.owner,"Workspace owner");token(s.id,"Workspace schema");token(s.version,"Workspace schema version");
    std::lock_guard<std::mutex> g(p->mutex);p->writable(true);auto it=p->schemas.find(s.provider);
    if(it!=p->schemas.end()&&(it->second.id!=s.id||it->second.owner!=s.owner||it->second.version!=s.version||it->second.required!=s.required))fail("SCHEMA","Provider registration cannot replace an existing native contract");
    p->schemas[s.provider]=std::move(s);
}
Receipt Store::create(std::string provider,std::string name,Value state,Value properties,Value provenance){
    std::lock_guard<std::mutex> g(p->mutex);p->writable();p->unique_name(name);auto it=p->schemas.find(provider);if(it==p->schemas.end())fail("PROVIDER","Native Workspace provider unavailable");
    Workspace w;w.identity={id(),random_hex(),1};while(p->entries.count(w.identity.id)||p->pending_ids.count(w.identity.id))w.identity.id=id();w.provider=std::move(provider);w.owner=it->second.owner;w.schema=it->second.id;w.schema_version=it->second.version;w.name=std::move(name);w.state=std::move(state);w.properties=std::move(properties);w.provenance=std::move(provenance);w.created_at=w.updated_at=now();p->validate(w);return p->submit(std::move(w));
}
Workspace Store::get(const std::string& id)const{p->ensure_loaded(id);std::lock_guard<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it==p->entries.end()||it->second.deleted)fail("MISSING","Workspace is unavailable");return it->second.value;}
Value Store::properties(const std::string& id)const{p->ensure_loaded(id);std::lock_guard<std::mutex> guard(p->mutex);auto found=p->entries.find(id);if(found==p->entries.end()||found->second.deleted)fail("MISSING","Workspace is unavailable");return found->second.value.properties;}
Summary Store::metadata(const std::string& id)const{std::lock_guard<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it==p->entries.end()||it->second.deleted)fail("MISSING","Workspace is unavailable");return p->describe(it->second);}
std::string Store::note_text(const std::string& id)const{std::lock_guard<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it==p->entries.end()||it->second.deleted)fail("MISSING","Workspace is unavailable");return it->second.value.notes;}
std::string Store::resource_owner_generation(const std::string& id)const{std::lock_guard<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it!=p->entries.end())return it->second.value.identity.generation;auto scientific=p->scientific_owners.find(id);if(scientific!=p->scientific_owners.end())return scientific->second;fail("MISSING","Scientific resource owner is unavailable");}
std::string Store::retired_owner_generation(const std::string& id)const{
    std::lock_guard<std::mutex> guard(p->mutex);auto found=p->entries.find(id);
    if(found==p->entries.end()||!found->second.deleted)fail("MISSING","Retired native Workspace owner is unavailable");
    return found->second.value.identity.generation;
}
Value Store::retained_references(const std::string& exclude,const std::string& only){
    {std::lock_guard<std::mutex> guard(p->mutex);if(p->recovery_pending)fail("RECOVERY_REQUIRED","Resolve the Workspace/History transition before resource collection");}
    // GC must never release the previous durable graph's resources while an
    // accepted replacement is pending or failed. A failed barrier aborts GC.
    flush_all();
    std::unique_lock<std::mutex> guard(p->mutex);
    // Captured source identities describe the accepted queue boundary. The
    // worker executes this read after every previously accepted transaction.
    std::vector<std::tuple<std::string,std::string,std::string>> roots;
    for(const auto& [id,entry]:p->entries)if(!entry.deleted&&id!=exclude&&(only.empty()||id==only)){
        roots.emplace_back(id,"active",entry.value.content_sha256);auto found=p->archives.find(id);if(found!=p->archives.end())for(const auto& [key,archive]:found->second)roots.emplace_back(id,key,archive.sha256);
    }
    auto future=p->read_submit<Value>([roots=std::move(roots)](sqlite3* db){Pins retained;for(const auto& [workspace,scope,sha]:roots){auto pins=read_pins(db,workspace,scope,sha);for(const auto& [key,value]:pins)retention_collect(value,retained);}return pin_array(retained);});
    guard.unlock();return *future.get();
}
void Store::register_resource_owner(std::string owner,std::string generation){
    if(owner.compare(0,5,"idoc_")!=0||owner.size()<=5||owner.size()>32||!std::all_of(owner.begin()+5,owner.end(),[](unsigned char c){return c>='0'&&c<='9';})||generation.empty()||generation.size()>256||generation.find('\0')!=std::string::npos)fail("RESOURCE","Invalid scientific owner identity");
    std::lock_guard<std::mutex> g(p->mutex);p->writable();
    auto native=p->entries.find(owner);
    if(native!=p->entries.end()){if(native->second.value.identity.generation!=generation)fail("RESOURCE","Scientific owner conflicts with native identity");return;}
    auto existing=p->scientific_owners.find(owner);
    if(existing!=p->scientific_owners.end()&&existing->second!=generation)fail("RESOURCE","Scientific owner generation changed during this Session lifetime");
    p->scientific_owners.emplace(std::move(owner),std::move(generation));
}
std::vector<Summary> Store::query(const Query& q)const{
    if(q.limit>10000)fail("LIMIT","Workspace query limit exceeds 10000");
    if(!q.limit)return {};
    std::lock_guard<std::mutex> g(p->mutex);std::vector<Summary> r;std::size_t offset=q.offset;
    const auto* candidates=&p->names;
    if(!q.provider.empty()){auto found=p->providers.find(q.provider);if(found==p->providers.end())return {};candidates=&found->second;}
    if(!q.owner.empty()){auto found=p->owners.find(q.owner);if(found==p->owners.end())return {};if(candidates==&p->names||found->second.size()<candidates->size())candidates=&found->second;}
    // All three indexes are ordered by name. Seek the prefix and stop at the
    // requested page; no matching scientific bodies or full-result sort exist.
    for(auto it=q.name_prefix.empty()?candidates->begin():candidates->lower_bound(q.name_prefix);it!=candidates->end();++it){
        if(!q.name_prefix.empty()&&it->first.compare(0,q.name_prefix.size(),q.name_prefix)!=0)break;
        const auto& w=p->entries.at(it->second).value;if((!q.provider.empty()&&q.provider!=w.provider)||(!q.owner.empty()&&q.owner!=w.owner))continue;if(offset){--offset;continue;}if(r.size()==q.limit)break;r.push_back(p->describe(p->entries.at(it->second)));
    }return r;
}
Value Store::lineage(const std::string& id)const{
    std::lock_guard<std::mutex> guard(p->mutex);p->live(id);std::vector<Value> values;
    auto found=p->lineage.find(id);if(found!=p->lineage.end())for(const auto& source:found->second)values.push_back(Value::object({{"id",Value::string(source.identity.id)},{"generation",Value::string(source.identity.generation)},{"revision",Value::number(static_cast<std::int64_t>(source.identity.revision))},{"sha256",Value::string(source.sha256)}}));return Value::array(std::move(values));
}
void Store::checkpoint(){
    std::unique_lock<std::mutex> guard(p->mutex);p->writable();auto future=p->read_submit<bool>([this](sqlite3* db){if(sqlite3_wal_checkpoint_v2(db,nullptr,SQLITE_CHECKPOINT_TRUNCATE,nullptr,nullptr)!=SQLITE_OK)fail("STORAGE",sqlite3_errmsg(db));sync_dir(std::filesystem::path(p->path).parent_path());return true;});guard.unlock();future.get();
}
Receipt Store::duplicate(const Identity& source,std::string name){
    std::unique_lock<std::mutex> guard(p->mutex);p->expected(source);p->unique_name(name);
    auto destination=id();while(p->entries.count(destination)||p->pending_ids.count(destination))destination=id();auto generation=random_hex();
    p->pending_names.insert(name);p->pending_ids.insert(destination);
    try{
        auto future=p->read_submit<Receipt>([this,source,name,destination,generation](sqlite3* db){
            try{
                Workspace original;
                Statement metadata(db,"SELECT generation,revision,owner,provider,schema_id,schema_version,name,notes,created_at,updated_at,content_sha256 FROM workspaces WHERE id=?");metadata.bind(1,source.id);
                if(!metadata.row()||metadata.text(0)!=source.generation||static_cast<std::uint64_t>(metadata.integer(1))!=source.revision)fail("CONFLICT","Workspace changed before duplication");
                original.identity=source;original.owner=metadata.text(2);original.provider=metadata.text(3);original.schema=metadata.text(4);original.schema_version=metadata.text(5);original.name=metadata.text(6);original.notes=metadata.text(7);original.created_at=metadata.text(8);original.updated_at=metadata.text(9);original.content_sha256=metadata.text(10);
                original=read_workspace(db,std::move(original));bool preview=summary(original).has_preview;
                // Explicit duplication validates cold graphs once. It never
                // replays History or copies scientific resource bytes.
                std::map<std::string,Impl::Archive> retained;std::map<std::string,Pins> pinsets;
                retention_collect(original.state,pinsets["active"]);retention_collect(original.properties,pinsets["active"]);retention_collect(original.provenance,pinsets["active"]);
                Statement saved(db,"SELECT archive_id,name,sha256 FROM history_archives WHERE workspace=? ORDER BY archive_id");saved.bind(1,source.id);
                while(saved.row()){auto key=saved.text(0),label=saved.text(1),sha=saved.text(2);auto content=read_archive(db,source.id,key,sha);retention_collect(content,pinsets[key]);retained.emplace(key,Impl::Archive{label,Value::object(),sha,archive_listing(key,label,content),false,{}});}
                Pins resources;for(const auto& [scope,pins]:pinsets)for(const auto& [key,value]:pins)retention_collect(value,resources);
                References refs;for(const auto& [key,value]:resources)refs.emplace(key,&value);
                {std::lock_guard<std::mutex> lock(p->mutex);p->validate_references(refs,original);}
                for(const auto& [key,value]:resources)resource_sync(std::filesystem::path(p->path).parent_path(),value);
                auto next=metadata_copy(original);next.identity={destination,generation,1};next.name=name;next.created_at=next.updated_at=now();
                std::vector<Impl::Origin> origins;
                Statement ancestors(db,"SELECT source_id,source_generation,source_revision,source_sha256 FROM workspace_lineage WHERE workspace=? ORDER BY source_id,source_generation");ancestors.bind(1,source.id);
                while(ancestors.row())origins.push_back({{ancestors.text(0),ancestors.text(1),static_cast<std::uint64_t>(ancestors.integer(2))},ancestors.text(3)});
                origins.push_back({source,original.content_sha256});
                sql(db,"BEGIN IMMEDIATE");
                try{
                    Statement create(db,"INSERT INTO workspaces(id,generation,revision,owner,provider,schema_id,schema_version,name,notes,created_at,updated_at,content_sha256) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)");
                    create.bind(1,destination);create.bind(2,generation);create.bind(3,std::int64_t(1));create.bind(4,next.owner);create.bind(5,next.provider);create.bind(6,next.schema);create.bind(7,next.schema_version);create.bind(8,name);create.bind(9,next.notes);create.bind(10,next.created_at);create.bind(11,next.updated_at);create.bind(12,next.content_sha256);create.row();
                    for(const auto* statement:{
                        "INSERT INTO values_v1 SELECT ?,path,parent,key,kind,text_value,integer_value,real_value,ordinal FROM values_v1 WHERE workspace=?",
                        "INSERT INTO history_archives SELECT ?,archive_id,name,sha256 FROM history_archives WHERE workspace=?"}){Statement copy(db,statement);copy.bind(1,destination);copy.bind(2,source.id);copy.row();}
                    for(const auto& [scope,pins]:pinsets)persist_pins(db,destination,scope,scope=="active"?next.content_sha256:retained.at(scope).sha256,pins);
                    Statement put(db,"INSERT INTO workspace_lineage(workspace,source_id,source_generation,source_revision,source_sha256) VALUES(?,?,?,?,?) ON CONFLICT(workspace,source_id,source_generation) DO UPDATE SET source_revision=excluded.source_revision,source_sha256=excluded.source_sha256");
                    for(const auto& origin:origins){put.reset();put.bind(1,destination);put.bind(2,origin.identity.id);put.bind(3,origin.identity.generation);put.bind(4,static_cast<std::int64_t>(origin.identity.revision));put.bind(5,origin.sha256);put.row();}
                    sql(db,"COMMIT");
                }catch(...){sqlite3_exec(db,"ROLLBACK",nullptr,nullptr,nullptr);throw;}
                std::lock_guard<std::mutex> lock(p->mutex);
                p->entries.emplace(destination,Impl::Entry{std::move(next),1,false,0,false,preview,{}});auto& entry=p->entries.at(destination);
                p->names[name]=destination;p->providers[entry.value.provider][name]=destination;p->owners[entry.value.owner][name]=destination;p->archives[destination]=std::move(retained);p->lineage[destination]=std::move(origins);
                p->pending_names.erase(name);p->pending_ids.erase(destination);return p->receipt(entry);
            }catch(...){std::lock_guard<std::mutex> lock(p->mutex);p->pending_names.erase(name);p->pending_ids.erase(destination);throw;}
        });
        guard.unlock();return *future.get();
    }catch(...){if(!guard.owns_lock())guard.lock();p->pending_names.erase(name);p->pending_ids.erase(destination);throw;}
}
#include "workspace_transition_v1.inc"
#include "workspace_capsule_v1.inc"
Receipt Store::save(const Identity& e,Value state,Value properties){{std::lock_guard<std::mutex> guard(p->mutex);p->expected(e);}p->ensure_loaded(e.id);std::lock_guard<std::mutex> g(p->mutex);auto w=p->expected(e).value;w.state=std::move(state);w.properties=std::move(properties);p->validate(w);if(w.state==p->entries.at(e.id).value.state&&w.properties==p->entries.at(e.id).value.properties)return p->receipt(p->entries.at(e.id));++w.identity.revision;w.updated_at=now();return p->submit(std::move(w));}
Receipt Store::save_properties(const Identity& expected,Value properties){
    {std::lock_guard<std::mutex> guard(p->mutex);p->expected(expected);}p->ensure_loaded(expected.id);
    std::lock_guard<std::mutex> guard(p->mutex);auto& entry=p->expected(expected);
    if(properties==entry.value.properties)return p->receipt(entry);
    auto next=entry.value;next.properties=std::move(properties);p->validate(next);++next.identity.revision;next.updated_at=now();return p->submit(std::move(next));
}
Receipt Store::rename(const Identity& e,std::string name){std::lock_guard<std::mutex> g(p->mutex);auto& entry=p->expected(e);p->unique_name(name,e.id);if(name==entry.value.name)return p->receipt(entry);auto w=metadata_copy(entry.value);w.name=std::move(name);++w.identity.revision;w.updated_at=now();return p->metadata_submit(std::move(w));}
Receipt Store::notes(const Identity& e,std::string text){p->ensure_size(e);std::lock_guard<std::mutex> g(p->mutex);auto& entry=p->expected(e);if(text==entry.value.notes)return p->receipt(entry);auto w=metadata_copy(entry.value);w.notes=std::move(text);++w.identity.revision;w.updated_at=now();return p->metadata_submit(std::move(w));}
Receipt Store::erase(const Identity& e,bool confirmed){if(!confirmed)fail("CONFIRMATION","Workspace Delete requires explicit confirmation");std::lock_guard<std::mutex> g(p->mutex);auto w=metadata_copy(p->expected(e).value);++w.identity.revision;return p->metadata_submit(std::move(w),true);}
std::pair<Receipt,std::string> Store::history_save(const Identity& expected,std::string name,Value record,Value auxiliary,Value context){
    {std::lock_guard<std::mutex> guard(p->mutex);p->expected(expected);}p->ensure_loaded(expected.id);
    std::lock_guard<std::mutex> g(p->mutex);const auto& source=p->expected(expected).value;auto w=metadata_copy(source);name_valid(name);
    if(record.kind!=Kind::object||auxiliary.kind!=Kind::object||context.kind!=Kind::object)fail("HISTORY","History archive requires typed record, auxiliary and context objects");
    for(const auto* key:{"format","workbench_id","base","steps","cursor","retention"})if(!record.fields.count(key))fail("HISTORY",std::string("Complete History archive requires ")+key);
    const auto& f=record.fields;
    if(f.at("format").kind!=Kind::text||f.at("format").text!="gxtxt.scientific_recipe.v1"||f.at("workbench_id").kind!=Kind::text||f.at("workbench_id").text!=w.owner||f.at("base").kind!=Kind::object||f.at("steps").kind!=Kind::array||f.at("cursor").kind!=Kind::integer||f.at("cursor").integer<0||static_cast<std::size_t>(f.at("cursor").integer)>f.at("steps").elements.size()||f.at("steps").elements.size()>4096)fail("HISTORY","History archive has a foreign owner, incompatible format or invalid initial state/cursor");
    for(const auto& [key,archive]:p->archives[w.identity.id])if(archive.name==name)fail("NAME_EXISTS","History archive name already exists in this Workspace");
    if(p->archives[w.identity.id].size()>=256)fail("LIMIT","Workspace retains at most 256 named History archives");
    for(const auto& step:f.at("steps").elements){
        if(step.kind!=Kind::object)fail("HISTORY","History operation must be a typed object");
        for(const auto* key:{"api_id","api_version","operation","parameters","targets","result_ids","working_unit","patch"})if(!step.fields.count(key))fail("HISTORY",std::string("History operation requires ")+key);
        if(step.fields.at("patch").kind!=Kind::object||step.fields.at("api_version").kind!=Kind::integer||step.fields.at("api_version").integer!=1)fail("HISTORY","Invalid native History operation patch/version");
    }
    Value content=Value::object({{"record",std::move(record)},{"auxiliary",std::move(auxiliary)},{"context",std::move(context)},
        {"source_workspace",Value::string(w.identity.id)},{"source_generation",Value::string(w.identity.generation)},
        {"source_revision",Value::number(static_cast<std::int64_t>(w.identity.revision))},{"owner",Value::string(w.owner)},
        {"provider",Value::string(w.provider)},{"schema",Value::string(w.schema)},{"schema_version",Value::string(w.schema_version)},
        {"provenance",source.provenance},{"saved_at",Value::string(now())}});
    value_size(content);
    // Existing scientific resource authority is retained by reference. It is
    // validated against this native Session and synchronized on the worker.
    References refs;references(content,refs);p->validate_references(refs,w);
    auto archive="history_"+random_hex();++w.identity.revision;w.updated_at=now();
    auto sha=archive_hash(content);
    auto receipt=p->archive_submit(w,1,archive,name,content);
    p->archives[w.identity.id].emplace(archive,Impl::Archive{name,content,std::move(sha),archive_listing(archive,name,content),true,{}});
    return {receipt,archive};
}
Value Store::history_list(const std::string& workspace)const{
    std::lock_guard<std::mutex> g(p->mutex);auto owner=p->entries.find(workspace);if(owner==p->entries.end()||owner->second.deleted)fail("MISSING","History archive Workspace is unavailable");
    std::vector<Value> values;auto found=p->archives.find(workspace);
    if(found!=p->archives.end())for(const auto& [id,a]:found->second){
        auto listing=a.listing;listing.fields["name"]=Value::string(a.name);values.push_back(std::move(listing));
    }
    return Value::array(std::move(values));
}
Value Store::history_get(const std::string& workspace,const std::string& archive)const{
    p->ensure_archive(workspace,archive);
    std::lock_guard<std::mutex> g(p->mutex);auto owner=p->entries.find(workspace);if(owner==p->entries.end()||owner->second.deleted)fail("MISSING","History archive Workspace is unavailable");
    auto found=p->archives.find(workspace);if(found==p->archives.end()||!found->second.count(archive))fail("MISSING","Named History archive is unavailable");
    const auto& a=found->second.at(archive);auto value=a.content;
    bool owned=value.fields.at("source_workspace").text==workspace&&value.fields.at("source_generation").text==owner->second.value.identity.generation;
    if(!owned){auto origins=p->lineage.find(workspace);if(origins!=p->lineage.end())for(const auto& origin:origins->second)if(origin.identity.id==value.fields.at("source_workspace").text&&origin.identity.generation==value.fields.at("source_generation").text){owned=true;break;}}
    if(!owned)fail("HISTORY","Named History archive owner is unrelated to this Workspace lineage");
    value.fields.emplace("id",Value::string(archive));value.fields.emplace("name",Value::string(a.name));value.fields.emplace("sha256",Value::string(a.sha256));return value;
}
Receipt Store::history_rename(const Identity& expected,const std::string& archive,std::string name){
    std::lock_guard<std::mutex> g(p->mutex);auto w=metadata_copy(p->expected(expected).value);name_valid(name);auto& all=p->archives[w.identity.id];
    if(!all.count(archive))fail("MISSING","Named History archive is unavailable");
    for(const auto& [id,a]:all)if(id!=archive&&a.name==name)fail("NAME_EXISTS","History archive name already exists");
    if(all.at(archive).name==name)return p->receipt(p->entries.at(w.identity.id));
    ++w.identity.revision;w.updated_at=now();auto r=p->archive_submit(w,2,archive,name);all.at(archive).name=std::move(name);return r;
}
Receipt Store::history_delete(const Identity& expected,const std::string& archive,bool confirmed){
    if(!confirmed)fail("CONFIRMATION","Named History Delete requires explicit confirmation");
    std::lock_guard<std::mutex> g(p->mutex);auto w=metadata_copy(p->expected(expected).value);auto& all=p->archives[w.identity.id];if(!all.count(archive))fail("MISSING","Named History archive is unavailable");
    ++w.identity.revision;w.updated_at=now();auto r=p->archive_submit(w,3,archive,{});all.erase(archive);return r;
}
Receipt Store::status(const std::string& id)const{std::lock_guard<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it==p->entries.end())fail("MISSING","Workspace identity unavailable");return p->receipt(it->second);}
Receipt Store::flush(const std::string& id,unsigned timeout){
    if(timeout>600000)fail("LIMIT","Workspace flush timeout exceeds 600000 ms");
    std::unique_lock<std::mutex> g(p->mutex);auto it=p->entries.find(id);if(it==p->entries.end())fail("MISSING","Workspace identity unavailable");auto revision=it->second.value.identity.revision;
    if(!p->finished.wait_for(g,std::chrono::milliseconds(timeout),[&]{return !p->error.empty()||p->entries.at(id).durable>=revision;}))fail("TIMEOUT","Workspace durability wait timed out; accepted state is retained");
    if(!p->error.empty())fail("STORAGE",p->error);
    return p->receipt(p->entries.at(id));
}
void Store::flush_all(unsigned timeout){if(timeout>600000)fail("LIMIT","Workspace flush timeout exceeds 600000 ms");std::unique_lock<std::mutex> g(p->mutex);if(!p->finished.wait_for(g,std::chrono::milliseconds(timeout),[&]{return !p->error.empty()||p->queued==0;}))fail("TIMEOUT","Workspace durability wait timed out");if(!p->error.empty())fail("STORAGE",p->error);}
void Store::close(){
    {std::lock_guard<std::mutex> g(p->mutex);if(p->closed)return;}
    flush_all();{std::lock_guard<std::mutex> g(p->mutex);p->stopping=true;p->wake.notify_one();}
    if(p->worker.joinable())p->worker.join();
    std::lock_guard<std::mutex> g(p->mutex);if(!p->error.empty())fail("STORAGE",p->error);p->closed=true;if(p->lock>=0){::close(p->lock);p->lock=-1;}
}
}
