#!/usr/bin/env python3
from pathlib import Path
import csv, math, json, hashlib
import numpy as np
import pandas as pd
import geopandas as gpd
import rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from shapely.geometry import box, Point, LineString
from pyproj import Transformer

SRC=Path('/mnt/data/ticino_bundle_check/ticino_valley_source_bundle')
OUT=Path('/mnt/data/ticino_normalized')
OUT.mkdir(parents=True,exist_ok=True)

# Final complete UTM grid, chosen as the largest simple snapped rectangle that stays
# inside the supplied study polygon while preserving the full requested river corridor.
EPSG=25832
ORIGIN_E=458000.0
ORIGIN_N=4995000.0
E_MAX=526000.0
N_MAX=5075000.0
CELL=1000.0
NX=int((E_MAX-ORIGIN_E)/CELL)
NY=int((N_MAX-ORIGIN_N)/CELL)
assert NX==68 and NY==80
study_poly=gpd.read_file(SRC/'extent/study_extent_25832.gpkg').geometry.iloc[0]
final_rect=box(ORIGIN_E,ORIGIN_N,E_MAX,N_MAX)
assert study_poly.contains(final_rect)

# Grid cells ordered south->north, west->east for stable CSV identity.
rows=[]; geoms=[]
for j in range(NY):
    y0=ORIGIN_N+j*CELL
    for i in range(NX):
        x0=ORIGIN_E+i*CELL
        gid=f'G{j:03d}_{i:03d}'
        geoms.append(box(x0,y0,x0+CELL,y0+CELL))
        rows.append((gid,i,j,x0+CELL/2,y0+CELL/2))
grid=gpd.GeoDataFrame(rows,columns=['grid_id','grid_i','grid_j','easting_m','northing_m'],geometry=geoms,crs=f'EPSG:{EPSG}')

# Coordinate transforms.
to4326=Transformer.from_crs(EPSG,4326,always_xy=True)
lon,lat=to4326.transform(grid['easting_m'].to_numpy(),grid['northing_m'].to_numpy())
grid['x_km']=(grid['easting_m']-ORIGIN_E)/1000.0
grid['y_km']=(grid['northing_m']-ORIGIN_N)/1000.0
grid['longitude_deg']=lon
grid['latitude_deg']=lat

# DEM aggregate onto exactly the 68 x 80 grid. Raster destination rows are north->south;
# later mapped by grid_i/grid_j to CSV's south->north ordering.
dem_path=SRC/'terrain/cop_dem_glo30_25832.tif'
dst_transform=from_origin(ORIGIN_E,N_MAX,CELL,CELL)
shape=(NY,NX)
with rasterio.open(dem_path) as src:
    src_arr=src.read(1)
    src_nodata=src.nodata
    out_stats={}
    for name,resampling in [('elevation_m',Resampling.average),('min_elevation_m',Resampling.min),('max_elevation_m',Resampling.max)]:
        dest=np.full(shape,np.nan,dtype='float64')
        reproject(src_arr,dest,src_transform=src.transform,src_crs=src.crs,src_nodata=src_nodata,
                  dst_transform=dst_transform,dst_crs=f'EPSG:{EPSG}',dst_nodata=np.nan,resampling=resampling)
        out_stats[name]=dest
for name,arr in out_stats.items():
    vals=[]
    for _,r in grid.iterrows():
        rr=NY-1-int(r.grid_j); cc=int(r.grid_i)
        vals.append(float(arr[rr,cc]))
    grid[name]=vals
    assert np.isfinite(grid[name]).all(), name

# Population: area-weight source ISTAT 1km cells to the target UTM grid.
pop=gpd.read_file(SRC/'population/istat_2021_grid_1km_25832.gpkg')[['GRD_ID','T','geometry']].copy()
pop['source_area_m2']=pop.geometry.area
inter=gpd.overlay(grid[['grid_id','geometry']],pop,how='intersection',keep_geom_type=False)
inter['intersection_area_m2']=inter.geometry.area
inter['allocated_population']=inter['T'].astype(float)*inter['intersection_area_m2']/inter['source_area_m2']
pop_alloc=inter.groupby('grid_id',sort=False)['allocated_population'].sum()
grid['population']=grid['grid_id'].map(pop_alloc).fillna(0.0).astype(float)
grid['population_density_km2']=grid['population'] # exact target area = 1 km2

