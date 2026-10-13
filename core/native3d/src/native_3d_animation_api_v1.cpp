// SPDX-License-Identifier: GPL-3.0-or-later
#include "native_3d_animation_api_v1.h"
#include "animation_lifecycle.hpp"
#include "field_cancellation.hpp"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <vector>

struct gx3de_animation;
struct AnimationFrame {
        double time=0;
        gx3de_object* source=nullptr;
        gx3de_animation_frame_loader loader=nullptr;
        void* user=nullptr;
        bool owns=false;
        uint64_t last_use=0;
        uint64_t estimated_bytes=0;
};
struct gx3de_animation_layer {
    gx3de_animation* timeline=nullptr;
    std::string id;
    std::map<uint64_t,AnimationFrame> frames;
    enum class Derived {none,lines,slice,isosurface,pathlines} derived=Derived::none;
    gx3de_animation_layer* source_layer=nullptr;
    gx3de_field_line_spec line_spec{};
    gx3de_field_slice_spec slice_spec{};
    gx3de_field_pathline_spec pathline_spec{};
    std::vector<gx3de_vec3> seeds;
    std::string scalar_name;
    double isovalue=0;
};
struct gx3de_animation {
    using Frame=AnimationFrame;
    struct ObjectState {gx3de_mat4 pose{};uint32_t visible=0;double opacity=1;};
    struct CameraState {gx3de_camera value{};};
    gx3de_scene* scene=nullptr;
    std::string unit;
    std::vector<Frame> frames;
    std::vector<std::unique_ptr<gx3de_animation_layer>> layers;
    std::map<gx3de_object*,std::map<uint64_t,ObjectState>> object_keys;
    std::map<gx3de_object*,ObjectState> original_objects;
    std::map<gx3de_view*,std::map<uint64_t,CameraState>> camera_keys;
    std::map<gx3de_view*,CameraState> original_cameras;
    std::map<gx3de_object*,uint32_t> original_source_visibility;
    uint64_t max_resident=2,max_resident_bytes=256ull*1024*1024,use_counter=0,current_frame=0;
    uint64_t range_first=0,range_last=0;
    bool range_explicit=false;
    double current_time=0,rate=1;
    uint32_t interpolation=GX3DE_ANIM_NEAREST,loop=GX3DE_ANIM_ONCE,state=GX3DE_ANIM_STOPPED;
    int ping_direction=1;
    bool initialized=false;
    std::atomic<bool> cancelled{false};
};
namespace {
using A=gx3de_animation;
std::mutex timeline_mutex;
std::vector<A*> timelines;
bool finite_mat(const gx3de_mat4& p){for(double x:p.m)if(!std::isfinite(x))return false;return p.m[3]==0&&p.m[7]==0&&p.m[11]==0&&p.m[15]==1;}
bool valid_utf8_text(const char* s,size_t maximum){
    if(!s)return false;size_t n=strlen(s);if(n==0||n>maximum)return false;
    for(size_t i=0;i<n;){unsigned char c=(unsigned char)s[i];size_t count=0;
        if(c<0x80){if(c<32||c==127)return false;++i;continue;}
        if(c>=0xc2&&c<=0xdf)count=2;else if(c>=0xe0&&c<=0xef)count=3;
        else if(c>=0xf0&&c<=0xf4)count=4;else return false;
        if(i+count>n)return false;
        for(size_t j=1;j<count;++j)if(((unsigned char)s[i+j]&0xc0)!=0x80)return false;
        unsigned char d=(unsigned char)s[i+1];
        if((c==0xe0&&d<0xa0)||(c==0xed&&d>=0xa0)||(c==0xf0&&d<0x90)||(c==0xf4&&d>=0x90))return false;
        i+=count;
    }return true;
}
bool snapshot(gx3de_object* o,A::ObjectState& s){return gx3de_object_get_transform(o,&s.pose)==GX3DE_OK&&
    gx3de_object_get_visible(o,&s.visible)==GX3DE_OK&&gx3de_object_get_opacity(o,&s.opacity)==GX3DE_OK;}
void restore(gx3de_object* o,const A::ObjectState& s){gx3de_object_set_transform(o,&s.pose);gx3de_object_set_opacity(o,s.opacity);gx3de_object_set_visible(o,s.visible);}
gx3de_result estimate_frame_bytes(gx3de_object* object,uint64_t& bytes){
    gx3de_scientific_info si{};si.struct_size=sizeof(si);
    auto rc=gx3de_scientific_info_get(object,&si);
    if(rc==GX3DE_OK){
        if(si.point_count>UINT64_MAX/24||si.cell_count>UINT64_MAX/32)return GX3DE_RANGE;
        if(si.cell_count>(UINT64_MAX-si.point_count*24)/32)return GX3DE_RANGE;
        bytes=si.point_count*24+si.cell_count*32;
        for(uint64_t i=0;i<si.array_count;++i){gx3de_scientific_array_info ai{};ai.struct_size=sizeof(ai);
            rc=gx3de_scientific_array_info_get(object,i,&ai);if(rc!=GX3DE_OK)return rc;
            if(ai.components&&ai.tuple_count>(UINT64_MAX-bytes)/(uint64_t(ai.components)*8))return GX3DE_RANGE;
            bytes+=ai.tuple_count*uint64_t(ai.components)*8;}
        return GX3DE_OK;
    }
    uint64_t vertices=0,triangles=0;rc=gx3de_object_counts(object,&vertices,&triangles);
    if(rc!=GX3DE_OK)return GX3DE_UNSUPPORTED;
    if(vertices>UINT64_MAX/24||triangles>(UINT64_MAX-vertices*24)/12)return GX3DE_RANGE;
    bytes=vertices*24+triangles*12;return GX3DE_OK;
}
uint64_t nearest_frame(const A* a,double t){
    auto it=std::lower_bound(a->frames.begin(),a->frames.end(),t,[](const A::Frame& f,double value){return f.time<value;});
    if(it==a->frames.begin())return 0;if(it==a->frames.end())return a->frames.size()-1;
    uint64_t hi=uint64_t(it-a->frames.begin()),lo=hi-1;
    return (t-a->frames[lo].time<=a->frames[hi].time-t)?lo:hi;
}
bool sample_state(const A* a,const std::map<uint64_t,A::ObjectState>& keys,double t,A::ObjectState& out){
    auto upper=std::lower_bound(a->frames.begin(),a->frames.end(),t,[](const A::Frame& f,double value){return f.time<value;});
    uint64_t frame=nearest_frame(a,t);
    if(a->interpolation==GX3DE_ANIM_LINEAR&&upper!=a->frames.begin()&&upper!=a->frames.end()&&upper->time!=t){
        uint64_t hi=uint64_t(upper-a->frames.begin()),lo=hi-1;
        auto l=keys.find(lo),h=keys.find(hi);
        if(l!=keys.end()&&h!=keys.end()){
            for(int k=0;k<16;++k)if(k!=12&&k!=13&&k!=14&&std::abs(l->second.pose.m[k]-h->second.pose.m[k])>1e-12)return false;
            double alpha=(t-a->frames[lo].time)/(a->frames[hi].time-a->frames[lo].time);
            out=l->second;
            for(int k=12;k<=14;++k)out.pose.m[k]=l->second.pose.m[k]*(1-alpha)+h->second.pose.m[k]*alpha;
            out.opacity=l->second.opacity*(1-alpha)+h->second.opacity*alpha;
            out.visible=frame==lo?l->second.visible:h->second.visible;
            return true;
        }
    }
    auto it=keys.lower_bound(frame);if(it==keys.end())--it;
    else if(it!=keys.begin()&&it->first!=frame){auto prev=std::prev(it);
        if(t-a->frames[prev->first].time<=a->frames[it->first].time-t)it=prev;}
    out=it->second;return true;
}
struct PathlineLoaderContext {A* timeline;gx3de_animation_layer* source;};
gx3de_result load_pathline_source(gx3de_scene* scene,uint64_t index,double time,void* user,gx3de_object** out){
    auto* context=static_cast<PathlineLoaderContext*>(user);
    *out=nullptr;
    if(context->timeline->cancelled.load())return GX3DE_UNSUPPORTED;
    auto it=context->source->frames.find(index);
    if(it==context->source->frames.end())return GX3DE_NOT_FOUND;
    auto& frame=it->second;
    if(frame.source)return gx3de_object_duplicate(frame.source,out);
    if(!frame.loader)return GX3DE_NOT_FOUND;
    return frame.loader(scene,index,time,frame.user,out);
}
void prune_cache(A* a){
    uint64_t resident=0,resident_bytes=0;
    auto count=[&](A::Frame& f){if(f.owns&&f.source){++resident;resident_bytes+=f.estimated_bytes;}};
    for(auto& f:a->frames)count(f);
    for(auto& layer:a->layers)for(auto& pair:layer->frames)count(pair.second);
    while(resident>a->max_resident||resident_bytes>a->max_resident_bytes){
        A::Frame* victim=nullptr;uint64_t oldest=UINT64_MAX;
        auto candidate=[&](A::Frame& f,bool current){if(!current&&f.owns&&f.source&&f.last_use<oldest){
            victim=&f;oldest=f.last_use;}};
        for(auto& layer:a->layers)if(layer->derived!=gx3de_animation_layer::Derived::none)
            for(auto& pair:layer->frames)candidate(pair.second,a->initialized&&pair.first==a->current_frame);
        if(!victim){for(size_t i=0;i<a->frames.size();++i)
                candidate(a->frames[i],a->initialized&&i==a->current_frame);
            for(auto& layer:a->layers)for(auto& pair:layer->frames)
                candidate(pair.second,a->initialized&&pair.first==a->current_frame);}
        if(!victim)break;
        resident_bytes-=victim->estimated_bytes;gx3de_object_destroy(victim->source);
        victim->source=nullptr;victim->owns=false;victim->estimated_bytes=0;--resident;
    }
}
gx3de_result seek(A* a,double time){
    if(!a||a->frames.empty()||!std::isfinite(time))return GX3DE_INVALID_ARGUMENT;
    if(time<a->frames.front().time||time>a->frames.back().time)return GX3DE_RANGE;
    if(a->cancelled.load())return GX3DE_UNSUPPORTED;
    const uint64_t idx=nearest_frame(a,time);
    auto& selected=a->frames[idx];
    std::vector<A::Frame*> created;
    auto discard_created=[&](){for(auto it=created.rbegin();it!=created.rend();++it){auto* frame=*it;
        if(frame->source)gx3de_object_destroy(frame->source);
        frame->source=nullptr;frame->owns=false;frame->estimated_bytes=0;}created.clear();};
    std::vector<std::pair<gx3de_object*,A::ObjectState>> backup;
    std::vector<std::pair<gx3de_view*,gx3de_camera>> camera_backup;
    std::vector<std::pair<gx3de_object*,uint32_t>> visibility_backup;
    const uint64_t original_frame=a->current_frame;
    const double original_time=a->current_time;
    const bool original_initialized=a->initialized;
    bool mutating=false;
    auto rollback_state=[&](){if(mutating){for(auto& entry:backup)restore(entry.first,entry.second);
        for(auto& entry:camera_backup)gx3de_view_set_camera(entry.first,&entry.second);
        for(auto& entry:visibility_backup)gx3de_object_set_visible(entry.first,entry.second);
        a->current_frame=original_frame;a->current_time=original_time;
        a->initialized=original_initialized;
        mutating=false;}discard_created();};
    try{
    created.reserve(a->layers.size()+1);
    auto load=[&](A::Frame& frame,gx3de_animation_layer* layer)->gx3de_result{
        if(frame.source||(!frame.loader&&!layer))return GX3DE_OK;
        gx3de_object* object=nullptr;gx3de_result rc=GX3DE_OK;
        try{
        if(layer&&layer->derived!=gx3de_animation_layer::Derived::none){
            gx3de_field_cancel_scope cancel_scope(&a->cancelled);
            auto source_it=layer->source_layer->frames.find(idx);
            if(layer->derived==gx3de_animation_layer::Derived::pathlines){
                if(idx==0)return GX3DE_OK;
                std::vector<double> times;times.reserve(size_t(idx+1));
                for(uint64_t i=0;i<=idx;++i)times.push_back(a->frames[size_t(i)].time);
                auto spec=layer->pathline_spec;spec.times=times.data();spec.frame_count=times.size();
                spec.seed_points=layer->seeds.data();
                PathlineLoaderContext context{a,layer->source_layer};
                spec.loader=load_pathline_source;spec.loader_user=&context;
                gx3de_field_pathline_info info{};info.struct_size=sizeof(info);
                rc=gx3de_field_pathlines_create(a->scene,&spec,&object,&info);
                if(rc==GX3DE_NOT_FOUND)rc=GX3DE_OK;
            }else if(source_it==layer->source_layer->frames.end()||!source_it->second.source)
                return GX3DE_OK;
            else if(layer->derived==gx3de_animation_layer::Derived::lines){
                gx3de_object* source=source_it->second.source;
                auto spec=layer->line_spec;spec.field=source;spec.seed_points=layer->seeds.data();
                gx3de_field_line_info info{};info.struct_size=sizeof(info);
                rc=gx3de_field_lines_create(a->scene,&spec,&object,&info);
                if(rc==GX3DE_NOT_FOUND)rc=GX3DE_OK;
            }else if(layer->derived==gx3de_animation_layer::Derived::slice){
                gx3de_object* source=source_it->second.source;
                auto spec=layer->slice_spec;spec.field=source;
                rc=gx3de_field_slice_create(a->scene,&spec,&object);
            }else rc=gx3de_scientific_isosurfaces(source_it->second.source,layer->scalar_name.c_str(),
                            &layer->isovalue,1,&object);
        }else if(frame.loader)rc=frame.loader(a->scene,idx,a->frames[idx].time,frame.user,&object);
        if(rc!=GX3DE_OK){if(object)gx3de_object_destroy(object);return rc;}
        if(a->cancelled.load()){if(object)gx3de_object_destroy(object);return GX3DE_UNSUPPORTED;}
        if(!object){if(layer&&layer->derived!=gx3de_animation_layer::Derived::none)return GX3DE_OK;
            return GX3DE_DEGENERATE;}
        gx3de_scene* owner=nullptr;rc=gx3de_object_scene_get(object,&owner);
        if(rc!=GX3DE_OK)return rc;
        if(owner!=a->scene)return GX3DE_WRONG_OWNER; /* foreign object remains caller-owned */
        uint64_t bytes=0;rc=estimate_frame_bytes(object,bytes);
        if(rc==GX3DE_OK&&bytes>a->max_resident_bytes)rc=GX3DE_RANGE;
        if(rc==GX3DE_OK)rc=gx3de_object_set_visible(object,0);
        if(rc!=GX3DE_OK){gx3de_object_destroy(object);return rc;}
        frame.source=object;frame.owns=true;frame.estimated_bytes=bytes;
        created.push_back(&frame);return GX3DE_OK;
        }catch(...){if(object&&frame.source!=object)gx3de_object_destroy(object);throw;}
    };
    auto rc=load(selected,nullptr);if(rc!=GX3DE_OK){discard_created();return rc;}
    for(auto& layer:a->layers){
        auto it=layer->frames.find(idx);
        if(layer->derived!=gx3de_animation_layer::Derived::none&&it==layer->frames.end())
            it=layer->frames.emplace(idx,A::Frame{}).first;
        if(it!=layer->frames.end()){rc=load(it->second,layer.get());
            if(rc!=GX3DE_OK){discard_created();return rc;}}
    }
    uint64_t active_bytes=0,active_frames=0;
    auto active_count=[&](const A::Frame& f){if(f.owns&&f.source){++active_frames;active_bytes+=f.estimated_bytes;}};
    active_count(selected);
    for(auto& layer:a->layers){auto it=layer->frames.find(idx);
        if(it!=layer->frames.end())active_count(it->second);}
    if(active_bytes>a->max_resident_bytes||active_frames>a->max_resident){discard_created();return GX3DE_RANGE;}
    std::vector<std::pair<gx3de_object*,A::ObjectState>> desired;
    try{
        desired.reserve(a->object_keys.size());backup.reserve(a->object_keys.size());
        for(auto& entry:a->object_keys){A::ObjectState state{},before{};
            if(!sample_state(a,entry.second,time,state)){discard_created();return GX3DE_UNSUPPORTED;}
            if(!snapshot(entry.first,before)){discard_created();return GX3DE_INVALID_ARGUMENT;}
            desired.emplace_back(entry.first,state);backup.emplace_back(entry.first,before);
        }
    }catch(const std::bad_alloc&){discard_created();return GX3DE_OUT_OF_MEMORY;}
    for(auto& entry:a->camera_keys){gx3de_camera before{};before.struct_size=sizeof(before);
        if(gx3de_view_get_camera(entry.first,&before)!=GX3DE_OK){discard_created();return GX3DE_INVALID_ARGUMENT;}
        camera_backup.emplace_back(entry.first,before);}
    uint64_t previous=a->current_frame;bool had_previous=a->initialized;
    auto remember=[&](gx3de_object* object){if(!object)return;
        for(const auto& entry:visibility_backup)if(entry.first==object)return;
        uint32_t visible=0;if(gx3de_object_get_visible(object,&visible)==GX3DE_OK)
            visibility_backup.emplace_back(object,visible);};
    if(had_previous)remember(a->frames[previous].source);
    remember(selected.source);
    for(auto& layer:a->layers){
        if(had_previous){auto it=layer->frames.find(previous);
            if(it!=layer->frames.end())remember(it->second.source);}
        auto it=layer->frames.find(idx);if(it!=layer->frames.end())remember(it->second.source);
    }
    auto rollback=[&](){rollback_state();};
    mutating=true;
    if(had_previous&&previous!=idx&&a->frames[previous].source)
        if(gx3de_object_set_visible(a->frames[previous].source,0)!=GX3DE_OK){rollback();return GX3DE_INVALID_ARGUMENT;}
    if(had_previous&&previous!=idx)for(auto& layer:a->layers){auto it=layer->frames.find(previous);
        if(it!=layer->frames.end()&&it->second.source){rc=gx3de_object_set_visible(it->second.source,0);
            if(rc!=GX3DE_OK){rollback();return rc;}}}
    for(auto& pair:desired){auto rc=gx3de_object_set_transform(pair.first,&pair.second.pose);
        if(rc==GX3DE_OK)rc=gx3de_object_set_opacity(pair.first,pair.second.opacity);
        if(rc==GX3DE_OK)rc=gx3de_object_set_visible(pair.first,pair.second.visible);
        if(rc!=GX3DE_OK){rollback();return rc;}}
    for(auto& entry:a->camera_keys){
        uint64_t nearest=idx;auto it=entry.second.lower_bound(nearest);
        if(it==entry.second.end())--it;
        else if(it!=entry.second.begin()&&it->first!=nearest){auto prev=std::prev(it);
            if(time-a->frames[prev->first].time<=a->frames[it->first].time-time)it=prev;}
        rc=gx3de_view_set_camera(entry.first,&it->second.value);if(rc!=GX3DE_OK){rollback();return rc;}
    }
    if(selected.source){rc=gx3de_object_set_visible(selected.source,1);if(rc!=GX3DE_OK){rollback();return rc;}}
    for(auto& layer:a->layers){auto it=layer->frames.find(idx);
        if(it!=layer->frames.end()&&it->second.source){rc=gx3de_object_set_visible(it->second.source,1);
            if(rc!=GX3DE_OK){rollback();return rc;}it->second.last_use=++a->use_counter;}}
    a->current_time=time;a->current_frame=idx;a->initialized=true;selected.last_use=++a->use_counter;
    prune_cache(a);
    mutating=false;
    return GX3DE_OK;
    }catch(const std::bad_alloc&){rollback_state();return GX3DE_OUT_OF_MEMORY;}
    catch(...){rollback_state();return GX3DE_DEGENERATE;}
}
} // namespace

