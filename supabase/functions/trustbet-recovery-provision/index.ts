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
 const url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!serviceKey)return reply({error:"Server configuration missing."},500);
 const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");
 if(!token)return reply({error:"Authentication required."},401);
 const admin=createClient(url,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
 let userId:string;
 if(token===serviceKey){
  let body:any;try{body=await req.json();}catch{return reply({error:"Invalid request."},400);}
  if(!/^[0-9a-f-]{36}$/i.test(body.userId||""))return reply({error:"Valid user ID required."},400);
  userId=body.userId;
 }else{
  const {data,error}=await admin.auth.getUser(token);
  if(error||!data.user)return reply({error:"Invalid session."},401);
  userId=data.user.id;
 }
 const {data:profile,error:profileError}=await admin.from("profiles").select("account_approval_status").eq("id",userId).maybeSingle();
 if(profileError||!profile)return reply({error:"Account profile not found."},404);
 if(profile.account_approval_status==="rejected")return reply({error:"Rejected accounts cannot receive recovery codes."},403);
 try{await provision(admin,userId);}catch(error){console.error("Recovery provisioning failed",error);return reply({error:"Could not securely assign all three recovery codes."},500);}
 return reply({success:true,assigned:3});
});