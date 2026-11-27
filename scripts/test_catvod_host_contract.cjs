'use strict';
// Runs the exact embedded production host, never any reference-app or user bundle.
const fs=require('fs'), path=require('path'), os=require('os'), cp=require('child_process'), http=require('http');
const input=path.resolve(process.argv[2] || path.join(__dirname,'..'));
const swift=fs.statSync(input).isDirectory()?fs.readFileSync(path.join(input,'Modules/Services/CatVod/CatVodHostScript.swift'),'utf8'):cp.execFileSync('python3',['-c','import zipfile,sys;print(zipfile.ZipFile(sys.argv[1]).read("Modules/Services/CatVod/CatVodHostScript.swift").decode())',input],{encoding:'utf8'});
const match=swift.match(/static let source = #"""\n([\s\S]*?)\n"""#/);if(!match)throw Error('Host source missing');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'readcc-catvod-probe-'));fs.writeFileSync(path.join(dir,'host.cjs'),match[1]);
const fixture=String.raw`
const http=require('http');let server,mode='',count=0,detailCalls=0,retryCount=0,missingCalls=0,bridgeOK=false,extOK=false;
exports.start=async()=>{server=catServerFactory(async(req,res)=>{
 const chunks=[];for await(const c of req)chunks.push(c);let b={};try{b=JSON.parse(Buffer.concat(chunks)||'{}')}catch{}
 const send=(status,value)=>{res.writeHead(status,{'content-type':'application/json'});res.end(typeof value==='string'?value:JSON.stringify(value))};
 const port=server.address().port;
 if(req.url==='/config')return send(200,{video:{sites:[
 {key:'A',name:'A',api:'/spider/shared/3',ext:{mode:'A'},searchable:1},
 {key:'B',name:'B',api:'/spider/shared/3',ext:'B',searchable:1},
 ...['missing','retry','denied'].map(key=>({key,name:key,api:'/spider/'+key+'/3',searchable:1}))]}});
 if(req.url.endsWith('/init')){
  if(req.url.includes('/missing/')){missingCalls++;return send(404,{error:'not found'})}
  if(req.url.includes('/denied/'))return send(401,{error:'fixture login required'});
  if(req.url.includes('/retry/')&&retryCount++===0)return send(500,{error:'fixture init failure'});
  count++;bridgeOK=b.bridge==='http://127.0.0.1:'+port;
  mode=b.ext===JSON.stringify({mode:'A'})?'A':b.ext==='B'?'B':'other';extOK=mode!=='other';return send(200,{code:0});
 }
 if(req.url.endsWith('/detail')){
  detailCalls++;
  const ready=(req.url.includes('/missing/')||count>0)&&!req.url.includes('/denied/');
  return send(200,{list:ready?[{vod_id:'fixture-film',vod_name:'Fixture movie',vod_play_from:'quark',vod_play_url:'第一集$opaque%2Fid$tail'}]:[{}],probe:{mode,count,bridgeOK,extOK,missingCalls,detailCalls}});
 }
 if(req.url.endsWith('/search')){if(b.wd==='empty-body')return send(200,'');if(b.wd==='not-found')return send(404,{error:'not found'});return send(401,{error:'fixture auth failure'})}
 if(req.url.endsWith('/play')){
  if(b.id==='labels')return send(200,{result:{url:['HD','/stream/second.m3u8','/stream/second.ts','/stream/second.m3u8']}});
  if(b.id==='bad-v')return send(200,{result:{values:[{n:'bad',v:{url:'/stream/second.ts'}}]}});
  if(b.id==='headers')return send(200,{result:{values:[{n:'/stream/second.ts',v:'/stream/second.m3u8',headers:{url:'/stream/second.ts'}}],headers:{url:'/stream/second.ts'}}});
  if(b.id==='business-error')return send(200,{code:401,url:'/stream/second.ts'});
  if(b.id==='failure')return send(500,{error:'fixture play failure'});
  return send(200,{result:{url:{values:[{n:'HD',v:'http://127.0.0.1:'+port+'/stream/master.m3u8?sig=x%2Fy'},{n:'SD',v:'/stream/second.m3u8'}],position:0},parse:0}});
 }
 if(req.url==='/stream/master.m3u8?sig=x%2Fy'){res.writeHead(200,{'content-type':'application/vnd.apple.mpegurl'});return res.end('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\nseg.ts\n')}
 if(req.url==='/stream/second.m3u8'){res.writeHead(200,{'content-type':'application/vnd.apple.mpegurl'});return res.end('#EXTM3U\nsecond.ts\n')}
 if(req.url==='/stream/key.bin'||req.url==='/stream/seg.ts'||req.url==='/stream/second.ts')return send(200,'fixture-media');
 return send(404,{error:'fixture not found'});
 });await new Promise(r=>server.listen(0,r));};exports.stop=async()=>{};
`;
fs.writeFileSync(path.join(dir,'fixture.cjs'),fixture);
const child=cp.spawn(process.execPath,[path.join(dir,'host.cjs'),path.join(dir,'ready.json')],{stdio:['ignore','pipe','pipe']});let stderr='';child.stderr.on('data',b=>stderr+=b);
function request(port,route,body,token){return new Promise((resolve,reject)=>{const bytes=body==null?null:Buffer.from(JSON.stringify(body));const req=http.request({hostname:'127.0.0.1',port,path:route,method:bytes?'POST':'GET',headers:{...(bytes?{'content-type':'application/json','content-length':bytes.length}:{}),...(token?{'x-readcc-token':token}:{})}},res=>{const parts=[];res.on('data',b=>parts.push(b));res.on('end',()=>{const text=Buffer.concat(parts).toString();let value;try{value=JSON.parse(text)}catch{}resolve({status:res.statusCode,text,value})})});req.on('error',reject);req.setTimeout(12000,()=>req.destroy(Error('fixture timeout')));req.end(bytes)})}
(async()=>{
 const deadline=Date.now()+12000;while(!fs.existsSync(path.join(dir,'ready.json'))){if(Date.now()>deadline)throw Error('Host readiness timeout');await new Promise(r=>setTimeout(r,15))}
 const ready=JSON.parse(fs.readFileSync(path.join(dir,'ready.json'))),control=(route,b)=>request(ready.port,route,b,ready.token);
 const load=await control('/load',{sourceID:'fixture-source',path:path.join(dir,'fixture.cjs'),data:path.join(dir,'data')});if(load.status!==200||!load.value.ok)throw Error('Fixture load failed');
 const state=load.value,invoke=(key,action,args={})=>control('/invoke',{sourceID:'fixture-source',site:key,api:key==='A'||key==='B'?'/spider/shared/3':'/spider/'+key+'/3',action,arguments:args});
 const observations={};const parsed=r=>{try{return JSON.parse(r.value.body)}catch{return {}}};
 const first=await invoke('A','detail',{id:['fixture-film']});let f=parsed(first);observations.initializes_before_detail=f.list?.[0]?.vod_name==='Fixture movie';observations.init_receives_ext_and_bridge=f.probe?.extOK===true&&f.probe?.bridgeOK===true;
 const repeat=parsed(await invoke('A','detail'));observations.same_configuration_initialized_once=repeat.probe?.count===1;
 const b=parsed(await invoke('B','detail')),a=parsed(await invoke('A','detail'));observations.same_api_ext_ABA_reinitializes=b.probe?.mode==='B'&&a.probe?.mode==='A'&&a.probe?.count===3;
 const missing=parsed(await invoke('missing','detail'));const missing2=parsed(await invoke('missing','detail'));observations.optional_init404_only_once=missing.list?.[0]?.vod_name==='Fixture movie'&&missing2.probe?.missingCalls===1;
 const beforeRetry=missing2.probe?.detailCalls;const retry1=await invoke('retry','detail');const retry2=await invoke('retry','detail');observations.failed_init_short_circuits_and_retries=retry1.value?.status===500&&retry2.value?.status===200&&parsed(retry2).probe?.detailCalls===beforeRetry+1;
 const denied=await invoke('denied','detail');observations.init401_not_bypassed=denied.value?.status===401;
 const empty=await invoke('A','search',{wd:'empty-body'}),notfound=await invoke('A','search',{wd:'not-found'}),auth=await invoke('A','search',{wd:'auth'});observations.empty_search_body_is_empty_list=empty.value?.status===200&&Array.isArray(parsed(empty).list)&&parsed(empty).list.length===0;observations.search404_is_empty_list=notfound.value?.status===200&&Array.isArray(parsed(notfound).list)&&parsed(notfound).list.length===0;observations.search401_preserved=auth.value?.status===401;
 const play=await invoke('A','play',{flag:'quark',id:'opaque%2Fid$tail'});observations.play_request_succeeds=play.value?.status===200;
 const scoped='/.readcc-media/'+state.mediaScope;const media=await request(state.port,scoped+'/stream/master.m3u8?sig=x%2Fy');observations.result_fongmi_media_granted=media.status===200&&media.text.includes('#EXTM3U');
 observations.hls_key_and_segment_granted=media.status===200&&media.text.includes(scoped+'/stream/key.bin')&&media.text.includes(scoped+'/stream/seg.ts');
 const unsigned=await request(state.port,'/stream/master.m3u8?sig=x%2Fy'),blocked=await request(state.port,scoped+'/config');observations.unsigned_media_blocked=unsigned.status===401;observations.management_media_blocked=blocked.status===403;
 const key=await request(state.port,scoped+'/stream/key.bin'),segment=await request(state.port,scoped+'/stream/seg.ts');observations.hls_key_and_segment_fetch=key.status===200&&segment.status===200;
 const deniedTarget=()=>request(state.port,scoped+'/stream/second.ts');observations.unadvertised_before_negative_probes=(await deniedTarget()).status===403;
 await invoke('A','play',{id:'labels'});observations.pair_labels_not_granted=(await deniedTarget()).status===403;
 await invoke('A','play',{id:'bad-v'});observations.fongmi_container_v_not_granted=(await deniedTarget()).status===403;
 await invoke('A','play',{id:'headers'});observations.headers_and_names_not_granted=(await deniedTarget()).status===403;
 await invoke('A','play',{id:'business-error'});observations.failed_envelope_not_granted=(await deniedTarget()).status===403;
 const second=await request(state.port,scoped+'/stream/second.m3u8');observations.second_quality_fetch_and_hls_grant=second.status===200&&(await deniedTarget()).status===200;
 const failed=await invoke('A','play',{id:'failure'});observations.play500_preserved=failed.value?.status===500;
 const stale=await control('/invoke',{sourceID:'removed',site:'A',api:'/spider/shared/3',action:'detail'});observations.stale_source_rejected=stale.status===409;
 const allPassed=Object.values(observations).every(Boolean);console.log(JSON.stringify({suite:'exact-production-host/local-owned-fixture',observations,allPassed},null,2));process.exitCode=allPassed?0:1;
})().catch(e=>{console.error(e.message,stderr);process.exitCode=2}).finally(()=>{child.kill('SIGKILL');fs.rmSync(dir,{recursive:true,force:true})});
