static int interaction_ids(Tcl_Interp *ip,Tcl_Obj *v,gx2d_id **out,size_t *count){
    Tcl_Obj **items;int n,i;if(Tcl_ListObjGetElements(ip,v,&n,&items)!=TCL_OK||n>65536)return fail(ip,"Too many exclusions");
    gx2d_id *ids=(gx2d_id *)malloc((n?n:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");
    for(i=0;i<n;++i)if(object_id(ip,items[i],&ids[i])!=TCL_OK){free(ids);return TCL_ERROR;}*out=ids;*count=n;return TCL_OK;
}
/* SPDX-License-Identifier: GPL-3.0-or-later */
static Tcl_Obj *reference_obj(Tcl_Interp *ip,const gx2d_reference *r){
    Tcl_Obj *v=Tcl_NewDictObj();const char *entities[]={"object","control","segment"};
    Tcl_DictObjPut(ip,v,Tcl_NewStringObj("object",-1),Tcl_NewWideIntObj(r->object));
    Tcl_DictObjPut(ip,v,Tcl_NewStringObj("entity",-1),Tcl_NewStringObj(entities[r->entity],-1));
    Tcl_DictObjPut(ip,v,Tcl_NewStringObj("index",-1),Tcl_NewWideIntObj(r->index));
    Tcl_DictObjPut(ip,v,Tcl_NewStringObj("epoch",-1),Tcl_NewWideIntObj(r->epoch));return v;
}
static int reference_read(Tcl_Interp *ip,Tcl_Obj *v,gx2d_reference *r){
    Tcl_Obj *field=NULL;Tcl_WideInt n;int i;const char *entities[]={"object","control","segment"};memset(r,0,sizeof(*r));
    if(Tcl_DictObjGet(ip,v,Tcl_NewStringObj("entity",-1),&field)!=TCL_OK||!field)return fail(ip,"Reference requires entity");
    for(i=0;i<3;++i)if(!strcmp(Tcl_GetString(field),entities[i]))break;if(i==3)return fail(ip,"Invalid reference entity");r->entity=(gx2d_entity)i;
#define RREAD(key,member) if(Tcl_DictObjGet(ip,v,Tcl_NewStringObj(key,-1),&field)!=TCL_OK||!field||Tcl_GetWideIntFromObj(ip,field,&n)!=TCL_OK||n<0)return fail(ip,"Invalid Native2D reference");r->member=n
    RREAD("object",object);RREAD("index",index);RREAD("epoch",epoch);
#undef RREAD
    return TCL_OK;
}
static int interaction_command(gx2d_scene *s,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id=0;gx2d_reference ref;gx2d_point p,q;gx2d_status code;Tcl_Obj *result;double tolerance;
    if(!strcmp(op,"interaction_constraint_values")){
        Tcl_DictSearch search;Tcl_Obj *key,*value;int done,n;gx2d_id *ids;double *values;size_t i=0;
        if(argc!=4||Tcl_DictObjSize(ip,argv[3],&n)!=TCL_OK||n>4096)return fail(ip,"Expected dimension ID/value dictionary");
        ids=malloc((n?n:1)*sizeof(*ids));values=malloc((n?n:1)*sizeof(*values));if(!ids||!values){free(ids);free(values);return fail(ip,"Out of memory");}
        Tcl_DictObjFirst(ip,argv[3],&search,&key,&value,&done);int valid=1;
        for(;!done;Tcl_DictObjNext(&search,&key,&value,&done)){if(object_id(ip,key,&ids[i])!=TCL_OK||Tcl_GetDoubleFromObj(ip,value,&values[i])!=TCL_OK){valid=0;break;}i++;}
        Tcl_DictObjDone(&search);gx2d_status result=valid?gx2d_constraint_values(s,ids,values,i):GX2D_INVALID;free(ids);free(values);return status(ip,result);
    }
    if(!strcmp(op,"interaction_from_fit")){
        Tcl_Obj **items;int n,i,f;double parameters[8];gx2d_point controls[4];gx2d_sketch_definition d;
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[4],&n,&items)!=TCL_OK||n>8)return fail(ip,"Usage: interaction_from_fit scene family numeric_parameters");
        for(f=0;f<12;++f)if(!strcmp(Tcl_GetString(argv[3]),sketch_names[f]))break;
        for(i=0;i<n;++i)if(Tcl_GetDoubleFromObj(ip,items[i],&parameters[i])!=TCL_OK)return TCL_ERROR;
        code=gx2d_sketch_from_fit((gx2d_sketch_family)(f+1),parameters,n,&d,controls,4);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,sketch_obj(ip,&d));return TCL_OK;
    }
    if(!strcmp(op,"interaction_construct")||!strcmp(op,"interaction_construct_preview")){
        gx2d_point *points,*controls;size_t n;gx2d_sketch_definition d;int i;
        if(argc!=5)return fail(ip,"Usage: interaction_construct scene family defining_points");
        for(i=0;i<12;++i)if(!strcmp(Tcl_GetString(argv[3]),sketch_names[i]))break;
        if(i==12)return fail(ip,"Unknown sketch family");if(point_list(ip,argv[4],&points,&n)!=TCL_OK)return TCL_ERROR;
        controls=(gx2d_point *)malloc(n*sizeof(*controls));if(!controls){free(points);return fail(ip,"Out of memory");}
        code=!strcmp(op,"interaction_construct_preview")?gx2d_sketch_preview_definition((gx2d_sketch_family)(i+1),points,n,&d,controls,n):gx2d_sketch_construct((gx2d_sketch_family)(i+1),points,n,&d,controls,n);free(points);
        if(code==GX2D_OK)Tcl_SetObjResult(ip,sketch_obj(ip,&d));free(controls);return status(ip,code);
    }
    if(!strcmp(op,"interaction_controls")){
        gx2d_control *controls;size_t n,i;const char *roles[]={"position","endpoint","center","radius","arc_start","arc_end","axis_x","axis_y","corner","bezier_control"};
        if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return fail(ip,"Usage: interaction_controls scene object");
        code=gx2d_sketch_controls(s,id,NULL,0,&n);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        controls=(gx2d_control *)malloc(n*sizeof(*controls));if(!controls)return fail(ip,"Out of memory");code=gx2d_sketch_controls(s,id,controls,n,&n);
        result=Tcl_NewListObj(0,NULL);if(code==GX2D_OK)for(i=0;i<n;++i){Tcl_Obj *v=reference_obj(ip,&controls[i].reference);Tcl_DictObjPut(ip,v,Tcl_NewStringObj("point",-1),point_obj(controls[i].point));Tcl_DictObjPut(ip,v,Tcl_NewStringObj("role",-1),Tcl_NewStringObj(roles[controls[i].role],-1));Tcl_ListObjAppendElement(ip,result,v);}
        free(controls);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"interaction_render")){
        gx2d_point points[129];size_t n;
        if(argc!=4||reference_read(ip,argv[3],&ref)!=TCL_OK)return fail(ip,"Usage: interaction_render scene segment_reference");
        if(status(ip,gx2d_reference_render(s,&ref,points,129,&n))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);for(size_t i=0;i<n;i++)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"interaction_reference")){
        size_t ordinal;int i;const char *entities[]={"object","control","segment"};
        if(argc!=6||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[5],&ordinal)!=TCL_OK)return fail(ip,"Usage: interaction_reference scene object entity ordinal");
        for(i=0;i<3;++i)if(!strcmp(Tcl_GetString(argv[4]),entities[i]))break;
        if(status(ip,gx2d_reference_create(s,id,(gx2d_entity)i,ordinal,&ref))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,reference_obj(ip,&ref));return TCL_OK;
    }
    if(!strcmp(op,"interaction_reference_index")){size_t index;
        if(argc!=5||object_id(ip,argv[3],&id)!=TCL_OK||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: interaction_reference_index scene object semantic_index");
        if(status(ip,gx2d_reference_from_index(s,id,index,&ref))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,reference_obj(ip,&ref));return TCL_OK;
    }
    if(!strcmp(op,"interaction_point_index")){size_t index;
        if(argc!=4||reference_read(ip,argv[3],&ref)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_reference_point_index(s,&ref,&index))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj(index));return TCL_OK;
    }
    if(!strcmp(op,"interaction_resolve")){
        if(argc!=4||reference_read(ip,argv[3],&ref)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_reference_resolve(s,&ref,&p))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,point_obj(p));return TCL_OK;
    }
    if(!strcmp(op,"interaction_pick")){
        if(argc!=6||object_id(ip,argv[3],&id)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&tolerance)!=TCL_OK)return fail(ip,"Usage: interaction_pick scene object device tolerance_px");
        code=gx2d_interaction_pick(s,id,p,tolerance,&ref);if(code==GX2D_NOT_FOUND){Tcl_SetObjResult(ip,Tcl_NewDictObj());return TCL_OK;}if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,reference_obj(ip,&ref));return TCL_OK;
    }
    if(!strcmp(op,"interaction_edit")||!strcmp(op,"interaction_edit_definition")){
        if(argc!=5||reference_read(ip,argv[3],&ref)!=TCL_OK||read_point(ip,argv[4],&p)!=TCL_OK)return fail(ip,"Usage: interaction_edit[_definition] scene reference world_target");
        if(!strcmp(op,"interaction_edit"))return status(ip,gx2d_control_edit(s,&ref,p));
        gx2d_sketch_definition *d=NULL;
        code=gx2d_control_definition_owned(s,&ref,p,&d);
        if(code==GX2D_OK)Tcl_SetObjResult(ip,sketch_obj(ip,d));
        gx2d_control_definition_release(d);return status(ip,code);
    }
    if(!strcmp(op,"interaction_snap")){
        gx2d_id *excluded;size_t n;int objects,grid,kind;
        if(argc!=8||read_point(ip,argv[3],&p)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&tolerance)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[6],&objects)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[7],&grid)!=TCL_OK)return fail(ip,"Usage: interaction_snap scene device tolerance excluded_ids object_snap grid_snap");
        if(interaction_ids(ip,argv[5],&excluded,&n)!=TCL_OK)return TCL_ERROR;code=gx2d_placement_snap(s,p,tolerance,excluded,n,objects,grid,&q,&kind,&ref);free(excluded);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point",-1),point_obj(q));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("kind",-1),Tcl_NewStringObj((const char *[]){"none","control","midpoint","grid","endpoint","center"}[kind],-1));
        if(kind==1||kind==2||kind==4||kind==5)Tcl_DictObjPut(ip,result,Tcl_NewStringObj("reference",-1),reference_obj(ip,&ref));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"interaction_constraints")){
        Tcl_Obj **items;int n,i;gx2d_reference refs[3];gx2d_constraint_v2 d;gx2d_constraint_diagnostic report={0};
        if(argc!=4||Tcl_ListObjGetElements(ip,argv[3],&n,&items)!=TCL_OK||n<1||n>3)return fail(ip,"Select one to three objects or defining controls");
        for(i=0;i<n;++i)if(reference_read(ip,items[i],&refs[i])!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();for(i=0;i<27;++i)if(gx2d_constraint_from_selection(s,(gx2d_constraint_kind)(i+1),refs,n,&d)==GX2D_OK){Tcl_Obj *v=constraint_obj(s,ip,0,&d,&report);Tcl_DictObjPut(ip,v,Tcl_NewStringObj("general_solver",-1),Tcl_NewBooleanObj(gx2d_sketch_get_definition(s,d.base.a,&(gx2d_sketch_definition){0})==GX2D_OK));Tcl_DictObjPut(ip,result,Tcl_NewStringObj(constraint_names[i],-1),v);}
        Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"interaction_constraint_location")){
        if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return fail(ip,"Usage: interaction_constraint_location scene constraint");
        if(status(ip,gx2d_constraint_location(s,id,&p))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,point_obj(p));return TCL_OK;
    }
    if(!strcmp(op,"interaction_constraint_apply")){
        gx2d_constraint_v2 d;gx2d_constraint_diagnostic report;
        if(argc!=5||index_arg(ip,argv[3],&id)!=TCL_OK||constraint_read(ip,argv[4],&d)!=TCL_OK)return fail(ip,"Usage: interaction_constraint_apply scene existing_constraint_or_0 specification");
        if(status(ip,gx2d_constraint_apply(s,id,&d,&id))!=TCL_OK||status(ip,gx2d_constraint_get(s,id,&d))!=TCL_OK||status(ip,gx2d_constraint_validate(s,id,&report))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,constraint_obj(s,ip,id,&d,&report));return TCL_OK;
    }
    if(!strcmp(op,"interaction_clip")){
        gx2d_point *points,a,b;size_t n,i;int shown;
        if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[4],&tolerance)!=TCL_OK)return fail(ip,"Usage: interaction_clip scene device_points inset_px");
        if(point_list(ip,argv[3],&points,&n)!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);Tcl_Obj *path=Tcl_NewListObj(0,NULL);Tcl_IncrRefCount(path);gx2d_point previous={0};int connected=0;
        for(i=1;i<n;++i){code=gx2d_viewport_clip_segment(s,points[i-1],points[i],tolerance,&a,&b,&shown);if(code!=GX2D_OK){free(points);Tcl_DecrRefCount(path);return status(ip,code);}
            if(shown){if(!connected||fabs(a.x-previous.x)>1e-7||fabs(a.y-previous.y)>1e-7){if(connected)Tcl_ListObjAppendElement(ip,result,path);Tcl_DecrRefCount(path);path=Tcl_NewListObj(0,NULL);Tcl_IncrRefCount(path);Tcl_ListObjAppendElement(ip,path,point_obj(a));}Tcl_ListObjAppendElement(ip,path,point_obj(b));previous=b;connected=1;}
            else if(connected){Tcl_ListObjAppendElement(ip,result,path);Tcl_DecrRefCount(path);path=Tcl_NewListObj(0,NULL);Tcl_IncrRefCount(path);connected=0;}}
        if(connected)Tcl_ListObjAppendElement(ip,result,path);Tcl_DecrRefCount(path);free(points);Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    return fail(ip,"Unknown Native2D interaction operation");
}
