// SPDX-License-Identifier: GPL-3.0-or-later
// Trusted native facade; author source is a separate independently validated unit.
#include "gxtxt_viewer_sdk_v1.hpp"
namespace gx {
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
