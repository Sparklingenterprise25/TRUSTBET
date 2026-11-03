import { createClient } from "npm:@supabase/supabase-js@2";
const headers={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...headers,"Content-Type":"application/json"}});
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers});
 if(req.method!=="POST")return reply({error:"Method not allowed."},405);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return reply({error:"Server configuration missing."},500);
 let body:{phone?:string;password?:string};
 try{body=await req.json();}catch{return reply({error:"Invalid request."},400);}
 const phone=String(body.phone||"").trim(),password=String(body.password||"");
 if(!/^\+[1-9]\d{7,14}$/.test(phone))return reply({error:"Enter a valid international phone number."},400);
 if(!/^\d{8,}$/.test(password))return reply({error:"Phone password must contain only numbers and at least 8 digits."},400);
 const admin=createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data,error}=await admin.auth.admin.createUser({
  phone,password,phone_confirm:true,user_metadata:{phone}
 });
 if(error)return reply({error:error.message},400);
 if(!data.user)return reply({error:"Registration could not be completed."},500);
 const {error:banError}=await admin.auth.admin.updateUserById(data.user.id,{ban_duration:"876000h"});
 if(banError){
  await admin.auth.admin.deleteUser(data.user.id);
  return reply({error:"Could not safely place the new account into approval hold. Please try again."},500);
 }
 return reply({success:true,submitted:true});
});
