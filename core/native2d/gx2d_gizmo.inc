/* Device-stable renderer-neutral CAD overlays and hit/gesture geometry. */
static gx2d_gizmo default_gizmo(void) {
    gx2d_gizmo g={0,GX2D_GIZMO_TRANSLATE,64,7,2,0,{0,0},{1,0},
        {.77,.11,.14,1},{.07,.38,.63,1},{.62,.35,0,1},{.14,.2,.27,1}};
    return g;
}
gx2d_status gx2d_gizmo_get(const gx2d_scene *s,gx2d_gizmo *g) {
    if(!s||!g)return GX2D_INVALID;*g=s->gizmo;return GX2D_OK;
}
gx2d_status gx2d_gizmo_set(gx2d_scene *s,const gx2d_gizmo *g) {
    if(!s||!g||(g->visible!=0&&g->visible!=1)||g->mode<GX2D_GIZMO_TRANSLATE||g->mode>GX2D_GIZMO_MIRROR||
       !isfinite(g->radius_px)||g->radius_px<20||g->radius_px>512||!isfinite(g->handle_px)||g->handle_px<3||g->handle_px>64||
       !isfinite(g->line_width)||g->line_width<=0||g->line_width>32||!isfinite(g->axes_angle)||
       !finite2(g->mirror_a)||!finite2(g->mirror_b)||!valid_color(g->x_color)||!valid_color(g->y_color)||
       !valid_color(g->rotation_color)||!valid_color(g->pivot_color))return GX2D_INVALID;
    if(g->mode==GX2D_GIZMO_MIRROR&&dist(g->mirror_a,g->mirror_b)==0)return GX2D_INVALID;
    if(s->dragging)return GX2D_BUSY;s->gizmo=*g;return GX2D_OK;
}
static void overlay_add(gx2d_overlay_primitive *p,size_t *n,gx2d_overlay_kind kind,
    gx2d_gizmo_handle handle,gx2d_point a,gx2d_point b,gx2d_color color,double width) {
    p[(*n)++]=(gx2d_overlay_primitive){kind,handle,a,b,color,width};
}
static void overlay_box(gx2d_overlay_primitive *p,size_t *n,gx2d_overlay_kind kind,
    gx2d_gizmo_handle handle,gx2d_point center,double radius,gx2d_color color,double width) {
    overlay_add(p,n,kind,handle,(gx2d_point){center.x-radius,center.y-radius},
        (gx2d_point){center.x+radius,center.y+radius},color,width);
}
static gx2d_point overlay_axis(const gx2d_scene *s,double angle) {
    double x=cos(angle)*(s->view.width-s->view.left-s->view.right)/(s->view.world.x1-s->view.world.x0);
    double y=-sin(angle)*(s->view.height-s->view.top-s->view.bottom)/(s->view.world.y1-s->view.world.y0),norm=hypot(x,y);
    return (gx2d_point){x/norm,y/norm};
}
static void overlay_arrow(gx2d_overlay_primitive *p,size_t *n,gx2d_point tip,gx2d_point unit,
    double head,gx2d_gizmo_handle handle,gx2d_color color,double width) {
    overlay_add(p,n,GX2D_OVERLAY_LINE,handle,tip,(gx2d_point){tip.x-head*unit.x+head*.5*unit.y,tip.y-head*unit.y-head*.5*unit.x},color,width);
    overlay_add(p,n,GX2D_OVERLAY_LINE,handle,tip,(gx2d_point){tip.x-head*unit.x-head*.5*unit.y,tip.y-head*unit.y+head*.5*unit.x},color,width);
}
gx2d_status gx2d_gizmo_render(const gx2d_scene *s,gx2d_overlay_primitive *out,size_t capacity,size_t *count) {
    gx2d_overlay_primitive p[64];gx2d_point pivot,center;gx2d_pivot_mode mode;
    gx2d_gizmo g;gx2d_status code;size_t n=0,i;double pi=acos(-1.);
    if(!s||!count)return GX2D_INVALID;g=s->gizmo;*count=0;if(!g.visible)return GX2D_OK;
    if(g.mode==GX2D_GIZMO_MIRROR) {
        gx2d_point a,b,delta,unit,mid;double length,extent;
        code=gx2d_world_to_device(s,g.mirror_a,&a);if(code!=GX2D_OK)return code;
        code=gx2d_world_to_device(s,g.mirror_b,&b);if(code!=GX2D_OK)return code;
        delta=(gx2d_point){b.x-a.x,b.y-a.y};length=hypot(delta.x,delta.y);if(length==0||!isfinite(length))return GX2D_RANGE;
        unit=(gx2d_point){delta.x/length,delta.y/length};mid=(gx2d_point){a.x*.5+b.x*.5,a.y*.5+b.y*.5};
        extent=hypot(s->view.width,s->view.height)*2;
        {gx2d_point first={mid.x-extent*unit.x,mid.y-extent*unit.y},last={mid.x+extent*unit.x,mid.y+extent*unit.y};
            gx2d_rect clip={s->view.left,s->view.top,s->view.width-s->view.right,s->view.height-s->view.bottom};
            if(clip_grid_segment(clip,&first,&last)) {
                first.x=fmax(clip.x0,fmin(clip.x1,first.x));first.y=fmax(clip.y0,fmin(clip.y1,first.y));
                last.x=fmax(clip.x0,fmin(clip.x1,last.x));last.y=fmax(clip.y0,fmin(clip.y1,last.y));
                overlay_add(p,&n,GX2D_OVERLAY_LINE,GX2D_HANDLE_NONE,first,last,g.rotation_color,g.line_width);
            }}
        overlay_box(p,&n,GX2D_OVERLAY_BOX,GX2D_HANDLE_MIRROR_A,a,g.handle_px,g.pivot_color,g.line_width);
        overlay_box(p,&n,GX2D_OVERLAY_BOX,GX2D_HANDLE_MIRROR_B,b,g.handle_px,g.pivot_color,g.line_width);
    } else {
        code=gx2d_pivot_get(s,&mode,&pivot);if(code!=GX2D_OK)return code;
        code=gx2d_world_to_device(s,pivot,&center);if(code!=GX2D_OK)return code;
        overlay_box(p,&n,GX2D_OVERLAY_CIRCLE,GX2D_HANDLE_PIVOT,center,g.handle_px,g.pivot_color,g.line_width);
        if(g.mode==GX2D_GIZMO_TRANSLATE) {
            for(i=0;i<2;++i) {
                gx2d_point unit=overlay_axis(s,g.axes_angle+i*pi*.5),tip={center.x+g.radius_px*unit.x,center.y+g.radius_px*unit.y};
                gx2d_gizmo_handle handle=i?GX2D_HANDLE_Y:GX2D_HANDLE_X;gx2d_color color=i?g.y_color:g.x_color;
                if(!finite2(unit)||!finite2(tip))return GX2D_RANGE;
                overlay_add(p,&n,GX2D_OVERLAY_LINE,handle,center,tip,color,g.line_width);
                overlay_arrow(p,&n,tip,unit,g.handle_px*1.5,handle,color,g.line_width);
                overlay_box(p,&n,GX2D_OVERLAY_BOX,handle,tip,g.handle_px*.6,color,g.line_width);
            }
            overlay_box(p,&n,GX2D_OVERLAY_BOX,GX2D_HANDLE_FREE,(gx2d_point){center.x+g.handle_px*3,center.y-g.handle_px*3},g.handle_px,g.pivot_color,g.line_width);
        } else {
            gx2d_point a={center.x+g.radius_px,center.y},b=a;
            for(i=1;i<=48;++i) {
                double theta=1.5*pi*i/48;b=(gx2d_point){center.x+g.radius_px*cos(theta),center.y+g.radius_px*sin(theta)};
                overlay_add(p,&n,GX2D_OVERLAY_LINE,GX2D_HANDLE_ROTATE,a,b,g.rotation_color,g.line_width);a=b;
            }
            overlay_arrow(p,&n,(gx2d_point){center.x+g.radius_px,center.y},(gx2d_point){0,-1},g.handle_px*1.5,GX2D_HANDLE_ROTATE,g.rotation_color,g.line_width);
            overlay_arrow(p,&n,b,(gx2d_point){1,0},g.handle_px*1.5,GX2D_HANDLE_ROTATE,g.rotation_color,g.line_width);
        }
    }
    for(i=0;i<n;++i)if(!finite2(p[i].a)||!finite2(p[i].b))return GX2D_RANGE;
    *count=n;if(out){if(capacity<n)return GX2D_RANGE;memcpy(out,p,n*sizeof(*out));}return GX2D_OK;
}
gx2d_status gx2d_gizmo_hit(const gx2d_scene *s,gx2d_point device,double tolerance,gx2d_gizmo_handle *handle) {
    gx2d_overlay_primitive p[64];size_t n,i;double best=DBL_MAX;gx2d_status code;
    if(!s||!handle||!finite2(device)||!isfinite(tolerance)||tolerance<0)return GX2D_INVALID;
    if(device.x<s->view.left||device.x>s->view.width-s->view.right||device.y<s->view.top||device.y>s->view.height-s->view.bottom) {*handle=GX2D_HANDLE_NONE;return GX2D_OK;}
    *handle=GX2D_HANDLE_NONE;code=gx2d_gizmo_render(s,p,64,&n);if(code==GX2D_NOT_FOUND)return GX2D_OK;if(code!=GX2D_OK)return code;
    for(i=0;i<n;++i) {
        double distance;gx2d_rect r={p[i].a.x,p[i].a.y,p[i].b.x,p[i].b.y};
        if(p[i].handle==GX2D_HANDLE_NONE)continue;
        if(p[i].kind==GX2D_OVERLAY_LINE)distance=dist(device,nearest_segment(device,p[i].a,p[i].b));
        else if(p[i].kind==GX2D_OVERLAY_CIRCLE) {
            gx2d_point center={r.x0*.5+r.x1*.5,r.y0*.5+r.y1*.5};
            distance=fmax(0,dist(center,device)-(r.x1-r.x0)*.5);
        }
        else if(inside(r,device))distance=0;
        else {gx2d_point q={fmax(r.x0,fmin(r.x1,device.x)),fmax(r.y0,fmin(r.y1,device.y))};distance=dist(q,device);}
        if(distance<=tolerance&&distance<best){best=distance;*handle=p[i].handle;}
    }
    return GX2D_OK;
}
gx2d_status gx2d_gizmo_parameters(const gx2d_scene *s,gx2d_gizmo_handle handle,
    gx2d_point start,gx2d_point current,gx2d_gizmo_delta *out) {
    gx2d_gizmo_delta result;gx2d_point a,b;gx2d_pivot_mode mode;gx2d_status code;
    if(!s||!out||handle<GX2D_HANDLE_PIVOT||handle>GX2D_HANDLE_MIRROR_B||!finite2(start)||!finite2(current))return GX2D_INVALID;
    memset(&result,0,sizeof(result));
    if(s->dragging){gx2d_scene baseline=*s;baseline.view=s->drag_view;code=gx2d_device_to_world(&baseline,start,&a);}
    else code=gx2d_device_to_world(s,start,&a);
    if(code!=GX2D_OK)return code;
    code=gx2d_device_to_world(s,current,&b);if(code!=GX2D_OK)return code;result.world_point=b;
    if(handle==GX2D_HANDLE_MIRROR_A||handle==GX2D_HANDLE_MIRROR_B){result.pivot=handle==GX2D_HANDLE_MIRROR_A?s->gizmo.mirror_a:s->gizmo.mirror_b;}
    else {code=gx2d_pivot_get(s,&mode,&result.pivot);if(code!=GX2D_OK)return code;}
    result.translation=(gx2d_point){b.x-a.x,b.y-a.y};
    if(handle==GX2D_HANDLE_X||handle==GX2D_HANDLE_Y) {
        double angle=s->gizmo.axes_angle+(handle==GX2D_HANDLE_Y?acos(-1.)*.5:0),x=cos(angle),y=sin(angle);
        double projected=result.translation.x*x+result.translation.y*y;
        result.translation=(gx2d_point){projected*x,projected*y};
    } else if(handle==GX2D_HANDLE_ROTATE) {
        gx2d_point u={a.x-result.pivot.x,a.y-result.pivot.y},v={b.x-result.pivot.x,b.y-result.pivot.y};
        double nu=hypot(u.x,u.y),nv=hypot(v.x,v.y);
        if(nu==0||nv==0||!isfinite(nu)||!isfinite(nv))return GX2D_INVALID;
        result.radians=atan2((u.x/nu)*(v.y/nv)-(u.y/nu)*(v.x/nv),(u.x/nu)*(v.x/nv)+(u.y/nu)*(v.y/nv));
    }
    if(!finite2(result.translation)||!finite2(result.world_point)||!isfinite(result.radians))return GX2D_RANGE;
    *out=result;return GX2D_OK;
}
