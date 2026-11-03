import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const enc=new TextEncoder();
function fromB64(value:string){return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}
function toB64(value:Uint8Array){return btoa(String.fromCharCode(...value));}
async function keys(){
 const raw=Deno.env.get("TRUSTBET_RECOVERY_ENCRYPTION_KEY")||"";
 const pepper=Deno.env.get("TRUSTBET_RECOVERY_HASH_PEPPER")||"";
 if(!raw||!pepper)throw new Error("Recovery security keys are not configured.");
 const bytes=fromB64(raw);
 if(bytes.length!==32)throw new Error("Recovery encryption key must be 32 bytes (base64).");
 return {aes:await crypto.subtle.importKey("raw",bytes,{name:"AES-GCM"},false,["encrypt","decrypt"]),pepper};
}
function randomCode(){
 const limit=Math.floor(0x100000000/900000)*900000;
 const buf=new Uint32Array(1);
 do{crypto.getRandomValues(buf);}while(buf[0]>=limit);
 return String(100000+(buf[0]%900000));
}
async function digest(code:string,pepper:string){
 const data=await crypto.subtle.digest("SHA-256",enc.encode(pepper+":"+code));
 return Array.from(new Uint8Array(data)).map(x=>x.toString(16).padStart(2,"0")).join("");
}
async function encrypt(code:string,key:CryptoKey){
 const iv=crypto.getRandomValues(new Uint8Array(12));
 const ciphertext=await crypto.subtle.encrypt({name:"AES-GCM",iv},key,enc.encode(code));
 return toB64(new Uint8Array([...iv,...new Uint8Array(ciphertext)]));
}
async function decrypt(value:string,key:CryptoKey){
 const packed=fromB64(value),iv=packed.slice(0,12),data=packed.slice(12);
 const plain=await crypto.subtle.decrypt({name:"AES-GCM",iv},key,data);
 return new TextDecoder().decode(plain);
}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
 if(req.method!=="POST")return reply({error:"Method not allowed."},405);
 const token=req.headers.get("Authorization")?.replace(/^Bearer\s+/i,"");
 const url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!token||!url||!serviceKey)return reply({error:"Unauthorized or server configuration missing."},401);
 const admin=createClient(url,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:auth,error:authErr}=await admin.auth.getUser(token);
 if(authErr||!auth.user)return reply({error:"Invalid session."},401);
 const {data:profile,error:profileErr}=await admin.from("profiles").select("role").eq("id",auth.user.id).maybeSingle();
 const owner=auth.user.email?.toLowerCase()==="superhybridservices@gmail.com"&&!!auth.user.email_confirmed_at;
 if(profileErr||(profile?.role!=="admin"&&!owner))return reply({error:"Admin access required."},403);
 let body:{action?:string;userId?:string};
 try{body=await req.json();}catch{return reply({error:"Invalid request body."},400);}
 if(!["list","ensure"].includes(body.action||""))return reply({error:"Unsupported action."},400);
 const {aes,pepper}=await keys();
 if(body.action==="ensure"&&!/^[0-9a-f-]{36}$/i.test(body.userId||""))return reply({error:"Valid user ID required."},400);
 let query=admin.from("account_recovery_codes").select("id,user_id,code_hash,code_ciphertext,code_slot,created_at,used_at").order("created_at",{ascending:true});
 if(body.action==="ensure")query=query.eq("user_id",body.userId!);
 const {data:rows,error}=await query;
 if(error)return reply({error:error.message},500);
 if(body.action==="ensure"){
  const existing=rows||[];
  for(let slot=1;slot<=3;slot++){
   if(existing.some(x=>x.code_slot===slot))continue;
   let inserted=false;
   for(let attempt=0;attempt<8&&!inserted;attempt++){
    const code=randomCode(),hash=await digest(code,pepper);
    if(existing.some(x=>x.code_hash===hash))continue;
    const {error:insertError}=await admin.from("account_recovery_codes").insert({
     user_id:body.userId,code_hash:hash,code_ciphertext:await encrypt(code,aes),code_slot:slot
    });
    if(!insertError)inserted=true;
    else if(insertError.code!=="23505")return reply({error:"Could not securely create recovery codes."},500);
   }
   if(!inserted)return reply({error:"Could not allocate a unique recovery-code slot. Please retry."},409);
  }
 const {data:all,error:readError}=await (body.action==="list"
  ?admin.from("account_recovery_codes").select("id,user_id,code_hash,code_ciphertext,created_at,used_at").order("created_at",{ascending:true})
  :admin.from("account_recovery_codes").select("id,user_id,code_hash,code_ciphertext,created_at,used_at").eq("user_id",body.userId!).order("created_at",{ascending:true}));
 if(readError)return reply({error:readError.message},500);
 const codes=[];
 for(const row of all||[]){
  try{codes.push({id:row.id,user_id:row.user_id,code:await decrypt(row.code_ciphertext,aes),created_at:row.created_at,used_at:row.used_at});}
  catch(e){console.error("Could not decrypt recovery code",row.id);}
 }
 return reply({codes});
});
