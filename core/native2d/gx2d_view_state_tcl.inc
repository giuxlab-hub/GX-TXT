/* SPDX-License-Identifier: GPL-3.0-or-later */
static Tcl_Obj *view_state_obj(Tcl_Interp *ip,const gx2d_view_state *state,Tcl_Obj *axis){Tcl_Obj *r=Tcl_NewDictObj(),*view=Tcl_NewListObj(0,NULL);const gx2d_view *v=&state->view;
    double fields[]={v->width,v->height,v->left,v->top,v->right,v->bottom};size_t i;for(i=0;i<6;++i)Tcl_ListObjAppendElement(ip,view,Tcl_NewDoubleObj(fields[i]));Tcl_ListObjAppendElement(ip,view,rect_obj(v->world));
#define VPUT(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),value)
    VPUT("axis_presentation",axis?axis:Tcl_NewDictObj());VPUT("viewport",view);VPUT("grid",grid_obj(state->grid));VPUT("background",color_obj(state->background));VPUT("aspect",Tcl_NewStringObj(state->aspect==GX2D_ASPECT_AUTO?"auto":"xy_equal",-1));VPUT("polar",polar_obj(state->polar));VPUT("coordinate_mode",Tcl_NewStringObj(state->coordinate_mode==GX2D_POLAR?"polar":"cartesian",-1));
#undef VPUT
    return r;
}
static int view_state_read(Tcl_Interp *ip,Tcl_Obj *input,gx2d_view_state *state){Tcl_Obj *value,**items;int n;const char *mode;
#define VGET(key) if(Tcl_DictObjGet(ip,input,Tcl_NewStringObj(key,-1),&value)!=TCL_OK||!value)return fail(ip,"View state requires viewport, grid, background, aspect, polar, coordinate_mode")
    VGET("viewport");if(Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK||n!=7)return fail(ip,"Viewport requires six dimensions/margins and world bounds");
    double *fields[]={&state->view.width,&state->view.height,&state->view.left,&state->view.top,&state->view.right,&state->view.bottom};int i;for(i=0;i<6;++i)if(Tcl_GetDoubleFromObj(ip,items[i],fields[i])!=TCL_OK)return TCL_ERROR;if(read_rect(ip,items[6],&state->view.world)!=TCL_OK)return TCL_ERROR;
    VGET("grid");if(grid_read(ip,value,&state->grid)!=TCL_OK)return TCL_ERROR;VGET("background");if(read_color(ip,value,&state->background)!=TCL_OK)return TCL_ERROR;VGET("polar");if(polar_read(ip,value,&state->polar)!=TCL_OK)return TCL_ERROR;VGET("coordinate_mode");if(coordinate_mode_read(ip,value,&state->coordinate_mode)!=TCL_OK)return TCL_ERROR;
    VGET("aspect");mode=Tcl_GetString(value);if(!strcmp(mode,"auto"))state->aspect=GX2D_ASPECT_AUTO;else if(!strcmp(mode,"xy_equal"))state->aspect=GX2D_ASPECT_XY_EQUAL;else return fail(ip,"Aspect must be auto or xy_equal");
#undef VGET
    return TCL_OK;
}
/* Presentation metadata belongs to the Tcl scene host, preserving the C ABI.
 * The trusted CORE validator owns units/image mapping and bounded formatting. */
