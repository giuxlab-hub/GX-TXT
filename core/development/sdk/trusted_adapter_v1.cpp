// SPDX-License-Identifier: GPL-3.0-or-later
// Trusted native facade; author source is a separate independently validated unit.
#include "gxtxt_viewer_sdk_v1.hpp"
#include <string>
#include <vector>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <algorithm>
namespace gx {
namespace {thread_local std::vector<std::string> input_values;thread_local std::string event_data;}
const char* Host::input(unsigned component) const {return component>0&&component<=input_values.size()?input_values[component-1].c_str():"";}
const char* Host::data() const {return event_data.c_str();}
void Host::cad_command(unsigned component,const char* action) const {dispatch_(context_,36,component,0,0,action);}
void Host::diagnostics_command(unsigned form,const char* operation,const char* request) const {
    std::string value=operation?operation:"";value+='\n';value+=request?request:"{}";
    dispatch_(context_,37,form,0,0,value.c_str());
}
void Host::text_runs(unsigned component,const char* value) const {dispatch_(context_,38,component,0,0,value);}
void Host::table(unsigned component,const char* value) const {dispatch_(context_,39,component,0,0,value);}
void Host::text(unsigned component,const char* value) const {dispatch_(context_,1,component,0,0,value);}
void Host::number(unsigned component,double value) const {dispatch_(context_,2,component,value,0,nullptr);}
void Host::flag(unsigned component,bool value) const {dispatch_(context_,3,component,value?1:0,0,nullptr);}
double Host::numeric_add(double left,double right) const {return dispatch_(context_,4,0,left,right,nullptr);}
double Host::numeric_sqrt(double value) const {return dispatch_(context_,6,0,value,0,nullptr);}
double Host::numeric_exp(double value) const {return dispatch_(context_,7,0,value,0,nullptr);}
void Host::diagram_open(unsigned component) const {dispatch_(context_,8,component,0,0,nullptr);}
void Host::diagram_tool(unsigned component,const char* tool) const {dispatch_(context_,9,component,0,0,tool);}
void Host::diagram_command(unsigned component,const char* command) const {dispatch_(context_,10,component,0,0,command);}
void Host::scientific_discover(unsigned form) const {dispatch_(context_,11,form,0,0,nullptr);}
void Host::scientific_prepare(unsigned diagram,unsigned form) const {dispatch_(context_,12,form,diagram,0,nullptr);}
void Host::scientific_submit(unsigned form) const {dispatch_(context_,13,form,0,0,nullptr);}
void Host::scientific_status(unsigned form) const {dispatch_(context_,14,form,0,0,nullptr);}
void Host::scientific_cancel(unsigned form) const {dispatch_(context_,15,form,0,0,nullptr);}
void Host::scientific_reconnect(unsigned form) const {dispatch_(context_,16,form,0,0,nullptr);}
void Host::scientific_log(unsigned form) const {dispatch_(context_,17,form,0,0,nullptr);}
void Host::scientific_import(unsigned form,unsigned dataset_selector) const {dispatch_(context_,18,form,dataset_selector,0,nullptr);}
void Host::plot_discover(unsigned form) const {dispatch_(context_,19,form,0,0,nullptr);}
void Host::plot_bind(unsigned plot,unsigned form) const {dispatch_(context_,20,form,plot,0,nullptr);}
void Host::document_bind(unsigned document,unsigned dataset_selector) const {dispatch_(context_,26,document,dataset_selector,0,nullptr);}
void Host::document_command(unsigned document,const char* operation) const {dispatch_(context_,41,document,0,0,operation);}
void Host::raster_bind(unsigned viewport,unsigned dataset_selector) const {dispatch_(context_,33,viewport,dataset_selector,0,nullptr);}
void Host::raster_tool(unsigned viewport,const char* tool) const {dispatch_(context_,34,viewport,0,0,tool);}
void Host::raster_command(unsigned viewport,const char* command) const {dispatch_(context_,35,viewport,0,0,command);}
void Host::tex_command(unsigned form,const char* operation) const {dispatch_(context_,30,form,0,0,operation);}
void Host::em_command(unsigned form,const char* operation) const {dispatch_(context_,31,form,0,0,operation);}
void Host::workbench_command(unsigned form,const char* operation) const {dispatch_(context_,32,form,0,0,operation);}
void Host::catalog_refresh(unsigned form) const {dispatch_(context_,27,form,0,0,nullptr);}
void Host::catalog_inspect(unsigned form) const {dispatch_(context_,28,form,0,0,nullptr);}
void Host::catalog_action(unsigned form,const char* action) const {dispatch_(context_,29,form,0,0,action);}
void Host::numeric_discover(unsigned form) const {dispatch_(context_,21,form,0,0,nullptr);}
void Host::numeric_evaluate(unsigned form) const {dispatch_(context_,22,form,0,0,nullptr);}
void Host::numeric_statistics(unsigned form) const {dispatch_(context_,23,form,0,0,nullptr);}
void Host::numeric_compare(unsigned form) const {dispatch_(context_,24,form,0,0,nullptr);}
void Host::numeric_publish(unsigned form,unsigned dataset_selector) const {dispatch_(context_,25,form,dataset_selector,0,nullptr);}
void Host::demo(unsigned component,unsigned fixture) const {dispatch_(context_,5,component,fixture,0,nullptr);}
struct HostAccess {
    static void run(void* context,double (*dispatch)(void*,unsigned,unsigned,double,double,const char*),State& state,const Event& event) {
        Host host;host.context_=context;host.dispatch_=dispatch;
        on_event(host,state,event);
    }
};
}
extern "C" __attribute__((visibility("default"))) int gxtxt_viewer_event_v1(
    void* context,double (*dispatch)(void*,unsigned,unsigned,double,double,const char*),gx::State* state,const gx::Event* event) {
    if(!state||!event||!dispatch)return 1;
    gx::HostAccess::run(context,dispatch,*state,*event);
    return 0;
}
// Optional additive input ABI. The original Event/State/Host and entry remain
// byte/layout compatible with previously distributed SDK-v1 Viewers.
extern "C" __attribute__((visibility("default"))) int gxtxt_viewer_context_v1(
    unsigned count,const char* const* values,const char* data,unsigned bytes) {
    if(count>512||bytes>1048576||(count&&!values)||(bytes&&!data))return 1;
    std::vector<std::string> next;next.reserve(count);unsigned total=0;
    for(unsigned i=0;i<count;++i){std::string value=values[i]?values[i]:"";if(value.size()>4096)return 1;total+=value.size();if(total>1048576)return 1;next.push_back(std::move(value));}
    gx::input_values=std::move(next);gx::event_data.assign(data?data:"",bytes);return 0;
}

