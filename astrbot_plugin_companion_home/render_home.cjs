/* Render only bundled home assets and supplied state; no remote requests. */
const {chromium}=require('playwright-core');
const fs=require('fs'),path=require('path');
let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>input+=x);
process.stdin.on('end',async()=>{
 let browser;
 try{
  const payload=JSON.parse(input),root=path.join(__dirname,'views/home');
  browser=await chromium.launch({channel:'msedge',headless:true});
  const context=await browser.newContext({viewport:{width:1200,height:1000},deviceScaleFactor:1,locale:'zh-CN'});
  const page=await context.newPage();
  await page.route('**/*',async route=>{
   const url=new URL(route.request().url());
   if(url.origin!=='http://home.local')return route.abort();
   if(url.pathname==='/api/plugin/page/bridge-sdk.js')return route.fulfill({contentType:'text/javascript',body:`window.AstrBotPluginPage={ready:async()=>{},apiGet:async()=>(${JSON.stringify(payload.snapshot)}),apiPost:async()=>{throw Error('截图仅供查看')}};`});
   const name={'/':'index.html','/index.html':'index.html','/style.css':'style.css','/theme.css':'theme.css','/app.js':'app.js'}[url.pathname];
   if(!name)return route.abort();
   return route.fulfill({path:path.join(root,name)});
  });
  await page.goto('http://home.local/');
  await page.waitForFunction(()=>document.querySelector('#current-activity').textContent!=='正在读取她的日常');
  await page.addStyleTag({content:'#note-form,#refresh-plan,#reload,#open-memories,button.text-button{display:none!important}*{animation:none!important;transition:none!important}'});
  await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:payload.output,fullPage:true});
  process.stdout.write('OK');
 }catch(error){process.stderr.write(error.name+': '+error.message);process.exitCode=1;}
 finally{if(browser)await browser.close();}
});
