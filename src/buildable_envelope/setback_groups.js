/* Setback input groups. Every source vertex and edge is preserved. */
(function(root){
'use strict';
function turn(points,i){
 const n=points.length,a=points[(i+n-1)%n],b=points[i],c=points[(i+1)%n];
 return Math.atan2((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]),
   (b[0]-a[0])*(c[0]-b[0])+(b[1]-a[1])*(c[1]-b[1]))*180/Math.PI;
}
function same(a,b){return String(a).trim()!==''&&String(b).trim()!==''&&Number.isFinite(Number(a))&&Number(a)===Number(b);}
function validate(groups,n){
 const ids=groups.flatMap(g=>g.edges);
 if(ids.length!==n||new Set(ids).size!==n||ids.some(e=>!Number.isInteger(e)||e<0||e>=n)||
  ids.some((e,i)=>ids[(i+1)%n]!==((e+1)%n)))throw Error('边段分组不连续或存在漏边、重复边');
 return groups;
}
function auto(points,setbacks,maxTurn=25,labels=null){
 const n=points.length;
 if(n<3||setbacks.length!==n||!Number.isFinite(maxTurn)||maxTurn<1||maxTurn>60)throw Error('分组参数无效');
 const turns=points.map((_,i)=>turn(points,i)),cuts=[];
 const type=t=>Math.abs(t)<0.5?0:Math.sign(t);
 for(let i=0;i<n;i++){
  const p=(i+n-1)%n,t=turns[i],previous=turns[p];
  const sharp=Math.abs(t)>maxTurn;
  const transition=Math.abs(previous)<=maxTurn&&!sharp&&type(t)!==type(previous);
  if(sharp||transition||!same(setbacks[p],setbacks[i])||(labels&&labels[p]!==labels[i]))cuts.push(i);
 }
 if(!cuts.length)cuts.push(0);
 const groups=cuts.map((start,i)=>{
  const stop=cuts[(i+1)%cuts.length],edges=[];
  let edge=start;
  do{edges.push(edge);edge=(edge+1)%n;}while(edge!==stop);
  return {edges};
 });
 return validate(groups,n);
}
function value(group,setbacks){
 const first=setbacks[group.edges[0]];
 return group.edges.every(i=>same(first,setbacks[i]))?first:null;
}
function assign(group,setbacks,value){group.edges.forEach(i=>{setbacks[i]=value;});}
function merge(groups,selected,n){
 validate(groups,n);
 const chosen=new Set(selected);
 if(chosen.size<2||[...chosen].some(i=>!Number.isInteger(i)||i<0||i>=groups.length))throw Error('请选择至少两个相邻边段组');
 const starts=[...chosen].filter(i=>!chosen.has((i+groups.length-1)%groups.length));
 if(starts.length>1)throw Error('只能合并沿红线连续相邻的组');
 const start=starts.length?starts[0]:0,ordered=groups.slice(start).concat(groups.slice(0,start));
 let count=0;
 while(count<ordered.length&&chosen.has((start+count)%groups.length))count++;
 const combined={edges:ordered.slice(0,count).flatMap(g=>g.edges)};
 return validate([combined].concat(ordered.slice(count)),n);
}
function split(groups,selected,n){
 validate(groups,n);const chosen=new Set(selected);
 if(!chosen.size)throw Error('请先选择要拆分的边段组');
 return validate(groups.flatMap((g,i)=>chosen.has(i)?g.edges.map(edge=>({edges:[edge]})):[g]),n);
}
const api={auto,value,assign,merge,split,validate};
if(typeof module==='object'&&module.exports)module.exports=api;else root.SetbackGroups=api;
})(typeof window==='object'?window:globalThis);
