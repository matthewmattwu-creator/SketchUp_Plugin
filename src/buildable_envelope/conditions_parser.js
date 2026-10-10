/* Local plain-text planning condition parser. Text is data, never executed. */
(function(root){
'use strict';
const num='(?:-?\\d+(?:\\.\\d+)?|[零〇一二两三四五六七八九十百千点]+)';
const unit='(毫米|厘米|米|mm|cm|m)(?![a-zA-Z])';
function number(text){
 if(/^-?\d/.test(text))return Number(text);
 const digits={'零':0,'〇':0,'一':1,'二':2,'两':2,'三':3,'四':4,'五':5,'六':6,'七':7,'八':8,'九':9};
 const parts=text.split('点');if(parts.length===1&&!/[十百千]/.test(text))return Number([...text].map(c=>digits[c]).join(''));let total=0,current=0;
 for(const c of parts[0]){if(c in digits)current=digits[c];else{const scale={'十':10,'百':100,'千':1000}[c];if(!scale)return NaN;total+=(current||1)*scale;current=0;}}
 total+=current;
 if(parts.length>1){const fraction=[...parts[1]].map(c=>c in digits?digits[c]:'x').join('');if(!fraction||fraction.includes('x'))return NaN;total+=Number('0.'+fraction);}
 return total;
}
function normalize(text){return String(text).replace(/[０-９Ａ-Ｚａ-ｚ．：，；＝]/g,c=>String.fromCharCode(c.charCodeAt(0)-0xFEE0)).replace(/≤/g,'不大于').replace(/≥/g,'不小于');}
function parse(text){
 const raw=normalize(text);if(raw.length>30000)throw Error('粘贴内容超过 30000 字，请分段识别');
 const actions=[],warnings=[];
 const clauses=raw.split(/[;；,，。\n]+/).map(s=>s.trim()).filter(Boolean);
 const fields='(建筑限高|高度限制|建筑高度|限高|控高|层高|(?:退让|后退|退)(?:道路|用地|建筑)?红线|退线距离|退界距离|退线|退距|退让|退界)';
 const pattern=new RegExp(fields+'\\s*(?:不超过|不得超过|不大于|不得大于|不得小于|不小于|不少于|至少|不低于|控制在|为|是|[:=<>≤≥])*\\s*('+num+')\\s*'+unit,'gi');
 for(const clause of clauses){
  let found=false,previous=0,match;
  pattern.lastIndex=0;
  while((match=pattern.exec(clause))){
   found=true;const context=clause.slice(previous,match.index)+match[1];previous=pattern.lastIndex;
   const value=number(match[2])*(/^(毫米|mm)$/i.test(match[3])?0.001:/^(厘米|cm)$/i.test(match[3])?0.01:1);
   const kind=match[1]==='层高'?'floor_height':/(高|高度)/.test(match[1])?'height':'setback';
   let target='all',index=null;
   if(kind==='setback'){
    const group=context.match(/(?:第\s*)?组\s*(\d+)|第?\s*(\d+)\s*组/),edge=context.match(/(?:原边|第?\s*边)\s*(\d+)|第?\s*(\d+)\s*条?边/);
    if(group){target='group';index=Number(group[1]||group[2])-1;}
    else if(edge){target='edge';index=Number(edge[1]||edge[2])-1;}
    else if(/道路|临路|沿街|沿路|临街/.test(context))target='road';
    else if(/邻地|邻界|相邻地块/.test(context))target='neighbor';
    else if(/[东南西北]侧|[东南西北]边/.test(context))target='unmapped';
   }
   const valid=Number.isFinite(value)&&(kind==='setback'?value>=0:value>0)&&index!==-1;
   actions.push({kind,value,target,index,valid,usage:/道路|临路|沿街|沿路|临街/.test(context)?'road':/邻地|邻界|相邻地块/.test(context)?'neighbor':null,evidence:clause});
   if(!valid)warnings.push('数值无效：'+clause);
   if(target==='unmapped')warnings.push('方位描述尚未对应边段，请在识别结果中指定组：'+clause);
  }
  if(!found)warnings.push('未识别或单位/格式不明确：'+clause);
  // Ranges and inequalities in the opposite direction are not auto-decisions.
  if(new RegExp(num+'\\s*(?:毫米|厘米|米|mm|cm|m)?\\s*(?:-|~|～|至)\\s*'+num).test(clause)||/限高\s*(?:不少于|不小于|不低于)|高度\s*(?:不少于|不小于|不低于)|退(?:线|距|让|界)\s*(?:不超过|不大于)/.test(clause)){
   actions.filter(a=>a.evidence===clause).forEach(a=>a.valid=false);
   warnings.push('范围或约束方向需人工确认：'+clause);
  }
 }
 const seen=new Map(),unique=[];
 for(const action of actions){
  const key=[action.kind,action.target,action.index].join(':');
  if(seen.has(key)){
   const prior=seen.get(key);
   if(prior.value!==action.value){prior.valid=false;action.valid=false;warnings.push('同一条件存在冲突：'+prior.evidence+' / '+action.evidence);unique.push(action);}
  }else{seen.set(key,action);unique.push(action);}
 }
 return {actions:unique,warnings:[...new Set(warnings)]};
}
function plan(parcel,actions){
 if(!parcel||!parcel.points||!parcel.points.length)throw Error('请先导入 CAD 或读取地块');
 const setbacks=parcel.setbacks.slice(),labels=(parcel.edgeLabels||parcel.points.map(()=>'未标注')).slice();
 let height=parcel.height,floor_height=parcel.floor_height;const assignments=new Map();
 const ordered=actions.filter(a=>a.enabled!==false).slice().sort((a,b)=>(a.target==='all'?0:1)-(b.target==='all'?0:1));
 if(!ordered.length)throw Error('请至少勾选一条有效识别结果');
 for(const a of ordered){
  if(!a.valid||!Number.isFinite(a.value))throw Error('存在无效或冲突条件，请修改原文后重新识别');
  if(a.kind==='height'){height=a.value;continue;}if(a.kind==='floor_height'){floor_height=a.value;continue;}
  let edges;
  if(a.target==='all')edges=parcel.points.map((_,i)=>i);
  else if(a.target==='group'){if(!Number.isInteger(a.index)||!parcel.groups[a.index])throw Error('指定的组不存在');edges=parcel.groups[a.index].edges;}
  else if(a.target==='edge'){if(!Number.isInteger(a.index)||a.index<0||a.index>=parcel.points.length)throw Error('指定的原边不存在');edges=[a.index];}
  else if(a.target==='selected'){
   edges=(parcel.viewMode==='edges'?parcel.points.map((_,i)=>({edges:[i]})):parcel.groups).filter((_,i)=>parcel.selectedGroups.has(i)).flatMap(g=>g.edges);
  }else if(a.target==='road'||a.target==='neighbor')edges=labels.map((l,i)=>l===(a.target==='road'?'道路侧':'邻地侧')?i:-1).filter(i=>i>=0);
  else throw Error('请为方位条件选择对应边段组');
  if(!edges.length)throw Error('没有匹配的边段：请标记用途、选组或指定应用组');
  for(const i of edges){
   if(a.target!=='all'&&assignments.has(i)&&assignments.get(i)!==a.value)throw Error('所选条件对同一原边有不同退距，请取消冲突项');
   if(a.target!=='all')assignments.set(i,a.value);
   setbacks[i]=a.value;
   if(a.usage==='road'||a.sourceTarget==='road'||a.target==='road')labels[i]='道路侧';
   if(a.usage==='neighbor'||a.sourceTarget==='neighbor'||a.target==='neighbor')labels[i]='邻地侧';
  }
 }
 return {setbacks,edgeLabels:labels,height,floor_height};
}
const api={parse,plan,number};
if(typeof module==='object'&&module.exports)module.exports=api;else root.ConditionsParser=api;
})(typeof window==='object'?window:globalThis);
