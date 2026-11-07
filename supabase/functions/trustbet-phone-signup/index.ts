import { createClient } from "npm:@supabase/supabase-js@2";
const headers={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,"Content-Type":"application/json"}});
const enc=new TextEncoder();
function fromB64(value:string){return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}
function toB64(value:Uint8Array){return btoa(String.fromCharCode(...value));}
function randomCode(){const limit=Math.floor(0x100000000/900000)*900000;const buf=new Uint32Array(1);do{crypto.getRandomValues(buf);}while(buf[0]>=limit);return String(100000+(buf[0]%900000));}
async function digest(code:string,pepper:string){const data=await crypto.subtle.digest("SHA-256",enc.encode(pepper+":"+code));return Array.from(new Uint8Array(data)).map(x=>x.toString(16).padStart(2,"0")).join("");}
async function encrypt(code:string,key:CryptoKey){const iv=crypto.getRandomValues(new Uint8Array(12));const ciphertext=await crypto.subtle.encrypt({name:"AES-GCM",iv},key,enc.encode(code));return toB64(new Uint8Array([...iv,...new Uint8Array(ciphertext)]));}
async function provision(admin:any,userId:string){
 const raw=Deno.env.get("TRUSTBET_RECOVERY_ENCRYPTION_KEY")||"",pepper=Deno.env.get("TRUSTBET_RECOVERY_HASH_PEPPER")||"";
 if(!raw||!pepper)throw new Error("Recovery security keys are not configured.");
 const bytes=fromB64(raw);if(bytes.length!==32)throw new Error("Recovery encryption key must be 32 bytes.");
 const aes=await crypto.subtle.importKey("raw",bytes,{name:"AES-GCM"},false,["encrypt"]);
 const {data:existing,error}=await admin.from("account_recovery_codes").select("code_slot,code_hash").eq("user_id",userId);
 if(error)throw new Error("Could not check existing recovery codes.");
 for(let slot=1;slot<=3;slot++){
  if((existing||[]).some((r:any)=>r.code_slot===slot))continue;
  let inserted=false;
  for(let attempt=0;attempt<10&&!inserted;attempt++){
   const code=randomCode(),hash=await digest(code,pepper);
   if((existing||[]).some((r:any)=>r.code_hash===hash))continue;
   const {error:insertError}=await admin.from("account_recovery_codes").insert({user_id:userId,code_hash:hash,code_ciphertext:await encrypt(code,aes),code_slot:slot});
   if(!insertError){inserted=true;existing.push({code_slot:slot,code_hash:hash});}
   else if(insertError.code==="23505"){const {data:row}=await admin.from("account_recovery_codes").select("id").eq("user_id",userId).eq("code_slot",slot).maybeSingle();if(row)inserted=true;}
   else throw new Error("Could not securely create recovery codes.");
  }
  if(!inserted)throw new Error("Could not allocate all recovery-code slots.");
 }
}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers});
 if(req.method!=="POST")return reply({error:"Method not allowed."},405);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return reply({error:"Server configuration missing."},500);
 let body:{phone?:string;password?:string;first_name?:string;last_name?:string};try{body=await req.json();}catch{return reply({error:"Invalid request."},400);}
 const phone=String(body.phone||"").trim(),password=String(body.password||"");
 const firstName=String(body.first_name||"").trim().replace(/\s+/g," "),lastName=String(body.last_name||"").trim().replace(/\s+/g," ");
 if(!firstName||!lastName||/\s/.test(firstName)||/\s/.test(lastName)||firstName.length>60||lastName.length>60)return reply({error:"Enter one first name and one surname. Both are required."},400);
 if(!/^\+[1-9]\d{7,14}$/.test(phone))return reply({error:"Enter a valid international phone number."},400);
 if(!/^(?=.{8,15}$)(?=[0-9]*[A-Za-z][0-9]*$)[A-Za-z0-9]+$/.test(password))return reply({error:"Phone passwords must be 8–15 characters: exactly one letter and all remaining characters numbers."},400);
 const admin=createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data,error}=await admin.auth.admin.createUser({phone,password,phone_confirm:true,user_metadata:{phone,first_name:firstName,last_name:lastName,full_name:(firstName+" "+lastName).toUpperCase()}});
 if(error)return reply({error:error.message},400);
 if(!data.user)return reply({error:"Registration could not be completed."},500);
 const {error:banError}=await admin.auth.admin.updateUserById(data.user.id,{ban_duration:"876000h"});
 if(banError){await admin.auth.admin.deleteUser(data.user.id);return reply({error:"Could not safely place the new account into approval hold. Please try again."},500);}
 try{await provision(admin,data.user.id);}catch(error){await admin.auth.admin.deleteUser(data.user.id);return reply({error:"Secure recovery-code setup failed. The incomplete account was not retained. Please try again."},500);}
 return reply({success:true,submitted:true});
});