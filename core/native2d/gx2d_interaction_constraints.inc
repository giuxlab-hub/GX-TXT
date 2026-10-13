/* SPDX-License-Identifier: GPL-3.0-or-later */
static int interaction_is_line(const object *o){return o&&o->sketch&&(o->sketch->family==GX2D_SKETCH_LINE||o->sketch->family==GX2D_SKETCH_CONSTRUCTION_LINE||(o->sketch->family==GX2D_SKETCH_PATH&&o->sketch->control_count==2&&!o->sketch->path_closed));}
gx2d_status gx2d_constraint_location(const gx2d_scene *s,gx2d_id id,gx2d_point *out){
    size_t i;if(!s||!out)return GX2D_INVALID;
    for(i=0;i<s->rule_count;++i)if(s->rules[i].id==id)return constraint_point(cobj(s,s->rules[i].spec.a),s->rules[i].spec.a_index,out);
    return GX2D_NOT_FOUND;
}
static int interaction_is_round(const object *o){double radius;return constraint_radius(o,&radius)==GX2D_OK;}
static int interaction_is_point(const gx2d_reference *r){return r->entity==GX2D_ENTITY_CONTROL;}
static size_t interaction_segment_index(const object *o,const gx2d_reference *r){
    if(r->entity==GX2D_ENTITY_SEGMENT)return r->index;
    return o->sketch?GX2D_SEGMENT_INDEX:0;
}
static gx2d_status constraint_from_leaf_selection(const gx2d_scene *s,gx2d_constraint_kind kind,
    const gx2d_reference *refs,size_t n,gx2d_constraint_v2 *out) {
    gx2d_constraint_v2 d;gx2d_point p[3],a,b,dir;const object *oa,*ob;size_t i;double radius;gx2d_status code;
    if(!s||!refs||!out||n<1||n>3)return GX2D_INVALID;
    for(i=0;i<n;++i){code=gx2d_reference_resolve(s,&refs[i],&p[i]);if(code!=GX2D_OK)return code;}
    oa=cobj(s,refs[0].object);ob=n>1?cobj(s,refs[1].object):NULL;
    memset(&d,0,sizeof(d));d.base=(gx2d_constraint){kind,refs[0].object,n>1?refs[1].object:0,refs[0].index,n>1?refs[1].index:0,0,1e-8};d.angular_tolerance=1e-9;
    switch(kind){
    case GX2D_FIXED:if(n!=1)return GX2D_INVALID;
        if(refs[0].entity!=GX2D_ENTITY_CONTROL)d.base.a_index=GX2D_OBJECT_INDEX;
        break;
    case GX2D_LOCK_X:case GX2D_LOCK_Y:if(n!=1||!interaction_is_point(&refs[0]))return GX2D_INVALID;d.base.value=kind==GX2D_LOCK_X?p[0].x:p[0].y;break;
    case GX2D_RADIUS:case GX2D_DIAMETER:if(n!=1||!interaction_is_round(oa))return GX2D_INVALID;constraint_radius(oa,&radius);d.base.a_index=GX2D_OBJECT_INDEX;d.base.value=radius*(kind==GX2D_DIAMETER?2:1);break;
    case GX2D_HORIZONTAL:case GX2D_VERTICAL:
        if(n==2&&interaction_is_point(&refs[0])&&interaction_is_point(&refs[1]))break;
        if(n!=1||refs[0].entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
        d.base.a_index=interaction_segment_index(oa,&refs[0]);if(constraint_segment(oa,d.base.a_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;break;
    case GX2D_DISTANCE:
        /* A selected straight path segment dimensions its real shared vertices,
         * rather than the whole path or display-sample endpoints. */
        if(n==1&&refs[0].entity==GX2D_ENTITY_SEGMENT&&oa->sketch&&
           (oa->sketch->family==GX2D_SKETCH_PATH||oa->sketch->family==GX2D_SKETCH_POLYLINE)){
            size_t ordinal=refs[0].index-GX2D_SEGMENT_INDEX;
            if(constraint_segment(oa,refs[0].index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;
            d.base.b=oa->id;d.base.a_index=GX2D_CONTROL_INDEX+ordinal;
            d.base.b_index=GX2D_CONTROL_INDEX+(ordinal+1)%oa->sketch->control_count;
            p[0]=a;p[1]=b;
        }
        else if(n==1&&interaction_is_line(oa)&&refs[0].entity!=GX2D_ENTITY_CONTROL){d.base.b=oa->id;d.base.a_index=GX2D_CONTROL_INDEX;d.base.b_index=GX2D_CONTROL_INDEX+1;constraint_point(oa,d.base.a_index,&p[0]);constraint_point(oa,d.base.b_index,&p[1]);}
        else if(n!=2||!interaction_is_point(&refs[0])||!interaction_is_point(&refs[1]))return GX2D_INVALID;
        d.base.value=dist(p[0],p[1]);break;
    case GX2D_COINCIDENT:
        if(n==2&&(interaction_is_point(&refs[0])!=interaction_is_point(&refs[1]))){
            int first=interaction_is_point(&refs[0])?0:1,second=1-first;const object *curve=cobj(s,refs[second].object);if(!curve||!curve->sketch)return GX2D_INVALID;
            d.base.kind=GX2D_POINT_ON_CURVE;d.base.a=refs[first].object;d.base.a_index=refs[first].index;d.base.b=refs[second].object;d.base.b_index=GX2D_OBJECT_INDEX;break;
        }
        if(n!=2||!interaction_is_point(&refs[0])||!interaction_is_point(&refs[1])||(refs[0].object==refs[1].object&&refs[0].index==refs[1].index))return GX2D_INVALID;break;
    case GX2D_PARALLEL:case GX2D_PERPENDICULAR:case GX2D_ANGLE:case GX2D_COLLINEAR:case GX2D_EQUAL_LENGTH:
        if(n!=2||refs[0].entity==GX2D_ENTITY_CONTROL||refs[1].entity==GX2D_ENTITY_CONTROL||(oa==ob&&!(refs[0].entity==GX2D_ENTITY_SEGMENT&&refs[1].entity==GX2D_ENTITY_SEGMENT&&refs[0].index!=refs[1].index)))return GX2D_INVALID;
        d.base.a_index=interaction_segment_index(oa,&refs[0]);d.base.b_index=interaction_segment_index(ob,&refs[1]);
        if(constraint_segment(oa,d.base.a_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;
        gx2d_point other;if(constraint_segment(ob,d.base.b_index,&a,&b,&other)!=GX2D_OK)return GX2D_INVALID;
        if(kind==GX2D_EQUAL_LENGTH&&(!oa->sketch||!ob->sketch))return GX2D_INVALID;
        if(kind==GX2D_ANGLE)d.base.value=atan2(dir.x*other.y-dir.y*other.x,dir.x*other.x+dir.y*other.y);break;
    case GX2D_EQUAL_RADIUS:case GX2D_CONCENTRIC:
        if(n!=2||oa==ob||(kind==GX2D_EQUAL_RADIUS?(!interaction_is_round(oa)||!interaction_is_round(ob)):(constraint_center(oa,&a)!=GX2D_OK||constraint_center(ob,&b)!=GX2D_OK))||refs[0].entity==GX2D_ENTITY_CONTROL||refs[1].entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
        d.base.a_index=d.base.b_index=GX2D_OBJECT_INDEX;break;
    case GX2D_TANGENT:case GX2D_CURVATURE:
        if(n!=2||oa==ob||!oa->sketch||!ob->sketch)return GX2D_INVALID;
        if(kind==GX2D_TANGENT&&refs[0].entity!=GX2D_ENTITY_CONTROL&&refs[1].entity!=GX2D_ENTITY_CONTROL) {
            if(interaction_is_round(oa)&&interaction_is_round(ob)){d.base.a_index=d.base.b_index=GX2D_OBJECT_INDEX;break;}
            if(interaction_is_round(oa)!=interaction_is_round(ob)) {
                int z=interaction_is_round(oa)?1:0;const object *line=z?ob:oa;
                size_t ix=interaction_segment_index(line,&refs[z]);
                if((refs[z].entity==GX2D_ENTITY_SEGMENT||interaction_is_line(line))&&constraint_segment(line,ix,&a,&b,&dir)==GX2D_OK) {
                    d.base.a_index=z?GX2D_OBJECT_INDEX:ix;d.base.b_index=z?ix:GX2D_OBJECT_INDEX;break;
                }
            }
        }
        if(interaction_is_round(oa)!=interaction_is_round(ob)){
            const object *round=interaction_is_round(oa)?oa:ob,*curve=round==oa?ob:oa;int z=curve==oa?0:1;
            gx2d_sketch_family f=curve->sketch->family;if(f!=GX2D_SKETCH_QUADRATIC_BEZIER&&f!=GX2D_SKETCH_CUBIC_BEZIER&&f!=GX2D_SKETCH_SPLINE)return GX2D_INVALID;
            gx2d_point center,left,right;double r;constraint_center(round,&center);constraint_radius(round,&r);size_t first=GX2D_CONTROL_INDEX,last=GX2D_CONTROL_INDEX+curve->sketch->control_count-1;
            constraint_point(curve,first,&left);constraint_point(curve,last,&right);size_t ix=fabs(dist(left,center)-r)<fabs(dist(right,center)-r)?first:last;
            if(refs[z].entity==GX2D_ENTITY_CONTROL){ix=refs[z].index;if(ix!=first&&ix!=last)return GX2D_INVALID;}
            d.base.a_index=z==0?ix:GX2D_OBJECT_INDEX;d.base.b_index=z==1?ix:GX2D_OBJECT_INDEX;break;
        }
        /* Exact endpoint joins: choose the closest pair for object selection,
         * or respect the user's explicit endpoint controls. */
        size_t choices[2][2];double best=DBL_MAX;size_t ia=0,ib=0;
        const object *curves[2]={oa,ob};for(int z=0;z<2;z++){
            gx2d_sketch_family f=curves[z]->sketch->family;
            if(f==GX2D_SKETCH_PATH&&curves[z]->sketch->path_closed)return GX2D_INVALID;
            if(f!=GX2D_SKETCH_LINE&&f!=GX2D_SKETCH_CONSTRUCTION_LINE&&f!=GX2D_SKETCH_PATH&&f!=GX2D_SKETCH_ARC&&f!=GX2D_SKETCH_QUADRATIC_BEZIER&&f!=GX2D_SKETCH_CUBIC_BEZIER&&f!=GX2D_SKETCH_SPLINE)return GX2D_INVALID;
            choices[z][0]=GX2D_CONTROL_INDEX+(f==GX2D_SKETCH_ARC?1:0);choices[z][1]=GX2D_CONTROL_INDEX+(f==GX2D_SKETCH_ARC?2:curves[z]->sketch->control_count-1);
            if(refs[z].entity==GX2D_ENTITY_CONTROL){if(refs[z].index!=choices[z][0]&&refs[z].index!=choices[z][1])return GX2D_INVALID;choices[z][0]=choices[z][1]=refs[z].index;}
        }
        for(int x=0;x<2;x++)for(int y=0;y<2;y++){constraint_point(oa,choices[0][x],&a);constraint_point(ob,choices[1][y],&b);if(dist(a,b)<best){best=dist(a,b);ia=choices[0][x];ib=choices[1][y];}}
        if(kind==GX2D_CURVATURE&&(oa->sketch->family!=GX2D_SKETCH_QUADRATIC_BEZIER&&oa->sketch->family!=GX2D_SKETCH_CUBIC_BEZIER&&oa->sketch->family!=GX2D_SKETCH_SPLINE&&ob->sketch->family!=GX2D_SKETCH_QUADRATIC_BEZIER&&ob->sketch->family!=GX2D_SKETCH_CUBIC_BEZIER&&ob->sketch->family!=GX2D_SKETCH_SPLINE))return GX2D_INVALID;
        d.base.a_index=ia;d.base.b_index=ib;break;
    case GX2D_MIDPOINT:case GX2D_POINT_ON_LINE:case GX2D_POINT_ON_CURVE:
        if(n!=2||!interaction_is_point(&refs[0])||refs[1].entity==GX2D_ENTITY_CONTROL||oa==ob)return GX2D_INVALID;
        d.base.b_index=interaction_segment_index(ob,&refs[1]);
        if(kind==GX2D_POINT_ON_CURVE){double value;if(!ob->sketch&&constraint_curve_distance(s,ob,p[0],&value)!=GX2D_OK)return GX2D_INVALID;d.base.b_index=GX2D_OBJECT_INDEX;}
        else if(constraint_segment(ob,d.base.b_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;break;
    case GX2D_SYMMETRY:
        if(n!=3||refs[2].entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
        if(!interaction_is_point(&refs[0])||!interaction_is_point(&refs[1])){
            if(!oa->sketch||!ob->sketch||oa->sketch->family!=ob->sketch->family||oa->sketch->control_count!=ob->sketch->control_count)return GX2D_INVALID;
            gx2d_sketch_family f=oa->sketch->family;if(f==GX2D_SKETCH_ARC||f==GX2D_SKETCH_ELLIPSE||f==GX2D_SKETCH_RECTANGLE||(f==GX2D_SKETCH_CIRCLE&&(!interaction_is_round(oa)||!interaction_is_round(ob)))||oa->sketch->control_count>12)return GX2D_INVALID;
            d.base.a_index=d.base.b_index=GX2D_OBJECT_INDEX;
        }
        d.axis=refs[2].object;d.axis_index=interaction_segment_index(cobj(s,d.axis),&refs[2]);if(constraint_segment(cobj(s,d.axis),d.axis_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;break;
    case GX2D_HORIZONTAL_DISTANCE:case GX2D_VERTICAL_DISTANCE:
        if(n!=2||!interaction_is_point(&refs[0])||!interaction_is_point(&refs[1]))return GX2D_INVALID;
        d.base.value=fabs(kind==GX2D_HORIZONTAL_DISTANCE?p[1].x-p[0].x:p[1].y-p[0].y);break;
    case GX2D_AXIS_ANGLE:
        if(n!=1||refs[0].entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
        d.base.a_index=interaction_segment_index(oa,&refs[0]);if(constraint_segment(oa,d.base.a_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;d.base.value=atan2(dir.y,dir.x);break;
    case GX2D_POINT_LINE_DISTANCE:case GX2D_LINE_DISTANCE:
        if(n!=2||refs[1].entity==GX2D_ENTITY_CONTROL)return GX2D_INVALID;
        d.base.b_index=interaction_segment_index(ob,&refs[1]);if(constraint_segment(ob,d.base.b_index,&a,&b,&dir)!=GX2D_OK)return GX2D_INVALID;
        if(kind==GX2D_POINT_LINE_DISTANCE){if(!interaction_is_point(&refs[0]))return GX2D_INVALID;}
        else {gx2d_point other;d.base.a_index=interaction_segment_index(oa,&refs[0]);if(constraint_segment(oa,d.base.a_index,&p[0],&b,&other)!=GX2D_OK||fabs(other.x*dir.y-other.y*dir.x)>1e-6)return GX2D_INVALID;}
        d.base.value=fabs((p[0].x-a.x)*dir.y-(p[0].y-a.y)*dir.x);break;
    default:return GX2D_INVALID;
    }
    *out=d;return GX2D_OK;
}
gx2d_status gx2d_constraint_from_selection(const gx2d_scene *s,gx2d_constraint_kind kind,const gx2d_reference *refs,size_t n,gx2d_constraint_v2 *out){
    if(!s||!refs||n<1||n>3||!out)return GX2D_INVALID;
    for(size_t i=0;i<n;i++)for(size_t j=0;j<i;j++)if(refs[i].object==refs[j].object&&refs[i].index==refs[j].index)return GX2D_INVALID;
    object leaves[3];gx2d_sketch_definition definitions[3];gx2d_reference local[3];size_t parts[3]={0};int mapped[3]={0};
    gx2d_scene view=*s;view.objects=leaves;view.object_count=n;
    for(size_t i=0;i<n;i++){gx2d_point p;if(gx2d_reference_resolve(s,&refs[i],&p)!=GX2D_OK)return GX2D_INVALID;
        const object *root=cobj(s,refs[i].object);leaves[i]=*root;local[i]=refs[i];mapped[i]=network_leaf(root,&local[i].index,&leaves[i],&definitions[i],&parts[i]);if(mapped[i]<0)return GX2D_INVALID;
        leaves[i].id=i+1;local[i].object=i+1;
        if(local[i].index==GX2D_OBJECT_INDEX)local[i].entity=GX2D_ENTITY_OBJECT;
    }
    gx2d_status code=constraint_from_leaf_selection(&view,kind,local,n,out);if(code!=GX2D_OK)return code;
    gx2d_id *ids[3]={&out->base.a,&out->base.b,&out->axis};size_t *indices[3]={&out->base.a_index,&out->base.b_index,&out->axis_index};
    for(size_t j=0;j<3;j++)if(*ids[j]){size_t i=(size_t)*ids[j]-1;if(i>=n)return GX2D_INVALID;if(mapped[i])*indices[j]=network_index(cobj(s,refs[i].object),parts[i],*indices[j]);*ids[j]=refs[i].object;}
    return GX2D_OK;
}
static gx2d_status interaction_drive_point(object *o,size_t index,gx2d_point target) {
    gx2d_point local;size_t i;if(!finite2(target))return GX2D_RANGE;
    if(!o->sketch){if(index>=o->count)return GX2D_INVALID;o->points[index]=target;return GX2D_OK;}
    if(index<GX2D_CONTROL_INDEX||index>=GX2D_SEGMENT_INDEX)return GX2D_INVALID;i=index-GX2D_CONTROL_INDEX;
    if(i>=o->sketch->control_count)return GX2D_INVALID;
    gx2d_status code=interaction_inverse(o->sketch,target,&local);if(code!=GX2D_OK)return code;((gx2d_point *)o->sketch->controls)[i]=local;return GX2D_OK;
}
static gx2d_status interaction_drive(object *a,const object *b,const object *axis,const gx2d_constraint_v2 *spec) {
    const gx2d_constraint *c=&spec->base;gx2d_point p,q,pa,qa,da,pb,qb,db,target;double length,angle,radius,value;
    gx2d_status code=constraint_point(a,c->a_index,&p);if(code!=GX2D_OK)return code;
    if(b){code=constraint_point(b,c->b_index,&q);if(code!=GX2D_OK)return code;}
    switch(c->kind){
    case GX2D_FIXED:return GX2D_OK;
    case GX2D_LOCK_X:p.x=c->value;return interaction_drive_point(a,c->a_index,p);
    case GX2D_LOCK_Y:p.y=c->value;return interaction_drive_point(a,c->a_index,p);
    case GX2D_RADIUS:case GX2D_DIAMETER:case GX2D_EQUAL_RADIUS:
        if(!interaction_is_round(a))return GX2D_INVALID;
        radius=c->kind==GX2D_EQUAL_RADIUS?0:c->value/(c->kind==GX2D_DIAMETER?2:1);
        if(c->kind==GX2D_EQUAL_RADIUS){code=constraint_radius(b,&radius);if(code!=GX2D_OK)return code;}
        a->sketch->radius_x=radius/hypot(a->sketch->matrix[0],a->sketch->matrix[2]);return GX2D_OK;
    case GX2D_CONCENTRIC:code=constraint_center(b,&q);if(code!=GX2D_OK)return code;return interaction_drive_point(a,GX2D_CONTROL_INDEX,q);
    case GX2D_COINCIDENT:return interaction_drive_point(a,c->a_index,q);
    case GX2D_DISTANCE:
        if(c->a==c->b&&interaction_is_line(a)){length=dist(p,q);if(length==0||c->value<=0)return GX2D_INVALID;target=(gx2d_point){p.x+(q.x-p.x)*c->value/length,p.y+(q.y-p.y)*c->value/length};return interaction_drive_point(a,c->b_index,target);}
        length=dist(p,q);if(length==0&&c->value>0)return GX2D_INVALID;
        target=length==0?q:(gx2d_point){q.x+(p.x-q.x)*c->value/length,q.y+(p.y-q.y)*c->value/length};return interaction_drive_point(a,c->a_index,target);
    case GX2D_MIDPOINT:case GX2D_POINT_ON_LINE:
        code=constraint_segment(b,c->b_index,&pb,&qb,&db);if(code!=GX2D_OK)return code;
        if(c->kind==GX2D_MIDPOINT)target=(gx2d_point){pb.x/2+qb.x/2,pb.y/2+qb.y/2};
        else {value=(p.x-pb.x)*db.x+(p.y-pb.y)*db.y;target=(gx2d_point){pb.x+value*db.x,pb.y+value*db.y};}
        return interaction_drive_point(a,c->a_index,target);
    case GX2D_POINT_ON_CURVE:
        if(interaction_is_round(b)&&b->sketch->family==GX2D_SKETCH_CIRCLE){constraint_center(b,&pb);constraint_radius(b,&radius);length=dist(p,pb);if(length==0)return GX2D_INVALID;target=(gx2d_point){pb.x+(p.x-pb.x)*radius/length,pb.y+(p.y-pb.y)*radius/length};return interaction_drive_point(a,c->a_index,target);}
        return GX2D_OK; /* Validation-only for other supported exact curves. */
    case GX2D_SYMMETRY:
        code=constraint_segment(axis,spec->axis_index,&pa,&qa,&da);if(code!=GX2D_OK)return code;
        value=(q.x-pa.x)*da.x+(q.y-pa.y)*da.y;target=(gx2d_point){2*(pa.x+value*da.x)-q.x,2*(pa.y+value*da.y)-q.y};return interaction_drive_point(a,c->a_index,target);
    case GX2D_HORIZONTAL:case GX2D_VERTICAL:case GX2D_PARALLEL:case GX2D_PERPENDICULAR:case GX2D_ANGLE:case GX2D_COLLINEAR:case GX2D_EQUAL_LENGTH:case GX2D_TANGENT:
        /* Direct driving is intentionally limited to retained lines. Rectangle
         * edges and other supported references retain native validation. */
        if(!interaction_is_line(a))return GX2D_OK;
        code=constraint_segment(a,GX2D_SEGMENT_INDEX,&pa,&qa,&da);if(code!=GX2D_OK)return code;length=dist(pa,qa);
        if(c->kind==GX2D_HORIZONTAL)angle=da.x<0?acos(-1):0;
        else if(c->kind==GX2D_VERTICAL)angle=da.y<0?-acos(-1)/2:acos(-1)/2;
        else if(c->kind==GX2D_TANGENT){
            code=constraint_center(b,&pb);if(code!=GX2D_OK)return code;code=constraint_radius(b,&radius);if(code!=GX2D_OK)return code;
            value=(pb.x-pa.x)*(-da.y)+(pb.y-pa.y)*da.x;double delta=value-(value<0?-radius:radius);
            pa.x+=delta*(-da.y);pa.y+=delta*da.x;qa.x+=delta*(-da.y);qa.y+=delta*da.x;
            code=interaction_drive_point(a,GX2D_CONTROL_INDEX,pa);if(code!=GX2D_OK)return code;return interaction_drive_point(a,GX2D_CONTROL_INDEX+1,qa);
        }else{
            code=constraint_segment(b,c->b_index,&pb,&qb,&db);if(code!=GX2D_OK)return code;angle=atan2(db.y,db.x);
            if(c->kind==GX2D_PERPENDICULAR)angle+=acos(-1)/2;
            if(c->kind==GX2D_ANGLE)angle-=c->value;
            if(c->kind==GX2D_EQUAL_LENGTH){length=dist(pb,qb);angle=atan2(da.y,da.x);}
            if(c->kind==GX2D_COLLINEAR){value=(pa.x-pb.x)*db.x+(pa.y-pb.y)*db.y;pa=(gx2d_point){pb.x+value*db.x,pb.y+value*db.y};code=interaction_drive_point(a,GX2D_CONTROL_INDEX,pa);if(code!=GX2D_OK)return code;}
        }
        target=(gx2d_point){pa.x+length*cos(angle),pa.y+length*sin(angle)};return interaction_drive_point(a,GX2D_CONTROL_INDEX+1,target);
    default:return GX2D_INVALID;
    }
}
static gx2d_status interaction_legacy_apply(gx2d_scene *s,gx2d_id existing,const gx2d_constraint_v2 *spec,gx2d_id *out) {
    object *a;object before,candidate;gx2d_status code;gx2d_point *display=NULL;size_t n,i,rule_index=SIZE_MAX;rule oldrule;
    gx2d_constraint_v2 definition;gx2d_id result;
    if(!s||!spec||!out)return GX2D_INVALID;if(s->dragging)return GX2D_BUSY;
    a=obj(s,spec->base.a);if(!a)return GX2D_NOT_FOUND;definition=*spec;
    /* Validate scalar and structural contracts before a candidate can exist. */
    if(!isfinite(spec->base.value)||!isfinite(spec->base.tolerance)||spec->base.tolerance<=0||
       ((spec->base.kind==GX2D_DISTANCE||spec->base.kind==GX2D_RADIUS||spec->base.kind==GX2D_DIAMETER)&&spec->base.value<0))return GX2D_INVALID;
    if(existing){for(i=0;i<s->rule_count;++i)if(s->rules[i].id==existing){rule_index=i;break;}if(rule_index==SIZE_MAX)return GX2D_NOT_FOUND;oldrule=s->rules[rule_index];s->rules[rule_index].disabled=1;}
    if(!definition.disabled&&!can_move(s,a)){code=GX2D_LOCKED;goto restore_rule;}
    before=*a;candidate=*a;candidate.points=(gx2d_point *)malloc(a->count*sizeof(gx2d_point));candidate.sketch=a->sketch?sketch_clone(a->sketch):NULL;
    if(!candidate.points||(a->sketch&&!candidate.sketch)){code=GX2D_NOMEM;goto free_candidate;}
    memcpy(candidate.points,a->points,a->count*sizeof(gx2d_point));
    if(!definition.disabled){code=interaction_drive(&candidate,cobj(s,definition.base.b),cobj(s,definition.axis),&definition);if(code!=GX2D_OK)goto free_candidate;}
    if(candidate.sketch){code=sketch_display(candidate.sketch,candidate.count,&display,&n);if(code!=GX2D_OK)goto free_candidate;if(n!=candidate.count){code=GX2D_INVALID;goto free_candidate;}free(candidate.points);candidate.points=display;display=NULL;}
    *a=candidate;
    code=gx2d_check_constraints(s);
    if(code==GX2D_OK){if(existing){code=gx2d_constraint_update(s,existing,&definition);result=existing;}else code=gx2d_constraint_create(s,&definition,&result);}
    if(code!=GX2D_OK){*a=before;goto free_candidate;}
    free(before.points);sketch_free(before.sketch);*out=result;return GX2D_OK;
free_candidate:free(candidate.points);sketch_free(candidate.sketch);free(display);
restore_rule:if(existing)s->rules[rule_index]=oldrule;return code;
}
