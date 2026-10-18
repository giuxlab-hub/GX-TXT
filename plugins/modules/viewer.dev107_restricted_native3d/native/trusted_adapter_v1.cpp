// SPDX-License-Identifier: GPL-3.0-or-later
// Trusted native facade; author source is a separate independently validated unit.
#include "gxtxt_viewer_sdk_v1.hpp"
namespace gx {
void Host::text(unsigned component,const char* value) const {dispatch_(context_,1,component,0,0,value);}
void Host::number(unsigned component,double value) const {dispatch_(context_,2,component,value,0,nullptr);}
void Host::flag(unsigned component,bool value) const {dispatch_(context_,3,component,value?1:0,0,nullptr);}
double Host::numeric_add(double left,double right) const {return dispatch_(context_,4,0,left,right,nullptr);}
double Host::numeric_sqrt(double value) const {return dispatch_(context_,6,0,value,0,nullptr);}
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
