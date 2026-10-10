'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const E=require('../src/buildable_envelope/offset_engine');
let checks=0;const fixtures=[];
function solve(name,points,d,expectedRegions,expectedArea){
 const result=E.solve(points,points.map(()=>d));
 assert.equal(result.outlines.length,expectedRegions,name+' regions');checks++;
 if(expectedArea!==undefined){assert.ok(Math.abs(result.outlines.reduce((s,p)=>s+E.area(p),0)-expectedArea)<0.001,name+' area');checks++;}
 fixtures.push({name,points,setbacks:points.map(()=>d),outlines:result.outlines});
 return result;
}
const rect=[[0,0],[20,0],[20,10],[0,10]];
solve('analytic rectangle',rect,2,1,96);
solve('reverse rectangle',rect.slice().reverse(),2,1,96);
solve('zero setback preserves native vertices',rect,0,1,200);
solve('empty excessive setback',rect,50,0,0);
solve('concave L',[[0,0],[20,0],[20,10],[10,10],[10,20],[0,20]],2,1,156);
solve('narrow neck splits',[[0,0],[10,0],[10,4],[20,4],[20,0],[30,0],[30,10],[20,10],[20,6],[10,6],[10,10],[0,10]],2,2,72);
const dense=[];
rect.forEach((a,i)=>{const b=rect[(i+1)%rect.length];for(let j=0;j<600;j++){const t=j/600;dense.push([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]);}});
solve('2400 segment rectangle',dense,2,1,96);
const outer=[],inner=[],n=1094;
for(let i=0;i<=n;i++){const t=.3+i*4*Math.PI/n,r=100+60*t;outer.push([(r+40)*Math.cos(t),(r+40)*Math.sin(t)]);inner.push([(r-40)*Math.cos(t),(r-40)*Math.sin(t)]);}
const spiral=outer.concat(inner.reverse()),copy=JSON.stringify(spiral);
solve('2190 segment synthetic spiral',spiral,5,1);
assert.equal(JSON.stringify(spiral),copy,'source not mutated');checks++;
const rotated=rect.map(([x,y])=>[x*Math.cos(.43)-y*Math.sin(.43),x*Math.sin(.43)+y*Math.cos(.43)]);
solve('rotated rectangle',rotated,2,1,96);
assert.throws(()=>E.solve(rect,[2,3,2,2]),/统一/);checks++;
assert.throws(()=>E.solve(rect,[NaN,NaN,NaN,NaN]),/无效/);checks++;
assert.throws(()=>E.solve([[0,0],[1e-8,0],[1,1]],[1,1,1]),/精度/);checks++;
const html=fs.readFileSync(path.join(__dirname,'../src/buildable_envelope/ui.html'),'utf8');
for(const match of html.matchAll(/<script>([\s\S]*?)<\/script>/g)){new vm.Script(match[1]);checks++;}
fs.mkdirSync(path.join(__dirname,'../tmp'),{recursive:true});
fs.writeFileSync(path.join(__dirname,'../tmp/offset-fixtures.json'),JSON.stringify(fixtures));
console.log(checks+' Node checks passed; '+fixtures.length+' fixtures written for independent Ruby verification.');
