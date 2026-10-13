/* SPDX-License-Identifier: GPL-3.0-or-later */
static Tcl_Obj *sk_geometry_obj(Tcl_Interp *ip,const gx2d_dimension_geometry *g){
    Tcl_Obj *r=Tcl_NewDictObj(),*lines=Tcl_NewListObj(0,NULL);for(size_t i=0;i+1<g->line_count;i+=2){Tcl_Obj *line=Tcl_NewListObj(0,NULL);Tcl_ListObjAppendElement(ip,line,point_obj(g->lines[i]));Tcl_ListObjAppendElement(ip,line,point_obj(g->lines[i+1]));Tcl_ListObjAppendElement(ip,lines,line);}
    Tcl_DictObjPut(ip,r,Tcl_NewStringObj("lines",-1),lines);Tcl_DictObjPut(ip,r,Tcl_NewStringObj("label",-1),point_obj(g->label));
    double bounds[4]={g->hit_bounds.x0,g->hit_bounds.y0,g->hit_bounds.x1,g->hit_bounds.y1};Tcl_Obj *rect=Tcl_NewListObj(0,NULL);for(int i=0;i<4;i++)Tcl_ListObjAppendElement(ip,rect,Tcl_NewDoubleObj(bounds[i]));
    Tcl_DictObjPut(ip,r,Tcl_NewStringObj("hit_bounds",-1),rect);Tcl_DictObjPut(ip,r,Tcl_NewStringObj("value",-1),Tcl_NewDoubleObj(g->value));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("driven",-1),Tcl_NewBooleanObj(g->driven));return r;
}
static int sketch_solver_command(gx2d_scene *s,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id;gx2d_status code;gx2d_point p;gx2d_constraint_v2 d;gx2d_dimension_geometry g;
    if(!strcmp(op,"sketch_component")){
        gx2d_id ids[64];size_t n;if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_sketch_component_ids(s,id,ids,64,&n))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *result=Tcl_NewListObj(0,NULL);for(size_t i=0;i<n;i++)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj(ids[i]));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"sketch_status")){
        gx2d_sketch_status state;if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_sketch_status_get(s,id,&state))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *r=Tcl_NewDictObj();Tcl_DictObjPut(ip,r,Tcl_NewStringObj("parameter_count",-1),Tcl_NewWideIntObj(state.parameters));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("rank",-1),Tcl_NewWideIntObj(state.rank));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("dof",-1),Tcl_NewWideIntObj(state.degrees_of_freedom));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("valid",-1),Tcl_NewBooleanObj(state.valid));Tcl_DictObjPut(ip,r,Tcl_NewStringObj("analysis_complete",-1),Tcl_NewBooleanObj(state.analysis_complete));Tcl_SetObjResult(ip,r);return TCL_OK;
    }
    if(!strcmp(op,"sketch_dimension_infer")){
        Tcl_Obj **items;int n;gx2d_reference refs[2];if(argc!=5||Tcl_ListObjGetElements(ip,argv[3],&n,&items)!=TCL_OK||n<1||n>2||read_point(ip,argv[4],&p)!=TCL_OK)return fail(ip,"Select one or two dimension references");
        for(int i=0;i<n;i++)if(reference_read(ip,items[i],&refs[i])!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_dimension_infer(s,refs,n,p,&d))!=TCL_OK)return TCL_ERROR;gx2d_constraint_diagnostic report={0};Tcl_SetObjResult(ip,constraint_obj(s,ip,0,&d,&report));return TCL_OK;
    }
    if(!strcmp(op,"sketch_dimension_apply")){
        int driven;if(argc!=7||index_arg(ip,argv[3],&id)!=TCL_OK||constraint_read(ip,argv[4],&d)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[5],&driven)!=TCL_OK||read_point(ip,argv[6],&p)!=TCL_OK)return fail(ip,"Usage: sketch_dimension_apply scene existing specification driven annotation");
        if(status(ip,gx2d_dimension_apply(s,id,&d,driven,p,&id))!=TCL_OK)return TCL_ERROR;gx2d_constraint_diagnostic report;gx2d_constraint_get(s,id,&d);gx2d_constraint_validate(s,id,&report);Tcl_SetObjResult(ip,constraint_obj(s,ip,id,&d,&report));return TCL_OK;
    }
    if(!strcmp(op,"sketch_dimension_preview")){
        if(argc!=5||constraint_read(ip,argv[3],&d)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK)return TCL_ERROR;code=gx2d_dimension_preview(s,&d,p,&g);
    }else if(!strcmp(op,"sketch_dimension_geometry")){
        if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;code=gx2d_dimension_primitives(s,id,&g);
    }else if(!strcmp(op,"sketch_relationship_hit_score")){
        gx2d_rect rect;double score;if(argc!=6||object_id(ip,argv[3],&id)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK||read_rect(ip,argv[5],&rect)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_relationship_hit_score(s,id,p,rect,&score))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewDoubleObj(score));return TCL_OK;
    }else if(!strcmp(op,"sketch_relationship_hit")){
        gx2d_rect rect;int hit;if(argc!=6||object_id(ip,argv[3],&id)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK||read_rect(ip,argv[5],&rect)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_relationship_hit(s,id,p,rect,&hit))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewBooleanObj(hit));return TCL_OK;
    }else if(!strcmp(op,"sketch_relationship")){
        gx2d_relationship_state state;if((argc!=4&&argc!=5)||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_relationship_get(s,id,&state))!=TCL_OK)return TCL_ERROR;
        if(argc==5){Tcl_Obj *f;
#define SBOOL(key,member) Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj(key,-1),&f);if(f&&Tcl_GetBooleanFromObj(ip,f,&state.member)!=TCL_OK)return TCL_ERROR
            SBOOL("solved",solved);SBOOL("driven",driven);SBOOL("placed",placed);
#undef SBOOL
            Tcl_DictObjGet(ip,argv[4],Tcl_NewStringObj("annotation",-1),&f);if(f&&read_point(ip,f,&state.annotation)!=TCL_OK)return TCL_ERROR;
            if(status(ip,gx2d_relationship_set(s,id,&state))!=TCL_OK)return TCL_ERROR;
        }
        gx2d_constraint_diagnostic report;gx2d_constraint_get(s,id,&d);gx2d_constraint_validate(s,id,&report);Tcl_SetObjResult(ip,constraint_obj(s,ip,id,&d,&report));return TCL_OK;
    }else return fail(ip,"Unknown sketch solver operation");
    if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,sk_geometry_obj(ip,&g));return TCL_OK;
}
