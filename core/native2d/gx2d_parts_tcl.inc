/* Scene-bound serialization extends Tcl dictionaries, not the C definition ABI. */
static Tcl_Obj *sketch_obj(Tcl_Interp *,const gx2d_sketch_definition *);
static Tcl_Obj *owned_sketch_obj(Tcl_Interp *ip,gx2d_scene *s,gx2d_id id,const gx2d_sketch_definition *d) {
    Tcl_Obj *result=sketch_obj(ip,d);gx2d_part_state states[256];size_t count;
    if(gx2d_composition_states(s,id,states,256,&count)==GX2D_OK) {
        uint64_t counter;gx2d_composition_identity_counter(s,id,&counter);Tcl_DictObjPut(ip,result,Tcl_NewStringObj("part_identity_counter",-1),Tcl_NewWideIntObj(counter));
        Tcl_Obj *parts=NULL,**items;int n;Tcl_DictObjGet(ip,result,Tcl_NewStringObj("parts",-1),&parts);Tcl_ListObjGetElements(ip,parts,&n,&items);
        for(size_t i=0;i<count;i++){Tcl_DictObjPut(ip,items[i],Tcl_NewStringObj("part_id",-1),Tcl_NewWideIntObj(states[i].part_id));Tcl_DictObjPut(ip,items[i],Tcl_NewStringObj("direction",-1),marker_obj(states[i].direction));}
    }
    return result;
}
static int part_states_read(Tcl_Interp *ip,Tcl_Obj *value,gx2d_part_state *states,size_t *count) {
    Tcl_Obj *parts=NULL,**items,*field;int n;Tcl_DictObjGet(ip,value,Tcl_NewStringObj("parts",-1),&parts);*count=0;if(!parts)return TCL_OK;
    if(Tcl_ListObjGetElements(ip,parts,&n,&items)!=TCL_OK||n<1||n>256)return fail(ip,"Invalid constituent count");
    for(int i=0;i<n;i++) {
        states[i].part_id=i+1;
        states[i].direction=(gx2d_direction_marker){0,0,1,0,.5,12,32,2,1,{.12,.19,.34,1}};
        Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("reversed",-1),&field);int reversed=0;if(field&&Tcl_GetBooleanFromObj(ip,field,&reversed)!=TCL_OK)return TCL_ERROR;states[i].direction.forward=!reversed;
        Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("part_id",-1),&field);if(field&&index_arg(ip,field,&states[i].part_id)!=TCL_OK)return TCL_ERROR;
        Tcl_DictObjGet(ip,items[i],Tcl_NewStringObj("direction",-1),&field);if(field&&marker_read(ip,field,&states[i].direction)!=TCL_OK)return TCL_ERROR;
        if(!states[i].part_id)return fail(ip,"Part identity must be positive");
        for(int j=0;j<i;j++)if(states[j].part_id==states[i].part_id)return fail(ip,"Duplicate constituent identity");
    }
    *count=n;return TCL_OK;
}
static int part_command(gx2d_scene *s,Tcl_Interp *ip,const char *op,int argc,Tcl_Obj *const argv[]) {
    gx2d_id id;size_t ordinal,count;gx2d_part_state states[256];uint64_t part;gx2d_status code;Tcl_Obj *result;
    if(argc<4||object_id(ip,argv[3],&id)!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"composition_states")) {
        if(argc!=4)return fail(ip,"Usage: composition_states scene object");if(status(ip,gx2d_composition_states(s,id,states,256,&count))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);for(size_t i=0;i<count;i++){Tcl_Obj *entry=Tcl_NewDictObj();Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("part_id",-1),Tcl_NewWideIntObj(states[i].part_id));Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("ordinal",-1),Tcl_NewWideIntObj(i));Tcl_DictObjPut(ip,entry,Tcl_NewStringObj("direction",-1),marker_obj(states[i].direction));Tcl_ListObjAppendElement(ip,result,entry);}Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"composition_traversal")){int kind;if(argc!=4)return fail(ip,"Usage: composition_traversal scene object");if(status(ip,gx2d_composition_traversal(s,id,&kind))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewStringObj((const char *[]){"unordered","continuous","network"}[kind],-1));return TCL_OK;}
    if(!strcmp(op,"part_direction_batch")) {
        Tcl_Obj **updates,*key,*changes;int num;
        if(argc!=5||Tcl_ListObjGetElements(ip,argv[4],&num,&updates)!=TCL_OK)return fail(ip,"Usage: part_direction_batch scene object updates");
        if(status(ip,gx2d_composition_states(s,id,states,256,&count))!=TCL_OK)return TCL_ERROR;
        for(int j=0;j<num;j++) {
            Tcl_DictObjGet(ip,updates[j],Tcl_NewStringObj("part_id",-1),&key);Tcl_DictObjGet(ip,updates[j],Tcl_NewStringObj("changes",-1),&changes);
            if(!key||!changes||index_arg(ip,key,&part)!=TCL_OK)return fail(ip,"Each update requires part_id and changes");
            if(status(ip,gx2d_part_ordinal(s,id,part,&ordinal))!=TCL_OK)return TCL_ERROR;
            if(!states[ordinal].direction.present){int forward=states[ordinal].direction.forward;gx2d_direction_marker_get(s,id,&states[ordinal].direction);states[ordinal].direction.forward=forward;states[ordinal].direction.visible=0;states[ordinal].direction.interpolation=0;}
            if(marker_read(ip,changes,&states[ordinal].direction)!=TCL_OK)return TCL_ERROR;states[ordinal].direction.present=1;
        }
        if(status(ip,gx2d_composition_states_restore(s,id,states,count))!=TCL_OK)return TCL_ERROR;
        return part_command(s,ip,"composition_states",4,argv);
    }
    if(!strcmp(op,"part_pick")) {
        gx2d_point device;double tolerance;if(argc!=6||read_point(ip,argv[4],&device)!=TCL_OK||Tcl_GetDoubleFromObj(ip,argv[5],&tolerance)!=TCL_OK)return TCL_ERROR;
        code=gx2d_part_pick(s,id,device,tolerance,&part);if(code==GX2D_NOT_FOUND)return TCL_OK;if(status(ip,code)!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewWideIntObj(part));return TCL_OK;
    }
    if(argc<5||index_arg(ip,argv[4],&part)!=TCL_OK)return TCL_ERROR;
    if(status(ip,gx2d_part_ordinal(s,id,part,&ordinal))!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"part_direction")) {
        gx2d_direction_marker marker;if(argc!=5&&argc!=6)return fail(ip,"Usage: part_direction scene object part_id ?changes?");
        if(status(ip,gx2d_part_direction_get(s,id,part,&marker))!=TCL_OK)return TCL_ERROR;
        if(argc==6){if(!marker.present){int forward=marker.forward;gx2d_direction_marker_get(s,id,&marker);marker.forward=forward;marker.visible=0;marker.interpolation=0;}marker.present=1;if(marker_read(ip,argv[5],&marker)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_part_direction_set(s,id,part,&marker))!=TCL_OK)return TCL_ERROR;}
        Tcl_SetObjResult(ip,marker_obj(marker));return TCL_OK;
    }
    if(!strcmp(op,"part_render")) {
        gx2d_point points[4096];if(argc!=5)return fail(ip,"Usage: part_render scene object part_id");if(status(ip,gx2d_part_render(s,id,part,points,4096,&count))!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewListObj(0,NULL);for(size_t i=0;i<count;i++)Tcl_ListObjAppendElement(ip,result,point_obj(points[i]));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    if(!strcmp(op,"part_marker_render")) {
        gx2d_direction_primitives p;if(argc!=5)return fail(ip,"Usage: part_marker_render scene object part_id");code=gx2d_part_direction_render(s,id,part,&p);if(code==GX2D_NOT_FOUND)return TCL_OK;if(status(ip,code)!=TCL_OK)return TCL_ERROR;
        result=Tcl_NewDictObj();
#define PART_POINT(k) Tcl_DictObjPut(ip,result,Tcl_NewStringObj(#k,-1),point_obj(p.k))
        PART_POINT(anchor);PART_POINT(tail);PART_POINT(tip);PART_POINT(head_left);PART_POINT(head_right);
#undef PART_POINT
        Tcl_DictObjPut(ip,result,Tcl_NewStringObj("fraction",-1),Tcl_NewDoubleObj(p.fraction));Tcl_SetObjResult(ip,result);return TCL_OK;
    }
    gx2d_point device;if(argc<6||read_point(ip,argv[5],&device)!=TCL_OK)return TCL_ERROR;
    if(!strcmp(op,"part_marker_hit")){int hit;double tolerance;if(argc!=7||Tcl_GetDoubleFromObj(ip,argv[6],&tolerance)!=TCL_OK)return TCL_ERROR;if(status(ip,gx2d_part_direction_hit(s,id,part,device,tolerance,&hit))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewBooleanObj(hit));return TCL_OK;}
    if(!strcmp(op,"part_marker_place")){double fraction;if(argc!=6)return TCL_ERROR;if(status(ip,gx2d_part_direction_place(s,id,part,device,&fraction))!=TCL_OK)return TCL_ERROR;Tcl_SetObjResult(ip,Tcl_NewDoubleObj(fraction));return TCL_OK;}
    return fail(ip,"Unknown constituent operation");
}