# CORINE land-cover fractions: exact polygon area per target cell.
clc=gpd.read_file(SRC/'landcover/clc2018_v2020_20u1_25832.gpkg')[['Code_18','geometry']].copy()
li=gpd.overlay(grid[['grid_id','geometry']],clc,how='intersection',keep_geom_type=False)
li['area_m2']=li.geometry.area
built={'111','112','121','122','123','124','131','132','133','141','142'}
forest={'311','312','313'}
agri={'211','212','213','221','222','223','231','241','242','243','244'}
water={'511','512'}
def frac_for(codes):
    s=li[li['Code_18'].astype(str).isin(codes)].groupby('grid_id')['area_m2'].sum()/1_000_000.0
    return grid['grid_id'].map(s).fillna(0.0).astype(float)
grid['built_fraction']=frac_for(built)
grid['forest_fraction']=frac_for(forest)
grid['agriculture_fraction']=frac_for(agri)
grid['water_fraction']=frac_for(water)
li_total=li.groupby('grid_id')['area_m2'].sum()/1_000_000.0
grid['landcover_coverage_fraction']=grid['grid_id'].map(li_total).fillna(0.0).astype(float)
grid['other_land_fraction']=(grid['landcover_coverage_fraction']-grid[['built_fraction','forest_fraction','agriculture_fraction','water_fraction']].sum(axis=1)).clip(lower=0.0)

# Ticino route and distance.
river_gdf=gpd.read_file(SRC/'hydrography/ticino_ordered_candidate_25832.gpkg')
river=river_gdf.geometry.iloc[0]
if river.geom_type=='MultiLineString':
    # Package validation says candidate is a single ordered route, but normalize defensively.
    river=max(river.geoms,key=lambda g:g.length)
assert isinstance(river,LineString)
grid['distance_to_ticino_km']=[Point(x,y).distance(river)/1000.0 for x,y in zip(grid.easting_m,grid.northing_m)]
grid['in_study_corridor']=(grid['distance_to_ticino_km']<=20.0).astype(int)

# Save grid CSV without geometry.
grid_cols=['grid_id','grid_i','grid_j','easting_m','northing_m','x_km','y_km','latitude_deg','longitude_deg',
           'elevation_m','min_elevation_m','max_elevation_m','population','population_density_km2',
           'built_fraction','forest_fraction','agriculture_fraction','water_fraction','other_land_fraction',
           'distance_to_ticino_km','in_study_corridor']
grid[grid_cols].to_csv(OUT/'ticino_valley_grid.csv',index=False,float_format='%.12g')

# Settlements: inhabited localities only (ISTAT TIPO_LOC 1=center, 2=nucleus), inside final rectangle.
sett=gpd.read_file(SRC/'settlements/istat_localities_2021_25832.gpkg')
sett=sett[sett.geometry.within(final_rect) & sett['TIPO_LOC'].isin([1,2])].copy()
sett=sett.sort_values(['POP21','NOME'],ascending=[False,True],na_position='last').reset_index(drop=True)
sett_class={1:'inhabited_centre',2:'inhabited_nucleus'}
# sample actual DEM at points
with rasterio.open(dem_path) as ds:
    samples=[]
    for v in ds.sample([(p.x,p.y) for p in sett.geometry]):
        z=float(v[0]); samples.append(np.nan if z==ds.nodata else z)
sett['settlement_id']=[f'S{i+1:04d}' for i in range(len(sett))]
sett['easting_m']=sett.geometry.x
sett['northing_m']=sett.geometry.y
sett['x_km']=(sett['easting_m']-ORIGIN_E)/1000.0
sett['y_km']=(sett['northing_m']-ORIGIN_N)/1000.0
slon,slat=to4326.transform(sett['easting_m'].to_numpy(),sett['northing_m'].to_numpy())
sett['longitude_deg']=slon; sett['latitude_deg']=slat
sett['ground_elevation_m']=samples
sett['population']=pd.to_numeric(sett['POP21'],errors='coerce')
sett['population_reference_year']=2021
sett['settlement_class']=sett['TIPO_LOC'].map(sett_class)
sett['distance_to_ticino_km']=[p.distance(river)/1000.0 for p in sett.geometry]
# Keep representative inhabited localities for the demo: actual source population >=50 and within 20 km of the Ticino.
sett=sett[(pd.to_numeric(sett['population'],errors='coerce').fillna(0)>=50) & (sett['distance_to_ticino_km']<=20.0)].copy().reset_index(drop=True)
# Repair occasional legacy UTF-8-as-Latin-1 mojibake from source service/container encodings.
def repair_text(v):
    if not isinstance(v,str): return v
    if 'Ã' in v or 'Â' in v:
        try: return v.encode('latin1').decode('utf-8')
        except Exception: return v
    return v