static int axis_presentation_validate(scene_node *node,Tcl_Interp *ip,Tcl_Obj *input,Tcl_Obj **result){
    Tcl_CmdInfo info;int size;Tcl_Obj *args[3];
    if(Tcl_DictObjSize(ip,input,&size)!=TCL_OK)return TCL_ERROR;
    if(size==0){*result=Tcl_NewDictObj();Tcl_IncrRefCount(*result);return TCL_OK;}
    if(!Tcl_GetCommandInfo(ip,"::GX::native2DAxisPresentationValidate",&info))return fail(ip,"CORE axis presentation validator is unavailable");
    args[0]=Tcl_NewStringObj("::GX::native2DAxisPresentationValidate",-1);
    args[1]=Tcl_NewWideIntObj((Tcl_WideInt)node->serial);args[2]=input;
    for(int i=0;i<3;++i)Tcl_IncrRefCount(args[i]);
    int code=Tcl_EvalObjv(ip,3,args,TCL_EVAL_GLOBAL);
    for(int i=0;i<3;++i)Tcl_DecrRefCount(args[i]);
    if(code!=TCL_OK)return code;
    *result=Tcl_DuplicateObj(Tcl_GetObjResult(ip));Tcl_IncrRefCount(*result);return TCL_OK;
}
static void axis_presentation_commit(scene_node *node,Tcl_Obj *axis){
    Tcl_IncrRefCount(axis);if(node->axis_presentation)Tcl_DecrRefCount(node->axis_presentation);node->axis_presentation=axis;
}
static int axis_presentation_command(scene_node *node,Tcl_Interp *ip,int argc,Tcl_Obj *const argv[]){
    if(argc==4){Tcl_Obj *axis=NULL;if(axis_presentation_validate(node,ip,argv[3],&axis)!=TCL_OK)return TCL_ERROR;axis_presentation_commit(node,axis);Tcl_DecrRefCount(axis);}
    else if(argc!=3)return fail(ip,"Usage: core axis_presentation scene ?descriptor?");
    Tcl_SetObjResult(ip,node->axis_presentation?node->axis_presentation:Tcl_NewDictObj());return TCL_OK;
}
static int view_state_command(scene_node *node,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_view_state state,result;double factor;Tcl_Obj *axis=NULL,*input=NULL;
    if(status(ip,gx2d_view_state_get(node->scene,&state))!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"view_state_rescale")){
        if(argc!=5||view_state_read(ip,argv[3],&state)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&factor)!=TCL_OK)return fail(ip,"Usage: core view_state_rescale scene state factor");
        if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("axis_presentation",-1),&input)!=TCL_OK)return TCL_ERROR;
        int axis_size=0;if(input&&Tcl_DictObjSize(ip,input,&axis_size)!=TCL_OK)return TCL_ERROR;
        if(input&&axis_size>0){
            Tcl_Obj *args[4]={Tcl_NewStringObj("::GX::native2DAxisPresentationRescale",-1),Tcl_NewWideIntObj((Tcl_WideInt)node->serial),input,Tcl_NewDoubleObj(factor)};
            for(int i=0;i<4;++i)Tcl_IncrRefCount(args[i]);
            int code=Tcl_EvalObjv(ip,4,args,TCL_EVAL_GLOBAL);
            for(int i=0;i<4;++i)Tcl_DecrRefCount(args[i]);
            if(code!=TCL_OK)return code;
            axis=Tcl_DuplicateObj(Tcl_GetObjResult(ip));Tcl_IncrRefCount(axis);
        }else{axis=Tcl_NewDictObj();Tcl_IncrRefCount(axis);}
        if(status(ip,gx2d_view_state_rescale(&state,factor,&result))!=TCL_OK){Tcl_DecrRefCount(axis);return TCL_ERROR;}state=result;
    }else if(argc==4){
        if(view_state_read(ip,argv[3],&state)!=TCL_OK)return TCL_ERROR;
        if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("axis_presentation",-1),&input)!=TCL_OK)return TCL_ERROR;
        if(!input){axis=Tcl_NewDictObj();Tcl_IncrRefCount(axis);}
        else if(axis_presentation_validate(node,ip,input,&axis)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_view_state_set(node->scene,&state))!=TCL_OK){Tcl_DecrRefCount(axis);return TCL_ERROR;}
        axis_presentation_commit(node,axis);
    }else if(argc!=3)return fail(ip,"Usage: core view_state scene ?state?");
    if(!axis){axis=node->axis_presentation?node->axis_presentation:Tcl_NewDictObj();Tcl_IncrRefCount(axis);}
    Tcl_SetObjResult(ip,view_state_obj(ip,&state,axis));Tcl_DecrRefCount(axis);return TCL_OK;
}
