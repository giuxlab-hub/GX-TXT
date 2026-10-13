/* SPDX-License-Identifier: GPL-3.0-or-later */
static const char *constraint_names[]={"fixed","distance","angle","parallel","perpendicular","coincident","horizontal","vertical","equal_length","equal_radius","tangent","concentric","collinear","midpoint","point_on_line","point_on_curve","symmetry","radius","diameter","lock_x","lock_y","horizontal_distance","vertical_distance","point_line_distance","line_distance","axis_angle","curvature"};
static int constraint_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_constraint_v2 *d) {
    Tcl_Obj *field=NULL;const char *kind;int i,flag;
    memset(d,0,sizeof(*d));d->base.tolerance=1e-8;d->angular_tolerance=1e-9;
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("kind",-1),&field)!=TCL_OK||!field)return fail(ip,"Constraint requires kind");
    kind=Tcl_GetString(field);for(i=0;i<27;++i)if(strcmp(kind,constraint_names[i])==0)break;if(i==27)return fail(ip,"Unknown Native2D constraint kind");d->base.kind=(gx2d_constraint_kind)(GX2D_FIXED+i);
#define CONSTRAINT_ID(key,member,required) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(key,-1),&field)!=TCL_OK)return TCL_ERROR; if(field){Tcl_WideInt n;if(Tcl_GetWideIntFromObj(ip,field,&n)!=TCL_OK||n<0)return fail(ip,"Constraint object IDs must be nonnegative");d->member=(gx2d_id)n;}else if(required)return fail(ip,"Constraint requires object a")
#define CONSTRAINT_INDEX(key,member) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(key,-1),&field)!=TCL_OK)return TCL_ERROR; if(field&&index_arg(ip,field,&d->member)!=TCL_OK)return TCL_ERROR
#define CONSTRAINT_NUMBER(key,member) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(key,-1),&field)!=TCL_OK)return TCL_ERROR; if(field&&Tcl_GetDoubleFromObj(ip,field,&d->member)!=TCL_OK)return TCL_ERROR
    CONSTRAINT_ID("a",base.a,1);CONSTRAINT_ID("b",base.b,0);CONSTRAINT_ID("axis",axis,0);
    CONSTRAINT_INDEX("a_index",base.a_index);CONSTRAINT_INDEX("b_index",base.b_index);CONSTRAINT_INDEX("axis_index",axis_index);
    CONSTRAINT_NUMBER("value",base.value);CONSTRAINT_NUMBER("tolerance",base.tolerance);CONSTRAINT_NUMBER("angular_tolerance",angular_tolerance);
