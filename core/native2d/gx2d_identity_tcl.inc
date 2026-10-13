/* SPDX-License-Identifier: GPL-3.0-or-later */
static Tcl_Obj *fragment_obj(Tcl_Interp *ip,gx2d_id id,const gx2d_fragment *f){Tcl_Obj *r=Tcl_NewDictObj();
#define FPUT(key,value) Tcl_DictObjPut(ip,r,Tcl_NewStringObj(key,-1),value)
    FPUT("id",Tcl_NewWideIntObj((Tcl_WideInt)id));FPUT("parent",Tcl_NewWideIntObj((Tcl_WideInt)f->spec.parent));FPUT("parameter",Tcl_NewBooleanObj(f->spec.parameter));FPUT("first",Tcl_NewDoubleObj(f->spec.first));FPUT("last",Tcl_NewDoubleObj(f->spec.last));FPUT("topology_epoch",Tcl_NewWideIntObj((Tcl_WideInt)f->topology_epoch));FPUT("valid",Tcl_NewBooleanObj(f->valid));FPUT("missing",Tcl_NewBooleanObj(f->missing));
#undef FPUT
    return r;
}
static int fragment_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_fragment_spec *spec){Tcl_Obj *v;memset(spec,0,sizeof(*spec));
#define FGET(key) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(key,-1),&v)!=TCL_OK||!v)return fail(ip,"Fragment requires parent, parameter, first and last")
    FGET("parent");if(object_id(ip,v,&spec->parent)!=TCL_OK)return TCL_ERROR;FGET("parameter");if(Tcl_GetBooleanFromObj(ip,v,&spec->parameter)!=TCL_OK)return TCL_ERROR;FGET("first");if(Tcl_GetDoubleFromObj(ip,v,&spec->first)!=TCL_OK)return TCL_ERROR;FGET("last");if(Tcl_GetDoubleFromObj(ip,v,&spec->last)!=TCL_OK)return TCL_ERROR;
#undef FGET
    return TCL_OK;
}
static int identity_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){gx2d_id id=0,*ids;Tcl_Obj *result;gx2d_status code;size_t count,i;gx2d_fragment f;gx2d_fragment_spec spec;
    if(strcmp(op,"fragment_create")==0){if(argc!=4||fragment_read(ip,argv[3],&spec)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_fragment_create(scene,&spec,&id))!=TCL_OK)return TCL_ERROR;}
    else if(strcmp(op,"fragment_list")==0){if(argc!=3)return fail(ip,"Usage: core fragment_list scene");if(status(ip,gx2d_fragment_ids(scene,NULL,0,&count))!=TCL_OK)return TCL_ERROR;ids=(gx2d_id *)malloc((count?count:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");code=gx2d_fragment_ids(scene,ids,count,&count);result=Tcl_NewListObj(0,NULL);
        for(i=0;code==GX2D_OK&&i<count;++i){code=gx2d_fragment_get(scene,ids[i],&f);if(code==GX2D_OK)Tcl_ListObjAppendElement(ip,result,fragment_obj(ip,ids[i],&f));}free(ids);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;}
    else {
        Tcl_WideInt owner;if(argc<4||Tcl_GetWideIntFromObj(ip,argv[3],&owner)!=TCL_OK||owner<0)return fail(ip,"Identity owner must be a nonnegative native ID (0 means scene)");id=(gx2d_id)owner;
        if(strcmp(op,"identity_geometry_role")==0){gx2d_geometry_role role;const char *names[]={"regular","construction","reference"};
            if(argc==5){const char *value=Tcl_GetString(argv[4]);int match=-1,k;for(k=0;k<3;++k)if(!strcmp(value,names[k]))match=k;if(match<0)return fail(ip,"Geometry role must be regular, construction or reference");if(status(ip,gx2d_geometry_role_set(scene,id,(gx2d_geometry_role)match))!=TCL_OK)return TCL_ERROR;}
            else if(argc!=4)return fail(ip,"Usage: core identity_geometry_role scene object ?role?");
            if(status(ip,gx2d_geometry_role_get(scene,id,&role))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewStringObj(names[(int)role],-1));return TCL_OK;
        }
        if(strcmp(op,"identity_attributes")==0){const char **keys,*value;if(argc!=4)return fail(ip,"Usage: core identity_attributes scene owner");if(status(ip,gx2d_attribute_keys(scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;
            keys=(const char **)malloc((count?count:1)*sizeof(*keys));if(!keys)return fail(ip,"Out of memory");code=gx2d_attribute_keys(scene,id,keys,count,&count);result=Tcl_NewDictObj();for(i=0;code==GX2D_OK&&i<count;++i){code=gx2d_attribute_get(scene,id,keys[i],&value);if(code==GX2D_OK)Tcl_DictObjPut(ip,result,Tcl_NewStringObj(keys[i],-1),Tcl_NewStringObj(value,-1));}free(keys);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;}
        if(strcmp(op,"identity_name")==0){const char *name;if(argc==5){if(status(ip,gx2d_set_name(scene,id,Tcl_GetString(argv[4])))!=TCL_OK)return TCL_ERROR;}else if(argc!=4)return fail(ip,"Usage: core identity_name scene owner ?name?");code=gx2d_get_name(scene,id,&name);if(code==GX2D_NOT_FOUND){if(status(ip,gx2d_attribute_keys(scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewStringObj("",0));return TCL_OK;}if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewStringObj(name,-1));return TCL_OK;}
        if(strcmp(op,"identity_attribute")==0){const char *value;if(argc==6)return status(ip,gx2d_attribute_set(scene,id,Tcl_GetString(argv[4]),Tcl_GetString(argv[5])));if(argc!=5)return fail(ip,"Usage: core identity_attribute scene owner key ?value?");if(status(ip,gx2d_attribute_get(scene,id,Tcl_GetString(argv[4]),&value))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewStringObj(value,-1));return TCL_OK;}
        if(strcmp(op,"identity_attribute_remove")==0){if(argc!=5)return fail(ip,"Usage: core identity_attribute_remove scene owner key");return status(ip,gx2d_attribute_remove(scene,id,Tcl_GetString(argv[4])));}
        if(strcmp(op,"identity_topology_epoch")==0){uint64_t epoch;if(argc!=4)return fail(ip,"Usage: core identity_topology_epoch scene object");if(status(ip,gx2d_object_topology_epoch(scene,id,&epoch))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)epoch));return TCL_OK;}
        if(strcmp(op,"fragment_update")==0){if(argc!=5||fragment_read(ip,argv[4],&spec)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_fragment_update(scene,id,&spec))!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"fragment_delete")==0){if(argc!=4)return fail(ip,"Usage: core fragment_delete scene fragment");return status(ip,gx2d_fragment_delete(scene,id));}
        else if(strcmp(op,"fragment_sample")==0){gx2d_point *points;size_t total,start;if(argc!=7||index_arg(ip,argv[4],&total)!=TCL_OK||index_arg(ip,argv[5],&start)!=TCL_OK||index_arg(ip,argv[6],&count)!=TCL_OK||count>65536)return fail(ip,"Usage: core fragment_sample scene fragment total start count <=65536");points=(gx2d_point *)malloc((count?count:1)*sizeof(*points));if(!points)return fail(ip,"Out of memory");code=gx2d_fragment_sample(scene,id,total,start,count,points,count);result=Tcl_NewListObj(0,NULL);for(i=0;code==GX2D_OK&&i<count;++i)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));free(points);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;}
        else if(strcmp(op,"fragment_materialize")==0){size_t total;gx2d_id object;if(argc!=5||index_arg(ip,argv[4],&total)!=TCL_OK)return fail(ip,"Usage: core fragment_materialize scene fragment total");if(status(ip,gx2d_fragment_materialize(scene,id,total,&object))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)object));return TCL_OK;}
        else if(strcmp(op,"fragment_length")==0){double length;if(argc!=4)return fail(ip,"Usage: core fragment_length scene fragment");if(status(ip,gx2d_fragment_length(scene,id,&length))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewDoubleObj(length));return TCL_OK;}
        else if(strcmp(op,"fragment_bounds")==0){gx2d_rect bounds;size_t samples=257;if((argc!=4&&argc!=5)||(argc==5&&index_arg(ip,argv[4],&samples)!=TCL_OK))return fail(ip,"Usage: core fragment_bounds scene fragment ?linear_sampling_count?");if(status(ip,gx2d_fragment_bounds(scene,id,samples,&bounds))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,rect_obj(bounds));return TCL_OK;}
        else if(strcmp(op,"fragment_get")!=0||argc!=4)return fail(ip,"Unknown identity/fragment operation or wrong arguments");
    }
    if(status(ip,gx2d_fragment_get(scene,id,&f))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,fragment_obj(ip,id,&f));return TCL_OK;
}