// Additive Workspace context ABI; no raw host pointers cross a process boundary.
// The trusted Python worker supplies already typed flat nodes copied here.
namespace gx {
namespace {thread_local WorkspaceValue workspace_context;
std::string ws_quote(const std::string& text){std::ostringstream out;out<<'"';for(unsigned char c:text){if(c=='"'||c=='\\')out<<'\\'<<char(c);else if(c<32)out<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<unsigned(c)<<std::dec;else out<<char(c);}out<<'"';return out.str();}
std::string ws_json(const WorkspaceValue& v,unsigned depth=0){
    if(depth>64)throw std::runtime_error("Workspace value nesting exceeds 64");
    std::string kind,value;
    switch(v.kind){
    case WorkspaceValue::Kind::null:kind="null";value="null";break;
    case WorkspaceValue::Kind::text:kind="text";value=ws_quote(v.text);break;
    case WorkspaceValue::Kind::boolean:kind="bool";value=v.integer?"true":"false";break;
    case WorkspaceValue::Kind::integer:kind="int";value=std::to_string(v.integer);break;
    case WorkspaceValue::Kind::real:{if(!std::isfinite(v.real))throw std::runtime_error("Workspace real must be finite");kind="real";std::ostringstream out;out<<std::setprecision(std::numeric_limits<double>::max_digits10)<<v.real;value=out.str();break;}
    case WorkspaceValue::Kind::object:case WorkspaceValue::Kind::resource:kind=v.kind==WorkspaceValue::Kind::object?"object":"resource";value="{";for(const auto& field:v.fields){if(value.size()>1)value+=',';value+=ws_quote(field.first)+":"+ws_json(field.second,depth+1);}value+='}';break;
    case WorkspaceValue::Kind::array:kind="array";value="[";for(const auto& item:v.elements){if(value.size()>1)value+=',';value+=ws_json(item,depth+1);}value+=']';break;
    }return "{\"kind\":"+ws_quote(kind)+",\"value\":"+value+"}";
}
const WorkspaceValue& ws_field(const WorkspaceValue& object,const std::string& key){static const WorkspaceValue empty;auto it=object.fields.find(key);return it==object.fields.end()?empty:it->second;}
}
WorkspaceValue workspace_text(std::string text){WorkspaceValue v;v.kind=WorkspaceValue::Kind::text;v.text=std::move(text);return v;}
WorkspaceValue workspace_integer(std::int64_t n){WorkspaceValue v;v.kind=WorkspaceValue::Kind::integer;v.integer=n;return v;}
WorkspaceValue workspace_number(double n){WorkspaceValue v;v.kind=WorkspaceValue::Kind::real;v.real=n;return v;}
WorkspaceValue workspace_flag(bool n){WorkspaceValue v;v.kind=WorkspaceValue::Kind::boolean;v.integer=n;return v;}
WorkspaceValue workspace_object(std::map<std::string,WorkspaceValue> fields){WorkspaceValue v;v.kind=WorkspaceValue::Kind::object;v.fields=std::move(fields);return v;}
WorkspaceValue workspace_array(std::vector<WorkspaceValue> elements){WorkspaceValue v;v.kind=WorkspaceValue::Kind::array;v.elements=std::move(elements);return v;}
WorkspaceValue workspace_resource(std::map<std::string,WorkspaceValue> fields){WorkspaceValue v;v.kind=WorkspaceValue::Kind::resource;v.fields=std::move(fields);return v;}
Workspace Host::workspace()const{return Workspace(this);}
void Host::dataset_group_review(const WorkspaceValue& ids)const{auto request=ws_json(ids);dispatch_(context_,42,0,0,0,request.c_str());}
void Host::dataset_group_create(const WorkspaceValue& definition,const WorkspaceValue& review)const{auto request=ws_json(workspace_object({{"definition",definition},{"review",review}}));dispatch_(context_,43,0,0,0,request.c_str());}
void Host::dataset_publish_batch(const WorkspaceValue& value)const{auto request=ws_json(value);dispatch_(context_,44,0,0,0,request.c_str());}
WorkspaceValue Host::dataset_producer_result()const{return ws_field(workspace_context,"dataset_producer");}
namespace {
void client_value_check(const WorkspaceValue& value,unsigned depth,unsigned& nodes){
    if(depth>64||++nodes>8192)throw std::runtime_error("Typed client request exceeds its nesting/node bound");
    if(static_cast<unsigned>(value.kind)>static_cast<unsigned>(WorkspaceValue::Kind::resource))throw std::runtime_error("Invalid typed client value kind");
    if(value.kind==WorkspaceValue::Kind::resource)throw std::runtime_error("Typed client requests do not grant Resource authority");
    if(value.kind==WorkspaceValue::Kind::text&&value.text.find('\0')!=std::string::npos)throw std::runtime_error("Typed client text must not contain NUL");
    if(value.kind==WorkspaceValue::Kind::object){
        for(const auto& field:value.fields){
            if(field.first.find('\0')!=std::string::npos)throw std::runtime_error("Typed client field name must not contain NUL");
            client_value_check(field.second,depth+1,nodes);
        }
    }else if(value.kind==WorkspaceValue::Kind::array){for(const auto& item:value.elements)client_value_check(item,depth+1,nodes);}
}
std::string client_request(unsigned form,const char* operation,const WorkspaceValue& request,
                           const char* const* operations,unsigned count){
    if(!form||form>512)throw std::runtime_error("Typed client requires a declared one-based form");
    unsigned length=0;if(operation){while(length<65&&operation[length])++length;}
    if(!length||length>64)throw std::runtime_error("Typed client requires a finite operation name");
    const std::string name(operation,length);
    bool admitted=false;for(unsigned i=0;i<count;++i){if(name==operations[i]){admitted=true;break;}}
    if(!admitted)throw std::runtime_error("Unknown finite typed client operation");
    if(request.kind!=WorkspaceValue::Kind::object)throw std::runtime_error("Typed client request must be an object");
    unsigned nodes=2;client_value_check(request,1,nodes);
    auto encoded=ws_json(workspace_object({{"operation",workspace_text(name)},{"request",request}}));
    if(encoded.size()>49152)throw std::runtime_error("Typed client request exceeds 48 KiB; identities are never truncated");
    return encoded;
}
const WorkspaceValue* client_result(const char* name)noexcept{
    if(workspace_context.kind!=WorkspaceValue::Kind::object)return nullptr;
    // No allocation in the noexcept getter. Values live only until the trusted
    // owning thread replaces this event's immutable typed context.
    for(const auto& field:workspace_context.fields){if(field.first==name)return field.second.kind==WorkspaceValue::Kind::object?&field.second:nullptr;}
    return nullptr;
}
}
void Host::script_library_command(unsigned form,const char* operation,const WorkspaceValue& request)const{
    static const char* const operations[]={"list","select","new_script","new_project","source_select","save","copy_record","assign_session","open_workspace","run_review","import_script","import_project","export","delete","jobs","refresh","close","undo","redo","find","replace","cut","copy_text","paste","select_all"};
    auto encoded=client_request(form,operation,request,operations,sizeof(operations)/sizeof(*operations));
    dispatch_(context_,45,form,0,0,encoded.c_str());
}
const WorkspaceValue* Host::script_library_result()const noexcept{return client_result("script_library_result");}
void Host::scientific_preview_command(unsigned form,const char* operation,const WorkspaceValue& request)const{
    static const char* const operations[]={"discover","page","metadata","source"};
    auto encoded=client_request(form,operation,request,operations,sizeof(operations)/sizeof(*operations));
    dispatch_(context_,46,form,0,0,encoded.c_str());
}
const WorkspaceValue* Host::scientific_preview_result()const noexcept{return client_result("scientific_preview_result");}
void Host::comparison_command(unsigned form,const char* operation)const{
    static const char* const operations[]={"discover","add_dataset","add_library","add_browser","add_opened","remove","up","down","prepare","clear","inspect","plot_fit","plot_zoom_in","plot_zoom_out","plot_cursor","plot_clear_cursor","plot_reverse_x","plot_properties","plot_legend","plot_style","plot_copy","plot_export","plot_save_variant","plot_load_variant"};
    auto encoded=client_request(form,operation,workspace_object(),operations,sizeof(operations)/sizeof(*operations));
    dispatch_(context_,48,form,0,0,encoded.c_str());
}
const WorkspaceValue* Host::comparison_result()const noexcept{return client_result("comparison_result");}
void Host::analysis_command(unsigned form,const char* operation)const{
    static const char* const operations[]={"discover","submit","status","cancel","candidates","add_candidate"};
    auto encoded=client_request(form,operation,workspace_object(),operations,sizeof(operations)/sizeof(*operations));
    dispatch_(context_,49,form,0,0,encoded.c_str());
}
const WorkspaceValue* Host::analysis_result()const noexcept{return client_result("analysis_result");}

void Host::scientific_frame_bind(unsigned viewport,unsigned form)const{
    if(!viewport||viewport>512||!form||form>512)throw std::runtime_error("Frame binding requires declared one-based viewport and form components");
    dispatch_(context_,47,form,viewport,0,nullptr);
}
WorkspaceValue Workspace::state()const{return ws_field(workspace_context,"state");}
WorkspaceValue Workspace::property(const std::string& name)const{return ws_field(ws_field(workspace_context,"properties"),name);}
WorkspaceStatus Workspace::status()const{WorkspaceStatus s;s.id=ws_field(workspace_context,"id").text;s.generation=ws_field(workspace_context,"generation").text;s.error=ws_field(workspace_context,"error").text;s.revision=ws_field(workspace_context,"revision").integer;s.durable_revision=ws_field(workspace_context,"durable_revision").integer;s.dirty=ws_field(workspace_context,"dirty").integer!=0;s.pending=ws_field(workspace_context,"pending").integer!=0;s.failed=ws_field(workspace_context,"failed").integer!=0;return s;}
std::vector<WorkspaceEntry> Workspace::query(const std::string& prefix)const{std::vector<WorkspaceEntry> result;for(const auto& value:ws_field(workspace_context,"entries").elements){auto name=ws_field(value,"name").text;if(name.compare(0,prefix.size(),prefix)==0)result.push_back({ws_field(value,"id").text,name,ws_field(value,"provider").text,static_cast<std::uint64_t>(ws_field(value,"revision").integer)});}return result;}
void Workspace::send(const char* operation,const WorkspaceValue& value)const{auto request=std::string(operation)+"\n"+ws_json(value);host_->dispatch_(host_->context_,40,0,0,0,request.c_str());}
void Workspace::set_state(const WorkspaceValue& value)const{send("set_state",value);}
void Workspace::set_property(const std::string& name,const WorkspaceValue& value)const{send("set_property",workspace_object({{"name",workspace_text(name)},{"value",value}}));}
void Workspace::save(bool asynchronous)const{send("save",workspace_flag(asynchronous));}
void Workspace::save_as(const std::string& name)const{send("save_as",workspace_text(name));}
void Workspace::rename(const std::string& name)const{send("rename",workspace_text(name));}
void Workspace::open(const std::string& id)const{send("open",workspace_text(id));}
void Workspace::close()const{send("close",WorkspaceValue{});}
}
extern "C" __attribute__((visibility("default"))) int gxtxt_viewer_workspace_context_v1(
    unsigned count,const unsigned* parents,const unsigned* kinds,const char* const* keys,const char* const* values,const unsigned* sizes){
    if(!count||count>8192||!parents||!kinds||!keys||!values||!sizes)return 1;
    try{
        gx::WorkspaceValue root;std::vector<gx::WorkspaceValue*> nodes(count,nullptr);std::vector<unsigned> children(count,0);unsigned total=0;
        for(unsigned i=1;i<count;++i){if(parents[i]>=i)return 1;++children[parents[i]];}
        for(unsigned i=0;i<count;++i){if(kinds[i]>7||sizes[i]>1048576||total>1048576-sizes[i]||(sizes[i]&&!values[i]))return 1;total+=sizes[i];gx::WorkspaceValue value;value.kind=static_cast<gx::WorkspaceValue::Kind>(kinds[i]);std::string scalar(values[i]?values[i]:"",sizes[i]);
            switch(value.kind){case gx::WorkspaceValue::Kind::text:value.text=scalar;break;case gx::WorkspaceValue::Kind::integer:value.integer=std::stoll(scalar);break;case gx::WorkspaceValue::Kind::boolean:value.integer=scalar=="1";break;case gx::WorkspaceValue::Kind::real:value.real=std::stod(scalar);if(!std::isfinite(value.real))return 1;break;case gx::WorkspaceValue::Kind::array:value.elements.reserve(children[i]);break;default:break;}
            if(i==0){root=std::move(value);nodes[i]=&root;}else{auto* parent=nodes[parents[i]];if(parent->kind==gx::WorkspaceValue::Kind::array){parent->elements.push_back(std::move(value));nodes[i]=&parent->elements.back();}else if(parent->kind==gx::WorkspaceValue::Kind::object||parent->kind==gx::WorkspaceValue::Kind::resource){if(!keys[i])return 1;auto result=parent->fields.emplace(keys[i],std::move(value));if(!result.second)return 1;nodes[i]=&result.first->second;}else return 1;}
        }
        gx::workspace_context=std::move(root);return 0;
    }catch(...){return 1;}
}
extern "C" __attribute__((visibility("default"))) unsigned gxtxt_viewer_workspace_hooks_v1(){
    return (gx::on_workspace_capture?1u:0u)|(gx::on_workspace_validate?2u:0u)|(gx::on_workspace_restore?4u:0u)|(gx::on_workspace_committed?8u:0u);
}
extern "C" __attribute__((visibility("default"))) int gxtxt_viewer_workspace_hook_v1(unsigned operation,char* output,unsigned capacity,unsigned* used){
    if(!output||!used||capacity<2)return 1;
    try{
        std::string result;
        if(operation==0){
            auto value=gx::on_workspace_capture?gx::on_workspace_capture():gx::ws_field(gx::workspace_context,"state");
            if(value.kind!=gx::WorkspaceValue::Kind::object)throw std::runtime_error("Workspace capture must return a typed object");
            if(gx::on_workspace_validate)gx::on_workspace_validate(value);
            result="{\"ok\":true,\"value\":"+gx::ws_json(value)+"}";
        }else if(operation==1){
            const auto& value=gx::ws_field(gx::workspace_context,"state");
            if(gx::on_workspace_validate)gx::on_workspace_validate(value);
            auto previous=gx::on_workspace_capture?gx::on_workspace_capture():value;
            try{if(gx::on_workspace_restore)gx::on_workspace_restore(value);}
            catch(...){
                if(gx::on_workspace_capture&&gx::on_workspace_restore){
                    try{gx::on_workspace_restore(previous);}catch(...){throw std::runtime_error("Workspace restore and prior-model compensation failed; reopen the saved Workspace");}
                }
                throw;
            }
            result="{\"ok\":true}";
        }else if(operation==2){
            gx::WorkspaceStatus status;status.id=gx::ws_field(gx::workspace_context,"id").text;status.generation=gx::ws_field(gx::workspace_context,"generation").text;status.revision=gx::ws_field(gx::workspace_context,"revision").integer;status.durable_revision=gx::ws_field(gx::workspace_context,"durable_revision").integer;status.pending=gx::ws_field(gx::workspace_context,"pending").integer!=0;
            if(status.pending||status.durable_revision<status.revision)throw std::runtime_error("Committed hook requires a durable receipt");
            if(gx::on_workspace_committed)gx::on_workspace_committed(status);
            result="{\"ok\":true}";
        }else throw std::runtime_error("Unknown Workspace hook operation");
        if(result.size()>capacity)throw std::runtime_error("Workspace hook output exceeds its bound");
        std::copy(result.begin(),result.end(),output);*used=static_cast<unsigned>(result.size());return 0;
    }catch(const std::exception& error){
        auto result="{\"ok\":false,\"error\":"+gx::ws_quote(error.what())+"}";
        if(result.size()>capacity)return 1;std::copy(result.begin(),result.end(),output);*used=static_cast<unsigned>(result.size());return 0;
    }catch(...){return 1;}
}