extern "C" {
GX3DE_API gx3de_result gx3de_animation_create(gx3de_scene* scene,const char* unit,gx3de_animation** out){
    if(!scene||!out||!valid_utf8_text(unit,63))return GX3DE_INVALID_ARGUMENT;*out=nullptr;
    try{auto a=std::make_unique<gx3de_animation>();a->scene=scene;a->unit=unit;
        {std::lock_guard<std::mutex> lock(timeline_mutex);timelines.push_back(a.get());}
        *out=a.release();return GX3DE_OK;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_destroy(gx3de_animation* a){if(!a)return GX3DE_INVALID_ARGUMENT;
    {std::lock_guard<std::mutex> lock(timeline_mutex);auto it=std::find(timelines.begin(),timelines.end(),a);
        if(it!=timelines.end())timelines.erase(it);}
    for(auto& entry:a->original_cameras)gx3de_view_set_camera(entry.first,&entry.second.value);
    for(auto& entry:a->original_objects)restore(entry.first,entry.second);
    for(auto& entry:a->original_source_visibility)gx3de_object_set_visible(entry.first,entry.second);
    for(auto it=a->layers.rbegin();it!=a->layers.rend();++it)for(auto& pair:(*it)->frames)
        if(pair.second.owns&&pair.second.source)gx3de_object_destroy(pair.second.source);
    for(auto& f:a->frames)if(f.owns&&f.source)gx3de_object_destroy(f.source);
    delete a;return GX3DE_OK;
}

void gx3de_animation_scene_cleanup(gx3de_scene* scene){
    std::vector<gx3de_animation*> pending;
    {std::lock_guard<std::mutex> lock(timeline_mutex);
        for(auto* a:timelines)if(a->scene==scene)pending.push_back(a);}
    for(auto* a:pending)gx3de_animation_destroy(a);
}
GX3DE_API gx3de_result gx3de_animation_frame_add(gx3de_animation* a,double time,gx3de_object* source,
    gx3de_animation_frame_loader loader,void* user,uint64_t* index){
    if(!a||!std::isfinite(time)||(!source&&!loader)||a->initialized||a->frames.size()>=100000||
       (!a->frames.empty()&&time<=a->frames.back().time))return GX3DE_INVALID_ARGUMENT;
    if(source){gx3de_scene* owner=nullptr;auto rc=gx3de_object_scene_get(source,&owner);
        if(rc!=GX3DE_OK)return rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;}
    if(source){uint32_t visible=0;if(gx3de_object_get_visible(source,&visible)!=GX3DE_OK)return GX3DE_INVALID_ARGUMENT;
        if(a->original_source_visibility.find(source)==a->original_source_visibility.end())a->original_source_visibility[source]=visible;
        auto rc=gx3de_object_set_visible(source,0);if(rc!=GX3DE_OK)return rc;}
    try{a->frames.push_back({time,source,loader,user,false,0});
        if(!a->range_explicit)a->range_last=a->frames.size()-1;
        if(index)*index=a->frames.size()-1;return GX3DE_OK;}
    catch(const std::bad_alloc&){if(source)gx3de_object_set_visible(source,a->original_source_visibility[source]);return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_time_add(gx3de_animation* a,double time,uint64_t* index){
    if(!a||!std::isfinite(time)||a->initialized||a->frames.size()>=100000||
       (!a->frames.empty()&&time<=a->frames.back().time))return GX3DE_INVALID_ARGUMENT;
    try{a->frames.push_back({time,nullptr,nullptr,nullptr,false,0});
        if(!a->range_explicit)a->range_last=a->frames.size()-1;
        if(index)*index=a->frames.size()-1;return GX3DE_OK;}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_layer_create(gx3de_animation* a,const char* id,gx3de_animation_layer** out){
    if(!a||!out||!valid_utf8_text(id,127)||a->initialized||a->layers.size()>=64)return GX3DE_INVALID_ARGUMENT;
    *out=nullptr;
    for(auto& layer:a->layers)if(layer->id==id)return GX3DE_INVALID_ARGUMENT;
    try{auto layer=std::make_unique<gx3de_animation_layer>();layer->timeline=a;layer->id=id;
        *out=layer.get();a->layers.push_back(std::move(layer));return GX3DE_OK;}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_layer_id(gx3de_animation_layer* layer,char* buffer,uint64_t capacity,uint64_t* required){
    if(!layer||!required||(!buffer&&capacity))return GX3DE_INVALID_ARGUMENT;
    *required=layer->id.size()+1;if(capacity==0)return GX3DE_OK;
    if(capacity<*required)return GX3DE_RANGE;
    std::memcpy(buffer,layer->id.c_str(),size_t(*required));return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_layer_frame_set(gx3de_animation_layer* layer,uint64_t index,
    gx3de_object* source,gx3de_animation_frame_loader loader,void* user){
    if(!layer||(!source&&!loader))return GX3DE_INVALID_ARGUMENT;
    A* a=layer->timeline;
    if(a->initialized||index>=a->frames.size()||layer->derived!=gx3de_animation_layer::Derived::none||
       layer->frames.find(index)!=layer->frames.end())return GX3DE_INVALID_ARGUMENT;
    if(source){gx3de_scene* owner=nullptr;auto rc=gx3de_object_scene_get(source,&owner);
        if(rc!=GX3DE_OK)return rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;}
    try{layer->frames.emplace(index,A::Frame{a->frames[index].time,source,loader,user,false,0});}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
    if(source){uint32_t visible=0;auto rc=gx3de_object_get_visible(source,&visible);
        if(rc==GX3DE_OK&&a->original_source_visibility.find(source)==a->original_source_visibility.end())
            a->original_source_visibility.emplace(source,visible);
        if(rc==GX3DE_OK)rc=gx3de_object_set_visible(source,0);
        if(rc!=GX3DE_OK){layer->frames.erase(index);return rc;}}
    return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_layer_active_object_get(gx3de_animation_layer* layer,gx3de_object** out){
    if(!layer||!out)return GX3DE_INVALID_ARGUMENT;*out=nullptr;
    A* a=layer->timeline;if(!a->initialized)return GX3DE_NOT_FOUND;
    auto it=layer->frames.find(a->current_frame);
    if(it==layer->frames.end()||!it->second.source)return GX3DE_NOT_FOUND;
    *out=it->second.source;return GX3DE_OK;
}
static bool valid_binding(gx3de_animation_layer* layer,gx3de_animation_layer* source){
    if(!layer||!source||layer==source||layer->timeline!=source->timeline||
       layer->timeline->initialized||!layer->frames.empty()||
       layer->derived!=gx3de_animation_layer::Derived::none)return false;
    auto& all=layer->timeline->layers;
    auto find_index=[&](gx3de_animation_layer* p){for(size_t i=0;i<all.size();++i)if(all[i].get()==p)return i;
        return all.size();};
    return find_index(source)<find_index(layer);
}
GX3DE_API gx3de_result gx3de_animation_layer_bind_lines(gx3de_animation_layer* layer,
    gx3de_animation_layer* source,const gx3de_field_line_spec* spec){
    if(!valid_binding(layer,source)||!spec||spec->struct_size<sizeof(*spec)||
       (spec->seed_kind==GX3DE_FIELD_SEED_POINTS&&(!spec->seed_points||!spec->seed_count)))
        return GX3DE_INVALID_ARGUMENT;
    try{auto copy=*spec;std::vector<gx3de_vec3> seeds;
        if(spec->seed_kind==GX3DE_FIELD_SEED_POINTS)
            seeds.assign(spec->seed_points,spec->seed_points+spec->seed_count);
        layer->line_spec=copy;layer->line_spec.field=nullptr;layer->line_spec.seed_points=nullptr;
        layer->seeds=std::move(seeds);layer->source_layer=source;
        layer->derived=gx3de_animation_layer::Derived::lines;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_layer_bind_slice(gx3de_animation_layer* layer,
    gx3de_animation_layer* source,const gx3de_field_slice_spec* spec){
    if(!valid_binding(layer,source)||!spec||spec->struct_size<sizeof(*spec))return GX3DE_INVALID_ARGUMENT;
    layer->slice_spec=*spec;layer->slice_spec.field=nullptr;layer->source_layer=source;
    layer->derived=gx3de_animation_layer::Derived::slice;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_layer_bind_isosurface(gx3de_animation_layer* layer,
    gx3de_animation_layer* source,const char* name,double value){
    if(!valid_binding(layer,source)||!valid_utf8_text(name,255)||!std::isfinite(value))return GX3DE_INVALID_ARGUMENT;
    try{layer->scalar_name=name;layer->isovalue=value;layer->source_layer=source;
        layer->derived=gx3de_animation_layer::Derived::isosurface;return GX3DE_OK;}
    catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_layer_bind_pathlines(gx3de_animation_layer* layer,
    gx3de_animation_layer* source,const gx3de_field_pathline_spec* spec){
    if(!valid_binding(layer,source)||!spec||spec->struct_size<sizeof(*spec)||
       !spec->seed_points||spec->seed_count<1||spec->seed_count>10000||
       !std::isfinite(spec->time_step)||spec->time_step<=0||
       !std::isfinite(spec->min_vector_magnitude)||spec->min_vector_magnitude<=0||
       !std::isfinite(spec->tube_radius)||spec->tube_radius<0||
       spec->max_steps_per_seed<1||spec->max_steps_per_seed>100000||
       spec->max_output_points<2||spec->max_output_points>1000000||
       spec->max_memory_bytes<1024||spec->max_memory_bytes>512ull*1024*1024||
       layer->timeline->frames.size()<2)return GX3DE_INVALID_ARGUMENT;
    for(size_t i=0;i<spec->seed_count;++i)if(!std::isfinite(spec->seed_points[i].x)||
        !std::isfinite(spec->seed_points[i].y)||!std::isfinite(spec->seed_points[i].z))
        return GX3DE_INVALID_ARGUMENT;
    for(size_t i=0;i<layer->timeline->frames.size();++i)
        if(source->frames.find(i)==source->frames.end())return GX3DE_INVALID_ARGUMENT;
    try{auto seeds=std::vector<gx3de_vec3>(spec->seed_points,spec->seed_points+spec->seed_count);
        layer->pathline_spec=*spec;layer->pathline_spec.times=nullptr;
        layer->pathline_spec.frames=nullptr;layer->pathline_spec.loader=nullptr;
        layer->pathline_spec.loader_user=nullptr;layer->pathline_spec.seed_points=nullptr;
        layer->seeds=std::move(seeds);layer->source_layer=source;
        layer->derived=gx3de_animation_layer::Derived::pathlines;return GX3DE_OK;
    }catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_set_resident_limit(gx3de_animation* a,uint64_t n){
    if(!a||n<1||n>256)return GX3DE_INVALID_ARGUMENT;
    if(a->initialized){uint64_t active=0;
        if(a->frames[a->current_frame].owns&&a->frames[a->current_frame].source)++active;
        for(auto& layer:a->layers){auto it=layer->frames.find(a->current_frame);
            if(it!=layer->frames.end()&&it->second.owns&&it->second.source)++active;}
        if(active>n)return GX3DE_RANGE;}
    a->max_resident=n;prune_cache(a);return GX3DE_OK;}
GX3DE_API gx3de_result gx3de_animation_set_memory_limit(gx3de_animation* a,uint64_t bytes){
    if(!a||bytes<1024||bytes>4ull*1024*1024*1024)return GX3DE_INVALID_ARGUMENT;
    if(a->initialized){uint64_t active=0;auto& frame=a->frames[a->current_frame];
        if(frame.owns&&frame.source)active+=frame.estimated_bytes;
        for(auto& layer:a->layers){auto it=layer->frames.find(a->current_frame);
            if(it!=layer->frames.end()&&it->second.owns&&it->second.source)active+=it->second.estimated_bytes;}
        if(active>bytes)return GX3DE_RANGE;}
    a->max_resident_bytes=bytes;prune_cache(a);return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_mode_set(gx3de_animation* a,uint32_t interpolation,uint32_t loop,double rate){
    if(!a||(interpolation!=GX3DE_ANIM_NEAREST&&interpolation!=GX3DE_ANIM_LINEAR)||
       loop<GX3DE_ANIM_ONCE||loop>GX3DE_ANIM_PING_PONG||!std::isfinite(rate)||rate<=0||rate>10000)return GX3DE_INVALID_ARGUMENT;
    a->interpolation=interpolation;a->loop=loop;a->rate=rate;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_playback_range_set(gx3de_animation* a,uint64_t first,uint64_t last){
    if(!a||a->frames.empty()||first>last||last>=a->frames.size())return GX3DE_INVALID_ARGUMENT;
    a->range_first=first;a->range_last=last;a->range_explicit=true;a->ping_direction=1;
    return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_playback_range_get(gx3de_animation* a,uint64_t* first,uint64_t* last){
    if(!a||!first||!last||a->frames.empty())return GX3DE_INVALID_ARGUMENT;
    *first=a->range_first;*last=a->range_last;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_info_get(gx3de_animation* a,gx3de_animation_info* out){
    if(!a||!out||out->struct_size<sizeof(*out))return GX3DE_INVALID_ARGUMENT;
    gx3de_animation_info result{};result.struct_size=sizeof(result);result.state=a->state;
    result.interpolation=a->interpolation;result.loop_mode=a->loop;result.frame_count=a->frames.size();
    result.current_frame=a->current_frame;result.current_time=a->current_time;
    result.start_time=a->frames.empty()?0:a->frames.front().time;result.end_time=a->frames.empty()?0:a->frames.back().time;
    result.playback_rate=a->rate;result.max_resident_frames=a->max_resident;
    result.max_resident_bytes=a->max_resident_bytes;
    auto count=[&](const A::Frame& f){if(f.owns&&f.source){++result.resident_frames;
        result.resident_estimated_bytes+=f.estimated_bytes;}};
    for(auto& f:a->frames)count(f);
    for(auto& layer:a->layers)for(auto& pair:layer->frames)count(pair.second);
    *out=result;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_time_unit(gx3de_animation* a,char* buffer,uint64_t capacity,uint64_t* required){
    if(!a||!required||(!buffer&&capacity))return GX3DE_INVALID_ARGUMENT;*required=a->unit.size()+1;
    if(capacity<*required)return GX3DE_RANGE;memcpy(buffer,a->unit.c_str(),size_t(*required));return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_frame_time(gx3de_animation* a,uint64_t index,double* time){
    if(!a||!time)return GX3DE_INVALID_ARGUMENT;if(index>=a->frames.size())return GX3DE_RANGE;*time=a->frames[index].time;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_active_object_get(gx3de_animation* a,gx3de_object** out){
    if(!a||!out)return GX3DE_INVALID_ARGUMENT;*out=nullptr;
    if(!a->initialized)return GX3DE_NOT_FOUND;
    *out=a->frames[a->current_frame].source;return *out?GX3DE_OK:GX3DE_NOT_FOUND;
}
GX3DE_API gx3de_result gx3de_animation_object_key_set(gx3de_animation* a,uint64_t index,gx3de_object* object,
    const gx3de_mat4* pose,uint32_t visible,double opacity){
    if(!a||!object||!pose||index>=a->frames.size()||visible>1||!std::isfinite(opacity)||opacity<0||opacity>1||!finite_mat(*pose))return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;auto owner_rc=gx3de_object_scene_get(object,&owner);
    if(owner_rc!=GX3DE_OK)return owner_rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;
    A::ObjectState original{};if(!snapshot(object,original))return GX3DE_INVALID_ARGUMENT;
    try{if(a->original_objects.find(object)==a->original_objects.end())a->original_objects.emplace(object,original);
        a->object_keys[object][index]={*pose,visible,opacity};return GX3DE_OK;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_camera_key_set(gx3de_animation* a,uint64_t index,gx3de_view* view,const gx3de_camera* camera){
    if(!a||!view||!camera||camera->struct_size<sizeof(*camera)||index>=a->frames.size())return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;auto owner_rc=gx3de_view_scene_get(view,&owner);
    if(owner_rc!=GX3DE_OK)return owner_rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;
    gx3de_camera before{};before.struct_size=sizeof(before);if(gx3de_view_get_camera(view,&before)!=GX3DE_OK)return GX3DE_INVALID_ARGUMENT;
    try{if(a->original_cameras.find(view)==a->original_cameras.end())a->original_cameras.emplace(view,A::CameraState{before});
        a->camera_keys[view][index]={*camera};return GX3DE_OK;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
}
GX3DE_API gx3de_result gx3de_animation_seek_frame(gx3de_animation* a,uint64_t index){
    if(!a)return GX3DE_INVALID_ARGUMENT;if(index>=a->frames.size())return GX3DE_RANGE;return seek(a,a->frames[index].time);
}
GX3DE_API gx3de_result gx3de_animation_seek_time(gx3de_animation* a,double time){return seek(a,time);}
GX3DE_API gx3de_result gx3de_animation_play(gx3de_animation* a){if(!a||a->frames.empty())return GX3DE_INVALID_ARGUMENT;
    if(!a->initialized||a->current_frame<a->range_first||a->current_frame>a->range_last){
        auto rc=seek(a,a->frames[a->range_first].time);if(rc!=GX3DE_OK)return rc;}
    a->state=GX3DE_ANIM_PLAYING;return GX3DE_OK;}
GX3DE_API gx3de_result gx3de_animation_pause(gx3de_animation* a){if(!a)return GX3DE_INVALID_ARGUMENT;a->state=GX3DE_ANIM_PAUSED;return GX3DE_OK;}
GX3DE_API gx3de_result gx3de_animation_stop(gx3de_animation* a){if(!a||a->frames.empty())return GX3DE_INVALID_ARGUMENT;
    auto rc=seek(a,a->frames[a->range_first].time);if(rc==GX3DE_OK){a->state=GX3DE_ANIM_STOPPED;a->ping_direction=1;}return rc;}
GX3DE_API gx3de_result gx3de_animation_step(gx3de_animation* a,int32_t direction){if(!a||a->frames.empty()||(direction!=-1&&direction!=1))return GX3DE_INVALID_ARGUMENT;
    uint64_t i=std::clamp(a->current_frame,a->range_first,a->range_last);
    if(direction>0&&i<a->range_last)++i;else if(direction<0&&i>a->range_first)--i;
    return seek(a,a->frames[i].time);}
GX3DE_API gx3de_result gx3de_animation_advance(gx3de_animation* a,double elapsed){
    if(!a||!std::isfinite(elapsed)||elapsed<0)return GX3DE_INVALID_ARGUMENT;if(a->state!=GX3DE_ANIM_PLAYING)return GX3DE_OK;
    const double begin=a->frames[a->range_first].time,end=a->frames[a->range_last].time,span=end-begin;
    if(span==0)return GX3DE_OK;
    double next=std::clamp(a->current_time,begin,end)+elapsed*a->rate*a->ping_direction;
    uint32_t next_state=a->state;int next_direction=a->ping_direction;
    if(a->loop==GX3DE_ANIM_ONCE){if(next>=end){next=end;next_state=GX3DE_ANIM_PAUSED;}if(next<=begin){next=begin;next_state=GX3DE_ANIM_PAUSED;}}
    else if(a->loop==GX3DE_ANIM_LOOP){next=begin+std::fmod(std::fmod(next-begin,span)+span,span);}
    else{double cycle=2*span;double phase=a->ping_direction>0?a->current_time-begin:span+(end-a->current_time);
        double x=std::fmod(std::fmod(phase+elapsed*a->rate,cycle)+cycle,cycle);
        if(x<=span){next=begin+x;next_direction=1;}else{next=end-(x-span);next_direction=-1;}}
    auto rc=seek(a,next);if(rc==GX3DE_OK){a->state=next_state;a->ping_direction=next_direction;}
    return rc;
}
GX3DE_API gx3de_result gx3de_animation_cancel(gx3de_animation* a){if(!a)return GX3DE_INVALID_ARGUMENT;a->cancelled.store(true);return GX3DE_OK;}
GX3DE_API gx3de_result gx3de_animation_reset_cancel(gx3de_animation* a){if(!a)return GX3DE_INVALID_ARGUMENT;a->cancelled.store(false);return GX3DE_OK;}
GX3DE_API gx3de_result gx3de_animation_cancel_requested(gx3de_animation* a,uint32_t* requested){
    if(!a||!requested)return GX3DE_INVALID_ARGUMENT;
    *requested=a->cancelled.load()?1u:0u;return GX3DE_OK;
}
GX3DE_API gx3de_result gx3de_animation_render_frame_rgba(gx3de_animation* a,gx3de_view* view,uint64_t index,
    uint32_t width,uint32_t height,uint8_t* pixels,uint64_t capacity,uint64_t* required){
    if(!a||!view)return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;auto rc=gx3de_view_scene_get(view,&owner);
    if(rc!=GX3DE_OK)return rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;
    rc=gx3de_animation_seek_frame(a,index);if(rc!=GX3DE_OK)return rc;
    return gx3de_view_render_rgba(view,width,height,pixels,capacity,required);
}
GX3DE_API gx3de_result gx3de_animation_render_frame_png(gx3de_animation* a,gx3de_view* view,uint64_t index,
    uint32_t width,uint32_t height,const char* path){
    if(!a||!view||!path)return GX3DE_INVALID_ARGUMENT;
    gx3de_scene* owner=nullptr;auto rc=gx3de_view_scene_get(view,&owner);
    if(rc!=GX3DE_OK)return rc;if(owner!=a->scene)return GX3DE_WRONG_OWNER;
    rc=gx3de_animation_seek_frame(a,index);if(rc!=GX3DE_OK)return rc;
    return gx3de_view_write_png(view,width,height,path);
}
GX3DE_API gx3de_result gx3de_animation_write_png_sequence(gx3de_animation* a,gx3de_view* view,
    uint64_t first,uint64_t count,uint32_t width,uint32_t height,const char* prefix){
    if(!a||!view||!valid_utf8_text(prefix,4096)||count==0||first>=a->frames.size()||count>a->frames.size()-first)return GX3DE_INVALID_ARGUMENT;
    for(uint64_t i=0;i<count;++i){if(a->cancelled.load())return GX3DE_UNSUPPORTED;
        char suffix[32];std::snprintf(suffix,sizeof(suffix),"%06llu.png",(unsigned long long)(first+i));
        std::string path;try{path=std::string(prefix)+suffix;}catch(const std::bad_alloc&){return GX3DE_OUT_OF_MEMORY;}
        auto rc=gx3de_animation_render_frame_png(a,view,first+i,width,height,path.c_str());if(rc!=GX3DE_OK)return rc;
    }return GX3DE_OK;
}
}