sett=sett.rename(columns={'NOME':'name'})
sett['name']=sett['name'].map(repair_text)
sett['settlement_id']=[f'S{i+1:04d}' for i in range(len(sett))]
sett_cols=['settlement_id','LOC_ID','name','easting_m','northing_m','x_km','y_km','latitude_deg','longitude_deg','ground_elevation_m','population','population_reference_year','settlement_class','distance_to_ticino_km']
sett[sett_cols].to_csv(OUT/'ticino_valley_settlements.csv',index=False,float_format='%.12g')

# River centerline sampled at fixed 250 m chainage plus endpoint.
step=250.0
chains=list(np.arange(0.0,river.length,step))
if not math.isclose(chains[-1],river.length): chains.append(float(river.length))
pts=[river.interpolate(c) for c in chains]
with rasterio.open(dem_path) as ds:
    rz=[]
    for v in ds.sample([(p.x,p.y) for p in pts]):
        z=float(v[0]); rz.append(np.nan if z==ds.nodata else z)
re=np.array([p.x for p in pts]); rn=np.array([p.y for p in pts]); rlon,rlat=to4326.transform(re,rn)
river_df=pd.DataFrame({
    'river_point_id':[f'R{i+1:04d}' for i in range(len(pts))],
    'chainage_km':np.array(chains)/1000.0,
    'easting_m':re,'northing_m':rn,
    'x_km':(re-ORIGIN_E)/1000.0,'y_km':(rn-ORIGIN_N)/1000.0,
    'latitude_deg':rlat,'longitude_deg':rlon,
    'terrain_or_bed_reference_elevation_m':rz,
})
assert np.isfinite(river_df['terrain_or_bed_reference_elevation_m']).all()
river_df.to_csv(OUT/'ticino_river_centerline.csv',index=False,float_format='%.12g')

# Synthetic hydraulic ribbon: 1 km longitudinal spacing x 5 lateral offsets.
# Real geometry/DEM only provide spatial context. Hydraulic bed, water level and velocity are synthetic.
hstep=1000.0
hchains=list(np.arange(0.0,river.length,hstep))
if not math.isclose(hchains[-1],river.length): hchains.append(float(river.length))
offsets=np.array([-400.0,-200.0,0.0,200.0,400.0])
centres=[river.interpolate(c) for c in hchains]
# DEM sample at centerline for spatially anchored reference.
with rasterio.open(dem_path) as ds:
    centre_z=[]
    for v in ds.sample([(p.x,p.y) for p in centres]):
        z=float(v[0]); centre_z.append(np.nan if z==ds.nodata else z)
