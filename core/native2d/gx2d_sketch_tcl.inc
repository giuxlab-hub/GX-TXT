/* SPDX-License-Identifier: GPL-3.0-or-later */
static const char *sketch_names[]={"point","line","construction_line","polyline","rectangle","circle","arc","ellipse","quadratic_bezier","cubic_bezier","spline","path","composite_path","compound"};
static void sketch_read_release(gx2d_sketch_definition *d,gx2d_point *owned) {
    for(size_t i=0;i<d->part_count;i++)free((void *)d->parts[i].controls);
    free((void *)d->parts);free((void *)d->part_reversed);free((void *)d->nodes);free(owned);
    d->parts=NULL;d->part_reversed=NULL;d->part_count=0;
}
static int sketch_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_sketch_definition *d,gx2d_point **owned) {
    Tcl_Obj *field=NULL,**items;int n,i;const char *name;
    memset(d,0,sizeof(*d));*owned=NULL;d->matrix[0]=d->matrix[3]=1;
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("family",-1),&field)!=TCL_OK||!field)return fail(ip,"Sketch definition requires family");
    name=Tcl_GetString(field);for(i=0;i<14;++i)if(strcmp(name,sketch_names[i])==0)break;
    if(i==14)return fail(ip,"Unknown sketch family");d->family=(gx2d_sketch_family)(GX2D_SKETCH_POINT+i);
    if(i>=12) {
        if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("parts",-1),&field)!=TCL_OK||!field||Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||n<1||n>256)return fail(ip,"Composition requires 1..256 exact finite primitive parts");
        gx2d_sketch_definition *parts=calloc((size_t)n,sizeof(*parts));int *reversed=calloc((size_t)n,sizeof(int));
        if(!parts||!reversed){free(parts);free(reversed);return fail(ip,"Out of memory");}
        d->parts=parts;d->part_reversed=reversed;d->part_count=(size_t)n;
        for(i=0;i<n;i++) {
            Tcl_Obj *definition=NULL,*rev=NULL,*family=NULL;gx2d_point *storage=NULL;
            if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("definition",-1),&definition)!=TCL_OK||!definition||Tcl_DictObjGet(ip,definition,Tcl_NewStringObj("family",-1),&family)!=TCL_OK||!family)goto invalid;
            const char *f=Tcl_GetString(family);if(!strcmp(f,"compound")||!strcmp(f,"composite_path")){fail(ip,"Nested definitions are forbidden; composition_create flattens exact inputs");goto invalid;}
            if(sketch_read(ip,definition,&parts[i],&storage)!=TCL_OK)goto invalid;
            if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("reversed",-1),&rev)!=TCL_OK||(rev&&Tcl_GetBooleanFromObj(ip,rev,&reversed[i])!=TCL_OK))goto invalid;
        }
        if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("matrix",-1),&field)!=TCL_OK)goto invalid;
        if(field){if(Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||n!=6)goto invalid;for(i=0;i<6;i++)if(Tcl_GetDoubleFromObj(ip,items[i],&d->matrix[i])!=TCL_OK)goto invalid;}
        if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("tolerance",-1),&field)!=TCL_OK||(field&&Tcl_GetDoubleFromObj(ip,field,&d->join_tolerance)!=TCL_OK))goto invalid;
        if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("closed",-1),&field)!=TCL_OK||(field&&Tcl_GetBooleanFromObj(ip,field,&d->path_closed)!=TCL_OK))goto invalid;
        if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("nodes",-1),&field)!=TCL_OK)goto invalid;
        if(field){
            if(Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||n<1||n>65536)goto invalid;
            size_t *nodes=calloc((size_t)n,sizeof(size_t));if(!nodes)goto invalid;d->nodes=nodes;d->node_count=(size_t)n;
            for(i=0;i<n;i++)if(index_arg(ip,items[i],&nodes[i])!=TCL_OK)goto invalid;
        }
        if(status(ip,gx2d_sketch_validate(d))!=TCL_OK)goto invalid;
        return TCL_OK;
    }
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("controls",-1),&field)!=TCL_OK||!field||Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||n<1||n>65536)return fail(ip,"Sketch controls require 1..65536 XY pairs");
    *owned=(gx2d_point *)calloc(1,(size_t)n*(sizeof(**owned)+sizeof(gx2d_spline_tangent)+sizeof(gx2d_path_segment)));if(!*owned)return fail(ip,"Out of memory");
    d->controls=*owned;d->control_count=(size_t)n;
    for(i=0;i<n;++i)if(read_point(ip,items[i],&(*owned)[i])!=TCL_OK)goto invalid;
