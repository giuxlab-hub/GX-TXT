/* SPDX-License-Identifier: GPL-3.0-or-later */
static int construction_places_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_construction_placement **out,size_t *count){
    Tcl_Obj **items;int n;if(Tcl_ListObjGetElements(ip,value,&n,&items)!=TCL_OK||n>65536)return fail(ip,"Too many construction placements");
    gx2d_construction_placement *places=calloc(n?n:1,sizeof(*places));if(!places)return fail(ip,"Out of memory");
    for(int i=0;i<n;i++){Tcl_Obj *point=NULL,*reference=NULL,*earlier=NULL;
        if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("point",-1),&point)!=TCL_OK||Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("reference",-1),&reference)!=TCL_OK||Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("earlier",-1),&earlier)!=TCL_OK){free(places);return TCL_ERROR;}
        if(reference&&earlier){free(places);return fail(ip,"Placement cannot reference both existing and earlier controls");}
        if(point&&read_point(ip,point,&places[i].point)!=TCL_OK){free(places);return TCL_ERROR;}
        if(reference){places[i].mode=GX2D_PLACEMENT_REFERENCE;if(reference_read(ip,reference,&places[i].reference)!=TCL_OK){free(places);return TCL_ERROR;}}
        else if(earlier){places[i].mode=GX2D_PLACEMENT_EARLIER;if(index_arg(ip,earlier,&places[i].earlier)!=TCL_OK){free(places);return TCL_ERROR;}}
        else if(!point){free(places);return fail(ip,"Free placement requires point");}
    }
    *out=places;*count=n;return TCL_OK;
}
static Tcl_Obj *construction_place_obj(Tcl_Interp *ip,const gx2d_construction_placement *place){
    Tcl_Obj *result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point",-1),point_obj(place->point));
    if(place->mode==GX2D_PLACEMENT_REFERENCE)Tcl_DictObjPut(ip,result,Tcl_NewStringObj("reference",-1),reference_obj(ip,&place->reference));
    if(place->mode==GX2D_PLACEMENT_EARLIER)Tcl_DictObjPut(ip,result,Tcl_NewStringObj("earlier",-1),Tcl_NewWideIntObj(place->earlier));return result;
}
static int construction_command(gx2d_scene *s,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_construction_placement *places=NULL;size_t n=0;gx2d_status code;Tcl_Obj *result;
    if(!strcmp(op,"construction_connected")){gx2d_reference a,b;int connected;
        if(argc!=5||reference_read(ip,argv[3],&a)!=TCL_OK||reference_read(ip,argv[4],&b)!=TCL_OK)return TCL_ERROR;
        if(status(ip,gx2d_references_connected(s,&a,&b,&connected))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewBooleanObj(connected));return TCL_OK;
    }
    if(!strcmp(op,"construction_pick")){gx2d_point point;double tolerance;gx2d_id *excluded=NULL;size_t ne;int grid;gx2d_construction_placement place;
        if(argc!=8||read_point(ip,argv[3],&point)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[4],&tolerance)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[7],&grid)!=TCL_OK||construction_places_read(ip,argv[5],&places,&n)!=TCL_OK)return TCL_ERROR;
        if(interaction_ids(ip,argv[6],&excluded,&ne)!=TCL_OK){free(places);return TCL_ERROR;}
        code=gx2d_construction_pick(s,point,tolerance,places,n,excluded,ne,grid,&place);free(places);free(excluded);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,construction_place_obj(ip,&place));return TCL_OK;
    }
    if(!strcmp(op,"construction_points")){
        if(argc!=4||construction_places_read(ip,argv[3],&places,&n)!=TCL_OK)return TCL_ERROR;
        gx2d_point *points=malloc((n?n:1)*sizeof(*points));if(!points){free(places);return fail(ip,"Out of memory");}
        code=gx2d_construction_resolve(s,places,n,points,n);result=Tcl_NewListObj(0,NULL);if(code==GX2D_OK)for(size_t i=0;i<n;i++)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));free(points);free(places);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    int family;for(family=0;family<12;family++)if(argc>3&&!strcmp(Tcl_GetString(argv[3]),sketch_names[family]))break;
    if(family==12)return fail(ip,"Unknown construction family");
    if(!strcmp(op,"construction_preview")){
        if(argc!=5||construction_places_read(ip,argv[4],&places,&n)!=TCL_OK)return TCL_ERROR;
        gx2d_sketch_definition definition;gx2d_point *controls=malloc((n?n:1)*sizeof(*controls));if(!controls){free(places);return fail(ip,"Out of memory");}
        code=gx2d_construction_preview(s,family+1,places,n,&definition,controls,n);if(code==GX2D_OK)Tcl_SetObjResult(ip,sketch_obj(ip,&definition));free(controls);free(places);return status(ip,code);
    }
    if(!strcmp(op,"construction_create")){
        size_t samples;Tcl_Obj **items;int nc;if((argc!=7&&argc!=8)||index_arg(ip,argv[5],&samples)!=TCL_OK||Tcl_ListObjGetElements(ip,argv[6],&nc,&items)!=TCL_OK||nc>65536||construction_places_read(ip,argv[4],&places,&n)!=TCL_OK)return TCL_ERROR;
        gx2d_reference *closure=malloc((nc?nc:1)*sizeof(*closure));gx2d_id *rules=malloc((n?n:1)*sizeof(*rules));if(!closure||!rules){free(closure);free(rules);free(places);return fail(ip,"Out of memory");}
        for(int i=0;i<nc;i++)if(reference_read(ip,items[i],&closure[i])!=TCL_OK){free(closure);free(rules);free(places);return TCL_ERROR;}
        gx2d_id id;size_t count;gx2d_reference tail;int closed;code=gx2d_sketch_create_attached(s,family+1,places,n,samples,closure,nc,&id,rules,n,&count,&tail,&closed);free(places);free(closure);
        gx2d_id mirror=0,symmetry=0;
        if(code==GX2D_OK&&argc==8){gx2d_reference axis;if(reference_read(ip,argv[7],&axis)!=TCL_OK){gx2d_delete_object(s,id);free(rules);return TCL_ERROR;}code=gx2d_symmetry_attach(s,id,&axis,&mirror,&symmetry);if(code!=GX2D_OK)gx2d_delete_object(s,id);}
        if(code==GX2D_OK){gx2d_sketch_definition definition;gx2d_sketch_get_definition(s,id,&definition);result=Tcl_NewDictObj();
            Tcl_DictObjPut(ip,result,Tcl_NewStringObj("id",-1),Tcl_NewWideIntObj(id));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("definition",-1),sketch_obj(ip,&definition));
            Tcl_DictObjPut(ip,result,Tcl_NewStringObj("tail_reference",-1),reference_obj(ip,&tail));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("closed",-1),Tcl_NewBooleanObj(closed));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("periodic",-1),Tcl_NewBooleanObj(0));
            Tcl_Obj *relationships=Tcl_NewListObj(0,NULL);for(size_t i=0;i<count;i++){gx2d_constraint_v2 d;gx2d_constraint_diagnostic diagnostic;gx2d_constraint_get(s,rules[i],&d);gx2d_constraint_validate(s,rules[i],&diagnostic);Tcl_ListObjAppendElement(ip,relationships,constraint_obj(s,ip,rules[i],&d,&diagnostic));}
            if(mirror){gx2d_constraint_v2 d;gx2d_constraint_diagnostic diagnostic;gx2d_constraint_get(s,symmetry,&d);gx2d_constraint_validate(s,symmetry,&diagnostic);Tcl_ListObjAppendElement(ip,relationships,constraint_obj(s,ip,symmetry,&d,&diagnostic));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("mirror_id",-1),Tcl_NewWideIntObj(mirror));}
            Tcl_DictObjPut(ip,result,Tcl_NewStringObj("relationships",-1),relationships);Tcl_SetObjResult(ip,result);
        }
        free(rules);return status(ip,code);
    }
    return fail(ip,"Unknown construction operation");
}