centre_z=np.asarray(centre_z,float)
assert np.isfinite(centre_z).all()
# Monotone synthetic bed reference derived from a smoothed/cumulative-minimum terrain envelope.
k=7
pad=np.pad(centre_z,(k//2,k//2),mode='edge')
sm=np.convolve(pad,np.ones(k)/k,mode='valid')
bed_center=np.minimum.accumulate(sm)
# depth varies deterministically, always positive; water surface follows bed+depth.
L=river.length
rows=[]
with rasterio.open(dem_path) as ds:
    for si,(c,p,bc) in enumerate(zip(hchains,centres,bed_center)):
        delta=20.0
        c0=max(0.0,c-delta); c1=min(L,c+delta)
        p0=river.interpolate(c0); p1=river.interpolate(c1)
        dx=p1.x-p0.x; dy=p1.y-p0.y; norm=math.hypot(dx,dy)
        nx=-dy/norm; ny=dx/norm
        depth_center=3.2 + 0.55*math.sin(2*math.pi*c/L) + 0.25*math.cos(4*math.pi*c/L)
        ws=bc+depth_center
        for oi,off in enumerate(offsets):
            x=p.x+nx*off; y=p.y+ny*off
            terrain=float(next(ds.sample([(x,y)]))[0]);
            if terrain==ds.nodata: terrain=np.nan
            lateral=(off/400.0)
            bed=bc + 1.2*(lateral*lateral)
            depth=max(0.0,ws-bed)
            v_center=1.25 + 0.18*math.sin(2*math.pi*c/L+0.35)
            velocity=max(0.0,v_center*(1.0-0.55*lateral*lateral))
            lo,la=to4326.transform(x,y)
            rows.append({
                'hydro_cell_id':f'H{si:03d}_{oi:02d}',
                'easting_m':x,'northing_m':y,'x_km':(x-ORIGIN_E)/1000.0,'y_km':(y-ORIGIN_N)/1000.0,
                'latitude_deg':la,'longitude_deg':lo,'chainage_km':c/1000.0,'lateral_offset_m':off,
                'terrain_reference_elevation_m':terrain,'bed_elevation_m':bed,
                'water_surface_elevation_m':ws,'water_depth_m':depth,'velocity_m_s':velocity,
            })
hyd=pd.DataFrame(rows)
assert np.isfinite(hyd[['bed_elevation_m','water_surface_elevation_m','water_depth_m','velocity_m_s']].to_numpy()).all()
assert (hyd.water_depth_m>=0).all() and (hyd.velocity_m_s>=0).all()
assert np.allclose(hyd.water_surface_elevation_m,hyd.bed_elevation_m+hyd.water_depth_m,atol=1e-10)
hyd.to_csv(OUT/'ticino_hydraulic_demo.csv',index=False,float_format='%.12g')

# Extent/provenance summary.
final_wgs=gpd.GeoSeries([final_rect],crs=f'EPSG:{EPSG}').to_crs(4326).total_bounds
summary={
 'crs':'EPSG:25832','origin_easting_m':ORIGIN_E,'origin_northing_m':ORIGIN_N,
 'easting_min_m':ORIGIN_E,'easting_max_m':E_MAX,'northing_min_m':ORIGIN_N,'northing_max_m':N_MAX,
 'longitude_min_deg':float(final_wgs[0]),'latitude_min_deg':float(final_wgs[1]),'longitude_max_deg':float(final_wgs[2]),'latitude_max_deg':float(final_wgs[3]),
 'grid_nx':NX,'grid_ny':NY,'grid_cells':NX*NY,'cell_size_m':CELL,
 'settlement_count':len(sett),'river_points':len(river_df),'river_length_km':river.length/1000.0,
 'hydraulic_longitudinal_stations':len(hchains),'hydraulic_lateral_points':len(offsets),'hydraulic_points':len(hyd),
 'analysis_corridor_max_distance_km':20.0,
 'analysis_corridor_cells':int(grid.in_study_corridor.sum()),
 'population_total_estimated':float(grid.loc[grid.in_study_corridor==1,'population'].sum()),
 'elevation_min_m':float(grid.loc[grid.in_study_corridor==1,'elevation_m'].min()),'elevation_max_m':float(grid.loc[grid.in_study_corridor==1,'elevation_m'].max()),'elevation_mean_m':float(grid.loc[grid.in_study_corridor==1,'elevation_m'].mean()),
 'built_area_km2':float(grid.loc[grid.in_study_corridor==1,'built_fraction'].sum()),'forest_area_km2':float(grid.loc[grid.in_study_corridor==1,'forest_fraction'].sum()),
 'agriculture_area_km2':float(grid.loc[grid.in_study_corridor==1,'agriculture_fraction'].sum()),'water_area_km2':float(grid.loc[grid.in_study_corridor==1,'water_fraction'].sum()),
 'hydraulic_depth_min_m':float(hyd.water_depth_m.min()),'hydraulic_depth_max_m':float(hyd.water_depth_m.max()),'hydraulic_depth_mean_m':float(hyd.water_depth_m.mean()),
 'hydraulic_velocity_min_m_s':float(hyd.velocity_m_s.min()),'hydraulic_velocity_max_m_s':float(hyd.velocity_m_s.max()),'hydraulic_velocity_mean_m_s':float(hyd.velocity_m_s.mean()),
 'hydraulic_water_surface_drop_m':float(hyd.groupby('chainage_km').water_surface_elevation_m.first().iloc[0]-hyd.groupby('chainage_km').water_surface_elevation_m.first().iloc[-1]),
}
(OUT/'normalized_summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n',encoding='utf-8')
# hashes
with (OUT/'SHA256SUMS').open('w',encoding='utf-8') as f:
    for p in sorted(OUT.glob('*.csv')):
        h=hashlib.sha256(p.read_bytes()).hexdigest(); f.write(f'{h}  {p.name}\n')
print(json.dumps(summary,indent=2,sort_keys=True))
print('\nCSV hashes:')
print((OUT/'SHA256SUMS').read_text())
