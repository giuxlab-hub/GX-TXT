/* SPDX-License-Identifier: GPL-3.0-or-later */
static int image_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_reference_image *v){
    memset(v,0,sizeof(*v));v->scale=1;v->opacity=1;v->visible=1;Tcl_Obj *field=NULL;
#define IMAGE_FIELD(name) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(name,-1),&field)!=TCL_OK)return TCL_ERROR
#define IMAGE_DOUBLE(name) IMAGE_FIELD(#name);if(field&&Tcl_GetDoubleFromObj(ip,field,&v->name)!=TCL_OK)return TCL_ERROR
#define IMAGE_BOOL(name) IMAGE_FIELD(#name);if(field&&Tcl_GetBooleanFromObj(ip,field,&v->name)!=TCL_OK)return TCL_ERROR
    IMAGE_FIELD("resource_id");if(!field||strlen(Tcl_GetString(field))>=sizeof(v->resource_id))return fail(ip,"Image requires bounded resource identity");strcpy(v->resource_id,Tcl_GetString(field));
    IMAGE_FIELD("length_unit");if(!field||strlen(Tcl_GetString(field))>=sizeof(v->length_unit))return fail(ip,"Image requires declared working length unit");strcpy(v->length_unit,Tcl_GetString(field));
    IMAGE_DOUBLE(width);IMAGE_DOUBLE(height);IMAGE_DOUBLE(scale);IMAGE_DOUBLE(rotation);IMAGE_DOUBLE(opacity);IMAGE_DOUBLE(calibrated_distance);
    IMAGE_BOOL(visible);IMAGE_BOOL(locked);IMAGE_BOOL(calibrated);
    IMAGE_FIELD("translation");if(field&&read_point(ip,field,&v->translation)!=TCL_OK)return TCL_ERROR;
    IMAGE_FIELD("calibration");if(field){Tcl_Obj **rows;int n;if(Tcl_ListObjGetElements(ip,field,&n,&rows)!=TCL_OK||n!=2||read_point(ip,rows[0],&v->calibration[0])!=TCL_OK||read_point(ip,rows[1],&v->calibration[1])!=TCL_OK)return fail(ip,"Image calibration requires two XY pixel points");}
#undef IMAGE_FIELD
#undef IMAGE_DOUBLE
#undef IMAGE_BOOL
    return TCL_OK;
}
static Tcl_Obj *image_obj(Tcl_Interp *ip,const gx2d_reference_image *v){
    Tcl_Obj *result=Tcl_NewDictObj();
#define IMAGE_PUT(name,value) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(name,-1),value)
#define IMAGE_NUMBER(name) IMAGE_PUT(#name,Tcl_NewDoubleObj(v->name))
#define IMAGE_BOOLEAN(name) IMAGE_PUT(#name,Tcl_NewBooleanObj(v->name))
    IMAGE_PUT("resource_id",Tcl_NewStringObj(v->resource_id,-1));IMAGE_PUT("length_unit",Tcl_NewStringObj(v->length_unit,-1));
    IMAGE_NUMBER(width);IMAGE_NUMBER(height);IMAGE_NUMBER(scale);IMAGE_NUMBER(rotation);IMAGE_NUMBER(opacity);IMAGE_NUMBER(calibrated_distance);
    IMAGE_BOOLEAN(visible);IMAGE_BOOLEAN(locked);IMAGE_BOOLEAN(calibrated);IMAGE_PUT("translation",point_obj(v->translation));
    Tcl_Obj *points[2]={point_obj(v->calibration[0]),point_obj(v->calibration[1])};IMAGE_PUT("calibration",Tcl_NewListObj(2,points));
#undef IMAGE_PUT
#undef IMAGE_NUMBER
#undef IMAGE_BOOLEAN
    return result;
}
static int image_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id;gx2d_reference_image v;gx2d_point a,b,q;gx2d_status code;double distance;int inverse;
    if(strcmp(op,"image_create")==0){if(argc!=4||image_read(ip,argv[3],&v)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_image_create(scene,&v,&id))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj(id));return TCL_OK;}
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
    if(strcmp(op,"image_map")==0){if(argc!=6||read_point(ip,argv[4],&a)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[5],&inverse)!=TCL_OK)return fail(ip,"Usage: core image_map scene image point inverse");if(status(ip,gx2d_image_map(scene,id,a,inverse,&q))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,point_obj(q));return TCL_OK;}
    if(strcmp(op,"image_update")==0){if(argc!=5||image_read(ip,argv[4],&v)!=TCL_OK)return TCL_ERROR;code=gx2d_image_update(scene,id,&v);if(status(ip,code)!=TCL_OK)return TCL_ERROR;}
    else if(strcmp(op,"image_calibrate")==0){if(argc!=7||read_point(ip,argv[4],&a)!=TCL_OK||read_point(ip,argv[5],&b)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[6],&distance)!=TCL_OK)return fail(ip,"Usage: core image_calibrate scene image pixel_a pixel_b physical_distance");if(status(ip,gx2d_image_calibrate(scene,id,a,b,distance))!=TCL_OK)return TCL_ERROR;}
    else if(strcmp(op,"image_get")||argc!=4)return fail(ip,"Unknown image operation");
    code=gx2d_image_get(scene,id,&v);if(code==GX2D_INVALID){Tcl_SetObjResult(ip,Tcl_NewDictObj());return TCL_OK;}
    if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,image_obj(ip,&v));return TCL_OK;
}
