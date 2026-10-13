/* SPDX-License-Identifier: GPL-3.0-or-later */
static Tcl_Obj *layer_style_obj(Tcl_Interp *ip,const gx2d_layer_style *style){Tcl_Obj *result=Tcl_NewDictObj();
#define LPUT(key,value) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(key,-1),value)
    LPUT("visible",Tcl_NewBooleanObj(style->visible));LPUT("selectable",Tcl_NewBooleanObj(style->selectable));LPUT("locked",Tcl_NewBooleanObj(style->locked));LPUT("order",Tcl_NewIntObj(style->order));LPUT("opacity",Tcl_NewDoubleObj(style->opacity));
#undef LPUT
    return result;
}
static int layer_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){gx2d_layer_style style={1,1,0,0,1};gx2d_id id=0,*ids;size_t count;gx2d_status code;Tcl_Obj *result,*v;
    if(strcmp(op,"layer_list")==0){if(argc!=3)return fail(ip,"Usage: core layer_list scene");if(status(ip,gx2d_layer_ids(scene,NULL,0,&count))!=TCL_OK)return TCL_ERROR;if(count>4096)return fail(ip,"Layer list exceeds 4096");ids=(gx2d_id *)malloc((count?count:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");code=gx2d_layer_ids(scene,ids,count,&count);result=id_list_obj(ip,ids,count);free(ids);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"layer_create")==0||strcmp(op,"layer_update")==0){int offset=strcmp(op,"layer_create")==0?3:4;if(argc!=offset+1||(offset==4&&object_id(ip,argv[3],&id)!=TCL_OK))return fail(ip,"Usage: core layer_create scene properties | layer_update scene layer properties");if(offset==4&&status(ip,gx2d_get_layer(scene,id,&style))!=TCL_OK)return TCL_ERROR;
#define LGET(key,read,member) if(Tcl_DictObjGet(ip,argv[offset],Tcl_NewStringObj(key,-1),&v)!=TCL_OK)return TCL_ERROR;if(v&&read(ip,v,&style.member)!=TCL_OK)return TCL_ERROR
        LGET("visible",Tcl_GetBooleanFromObj,visible);LGET("selectable",Tcl_GetBooleanFromObj,selectable);LGET("locked",Tcl_GetBooleanFromObj,locked);LGET("order",Tcl_GetIntFromObj,order);LGET("opacity",Tcl_GetDoubleFromObj,opacity);
#undef LGET
        code=offset==3?gx2d_add_layer(scene,&style,&id):gx2d_set_layer(scene,id,&style);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
    }else if(strcmp(op,"layer_delete")==0){if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return fail(ip,"Usage: core layer_delete scene layer");return status(ip,gx2d_delete_layer(scene,id));}
    else if(strcmp(op,"layer_info")==0){if(argc!=4||object_id(ip,argv[3],&id)!=TCL_OK)return fail(ip,"Usage: core layer_info scene layer");if(status(ip,gx2d_get_layer(scene,id,&style))!=TCL_OK)return TCL_ERROR;}
    else return fail(ip,"Unknown Native2D layer operation");
    result=layer_style_obj(ip,&style);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("id",-1),Tcl_NewWideIntObj((Tcl_WideInt)id));Tcl_SetObjResult(ip,result);return TCL_OK;
}
static int selection_refs_read(Tcl_Interp *ip,Tcl_Obj *input,gx2d_selection_ref **out,size_t *count){Tcl_Obj **items,*v;int n,i;gx2d_selection_ref *refs;
    if(Tcl_ListObjGetElements(ip,input,&n,&items)!=TCL_OK||n<0||n>65536)return fail(ip,"Selection set requires 1..65536 member references");refs=(gx2d_selection_ref *)calloc((size_t)(n?n:1),sizeof(*refs));if(!refs)return fail(ip,"Out of memory");
    for(i=0;i<n;++i){const char *kind;if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("kind",-1),&v)!=TCL_OK||!v)goto invalid;kind=Tcl_GetString(v);refs[i].kind=!strcmp(kind,"object")?GX2D_SELECTION_OBJECT:!strcmp(kind,"point")?GX2D_SELECTION_POINT:!strcmp(kind,"fragment")?GX2D_SELECTION_FRAGMENT:!strcmp(kind,"control")?GX2D_SELECTION_CONTROL:!strcmp(kind,"segment")?GX2D_SELECTION_SEGMENT:0;if(!refs[i].kind)goto invalid;
        if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("id",-1),&v)!=TCL_OK||!v||object_id(ip,v,&refs[i].id)!=TCL_OK)goto invalid;
        if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("index",-1),&v)!=TCL_OK)goto invalid;if(v&&index_arg(ip,v,&refs[i].index)!=TCL_OK)goto invalid;
    }*out=refs;*count=(size_t)n;return TCL_OK;
