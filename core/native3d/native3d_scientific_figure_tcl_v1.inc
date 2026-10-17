// SPDX-License-Identifier: GPL-3.0-or-later
void scientificFigure(Tcl_Interp* ip,State& state,Tcl_Obj* d) {
    if(!d)return;
    gx3de_scientific_figure f{};f.struct_size=sizeof f;f.enabled=1;
    f.axes_grid_visible=yes(field(ip,d,"axes_grid_visible"));f.colorbar_visible=yes(field(ip,d,"colorbar_visible"));
    f.world_bounds.min=vec(field(ip,d,"bounds_min"),"scientific bounds min");
    f.world_bounds.max=vec(field(ip,d,"bounds_max"),"scientific bounds max");
    auto lo=vec(field(ip,d,"axis_min"),"calibrated axis min"),hi=vec(field(ip,d,"axis_max"),"calibrated axis max");
    f.axis_min[0]=lo.x;f.axis_min[1]=lo.y;f.axis_min[2]=lo.z;
    f.axis_max[0]=hi.x;f.axis_max[1]=hi.y;f.axis_max[2]=hi.z;
    auto copy=[&](char* dest,size_t size,const char* key){const auto value=field(ip,d,key);
        if(value.size()>=size)throw std::runtime_error(std::string("Scientific text too long: ")+key);
        std::memcpy(dest,value.c_str(),value.size()+1);};
    copy(f.title_utf8,sizeof f.title_utf8,"title");copy(f.legend_utf8,sizeof f.legend_utf8,"legend");
    copy(f.scalar_label_utf8,sizeof f.scalar_label_utf8,"scalar_label");
    copy(f.axis_labels_utf8[0],256,"x_label");copy(f.axis_labels_utf8[1],256,"y_label");copy(f.axis_labels_utf8[2],256,"z_label");
    if(f.colorbar_visible){f.scalar_min=number(field(ip,d,"scalar_min"),"scalar min");f.scalar_max=number(field(ip,d,"scalar_max"),"scalar max");
        int n=0;Tcl_Obj** items=nullptr;
        if(Tcl_ListObjGetElements(ip,get(ip,d,"palette"),&n,&items)!=TCL_OK||n<2||n>256)throw std::runtime_error("Scientific palette requires 2..256 RGB entries");
        f.palette_count=n;for(int i=0;i<n;++i)f.palette[i]=rgb(str(items[i]),"scientific palette RGB");}
    check(gx3de_view_scientific_figure_set(state.view,&f),"set calibrated scientific figure");
    if(auto style=get(ip,d,"native_style")){Tcl_DictSearch search;Tcl_Obj*key;Tcl_Obj*value;int done;if(Tcl_DictObjFirst(ip,style,&search,&key,&value,&done)!=TCL_OK)throw std::runtime_error("Native scientific style must be a dictionary");for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){double x;if(Tcl_GetDoubleFromObj(ip,value,&x)!=TCL_OK){Tcl_DictObjDone(&search);throw std::runtime_error("Native scientific style must be finite numeric fields");}check(gx3de_view_scientific_style_set(state.view,Tcl_GetString(key),x),"apply scientific presentation style");}Tcl_DictObjDone(&search);}
    auto custom=get(ip,d,"tick_labels");int axes=0;Tcl_Obj** axisLists=nullptr;
    if(custom&&(Tcl_ListObjGetElements(ip,custom,&axes,&axisLists)!=TCL_OK||axes!=3))throw std::runtime_error("Scientific custom labels require three axes");
    for(int axis=0;axis<3;++axis){std::vector<const char*> labels;
        if(custom){int count;Tcl_Obj** items;if(Tcl_ListObjGetElements(ip,axisLists[axis],&count,&items)!=TCL_OK||count>64)throw std::runtime_error("Scientific axis label limit exceeded");for(int i=0;i<count;++i)labels.push_back(Tcl_GetString(items[i]));}
        check(gx3de_view_scientific_axis_labels_set(state.view,axis,labels.data(),labels.size()),"set scientific numeric axis labels");
    }

}
int viewportResize(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
    if(argc!=4){Tcl_WrongNumArgs(ip,1,args,"width height png");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        if(!state.target||!state.view)throw std::runtime_error("Render a scene before resize");
        uint32_t w=integer(str(args[1]),"viewport width"),h=integer(str(args[2]),"viewport height");
        if(w<16||h<16||w>4096||h>4096)throw std::runtime_error("Viewport requires 16..4096 pixels per side");
        check(gx3de_viewport_destroy(state.viewport),"release old viewport");state.viewport=nullptr;
        check(gx3de_target_resize(state.target,w,h,w,h),"resize render target");
        check(gx3de_viewport_create(state.target,state.view,0,0,w,h,&state.viewport),"resize shared viewport");
        checkRender(state.target,gx3de_target_render(state.target),"render enlarged viewport");
        check(gx3de_target_write_png(state.target,str(args[3]).c_str()),"write resized viewport");
        Tcl_Obj* result=Tcl_NewDictObj();put(ip,result,"width",Tcl_NewIntObj(w));put(ip,result,"height",Tcl_NewIntObj(h));
        putRendererInfo(ip,result,state.target);Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
int scientificAxes(ClientData data,Tcl_Interp* ip,int argc,Tcl_Obj* const args[]) {
    if(argc!=3){Tcl_WrongNumArgs(ip,1,args,"visible png");return TCL_ERROR;}
    auto& state=*static_cast<State*>(data);
    try{
        gx3de_scientific_figure f{};f.struct_size=sizeof f;
        check(gx3de_view_scientific_figure_get(state.view,&f),"read scientific figure");
        if(!f.enabled)throw std::runtime_error("Scene has no calibrated scientific figure");
        f.axes_grid_visible=yes(str(args[1]));check(gx3de_view_scientific_figure_set(state.view,&f),"toggle scientific axes/grid");
        checkRender(state.target,gx3de_target_render(state.target),"render scientific presentation");
        check(gx3de_target_write_png(state.target,str(args[2]).c_str()),"write scientific presentation");
        Tcl_Obj* result=Tcl_NewDictObj();put(ip,result,"axes_grid_visible",Tcl_NewIntObj(f.axes_grid_visible));
        putRendererInfo(ip,result,state.target);Tcl_SetObjResult(ip,result);return TCL_OK;
    }catch(const std::exception& e){error(ip,e);return TCL_ERROR;}
}
