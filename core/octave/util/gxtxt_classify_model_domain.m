function [inside, classification] = gxtxt_classify_model_domain(domain, points, tolerance)
% Classify query points against a convex hull in MODEL INPUT SPACE.
% No output-Y or presentation orientation is used by this function.
  if(nargin<3||isempty(tolerance)),tolerance=[];endif
  domain=gxtxt_validate_model_domain(domain,{},'');V=domain.vertices;d=columns(V);
  if(isvector(points)&&d==1),points=points(:);endif
  if(!isnumeric(points)||columns(points)!=d),error('gxtxt_classify_model_domain: query point dimensionality mismatch');endif
  if(any(!isfinite(points(:)))),error('gxtxt_classify_model_domain: query coordinates must be finite');endif
  scale=max(1,max(max(V)-min(V)));
  if(isempty(tolerance)),tol=1e-9*scale;else tol=abs(double(tolerance));endif
  inside=true(rows(points),1);
  if(d==1)
    lo=min(V(:,1));hi=max(V(:,1));inside=(points(:,1)>=lo-tol)&(points(:,1)<=hi+tol);
  else
    facets=convhulln(V);
    centroid=mean(V,1);
    for fi=1:rows(facets)
      ids=facets(fi,:);p0=V(ids(1),:);E=V(ids(2:end),:)-p0;
      N=null(E);if(isempty(N)),error('gxtxt_classify_model_domain: cannot construct hull facet normal');endif
      n=N(:,1)';nn=norm(n);if(nn==0),continue;endif;n=n/nn;
      if((centroid-p0)*n'>0),n=-n;endif
      signed=(points-p0)*n';inside=inside&(signed<=tol);
    endfor
  endif
  classification=repmat({'outside'},rows(points),1);classification(inside)={'inside'};
endfunction
