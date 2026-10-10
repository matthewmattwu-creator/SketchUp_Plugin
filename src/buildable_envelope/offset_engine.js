/* Local uniform and variable setback engine. Coordinates are meters, integer grid 0.1 micrometer. */
(function(root) {
'use strict';
const C = typeof module==='object' && module.exports ? require('./vendor/clipper') : root.ClipperLib;
const SCALE=10000000;
function solve(points,setbacks) {
 if(!Array.isArray(points)||points.length<3||points.length>5000)throw Error('原红线顶点数量无效');
 if(!Array.isArray(setbacks)||setbacks.length!==points.length)throw Error('退线数量必须与原红线边数一致');
 const ds=setbacks.map(Number);
 if(ds.some(d=>!Number.isFinite(d)||d<0||d>1000000))throw Error('退线数值无效');
 const uniform=ds.every(d=>d===ds[0]);
 const path=points.map(p=>{
  if(!Array.isArray(p)||p.length!==2||p.some(x=>!Number.isFinite(x)||Math.abs(x)>1000000))throw Error('边界坐标超出可靠计算范围');
  return {X:Math.round(p[0]*SCALE),Y:Math.round(p[1]*SCALE)};
 });
 if(path.some((p,i)=>p.X===path[(i+1)%path.length].X&&p.Y===path[(i+1)%path.length].Y))throw Error('原红线存在小于整数网格精度的边，未自动合点');
 if(!uniform)return variable(path,ds);
 if(ds[0]===0)return {outlines:[points.map(p=>p.slice())],method:'parallel-miter'};
 if(!C.Clipper.Orientation(path))path.reverse();
 const offset=new C.ClipperOffset(1000,0.25);
 offset.AddPath(path,C.JoinType.jtMiter,C.EndType.etClosedPolygon);
 const raw=[];
 offset.Execute(raw,-ds[0]*SCALE);
 if(!raw.length)return {outlines:[],method:'parallel-miter'};
 // Intersection keeps even numerical excursions inside the original polygon.
 const clip=new C.Clipper(),tree=new C.PolyTree();
 clip.AddPaths(raw,C.PolyType.ptSubject,true);
 clip.AddPath(path,C.PolyType.ptClip,true);
 if(!clip.Execute(C.ClipType.ctIntersection,tree,C.PolyFillType.pftNonZero,C.PolyFillType.pftNonZero))throw Error('退线布尔计算失败');
 const regions=C.JS.PolyTreeToExPolygons(tree);
 if(regions.some(r=>r.holes.length))throw Error('偏移结果包含内孔，当前挤出内核尚不支持，已停止此地块');
 const outlines=regions.map(r=>r.outer.map(p=>[p.X/SCALE,p.Y/SCALE]));
 outlines.forEach(poly=>{ if(area(poly)<0)poly.reverse(); });
 return {outlines:outlines,method:'parallel-miter'};
}
function variable(path,ds){
 const n=path.length,arcTolerance=0.00005,extra=0.0001;
 // Run buffers use the actual distance of every source segment, not a
 // parcel-wide maximum. Equal-distance consecutive edges form one open chain.
 let start=ds.findIndex((d,i)=>d!==ds[(i+n-1)%n]),used=0;
 const forbidden=[];let budget=0;
 while(used<n){
  const first=(start+used)%n,d=ds[first],chain=[path[first]];
  do{used++;chain.push(path[(start+used)%n]);}while(used<n&&ds[(start+used)%n]===d);
  if(d===0)continue;
  const expected=chain.length*2+Math.ceil(2*Math.PI/Math.acos(1-arcTolerance/(d+extra)));
  budget+=expected;if(budget>1000000)throw Error('逐组退线曲线精度计算量过大，请分批或调整地块');
  const offset=new C.ClipperOffset(2,arcTolerance*SCALE),caps=[];
  offset.AddPath(chain,C.JoinType.jtRound,C.EndType.etOpenRound);
  // Offset arcs are inscribed. A 0.1 mm outward allowance compensates their
  // 0.05 mm chord error and integer rounding; it never grants extra clearance.
  offset.Execute(caps,(d+extra)*SCALE);
  forbidden.push(...caps);
 }
 const source=path.slice();
 if(!C.Clipper.Orientation(source))source.reverse();
 const clip=new C.Clipper(),tree=new C.PolyTree();
 clip.AddPath(source,C.PolyType.ptSubject,true);
 clip.AddPaths(forbidden,C.PolyType.ptClip,true);
 if(!clip.Execute(C.ClipType.ctDifference,tree,C.PolyFillType.pftNonZero,C.PolyFillType.pftNonZero))throw Error('逐组退线布尔计算失败');
 const regions=C.JS.PolyTreeToExPolygons(tree);
 if(regions.some(r=>r.holes.length))throw Error('结果包含内孔，当前体量内核暂不支持');
 const outlines=regions.map(r=>r.outer.map(p=>[p.X/SCALE,p.Y/SCALE]));
 outlines.forEach(poly=>{if(area(poly)<0)poly.reverse();});
 return {outlines,method:'segment-clearance',allowance_m:extra};
}
function area(poly){return poly.reduce((sum,a,i)=>{const b=poly[(i+1)%poly.length];return sum+a[0]*b[1]-b[0]*a[1];},0)/2;}
const api={solve:solve,area:area,scale:SCALE};
if(typeof module==='object'&&module.exports)module.exports=api;else root.BuildableOffset=api;
})(typeof window==='object'?window:globalThis);
