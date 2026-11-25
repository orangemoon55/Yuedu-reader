#!/usr/bin/env node
'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert'),crypto=require('crypto');
const root=process.argv[2],input=process.argv[3];
const swift=fs.readFileSync(root+'/Modules/Services/Music/MusicJSBootstrap.swift','utf8');
const bootstrap=swift.split('#"""')[1].split('"""#')[0];
const fixtureMode=input==='--fixture';
const source=fixtureMode?fs.readFileSync(root+'/Tests/iOS/yuedu appTests/MusicJSSourceTests.swift','utf8').split('private let script = #"""')[1].split('"""#')[0]:fs.readFileSync(input,'utf8');let context,requests=0;const messages=[];
const bridge={postMessage(text){const message=JSON.parse(text);messages.push(message);if(message.kind==='http'){
 requests++;const search=message.url.includes('163_search');
 const body=search?{code:200,data:[{id:123,name:'Offline Song',artists:'Fixture Artist',album:'Fixture Album',duration:10000}]}:
 {code:200,url:'https://fixture.invalid/authorized.mp3',data:{url:'https://fixture.invalid/authorized.mp3'}};
 queueMicrotask(()=>context.__readccMusicHTTP(message.id,null,{statusCode:200,headers:{},body:JSON.stringify(body)}));
}}};
context=vm.createContext({window:{webkit:{messageHandlers:{readccMusic:bridge}}}},{codeGeneration:{strings:false,wasm:false}});
vm.runInContext(bootstrap,context,{timeout:1000});vm.runInContext(source,context,{timeout:1000});
const init=messages.find(x=>x.kind==='inited');assert(init);
const keys=Object.keys(init.data.sources).sort();assert.deepStrictEqual(keys,fixtureMode?['tx','wy']:['kg','kw','mg','qs','tx','wy']);
const searchable=keys.filter(k=>init.data.sources[k].actions.includes('search'));assert.deepStrictEqual(searchable,fixtureMode?['wy']:['kw','mg','qs','wy']);
const missing=vm.createContext({window:{webkit:{messageHandlers:{readccMusic:{postMessage(){throw Error('unexpected init');}}}}}});
vm.runInContext(bootstrap,missing,{timeout:1000});
assert.throws(()=>vm.runInContext("lx.send(lx.EVENT_NAMES.inited,{sources:{}})",missing,{timeout:1000}),/missing request handler/);
async function invoke(id,payload){
 vm.runInContext('__readccMusicInvoke('+JSON.stringify(id)+','+JSON.stringify(payload)+')',context,{timeout:1000});
 for(let i=0;i<100;i++){await new Promise(resolve=>setImmediate(resolve));let m=messages.find(x=>x.id===id&&['result','failure'].includes(x.kind));if(m)return m;}
 throw Error('mock action did not finish');
}
(async()=>{
 const found=await invoke('search-fixture',{action:'search',source:'wy',info:{keyword:'Offline',limit:20}});
 assert.equal(found.kind,'result');assert.equal(found.data.length,1);assert.equal(found.data[0].id,fixtureMode?7:123);
 const played=await invoke('play-fixture',{action:'musicUrl',source:'wy',info:{musicInfo:found.data[0],type:'128k'}});
 assert.equal(played.kind,'result');assert.equal(played.data,fixtureMode?'https://fixture.invalid/audio.mp3':'https://fixture.invalid/authorized.mp3');
 if(!fixtureMode){const unsupported=await invoke('no-search',{action:'search',source:'tx',info:{keyword:'Offline'}});assert.equal(unsupported.kind,'failure');}
 const bad=await invoke('bad-action',{action:'unknown',source:'wy',info:{}});assert.equal(bad.kind,'failure');
 console.log(JSON.stringify({scope:fixtureMode?'actual Swift bootstrap + repository-owned fixture in Node; NOT uploaded JS, iOS or playback':'actual Swift bootstrap + exact uploaded source in Node; mocked HTTP only, not iOS playback',sha256:crypto.createHash('sha256').update(source).digest('hex'),providers:keys,searchable,searchResults:found.data.length,playURLResolved:true,unsupportedSearchRejected:fixtureMode?null:true,missingHandlerInitRejected:true,badActionRejected:true,mockHTTPRequests:requests,liveHTTPRequests:0}));
})().catch(()=>{console.error('LX fixture assertion failed');process.exitCode=1;});