invalid:free(refs);return fail(ip,"Selection members require kind object/point/fragment, id, optional index");
}
static Tcl_Obj *selection_ref_obj(Tcl_Interp *ip,gx2d_selection_ref ref){
    const char *names[]={"invalid","object","point","fragment","control","segment"};Tcl_Obj *result=Tcl_NewDictObj();
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("kind",-1),Tcl_NewStringObj(names[ref.kind],-1));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("id",-1),Tcl_NewWideIntObj(ref.id));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("index",-1),Tcl_NewWideIntObj(ref.index));return result;
}
static int semantic_selection_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id=0,*ids=NULL;size_t n=0,count=0,i;gx2d_selection_ref ref,*refs=NULL;gx2d_point p,*vertices=NULL;
    gx2d_status code;double tolerance;gx2d_select_mode mode;Tcl_Obj *result;
    if(!strcmp(op,"selection_set_bounds")){
        gx2d_rect bounds;Tcl_WideInt value;if(argc!=4||Tcl_GetWideIntFromObj(ip,argv[3],&value)!=TCL_OK||value<=0)return fail(ip,"Usage: core selection_set_bounds scene set_id");
        id=(gx2d_id)value;code=gx2d_selection_set_bounds(scene,id,&bounds);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,rect_obj(bounds));return TCL_OK;
    }
    if(!strcmp(op,"selection_set_apply")||!strcmp(op,"selection_set_restore")){
        Tcl_WideInt value;
        if(argc!=6||Tcl_GetWideIntFromObj(ip,argv[3],&value)!=TCL_OK||value<0||selection_refs_read(ip,argv[4],&refs,&count)!=TCL_OK)return fail(ip,"Usage: core selection_set_apply scene set_or_zero members mode");
        if(read_mode(ip,argv[5],&mode)!=TCL_OK){free(refs);return TCL_ERROR;}id=(gx2d_id)value;
        code=!strcmp(op,"selection_set_restore")?gx2d_selection_set_restore(scene,&id,refs,count):gx2d_selection_set_apply(scene,&id,refs,count,mode);free(refs);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj(id));return TCL_OK;
    }
    if((argc!=6&&argc!=7)||interaction_ids(ip,argv[3],&ids,&n)!=TCL_OK)return fail(ip,"Usage: core selection_pick scene scope_ids device tolerance | selection_region scene scope_ids polygon_world maximum");
    gx2d_selection_target target=GX2D_PICK_DETAIL;
    if(argc==7){const char *name=Tcl_GetString(argv[6]);
        if(!strcmp(name,"local"))target=GX2D_PICK_LOCAL;else if(!strcmp(name,"object"))target=GX2D_PICK_OBJECT;else if(strcmp(name,"detail")){free(ids);return fail(ip,"Selection target must be detail, local or object");}}
    if(!strcmp(op,"selection_pick")){
        if(read_point(ip,argv[4],&p)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&tolerance)!=TCL_OK){free(ids);return TCL_ERROR;}
        code=gx2d_selection_pick_target(scene,ids,n,p,tolerance,target,&ref);free(ids);
        if(code==GX2D_NOT_FOUND){Tcl_SetObjResult(ip,Tcl_NewDictObj());return TCL_OK;}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,selection_ref_obj(ip,ref));return TCL_OK;
    }
    size_t maximum;
    if(index_arg(ip,argv[5],&maximum)!=TCL_OK||maximum>65536||point_list(ip,argv[4],&vertices,&count)!=TCL_OK){free(ids);return fail(ip,"Selection region maximum must be 0..65536");}
    refs=malloc((maximum?maximum:1)*sizeof(*refs));if(!refs){free(ids);free(vertices);return fail(ip,"Out of memory");}
    code=gx2d_selection_polygon_target(scene,ids,n,vertices,count,target,refs,maximum,&count);free(ids);free(vertices);
    result=Tcl_NewListObj(0,NULL);if(code==GX2D_OK)for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,selection_ref_obj(ip,refs[i]));free(refs);
    if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;
}
static int selection_set_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){gx2d_id id=0,*ids;gx2d_status code;gx2d_selection_ref *refs;gx2d_selection_member *members;size_t count,i;Tcl_Obj *result,*list,*item;
    if(strcmp(op,"selection_set_list")==0){if(argc!=3)return fail(ip,"Usage: core selection_set_list scene");if(status(ip,gx2d_selection_set_ids(scene,NULL,0,&count))!=TCL_OK)return TCL_ERROR;ids=(gx2d_id *)malloc((count?count:1)*sizeof(*ids));if(!ids)return fail(ip,"Out of memory");code=gx2d_selection_set_ids(scene,ids,count,&count);result=id_list_obj(ip,ids,count);free(ids);if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"selection_set_create")==0){if(argc!=4||selection_refs_read(ip,argv[3],&refs,&count)!=TCL_OK)return TCL_ERROR;code=gx2d_selection_set_create(scene,refs,count,&id);free(refs);if(status(ip,code)!=TCL_OK)return TCL_ERROR;}
    else {if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
        if(strcmp(op,"selection_set_update")==0){if(argc!=5||selection_refs_read(ip,argv[4],&refs,&count)!=TCL_OK)return TCL_ERROR;code=gx2d_selection_set_update(scene,id,refs,count);free(refs);if(status(ip,code)!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"selection_set_add_member")==0){if(argc!=5||selection_refs_read(ip,argv[4],&refs,&count)!=TCL_OK)return TCL_ERROR;if(count!=1){free(refs);return fail(ip,"Add requires exactly one member reference");}code=gx2d_selection_set_add_member(scene,id,refs[0]);free(refs);if(status(ip,code)!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"selection_set_remove_member")==0){size_t index;if(argc!=5||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core selection_set_remove_member scene set member_index");if(status(ip,gx2d_selection_set_remove_member(scene,id,index))!=TCL_OK)return TCL_ERROR;}
        else if(strcmp(op,"selection_set_delete")==0){if(argc!=4)return fail(ip,"Usage: core selection_set_delete scene set");return status(ip,gx2d_selection_set_delete(scene,id));}
        else if(strcmp(op,"selection_set_activate")==0){gx2d_select_mode mode;if(argc!=5||read_mode(ip,argv[4],&mode)!=TCL_OK)return fail(ip,"Usage: core selection_set_activate scene set replace/add/subtract");return status(ip,gx2d_selection_set_activate(scene,id,mode));}
        else if(strcmp(op,"selection_set_get")!=0||argc!=4)return fail(ip,"Unknown Native2D selection set operation");
    }
    if(status(ip,gx2d_selection_set_get(scene,id,NULL,0,&count))!=TCL_OK)return TCL_ERROR;members=(gx2d_selection_member *)malloc(count*sizeof(*members));if(!members)return fail(ip,"Out of memory");code=gx2d_selection_set_get(scene,id,members,count,&count);list=Tcl_NewListObj(0,NULL);
    for(i=0;code==GX2D_OK&&i<count;++i){gx2d_selection_member *m=members+i;item=Tcl_NewDictObj();
#define SPUT(key,value) Tcl_DictObjPut(ip,item,Tcl_NewStringObj(key,-1),value)
        SPUT("kind",Tcl_NewStringObj(m->reference.kind==GX2D_SELECTION_OBJECT?"object":m->reference.kind==GX2D_SELECTION_POINT?"point":m->reference.kind==GX2D_SELECTION_FRAGMENT?"fragment":m->reference.kind==GX2D_SELECTION_CONTROL?"control":"segment",-1));SPUT("id",Tcl_NewWideIntObj((Tcl_WideInt)m->reference.id));SPUT("index",Tcl_NewWideIntObj((Tcl_WideInt)m->reference.index));SPUT("topology_epoch",Tcl_NewWideIntObj((Tcl_WideInt)m->topology_epoch));SPUT("valid",Tcl_NewBooleanObj(m->valid));SPUT("missing",Tcl_NewBooleanObj(m->missing));
#undef SPUT
        Tcl_ListObjAppendElement(ip,list,item);
    }free(members);if(status(ip,code)!=TCL_OK)return TCL_ERROR;result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("id",-1),Tcl_NewWideIntObj((Tcl_WideInt)id));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("members",-1),list);Tcl_SetObjResult(ip,result);return TCL_OK;
}
