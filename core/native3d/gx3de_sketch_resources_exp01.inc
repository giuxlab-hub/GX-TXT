// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental additive bridge over the existing public Native3D C ABI.
// No renderer, camera, scientific kernel, or persistent model implementation.
std::string sketchLayerId(const std::string& key,const std::string& layer) {
    return "sketch-resource/"+key+"/"+layer;
}
void createSketchActors(Tcl_Interp* ip,State& state,const std::string& key,SketchResource& resource) {
    Tcl_DictSearch search;Tcl_Obj *name=nullptr,*layer=nullptr;int done=0;
    if(Tcl_DictObjFirst(ip,resource.layers,&search,&name,&layer,&done)!=TCL_OK)
        throw std::runtime_error("Invalid Sketch layer collection");
    try {
        while(!done) {
            auto* object=memoryLines(ip,state.scene,layer);
            resource.objects.push_back(object);
            state.add(ip,object,sketchLayerId(key,str(name)),layer,
                resource.visible&&yes(field(ip,layer,"visible")),number(field(ip,layer,"opacity"),"opacity"));
            Tcl_DictObjNext(&search,&name,&layer,&done);
        }
    } catch(...) {Tcl_DictObjDone(&search);throw;}
    Tcl_DictObjDone(&search);
}
void releaseSketchActors(State& state,SketchResource& resource) {
    for(auto* object:resource.objects) {
        if(state.selectionObject==object){check(gx3de_view_set_selection(state.view,nullptr),"retire Sketch selection anchor");state.selectionObject=nullptr;}
        if(state.gizmoObject==object) {
            if(state.gizmo)gx3de_gizmo_destroy(state.gizmo);
            state.gizmo=nullptr;state.gizmoObject=nullptr;state.gizmoLayer.clear();
        }
        state.objects.erase(std::remove_if(state.objects.begin(),state.objects.end(),
            [&](const auto& entry){return entry.first==object;}),state.objects.end());
        // The existing C ABI detaches all anchors/relationships safely.
        check(gx3de_object_destroy(object),"release derived Sketch actor");
    }
    resource.objects.clear();
}
void restoreSketchResources(Tcl_Interp* ip,State& state) {
    for(auto& item:state.sketchResources) {
        createSketchActors(ip,state,item.first,*item.second);++state.sketchReplays;
    }
}
int sketchResources(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj*const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"sync changes PNG | status {} {} ");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try {
        const auto operation=str(args[1]);
        if(operation!="sync"&&operation!="status")throw std::runtime_error("Unknown Sketch resource operation");
        uint64_t changed=0,reused=0;
        const auto begin=std::chrono::steady_clock::now();
        if(operation=="sync") {
            if(!state.scene||!state.viewport||!state.target)throw std::runtime_error("Render the owning scene before admitting Sketch resources");
            int size=0;if(Tcl_DictObjSize(ip,args[2],&size)!=TCL_OK||size>512)throw std::runtime_error("Sketch resource batch exceeds512 entries");
            std::map<std::string,std::unique_ptr<SketchResource>> pending;
            std::map<std::string,bool> visibility;
            std::vector<std::string> removals;
            uint64_t points=0,bytes=0,layers=0;
            for(const auto& item:state.sketchResources){points+=item.second->points;bytes+=item.second->bytes;int n=0;Tcl_DictObjSize(ip,item.second->layers,&n);layers+=n;}
            Tcl_DictSearch search;Tcl_Obj *keyObj=nullptr,*spec=nullptr;int done=0;
            if(Tcl_DictObjFirst(ip,args[2],&search,&keyObj,&spec,&done)!=TCL_OK)throw std::runtime_error("Invalid Sketch changes");
            try {
                while(!done) {
                    const auto key=str(keyObj);
                    if(key.empty()||key.size()>128||key.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")!=std::string::npos)
                        throw std::runtime_error("Invalid opaque Sketch resource identity");
                    auto old=state.sketchResources.find(key);
                    if(str(spec)=="remove") {
                        removals.push_back(key);
                    } else {
                        const auto revision=field(ip,spec,"revision");
                        if(revision.empty()||revision.size()>256)throw std::runtime_error("Sketch display revision is required");
                        const bool visible=yes(field(ip,spec,"visible"));
                        if(old!=state.sketchResources.end()&&old->second->revision==revision) {
                            visibility[key]=visible;++reused;
                        } else {
                            auto item=std::make_unique<SketchResource>();item->layers=get(ip,spec,"layers");
                            if(!item->layers)throw std::runtime_error("New Sketch revision requires layers");
                            Tcl_IncrRefCount(item->layers);item->revision=revision;item->visible=visible;
                            int count=0;if(Tcl_DictObjSize(ip,item->layers,&count)!=TCL_OK||count>4096)throw std::runtime_error("Sketch layer budget exceeded");
                            int length=0;Tcl_GetStringFromObj(item->layers,&length);item->bytes=length;
                            Tcl_DictSearch rows;Tcl_Obj *name=nullptr,*layer=nullptr;int end=0;
                            Tcl_DictObjFirst(ip,item->layers,&rows,&name,&layer,&end);
                            try {
                                while(!end) {
                                    if(str(name).empty()||str(name).size()>128||field(ip,layer,"source_mode")!="memory_geometry"||
                                       !field(ip,layer,"texture").empty()||!field(ip,layer,"local_transform").empty())
                                        throw std::runtime_error("Sketch resources admit bounded native world curves only");
                                    int n=0;auto* vertices=get(ip,layer,"vertices");
                                    if(!vertices||Tcl_ListObjLength(ip,vertices,&n)!=TCL_OK||n<1||n>65536)throw std::runtime_error("Sketch vertex budget exceeded");
                                    item->points+=n;Tcl_DictObjNext(&rows,&name,&layer,&end);
                                }
                            } catch(...) {Tcl_DictObjDone(&rows);throw;}
                            Tcl_DictObjDone(&rows);
                            if(old!=state.sketchResources.end()){points-=old->second->points;bytes-=old->second->bytes;int n=0;Tcl_DictObjSize(ip,old->second->layers,&n);layers-=n;}
                            points+=item->points;bytes+=item->bytes;layers+=count;
                            if(points>1000000||bytes>67108864||layers>4096)throw std::runtime_error("Resident Sketch resource budget exceeded");
                            pending.emplace(key,std::move(item));
                        }
                    }
                    Tcl_DictObjNext(&search,&keyObj,&spec,&done);
                }
            } catch(...) {Tcl_DictObjDone(&search);throw;}
            Tcl_DictObjDone(&search);
            size_t retained=state.sketchResources.size();
            for(const auto& key:removals)if(state.sketchResources.count(key))--retained;
            for(const auto& item:pending)if(!state.sketchResources.count(item.first))++retained;
            if(retained>512)throw std::runtime_error("Resident Sketch identity budget exceeds512 resources");
            // Stage/validate every replacement using established native APIs
            // before retiring any previous visible actor. No event-loop entry.
            try {for(auto& item:pending)createSketchActors(ip,state,item.first,*item.second);}
            catch(...) {for(auto& item:pending)releaseSketchActors(state,*item.second);throw;}
            for(const auto& key:removals) {
                auto found=state.sketchResources.find(key);if(found==state.sketchResources.end())continue;
                releaseSketchActors(state,*found->second);state.sketchResources.erase(found);++changed;
            }
            for(auto& item:pending) {
                auto found=state.sketchResources.find(item.first);
                if(found!=state.sketchResources.end())releaseSketchActors(state,*found->second);
                state.sketchResources[item.first]=std::move(item.second);++changed;
            }
            for(const auto& item:visibility) {
                auto& resource=*state.sketchResources.at(item.first);
                if(resource.visible!=item.second) {
                    resource.visible=item.second;Tcl_DictSearch rows;Tcl_Obj *name=nullptr,*layer=nullptr;int end=0;size_t i=0;
                    Tcl_DictObjFirst(ip,resource.layers,&rows,&name,&layer,&end);
                    while(!end){check(gx3de_object_set_visible(resource.objects.at(i++),item.second&&yes(field(ip,layer,"visible"))),"show Sketch resource");Tcl_DictObjNext(&rows,&name,&layer,&end);}
                    Tcl_DictObjDone(&rows);++changed;
                }
            }
            state.sketchUpdates+=changed;state.sketchReuses+=reused;
            if(!str(args[3]).empty()) {
                checkRender(state.target,gx3de_target_render(state.target),"render resident Sketches");
                check(presentationPng(state,str(args[3]).c_str()),"write resident Sketch frame");
            }
        }
        uint64_t points=0,bytes=0,actors=0;
        for(const auto& item:state.sketchResources){points+=item.second->points;bytes+=item.second->bytes;actors+=item.second->objects.size();}
        Tcl_Obj* reply=Tcl_NewDictObj();
        Tcl_Obj* identities=Tcl_NewDictObj();
        for(const auto& item:state.sketchResources) {
            auto* row=Tcl_NewDictObj();put(ip,row,"revision",Tcl_NewStringObj(item.second->revision.c_str(),-1));
            put(ip,row,"visible",Tcl_NewBooleanObj(item.second->visible));
            put(ip,identities,item.first.c_str(),row);
        }
        put(ip,reply,"resource_states",identities);
        put(ip,reply,"resources",Tcl_NewWideIntObj(state.sketchResources.size()));put(ip,reply,"actors",Tcl_NewWideIntObj(actors));
        put(ip,reply,"points",Tcl_NewWideIntObj(points));put(ip,reply,"descriptor_bytes",Tcl_NewWideIntObj(bytes));
        put(ip,reply,"updates",Tcl_NewWideIntObj(state.sketchUpdates));put(ip,reply,"reuses",Tcl_NewWideIntObj(state.sketchReuses));put(ip,reply,"replays",Tcl_NewWideIntObj(state.sketchReplays));
        put(ip,reply,"changed",Tcl_NewWideIntObj(changed));put(ip,reply,"camera_unchanged",Tcl_NewIntObj(1));
        put(ip,reply,"elapsed_us",Tcl_NewWideIntObj(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begin).count()));
        Tcl_SetObjResult(ip,reply);return TCL_OK;
    } catch(const std::exception& exception) {Tcl_SetObjResult(ip,Tcl_NewStringObj(exception.what(),-1));return TCL_ERROR;}
}
