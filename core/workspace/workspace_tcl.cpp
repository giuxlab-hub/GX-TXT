// SPDX-License-Identifier: GPL-3.0-or-later
// Owning-thread transport only. The native Store/worker contains no Tcl objects.
#include "workspace_v1.hpp"
#include "workspace_json_v1.hpp"
#include <tcl.h>
#include <cmath>
#include <map>
#include <memory>
#include <string>

namespace {
using namespace gx::workspace::v1;
std::string string(Tcl_Obj* o){
    // Tcl's internal UTF representation is not the external UTF-8 contract
    // (notably embedded NUL and supplementary characters). Normalize only
    // this encoding boundary; scientific text content remains unchanged.
    int n=0;const char* p=Tcl_GetStringFromObj(o,&n);Tcl_DString bytes;Tcl_DStringInit(&bytes);
    auto encoding=Tcl_GetEncoding(nullptr,"utf-8");Tcl_UtfToExternalDString(encoding,p,n,&bytes);
    std::string out(Tcl_DStringValue(&bytes),static_cast<std::size_t>(Tcl_DStringLength(&bytes)));Tcl_DStringFree(&bytes);Tcl_FreeEncoding(encoding);return out;
}
void set_text(Tcl_Obj* o,const std::string& s){
    Tcl_DString bytes;Tcl_DStringInit(&bytes);auto encoding=Tcl_GetEncoding(nullptr,"utf-8");
    Tcl_ExternalToUtfDString(encoding,s.data(),static_cast<int>(s.size()),&bytes);
    Tcl_SetStringObj(o,Tcl_DStringValue(&bytes),Tcl_DStringLength(&bytes));Tcl_DStringFree(&bytes);Tcl_FreeEncoding(encoding);
}
Tcl_Obj* text(const std::string& s){auto* result=Tcl_NewObj();set_text(result,s);return result;}
void check(int result,Tcl_Interp* i){if(result!=TCL_OK)throw Error("TRANSPORT",string(Tcl_GetObjResult(i)));}
struct Ref {Tcl_Obj* p;explicit Ref(Tcl_Obj* v):p(v){Tcl_IncrRefCount(p);}~Ref(){Tcl_DecrRefCount(p);}operator Tcl_Obj*()const{return p;}};
void put(Tcl_Interp* i,Tcl_Obj* d,const char* key,Tcl_Obj* v){Ref k(Tcl_NewStringObj(key,-1));check(Tcl_DictObjPut(i,d,k,v),i);}
void put(Tcl_Interp* i,Tcl_Obj* d,const char* k,const std::string& v){put(i,d,k,text(v));}
void number(Tcl_Interp* i,Tcl_Obj* d,const char* k,std::uint64_t v){put(i,d,k,Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(v)));}
Kind kind(const std::string& s){if(s=="null")return Kind::null;if(s=="text")return Kind::text;if(s=="bool")return Kind::boolean;if(s=="int")return Kind::integer;if(s=="real")return Kind::real;if(s=="object")return Kind::object;if(s=="array")return Kind::array;if(s=="resource")return Kind::resource;throw Error("TYPE","Unknown Workspace type '"+s+"'");}
bool typed_equivalent(const Value& a,const Value& b){
    if(a.kind!=b.kind||a.field_order!=b.field_order||a.fields.size()!=b.fields.size()||a.elements.size()!=b.elements.size())return false;
    if(a.kind==Kind::text&&a.text!=b.text)return false;
    if((a.kind==Kind::integer||a.kind==Kind::boolean)&&a.integer!=b.integer)return false;
    if(a.kind==Kind::real&&(a.real!=b.real||std::signbit(a.real)!=std::signbit(b.real)))return false;
    for(const auto& [key,value]:a.fields){auto found=b.fields.find(key);if(found==b.fields.end()||!typed_equivalent(value,found->second))return false;}
    for(std::size_t i=0;i<a.elements.size();++i)if(!typed_equivalent(a.elements[i],b.elements[i]))return false;
    return true;
}
const char* kind(Kind k){switch(k){case Kind::null:return "null";case Kind::text:return "text";case Kind::boolean:return "bool";case Kind::integer:return "int";case Kind::real:return "real";case Kind::object:return "object";case Kind::array:return "array";case Kind::resource:return "resource";}throw Error("TYPE","Invalid Workspace type");}
Value decode(Tcl_Interp* i,Tcl_Obj* o,unsigned depth=0,std::size_t* count=nullptr){
    std::size_t local=0;if(!count)count=&local;if(depth>64||++*count>262144)throw Error("LIMIT","Workspace transport graph exceeds bound");
    int size;Tcl_Obj** fields;check(Tcl_ListObjGetElements(i,o,&size,&fields),i);if(size!=2)throw Error("TYPE","A typed Workspace value is exactly {kind value}");
    Value v;v.kind=kind(string(fields[0]));auto data=fields[1];
    switch(v.kind){
    case Kind::null:if(!string(data).empty())throw Error("TYPE","Null value must be empty");break;
    case Kind::text:v.text=string(data);if(v.text.size()>16777216)throw Error("LIMIT","Workspace scalar exceeds 16 MiB");break;
    case Kind::boolean:{v.text=string(data);int n;check(Tcl_GetBooleanFromObj(i,data,&n),i);v.integer=n;break;}
    case Kind::integer:{v.text=string(data);Tcl_WideInt n;check(Tcl_GetWideIntFromObj(i,data,&n),i);v.integer=n;break;}
    case Kind::real:v.text=string(data);check(Tcl_GetDoubleFromObj(i,data,&v.real),i);break;
    case Kind::object:case Kind::resource:{
        Tcl_DictSearch search;Tcl_Obj *key,*value;int done;check(Tcl_DictObjFirst(i,data,&search,&key,&value,&done),i);
        try{for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){auto k=string(key);v.fields.emplace(k,decode(i,value,depth+1,count));v.field_order.push_back(std::move(k));}}catch(...){Tcl_DictObjDone(&search);throw;}Tcl_DictObjDone(&search);break;
    }
    case Kind::array:{int n;Tcl_Obj** values;check(Tcl_ListObjGetElements(i,data,&n,&values),i);if(n>262144)throw Error("LIMIT","Workspace array exceeds node bound");v.elements.reserve(n);for(int j=0;j<n;++j)v.elements.push_back(decode(i,values[j],depth+1,count));break;}
    }return v;
}
Tcl_Obj* encode(Tcl_Interp* i,const Value& v){
    Ref data(Tcl_NewObj());
    switch(v.kind){
    case Kind::null:break;case Kind::text:set_text(data,v.text);break;
    case Kind::boolean:
        if(v.text.empty())Tcl_SetBooleanObj(data,v.integer!=0);
        else{set_text(data,v.text);int n;check(Tcl_GetBooleanFromObj(i,data,&n),i);if(n!=v.integer)throw Error("CORRUPT","Boolean scalar spelling differs from its native value");}break;
    case Kind::integer:
        if(v.text.empty())Tcl_SetWideIntObj(data,v.integer);
        else{set_text(data,v.text);Tcl_WideInt n;check(Tcl_GetWideIntFromObj(i,data,&n),i);if(n!=v.integer)throw Error("CORRUPT","Integer scalar spelling differs from its native value");}break;
    case Kind::real:
        if(v.text.empty())Tcl_SetDoubleObj(data,v.real);
        else{set_text(data,v.text);double n;check(Tcl_GetDoubleFromObj(i,data,&n),i);if(n!=v.real||std::signbit(n)!=std::signbit(v.real))throw Error("CORRUPT","Real scalar spelling differs from its native value");}break;
    case Kind::object:case Kind::resource:
        if(v.field_order.empty()){for(const auto& [key,value]:v.fields){Ref k(text(key));check(Tcl_DictObjPut(i,data,k,encode(i,value)),i);}}
        else for(const auto& key:v.field_order){Ref k(text(key));check(Tcl_DictObjPut(i,data,k,encode(i,v.fields.at(key))),i);}
        break;
    case Kind::array:for(const auto& x:v.elements)check(Tcl_ListObjAppendElement(i,data,encode(i,x)),i);break;
    }
    // Tkinter converts numeric internal representations before a client can
    // inspect their original Tcl spelling. Validation above may shimmer data;
    // return a pure string annotation inside this explicitly typed node.
    if(v.kind==Kind::integer||v.kind==Kind::real||v.kind==Kind::boolean){auto annotation=string(data);set_text(data,annotation);}
    Tcl_Obj* fields[]={Tcl_NewStringObj(kind(v.kind),-1),data};return Tcl_NewListObj(2,fields);
}
Tcl_Obj* identity(Tcl_Interp* i,const Identity& id){Tcl_Obj* d=Tcl_NewDictObj();put(i,d,"id",id.id);put(i,d,"workspace_id",id.id);put(i,d,"generation",id.generation);number(i,d,"revision",id.revision);return d;}
Tcl_Obj* receipt(Tcl_Interp* i,const Receipt& r){
    Tcl_Obj* d=identity(i,r.identity);put(i,d,"api_id","NATIVE_WORKSPACE_API_v1");number(i,d,"api_version",1);number(i,d,"accepted",r.accepted);number(i,d,"accepted_revision",r.identity.revision);number(i,d,"durable_revision",r.durable_revision);number(i,d,"pending",r.pending);number(i,d,"dirty",r.pending);number(i,d,"failed",r.failed);number(i,d,"queued_bytes",r.queued_bytes);put(i,d,"error",r.error);put(i,d,"status",r.failed?"failed":(r.pending?"pending":"durable"));return d;
}
Tcl_Obj* metadata(Tcl_Interp* i,const Summary& w){Tcl_Obj* d=identity(i,w.identity);put(i,d,"module_id",w.owner);put(i,d,"provider_id",w.provider);put(i,d,"format",w.schema);put(i,d,"format_version",w.schema_version);put(i,d,"name",w.name);put(i,d,"created_at",w.created_at);put(i,d,"updated_at",w.updated_at);put(i,d,"sha256",w.content_sha256);put(i,d,"content_encoding","GXWorkspaceNative.v1");put(i,d,"has_notes",Tcl_NewBooleanObj(w.has_notes));put(i,d,"has_preview",Tcl_NewBooleanObj(w.has_preview));return d;}
std::uint64_t integer(Tcl_Interp* i,Tcl_Obj* value){Tcl_WideInt n;check(Tcl_GetWideIntFromObj(i,value,&n),i);if(n<0)throw Error("TYPE","Expected a nonnegative revision/count");return n;}
struct Context {std::map<std::string,std::unique_ptr<Store>> stores;unsigned serial=0;};
void cleanup(ClientData data,Tcl_Interp*){delete static_cast<Context*>(data);}
void args(int n,int lo,int hi,const char* help){if(n<lo||n>hi)throw Error("ARGUMENTS",std::string("Usage: workspaceNative ")+help);}
int command(ClientData data,Tcl_Interp* i,int n,Tcl_Obj* const a[]){
    try{
        auto& c=*static_cast<Context*>(data);args(n,2,20,"operation ...");auto op=string(a[1]);
        if(op=="capsule_inspect"){args(n,3,3,"capsule_inspect path");Tcl_SetObjResult(i,encode(i,Store::capsule_inspect(string(a[2]))));return TCL_OK;}
        if(op=="typed_equal"){args(n,4,4,"typed_equal first second");Tcl_SetObjResult(i,Tcl_NewBooleanObj(decode(i,a[2])==decode(i,a[3])));return TCL_OK;}
        if(op=="typed_equivalent"){args(n,4,4,"typed_equivalent first second");Tcl_SetObjResult(i,Tcl_NewBooleanObj(typed_equivalent(decode(i,a[2]),decode(i,a[3]))));return TCL_OK;}
        if(op=="json_decode"){args(n,3,3,"json_decode explicit_json_transport");Tcl_SetObjResult(i,encode(i,workspace_json_decode(string(a[2]))));return TCL_OK;}
        if(op=="json_encode_lexical"){args(n,3,3,"json_encode_lexical typed_value");Tcl_SetObjResult(i,text(workspace_json_encode(decode(i,a[2]),true)));return TCL_OK;}
        if(op=="json_encode"){args(n,3,3,"json_encode typed_value");Tcl_SetObjResult(i,text(workspace_json_encode(decode(i,a[2]))));return TCL_OK;}
        if(op=="open"){args(n,3,3,"open database_path");if(c.stores.size()>=8)throw Error("LIMIT","Too many active Workspace Session stores");auto s=std::make_unique<Store>(string(a[2]));auto h="workspace-store#"+std::to_string(++c.serial);c.stores.emplace(h,std::move(s));Tcl_SetObjResult(i,text(h));return TCL_OK;}
        args(n,3,20,"operation store ...");auto found=c.stores.find(string(a[2]));if(found==c.stores.end())throw Error("CLOSED","Unknown or closed Workspace Session handle");auto& store=*found->second;
        if(op=="close"){args(n,3,3,"close store");store.close();c.stores.erase(found);Tcl_SetObjResult(i,text("closed"));}
        else if(op=="flush_all"){args(n,3,3,"flush_all store");store.flush_all();Tcl_SetObjResult(i,text("durable"));}
        else if(op=="register"){
            args(n,8,8,"register store provider owner schema version required_fields");Schema s{string(a[3]),string(a[4]),string(a[5]),string(a[6]),{}};
            Tcl_DictSearch search;Tcl_Obj *key,*value;int done;check(Tcl_DictObjFirst(i,a[7],&search,&key,&value,&done),i);try{for(;!done;Tcl_DictObjNext(&search,&key,&value,&done))s.required.emplace(string(key),kind(string(value)));}catch(...){Tcl_DictObjDone(&search);throw;}Tcl_DictObjDone(&search);store.register_schema(std::move(s));Tcl_SetObjResult(i,text("registered"));
        }
        else if(op=="create"){args(n,8,8,"create store provider name typed_state typed_properties typed_provenance");Tcl_SetObjResult(i,receipt(i,store.create(string(a[3]),string(a[4]),decode(i,a[5]),decode(i,a[6]),decode(i,a[7]))));}
        else if(op=="duplicate"){args(n,7,7,"duplicate store id generation revision name");Tcl_SetObjResult(i,receipt(i,store.duplicate({string(a[3]),string(a[4]),integer(i,a[5])},string(a[6]))));}
        else if(op=="transition_prepare"){args(n,7,7,"transition_prepare store id generation revision typed_intent");Tcl_SetObjResult(i,text(store.transition_prepare({string(a[3]),string(a[4]),integer(i,a[5])},decode(i,a[6]))));}
        else if(op=="transition_list"){args(n,3,3,"transition_list store");Tcl_SetObjResult(i,encode(i,store.transition_list()));}
        else if(op=="transition_commit"){args(n,9,9,"transition_commit store token id generation revision typed_state typed_properties");Tcl_SetObjResult(i,receipt(i,store.transition_commit(string(a[3]),{string(a[4]),string(a[5]),integer(i,a[6])},decode(i,a[7]),decode(i,a[8]))));}
        else if(op=="transition_finish"){args(n,4,4,"transition_finish store token");store.transition_finish(string(a[3]));Tcl_SetObjResult(i,text("durable"));}
        else if(op=="capsule_export"){args(n,7,7,"capsule_export store id generation revision newpath");store.capsule_export({string(a[3]),string(a[4]),integer(i,a[5])},string(a[6]));Tcl_SetObjResult(i,text("durable"));}
        else if(op=="capsule_import"){args(n,5,5,"capsule_import store path name");Tcl_SetObjResult(i,receipt(i,store.capsule_import(string(a[3]),string(a[4]))));}
        else if(op=="lineage"){args(n,4,4,"lineage store id");Tcl_SetObjResult(i,encode(i,store.lineage(string(a[3]))));}
        else if(op=="checkpoint"){args(n,3,3,"checkpoint store");store.checkpoint();Tcl_SetObjResult(i,text("durable"));}
        else if(op=="resource_references"){args(n,4,4,"resource_references store id");store.metadata(string(a[3]));Tcl_SetObjResult(i,encode(i,store.retained_references({},string(a[3]))));}
        else if(op=="get"){args(n,4,4,"get store id");auto w=store.get(string(a[3]));Tcl_Obj* d=metadata(i,store.metadata(w.identity.id));put(i,d,"state",encode(i,w.state));put(i,d,"properties",encode(i,w.properties));put(i,d,"provenance",encode(i,w.provenance));put(i,d,"notes",w.notes);Tcl_SetObjResult(i,d);}
        else if(op=="metadata"){args(n,4,4,"metadata store id");Tcl_SetObjResult(i,metadata(i,store.metadata(string(a[3]))));}
        else if(op=="properties"){args(n,4,4,"properties store id");Tcl_SetObjResult(i,encode(i,store.properties(string(a[3]))));}
        else if(op=="save_properties"){args(n,7,7,"save_properties store id generation revision typed_properties");Tcl_SetObjResult(i,receipt(i,store.save_properties({string(a[3]),string(a[4]),integer(i,a[5])},decode(i,a[6]))));}
        else if(op=="notes_get"){args(n,4,4,"notes_get store id");Tcl_SetObjResult(i,text(store.note_text(string(a[3]))));}
        else if(op=="resource_owner_generation"){args(n,4,4,"resource_owner_generation store id");Tcl_SetObjResult(i,text(store.resource_owner_generation(string(a[3]))));}
        else if(op=="retired_owner_generation"){args(n,4,4,"retired_owner_generation store id");Tcl_SetObjResult(i,text(store.retired_owner_generation(string(a[3]))));}
        else if(op=="retained_references"){args(n,3,4,"retained_references store ?exclude_workspace?");Tcl_SetObjResult(i,encode(i,store.retained_references(n==4?string(a[3]):std::string{})));}
        else if(op=="register_resource_owner"){args(n,5,5,"register_resource_owner store id generation");store.register_resource_owner(string(a[3]),string(a[4]));Tcl_SetObjResult(i,text("registered"));}
        else if(op=="history_save"){
            args(n,10,10,"history_save store id generation revision name typed_record typed_auxiliary typed_context");
            auto result=store.history_save({string(a[3]),string(a[4]),integer(i,a[5])},string(a[6]),decode(i,a[7]),decode(i,a[8]),decode(i,a[9]));auto d=receipt(i,result.first);put(i,d,"archive_id",result.second);Tcl_SetObjResult(i,d);
        }
        else if(op=="history_list"){args(n,4,4,"history_list store id");Tcl_SetObjResult(i,encode(i,store.history_list(string(a[3]))));}
        else if(op=="history_get"){args(n,5,5,"history_get store id archive_id");Tcl_SetObjResult(i,encode(i,store.history_get(string(a[3]),string(a[4]))));}
        else if(op=="history_rename"||op=="history_delete"){
            args(n,8,8,"history_rename|history_delete store id generation revision archive_id name|confirmed");Identity expected{string(a[3]),string(a[4]),integer(i,a[5])};Receipt r;
            if(op=="history_rename")r=store.history_rename(expected,string(a[6]),string(a[7]));
            else{int confirmed;check(Tcl_GetBooleanFromObj(i,a[7],&confirmed),i);r=store.history_delete(expected,string(a[6]),confirmed!=0);}Tcl_SetObjResult(i,receipt(i,r));
        }
        else if(op=="query"){
            args(n,3,8,"query store ?provider owner name_prefix offset limit?");Query q;if(n>=4)q.provider=string(a[3]);if(n>=5)q.owner=string(a[4]);if(n>=6)q.name_prefix=string(a[5]);if(n>=7)q.offset=integer(i,a[6]);if(n>=8)q.limit=integer(i,a[7]);Tcl_Obj* rows=Tcl_NewListObj(0,nullptr);for(const auto& r:store.query(q))check(Tcl_ListObjAppendElement(i,rows,metadata(i,r)),i);Tcl_SetObjResult(i,rows);
        }
        else if(op=="status"||op=="flush"){args(n,4,4,"status|flush store id");Tcl_SetObjResult(i,receipt(i,op=="status"?store.status(string(a[3])):store.flush(string(a[3]))));}
        else if(op=="save"||op=="rename"||op=="notes"||op=="delete"){
            args(n,op=="save"?8:7,op=="save"?8:7,"save|rename|notes|delete store id generation revision value ?properties?");Identity expected{string(a[3]),string(a[4]),integer(i,a[5])};Receipt r;
            if(op=="save")r=store.save(expected,decode(i,a[6]),decode(i,a[7]));else if(op=="rename")r=store.rename(expected,string(a[6]));else if(op=="notes")r=store.notes(expected,string(a[6]));else{int confirmed;check(Tcl_GetBooleanFromObj(i,a[6],&confirmed),i);r=store.erase(expected,confirmed!=0);}Tcl_SetObjResult(i,receipt(i,r));
        }
        else throw Error("OPERATION","Unsupported native Workspace operation");
        return TCL_OK;
    }catch(const Error& e){Tcl_SetObjResult(i,Tcl_NewStringObj(e.what(),-1));Tcl_SetErrorCode(i,"GX","WORKSPACE",e.code.c_str(),nullptr);return TCL_ERROR;}
    catch(const std::exception& e){Tcl_SetObjResult(i,Tcl_NewStringObj(e.what(),-1));Tcl_SetErrorCode(i,"GX","WORKSPACE","INTERNAL",nullptr);return TCL_ERROR;}
}
}
extern "C" int Gxtxt_workspace_Init(Tcl_Interp* i){
    if(!Tcl_InitStubs(i,"8.6",0))return TCL_ERROR;
    if(!Tcl_FindNamespace(i,"::GX",nullptr,0))Tcl_CreateNamespace(i,"::GX",nullptr,nullptr);
    auto* c=new Context;Tcl_SetAssocData(i,"GX.Workspace.v1",cleanup,c);Tcl_CreateObjCommand(i,"::GX::workspaceNative",command,c,nullptr);return Tcl_PkgProvide(i,"gxtxt_workspace","1.0");
}
