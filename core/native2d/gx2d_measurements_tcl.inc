/* SPDX-License-Identifier: GPL-3.0-or-later */
static const char *measurement_names[]={"point_distance","horizontal_distance","vertical_distance","segment_length","segment_angle","tangent_angle","path_length","radius","diameter","arc_angle","bounding_width","bounding_height","signed_area","point_curve_distance","object_distance"};
static int measurement_command(gx2d_scene *scene,Tcl_Interp *ip,int argc,Tcl_Obj *const argv[]) {
    gx2d_measurement_spec spec;gx2d_measurement value;Tcl_Obj *field=NULL,*result;const char *kind;int i;
    memset(&spec,0,sizeof(spec));if(argc!=4)return fail(ip,"Usage: core measure scene request");
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("kind",-1),&field)!=TCL_OK||!field)return fail(ip,"Measurement requires kind");kind=Tcl_GetString(field);
    for(i=0;i<15;++i)if(strcmp(kind,measurement_names[i])==0)break;if(i==15)return fail(ip,"Unknown Native2D measurement kind");spec.kind=(gx2d_measurement_kind)(GX2D_MEASURE_POINT_DISTANCE+i);
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("a",-1),&field)!=TCL_OK||!field||object_id(ip,field,&spec.a)!=TCL_OK)return fail(ip,"Measurement requires object a");
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("b",-1),&field)!=TCL_OK)return TCL_ERROR;if(field&&object_id(ip,field,&spec.b)!=TCL_OK)return TCL_ERROR;
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("a_index",-1),&field)!=TCL_OK)return TCL_ERROR;if(field&&index_arg(ip,field,&spec.a_index)!=TCL_OK)return TCL_ERROR;
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("b_index",-1),&field)!=TCL_OK)return TCL_ERROR;if(field&&index_arg(ip,field,&spec.b_index)!=TCL_OK)return TCL_ERROR;
    if(Tcl_DictObjGet(ip,argv[3],Tcl_NewStringObj("pair_budget",-1),&field)!=TCL_OK)return TCL_ERROR;if(field&&index_arg(ip,field,&spec.pair_budget)!=TCL_OK)return TCL_ERROR;
    if(status(ip,gx2d_measure(scene,&spec,&value))!=TCL_OK)return TCL_ERROR;
    result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("value",-1),Tcl_NewDoubleObj(value.value));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("unit_power",-1),Tcl_NewIntObj(value.unit_power));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("angular",-1),Tcl_NewBooleanObj(value.angular));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("exact",-1),Tcl_NewBooleanObj(value.exact));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point_a",-1),point_obj(value.point_a));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point_b",-1),point_obj(value.point_b));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("policy",-1),Tcl_NewStringObj(value.policy,-1));Tcl_SetObjResult(ip,result);return TCL_OK;
}