#define SKETCH_NUMBER(key,member) if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj(key,-1),&field)!=TCL_OK)goto invalid; if(field&&Tcl_GetDoubleFromObj(ip,field,&d->member)!=TCL_OK)goto invalid
    SKETCH_NUMBER("radius_x",radius_x);SKETCH_NUMBER("radius_y",radius_y);SKETCH_NUMBER("rotation",rotation);SKETCH_NUMBER("angle_start",angle_start);SKETCH_NUMBER("angle_sweep",angle_sweep);
#undef SKETCH_NUMBER
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("matrix",-1),&field)!=TCL_OK)goto invalid;
    if(field){if(Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||n!=6){fail(ip,"Sketch matrix requires six affine coefficients");goto invalid;}for(i=0;i<6;++i)if(Tcl_GetDoubleFromObj(ip,items[i],&d->matrix[i])!=TCL_OK)goto invalid;}
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("tangents",-1),&field)!=TCL_OK)goto invalid;
    if(field){
        if(Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||(size_t)n!=d->control_count){fail(ip,"Tangent state requires one record per spline knot");goto invalid;}
        gx2d_spline_tangent *arms=(gx2d_spline_tangent *)(*owned+d->control_count);d->tangents=arms;d->tangent_count=(size_t)n;
        for(i=0;i<n;i++){
            Tcl_Obj **entry;int count,flags;
            if(Tcl_ListObjGetElements(ip,items[i],&count,&entry)!=TCL_OK||count!=3||Tcl_GetIntFromObj(ip,entry[0],&flags)!=TCL_OK||flags<0||flags>3||read_point(ip,entry[1],&arms[i].incoming)!=TCL_OK||read_point(ip,entry[2],&arms[i].outgoing)!=TCL_OK)goto invalid;
            arms[i].flags=(unsigned)flags;
        }
    }
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("closed",-1),&field)!=TCL_OK)goto invalid;
    if(field&&Tcl_GetBooleanFromObj(ip,field,&d->path_closed)!=TCL_OK)goto invalid;
    if(Tcl_DictObjGet(ip,value,Tcl_NewStringObj("segments",-1),&field)!=TCL_OK)goto invalid;
    if(field){
        if(Tcl_ListObjGetElements(ip,field,&n,&items)!=TCL_OK||(size_t)n>d->control_count)goto invalid;
        gx2d_path_segment *edges=(gx2d_path_segment *)((gx2d_spline_tangent *)(*owned+d->control_count)+d->control_count);
        d->path_segments=edges;d->path_segment_count=(size_t)n;
        for(i=0;i<n;++i){Tcl_Obj *v;
            if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("family",-1),&v)!=TCL_OK||!v||strcmp(Tcl_GetString(v),"line"))goto invalid;
            edges[i].family=GX2D_SKETCH_LINE;
            if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("first",-1),&v)!=TCL_OK||!v||index_arg(ip,v,&edges[i].first)!=TCL_OK)goto invalid;
            if(Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("last",-1),&v)!=TCL_OK||!v||index_arg(ip,v,&edges[i].last)!=TCL_OK)goto invalid;
        }
    }
    if(status(ip,gx2d_sketch_validate(d))!=TCL_OK)goto invalid;
    return TCL_OK;