#undef CONSTRAINT_ID
#undef CONSTRAINT_INDEX
#undef CONSTRAINT_NUMBER
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("disabled",-1),&field)!=TCL_OK)return TCL_ERROR;if(field){if(Tcl_GetBooleanFromObj(ip,field,&flag)!=TCL_OK)return TCL_ERROR;d->disabled=flag;}
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("anchor",-1),&field)!=TCL_OK)return TCL_ERROR;if(field){if(read_point(ip,field,&d->anchor)!=TCL_OK)return TCL_ERROR;d->anchor_valid=1;}
    return TCL_OK;
}
static Tcl_Obj *constraint_obj(gx2d_scene *scene,Tcl_Interp *ip,gx2d_id id,const gx2d_constraint_v2 *d,const gx2d_constraint_diagnostic *report) {
    Tcl_Obj *r=Tcl_NewDictObj();
#define CPUT_ID(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),Tcl_NewWideIntObj((Tcl_WideInt)(value)))
#define CPUT_DOUBLE(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),Tcl_NewDoubleObj(value))
#define CPUT_BOOL(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),Tcl_NewBooleanObj(value))
    gx2d_relationship_state state={0};if(id)gx2d_relationship_get(scene,id,&state);
    CPUT_DOUBLE("curvature_tolerance",state.curvature_tolerance>0?state.curvature_tolerance:1e-8);
    CPUT_BOOL("solved",state.solved);CPUT_BOOL("driven",state.driven);CPUT_BOOL("placed",state.placed);Tcl_DictObjPut(ip,r,Tcl_NewStringObj("branch",-1),Tcl_NewIntObj(state.branch));
    Tcl_DictObjPut(ip,r,Tcl_NewStringObj("annotation",-1),point_obj(state.annotation));
    CPUT_ID("id",id);CPUT_ID("a",d->base.a);CPUT_ID("b",d->base.b);CPUT_ID("axis",d->axis);CPUT_ID("a_index",d->base.a_index);CPUT_ID("b_index",d->base.b_index);CPUT_ID("axis_index",d->axis_index);
    Tcl_DictObjPut(ip,r,Tcl_NewStringObj("kind",-1),Tcl_NewStringObj(constraint_names[d->base.kind-GX2D_FIXED],-1));
    CPUT_DOUBLE("value",d->base.value);CPUT_DOUBLE("tolerance",d->base.tolerance);CPUT_DOUBLE("angular_tolerance",d->angular_tolerance);
    CPUT_BOOL("disabled",d->disabled);Tcl_DictObjPut(ip,r,Tcl_NewStringObj("anchor",-1),point_obj(d->anchor));
    CPUT_BOOL("valid",report->valid);CPUT_BOOL("geometry_supported",report->geometry_supported);CPUT_DOUBLE("measured_value",report->value);CPUT_DOUBLE("residual",report->residual);CPUT_DOUBLE("angular_residual",report->angular_residual);
    Tcl_DictObjPut(ip,r,Tcl_NewStringObj("enforcement",-1),Tcl_NewStringObj(d->disabled?"disabled":state.driven?"reference_measurement":state.solved?"retained_component_solver":"native_mutation_validation",-1));CPUT_BOOL("general_solver",state.solved);
#undef CPUT_ID
#undef CPUT_DOUBLE
#undef CPUT_BOOL
    return r;
}
static int constraint_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]) {
    gx2d_constraint_v2 definition;gx2d_constraint_diagnostic report;gx2d_id id=0,*ids=NULL;size_t count,i;int enabled;gx2d_status code;Tcl_Obj *result;
    if(strcmp(op,"constraint_join")==0){gx2d_id a,b;size_t ai,bi;int merge;double tolerance;
        if(argc!=9||object_id(ip,argv[3],&a)!=TCL_OK||index_arg(ip,argv[4],&ai)!=TCL_OK||object_id(ip,argv[5],&b)!=TCL_OK||index_arg(ip,argv[6],&bi)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[7],&merge)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[8],&tolerance)!=TCL_OK)return fail(ip,"Usage: core constraint_join scene a a_index b b_index merge tolerance");
        if(status(ip,gx2d_join_points(scene,a,ai,b,bi,merge,tolerance,&id))!=TCL_OK)return TCL_ERROR;
    } else
    if(strcmp(op,"constraint_create")==0){if(argc!=4||constraint_read(ip,argv[3],&definition)!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *field;int solved=0,driven=0,placed=0,branch=0;gx2d_point annotation={0};double curvature_tolerance=1e-8;
        Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("solved",-1),&field);if(field&&Tcl_GetBooleanFromObj(ip,field,&solved)!=TCL_OK)return TCL_ERROR;
        if(solved){
            Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("driven",-1),&field);if(field&&Tcl_GetBooleanFromObj(ip,field,&driven)!=TCL_OK)return TCL_ERROR;
            Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("placed",-1),&field);if(field&&Tcl_GetBooleanFromObj(ip,field,&placed)!=TCL_OK)return TCL_ERROR;
            Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("annotation",-1),&field);if(field&&read_point(ip,field,&annotation)!=TCL_OK)return TCL_ERROR;
            Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("branch",-1),&field);if(field&&Tcl_GetIntFromObj(ip,field,&branch)!=TCL_OK)return TCL_ERROR;
            Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("curvature_tolerance",-1),&field);if(field&&Tcl_GetDoubleFromObj(ip,field,&curvature_tolerance)!=TCL_OK)return TCL_ERROR;
            gx2d_relationship_state state={1,driven,placed,annotation,branch,curvature_tolerance};if(status(ip,gx2d_constraint_create_state(scene,&definition,&state,&id))!=TCL_OK)return TCL_ERROR;
        }else if(status(ip,gx2d_constraint_create(scene,&definition,&id))!=TCL_OK)return TCL_ERROR;}
    else if(strcmp(op,"constraint_list")==0){if(argc!=3)return fail(ip,"Usage: core constraint_list scene");
        if(status(ip,gx2d_constraint_ids(scene,NULL,0,&count))!=TCL_OK)return TCL_ERROR;if(count>4096)return fail(ip,"Constraint inspection list exceeds 4096; use the public native IDs/get buffer APIs");
        ids=(gx2d_id *)malloc((count?count:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");code=gx2d_constraint_ids(scene,ids,count,&count);if(status(ip,code)!=TCL_OK){free(ids);return TCL_ERROR;}
        result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i){code=gx2d_constraint_get(scene,ids[i],&definition);if(code==GX2D_OK)code=gx2d_constraint_validate(scene,ids[i],&report);if(status(ip,code)!=TCL_OK){free(ids);return TCL_ERROR;}Tcl_ListObjAppendElement(ip,result,constraint_obj(scene,ip,ids[i],&definition,&report));}
        free(ids);Tcl_SetObjResult(ip,result);return TCL_OK;
    } else {if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"constraint_update")==0){if(argc!=5||constraint_read(ip,argv[4],&definition)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_constraint_update(scene,id,&definition))!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"constraint_enable")==0){if(argc!=5||Tcl_GetBooleanFromObj(ip,argv[4],&enabled)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_constraint_enable(scene,id,enabled))!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"constraint_delete")==0){if(argc!=4)return fail(ip,"Usage: core constraint_delete scene constraint");return status(ip,gx2d_remove_constraint(scene,id));}
        else if(strcmp(op,"constraint_get")!=0||argc!=4)return fail(ip,"Unknown Native2D constraint operation or wrong arguments");
    }
    if(status(ip,gx2d_constraint_get(scene,id,&definition))!=TCL_OK||status(ip,gx2d_constraint_validate(scene,id,&report))!=TCL_OK)return TCL_ERROR;
    Tcl_SetObjResult(ip,constraint_obj(scene,ip,id,&definition,&report));return TCL_OK;
}
