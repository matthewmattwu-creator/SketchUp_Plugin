'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const G=require('../src/buildable_envelope/setback_groups');
let checks=0;function check(fn){fn();checks++;}
const circle=Array.from({length:168},(_,i)=>[100*Math.cos(i*2*Math.PI/168),100*Math.sin(i*2*Math.PI/168)]),distances=circle.map(()=>5),original=JSON.stringify(circle);
const groups=G.auto(circle,distances);
check(()=>assert.equal(groups.length,1));
check(()=>assert.equal(groups[0].edges.length,168));
check(()=>assert.equal(JSON.stringify(circle),original));
const dense=[];[[0,0],[100,0],[100,100],[0,100]].forEach((a,i,p)=>{const b=p[(i+1)%4];for(let j=0;j<42;j++){const t=j/42;dense.push([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]);}});
const four=G.auto(dense,dense.map(()=>5));
check(()=>assert.equal(four.length,4));
check(()=>assert.ok(four.every(g=>g.edges.length===42)));
const values=dense.map(()=>5);
G.assign(four[1],values,'8');
check(()=>assert.equal(values.filter(x=>x==='8').length,42));
check(()=>assert.equal(values.filter(x=>x===5).length,126));
check(()=>assert.equal(G.value(four[1],values),'8'));
const mixed=G.merge(four,[0,1],168);
check(()=>assert.equal(mixed.length,3));
check(()=>assert.equal(G.value(mixed[0],values),null));
check(()=>assert.equal(values[0],5));
const wrapped=G.merge(four,[3,0],168);
check(()=>assert.deepEqual(wrapped[0].edges,[...four[3].edges,...four[0].edges]));
check(()=>assert.throws(()=>G.merge(four,[0,2],168),/相邻/));
check(()=>assert.equal(G.merge(four,[0,1,2,3],168).length,1));
check(()=>assert.equal(G.split(four,[0],168).length,45));
check(()=>assert.equal(G.auto(circle,distances.map((d,i)=>i<80?5:8)).length,2));
check(()=>assert.throws(()=>G.validate([{edges:[0,1]},{edges:[1,2]}],4),/漏边/));
check(()=>assert.throws(()=>G.auto(circle,distances,NaN),/无效/));
check(()=>assert.throws(()=>G.split(four,[],168),/选择/));
// Run the real bundled UI with minimal DOM doubles, exercising callbacks and
// payload transport rather than mocking the grouping/offset functions.
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.listeners={};this.attributes={};this.style={};this.value='';this.textContent='';}
 replaceChildren(...children){this.children=children;}
 append(...children){this.children.push(...children);}
 appendChild(child){this.children.push(child);return child;}
 setAttribute(k,v){this.attributes[k]=v;}
 addEventListener(type,fn){(this.listeners[type]||(this.listeners[type]=[])).push(fn);}
 fire(type){(this.listeners[type]||[]).forEach(fn=>fn({target:this}));}
}
const elements={},document={getElementById:id=>elements[id]||(elements[id]=new Element('div')),createElement:tag=>new Element(tag),createElementNS:(_ns,tag)=>new Element(tag),addEventListener:()=>{}};
let payload;
const context={document,console,navigator:{userAgent:'Chrome',appName:'Netscape'},setTimeout:fn=>fn(),sketchup:{ready(){},reload(){},generate(text){payload=JSON.parse(text);}}};
context.window=context;context.self=context;vm.createContext(context);
for(const file of ['vendor/clipper.js','offset_engine.js','setback_groups.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../src/buildable_envelope',file),'utf8'),context);
const html=fs.readFileSync(path.join(__dirname,'../src/buildable_envelope/ui.html'),'utf8');
for(const match of html.matchAll(/<script>([\s\S]*?)<\/script>/g))vm.runInContext(match[1],context);
context.receive({parcels:[{id:'0',name:'测试',points:circle,holes:[],area:31400,height:36,floor_height:3.6,setbacks:distances.slice()}],errors:[]});
check(()=>assert.equal(elements.edges.children.length,1));
check(()=>assert.match(elements.boundaryInfo.textContent,/168 条边 · 退线输入 1 项/));
const input=elements.edges.children[0].children[1].children[0];input.value='8';input.fire('input');
elements.generate.fire('click');
check(()=>assert.equal(payload[0].setbacks.length,168));
check(()=>assert.ok(payload[0].setbacks.every(d=>d==='8')));
check(()=>assert.equal(payload[0].offset_result.method,'parallel-miter'));
check(()=>assert.equal(JSON.stringify(circle),original));
context.report('完成');
elements.viewMode.value='edges';elements.viewMode.fire('change');
check(()=>assert.equal(elements.edges.children.length,168));
elements.viewMode.value='groups';elements.viewMode.fire('change');
elements.edges.children[0].children[0].children[0].fire('change');
elements.splitGroups.fire('click');
check(()=>assert.equal(elements.edges.children.length,168));
context.report('完成');
const roadInput=elements.edges.children[0].children[1].children[0];roadInput.value='12';roadInput.fire('input');
const roadLabel=elements.edges.children[0].children[0].children[3];roadLabel.value='道路侧';roadLabel.fire('change');
const neighborLabel=elements.edges.children[1].children[0].children[3];neighborLabel.value='邻地侧';neighborLabel.fire('change');
elements.generate.fire('click');
check(()=>assert.equal(payload[0].offset_result.method,'segment-clearance'));
check(()=>assert.equal(payload[0].setbacks[0],'12'));
check(()=>assert.ok(payload[0].setbacks.slice(1).every(d=>d==='8')));
check(()=>assert.equal(payload[0].edge_labels[0],'道路侧'));
check(()=>assert.equal(payload[0].edge_labels[1],'邻地侧'));
check(()=>assert.equal(G.auto(circle,distances,25,circle.map((_,i)=>i<80?'道路侧':'邻地侧')).length,2));
check(()=>assert.equal(JSON.stringify(circle),original));
console.log(checks+' grouping and real UI transport checks passed.');