invalid:sketch_read_release(d,*owned);d->controls=NULL;*owned=NULL;return TCL_ERROR;
}
static Tcl_Obj *sketch_obj(Tcl_Interp *ip,const gx2d_sketch_definition *d) {
    Tcl_Obj *result=Tcl_NewDictObj(),*controls=Tcl_NewListObj(0,NULL),*matrix=Tcl_NewListObj(0,NULL);size_t i;
    for(i=0;i<d->control_count;++i)Tcl_ListObjAppendElement(ip,controls,point_obj(d->controls[i]));
    for(i=0;i<6;++i)Tcl_ListObjAppendElement(ip,matrix,Tcl_NewDoubleObj(d->matrix[i]));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("family",-1),Tcl_NewStringObj(sketch_names[d->family-GX2D_SKETCH_POINT],-1));
    Tcl_DictObjPut(ip,result,Tcl_NewStringObj("controls",-1),controls);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("matrix",-1),matrix);
    if(d->part_count) {
        Tcl_Obj *parts=Tcl_NewListObj(0,NULL);
        for(i=0;i<d->part_count;i++){Tcl_Obj *part=Tcl_NewDictObj();
            Tcl_DictObjPut(ip,part,Tcl_NewStringObj("definition",-1),sketch_obj(ip,&d->parts[i]));
            Tcl_DictObjPut(ip,part,Tcl_NewStringObj("reversed",-1),Tcl_NewBooleanObj(d->part_reversed[i]));Tcl_ListObjAppendElement(ip,parts,part);
        }
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("parts",-1),parts);
        if(d->node_count){Tcl_Obj *nodes=Tcl_NewListObj(0,NULL);for(i=0;i<d->node_count;i++)Tcl_ListObjAppendElement(ip,nodes,Tcl_NewWideIntObj(d->nodes[i]));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("nodes",-1),nodes);}
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("closed",-1),Tcl_NewBooleanObj(d->path_closed));
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("tolerance",-1),Tcl_NewDoubleObj(d->join_tolerance));
    }
#define SKETCH_PUT(key,member) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(key,-1),Tcl_NewDoubleObj(d->member))
    SKETCH_PUT("radius_x",radius_x);SKETCH_PUT("radius_y",radius_y);SKETCH_PUT("rotation",rotation);SKETCH_PUT("angle_start",angle_start);SKETCH_PUT("angle_sweep",angle_sweep);
#undef SKETCH_PUT
    if(d->tangent_count){
        Tcl_Obj *arms=Tcl_NewListObj(0,NULL);
        for(i=0;i<d->tangent_count;i++){Tcl_Obj *entry[3]={Tcl_NewIntObj((int)d->tangents[i].flags),point_obj(d->tangents[i].incoming),point_obj(d->tangents[i].outgoing)};Tcl_ListObjAppendElement(ip,arms,Tcl_NewListObj(3,entry));}
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("tangents",-1),arms);
    }
    if(d->family==GX2D_SKETCH_PATH){
        Tcl_Obj *segments=Tcl_NewListObj(0,NULL);
        for(i=0;i<d->control_count-1+(size_t)d->path_closed;++i){Tcl_Obj *edge=Tcl_NewDictObj();
            Tcl_DictObjPut(ip,edge,Tcl_NewStringObj("family",-1),Tcl_NewStringObj("line",-1));
            Tcl_DictObjPut(ip,edge,Tcl_NewStringObj("first",-1),Tcl_NewWideIntObj(i));
            Tcl_DictObjPut(ip,edge,Tcl_NewStringObj("last",-1),Tcl_NewWideIntObj((i+1)%d->control_count));
            Tcl_ListObjAppendElement(ip,segments,edge);
        }
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("segments",-1),segments);
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("closed",-1),Tcl_NewBooleanObj(d->path_closed));
    }
    return result;
}
static int composition_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]) {
    gx2d_id id,ids[256],created[256];size_t index,count;int reverse[256],ordered;double tolerance;Tcl_Obj **items,**flags;int n,nr;
    if(!strcmp(op,"composition_create")) {
        if(argc!=7||Tcl_ListObjGetElements(ip,argv[3],&n,&items)!=TCL_OK||n<1||n>256||Tcl_ListObjGetElements(ip,argv[4],&nr,&flags)!=TCL_OK||(nr&&nr!=n)||Tcl_GetIntFromObj(ip,argv[5],&ordered)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[6],&tolerance)!=TCL_OK)return fail(ip,"Usage: core composition_create scene objects reversals mode(0 compound,1 ordered,2 infer) tolerance");
        for(int i=0;i<n;i++){if(object_id(ip,items[i],&ids[i])!=TCL_OK)return TCL_ERROR;reverse[i]=0;if(nr&&Tcl_GetBooleanFromObj(ip,flags[i],&reverse[i])!=TCL_OK)return TCL_ERROR;}
        if(status(ip,gx2d_composition_create(scene,ids,reverse,(size_t)n,ordered,tolerance,&id))!=TCL_OK)return TCL_ERROR;
        Tcl_SetObjResult(ip,Tcl_NewWideIntObj(id));return TCL_OK;
    }
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"composition_retarget")) {
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[4],&n,&items)!=TCL_OK||n<1||n>256)return fail(ip,"Usage: composition_retarget scene target sources");
        for(int i=0;i<n;i++)if(object_id(ip,items[i],&ids[i])!=TCL_OK)return TCL_ERROR;
        return status(ip,gx2d_composition_retarget(scene,id,ids,(size_t)n));
    }
    if(!strcmp(op,"composition_part")) {
        gx2d_sketch_definition d;int reversed;
        if(argc!=5||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core composition_part scene object part_index");
        if(status(ip,gx2d_composition_part(scene,id,index,&d,&reversed))!=TCL_OK)return TCL_ERROR;
        Tcl_Obj *result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("definition",-1),sketch_obj(ip,&d));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("reversed",-1),Tcl_NewBooleanObj(reversed));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"composition_split")) {
        if(argc!=5||index_arg(ip,argv[4],&index)!=TCL_OK)return fail(ip,"Usage: core composition_split scene object junction_index");
        if(status(ip,gx2d_composition_split(scene,id,index,created))!=TCL_OK)return TCL_ERROR;count=2;
    } else if(!strcmp(op,"composition_explode")) {
        if(argc!=4)return fail(ip,"Usage: core composition_explode scene object");
        if(status(ip,gx2d_composition_explode(scene,id,created,256,&count))!=TCL_OK)return TCL_ERROR;
    } else return fail(ip,"Unknown composition operation");
    Tcl_Obj *result=Tcl_NewListObj(0,NULL);for(size_t i=0;i<count;i++)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj(created[i]));Tcl_SetObjResult(ip,result);return TCL_OK;
}
static int path_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]){
    gx2d_id id,other,created,parts[2];gx2d_status code;int repeat,ra,rb;size_t count,i,vertex;double tolerance;gx2d_point *points;Tcl_Obj *result;
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"path_vertices")){
        if(argc!=5||Tcl_GetBooleanFromObj(ip,argv[4],&repeat)!=TCL_OK)return fail(ip,"Usage: core path_vertices scene path repeat_closed_endpoint");
        code=gx2d_path_vertices(scene,id,repeat,NULL,0,&count);if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        points=malloc(count*sizeof(*points));if(!points)return fail(ip,"Out of memory");code=gx2d_path_vertices(scene,id,repeat,points,count,&count);
        result=Tcl_NewListObj(0,NULL);if(code==GX2D_OK)for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));free(points);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"path_split")){
        if(argc!=5||index_arg(ip,argv[4],&vertex)!=TCL_OK)return fail(ip,"Usage: core path_split scene path vertex");
        if(status(ip,gx2d_path_split(scene,id,vertex,parts))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);for(i=0;i<2;++i)Tcl_ListObjAppendElement(ip,result,Tcl_NewWideIntObj(parts[i]));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(argc!=8||object_id(ip,argv[4],&other)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[5],&ra)!=TCL_OK||Tcl_GetBooleanFromObj(ip,argv[6],&rb)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[7],&tolerance)!=TCL_OK)return fail(ip,"Usage: core path_join scene a b reverse_a reverse_b tolerance");
    if(status(ip,gx2d_path_join(scene,id,other,ra,rb,tolerance,&created))!=TCL_OK)return TCL_ERROR;
    Tcl_SetObjResult(ip,Tcl_NewWideIntObj(created));return TCL_OK;
}
static int sketch_command(gx2d_scene *scene,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]) {
    gx2d_sketch_definition definition;gx2d_point *owned=NULL,*points=NULL,p,v;gx2d_id id=0;gx2d_status code;size_t samples=257,total,start,count,i;double t,first,last;Tcl_Obj *result;
    if(strcmp(op,"sketch_create")==0||strcmp(op,"sketch_update")==0){int offset=strcmp(op,"sketch_create")==0?3:4;
        if(argc!=offset+2||(offset==4&&object_id(ip,argv[3],&id)!=TCL_OK)||index_arg(ip,argv[offset+1],&samples)!=TCL_OK)return fail(ip,"Usage: core sketch_create scene definition display_samples | sketch_update scene object definition display_samples");
        if(sketch_read(ip,argv[offset],&definition,&owned)!=TCL_OK)return TCL_ERROR;
        gx2d_part_state part_states[256];size_t part_count;
        if(part_states_read(ip,argv[offset],part_states,&part_count)!=TCL_OK){sketch_read_release(&definition,owned);return TCL_ERROR;}
        Tcl_Obj *counter_obj=NULL,*parts_obj=NULL,**part_items,*identity=NULL;int part_n=0,explicit_state=0;uint64_t counter=0;
        Tcl_DictObjGet(ip,argv[offset],Tcl_NewStringObj("part_identity_counter",-1),&counter_obj);
        if(counter_obj&&index_arg(ip,counter_obj,&counter)!=TCL_OK){sketch_read_release(&definition,owned);return TCL_ERROR;}
        Tcl_DictObjGet(ip,argv[offset],Tcl_NewStringObj("parts",-1),&parts_obj);
        if(parts_obj){Tcl_ListObjGetElements(ip,parts_obj,&part_n,&part_items);for(int pi=0;pi<part_n;pi++){Tcl_DictObjGet(ip,part_items[pi],Tcl_NewStringObj("part_id",-1),&identity);explicit_state|=identity!=NULL;Tcl_DictObjGet(ip,part_items[pi],Tcl_NewStringObj("direction",-1),&identity);explicit_state|=identity!=NULL;}}
        code=offset==3?gx2d_sketch_create(scene,&definition,samples,&id):GX2D_OK;
        if(code==GX2D_OK){if(part_count&&(offset==3||explicit_state))code=gx2d_sketch_update_parts(scene,id,&definition,samples,part_states,part_count,counter);else if(offset==4)code=gx2d_sketch_update(scene,id,&definition,samples);}
        sketch_read_release(&definition,owned);
        if(code!=GX2D_OK&&offset==3)gx2d_delete_object(scene,id);
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;
    }
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
    if(strcmp(op,"sketch_definition")==0){if(argc!=4)return fail(ip,"Usage: core sketch_definition scene object");code=gx2d_sketch_get_definition(scene,id,&definition);
        if(code==GX2D_INVALID){Tcl_SetObjResult(ip,Tcl_NewDictObj());return TCL_OK;}
        if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,owned_sketch_obj(ip,scene,id,&definition));return TCL_OK;}
    if(strcmp(op,"sketch_explode")==0){if(argc!=5||index_arg(ip,argv[4],&samples)!=TCL_OK)return fail(ip,"Usage: core sketch_explode scene object samples");if(status(ip,gx2d_sketch_explode(scene,id,samples,&id))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;}
    if(strcmp(op,"sketch_materialize")==0){if(argc!=7||Tcl_GetDoubleFromObj(ip,argv[4],&first)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&last)!=TCL_OK||index_arg(ip,argv[6],&total)!=TCL_OK)return fail(ip,"Usage: core sketch_materialize scene object first last total");
        if(status(ip,gx2d_sketch_materialize(scene,id,first,last,total,&id))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj((Tcl_WideInt)id));return TCL_OK;}
    if(status(ip,gx2d_sketch_get_definition(scene,id,&definition))!=TCL_OK)return TCL_ERROR;
    if(strcmp(op,"sketch_evaluate")==0){if(argc!=5||Tcl_GetDoubleFromObj(ip,argv[4],&t)!=TCL_OK)return fail(ip,"Usage: core sketch_evaluate scene object t");
        if(status(ip,gx2d_sketch_evaluate(&definition,t,&p,&v))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();Tcl_DictObjPut(ip,result,Tcl_NewStringObj("point",-1),point_obj(p));Tcl_DictObjPut(ip,result,Tcl_NewStringObj("derivative",-1),point_obj(v));Tcl_SetObjResult(ip,result);return TCL_OK;}
    if(strcmp(op,"sketch_sample")==0){if(argc!=9||Tcl_GetDoubleFromObj(ip,argv[4],&first)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&last)!=TCL_OK||index_arg(ip,argv[6],&total)!=TCL_OK||index_arg(ip,argv[7],&start)!=TCL_OK||index_arg(ip,argv[8],&count)!=TCL_OK||!count||count>65536)return fail(ip,"Usage: core sketch_sample scene object t_first t_last total start count (page <= 65536)");
        points=(gx2d_point *)malloc(count*sizeof(*points));if(!points)return fail(ip,"Out of memory");code=gx2d_sketch_sample(&definition,first,last,total,start,count,points,count);
        if(status(ip,code)!=TCL_OK){free(points);return TCL_ERROR;}result=Tcl_NewListObj(0,NULL);for(i=0;i<count;++i)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));free(points);Tcl_SetObjResult(ip,result);return TCL_OK;}
    return fail(ip,"Unknown sketch operation");
}
