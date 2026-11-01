import { processBusinessBillingEvent, BillingDependencies } from "./business_billing.ts";
import { MEMBERSHIP_PRICE_ID } from "./membership_policy.ts";
import type Stripe from "npm:stripe@18.5.0";
const price={id:MEMBERSHIP_PRICE_ID,active:true,livemode:true,currency:"nzd",unit_amount:4999,recurring:{interval:"month",interval_count:1}};
const subscription={id:"sub_verified",status:"active",livemode:true,customer:"cus_verified",metadata:{spicyself_kind:"business_subscription",spicyself_business_id:"business-1"},items:{data:[{quantity:1,price,current_period_end:2000000000}]},cancel_at_period_end:false};
function fixture({row = {business_id:"business-1",stripe_customer_id:"cus_verified",stripe_subscription_id:"sub_verified"} as Record<string,unknown>|null, current = subscription}={}){
  const updates:Record<string,unknown>[]=[];
  let retrievals=0;
  const chain={error:null,select(){return this;},eq(){return this;},maybeSingle(){return Promise.resolve({data:row,error:null});},update(value:Record<string,unknown>){updates.push(value);return this;}};
  const dependencies={stripe:()=>({subscriptions:{retrieve:async()=>{retrievals++;return current;}}}),service:()=>({from:()=>chain})} as unknown as BillingDependencies;
  return {dependencies,updates,retrievals:()=>retrievals};
}
function event(type:string,object:unknown,account?:string){return {type,data:{object},account} as unknown as Stripe.Event;}
Deno.test("subscription updates retrieve current state rather than trusting out-of-order payloads",async()=>{
  const f=fixture();
  await processBusinessBillingEvent(event("customer.subscription.updated",{...subscription,status:"past_due"}),f.dependencies);
  if(f.updates.length!==1||f.updates[0].status!=="active")throw Error("Stale payload changed verified status");
  if(f.updates[0].current_period_end!==new Date(2000000000*1000).toISOString())throw Error("Renewal period missing");
});
Deno.test("renewal payment failures reconcile the authoritative subscription status",async()=>{
  const f=fixture({current:{...subscription,status:"past_due"}});
  await processBusinessBillingEvent(event("invoice.payment_failed",{parent:{subscription_details:{subscription:"sub_verified"}}}),f.dependencies);
  if(f.updates[0]?.status!=="past_due")throw Error("Invoice failure was not reconciled");
});
Deno.test("stale replaced subscriptions cannot overwrite a newer billing contract",async()=>{
  const f=fixture({row:{business_id:"business-1",stripe_customer_id:"cus_verified",stripe_subscription_id:"sub_newer"}});
  await processBusinessBillingEvent(event("customer.subscription.deleted",subscription),f.dependencies);
  if(f.updates.length!==0)throw Error("Replaced subscription updated billing");
});
Deno.test("unrecognised billing customers and wrong prices never unlock a membership",async()=>{
  for(const f of [fixture({row:null}),fixture({current:{...subscription,items:{data:[{...subscription.items.data[0],price:{...price,unit_amount:0}}]}}})]){
    let failed=false;try{await processBusinessBillingEvent(event("customer.subscription.updated",subscription),f.dependencies);}catch{failed=true;}
    if(!failed||f.updates.length)throw Error("Unverified membership persisted");
  }
});
Deno.test("connected account events cannot change platform business subscriptions",async()=>{
  const f=fixture();
  const handled=await processBusinessBillingEvent(event("customer.subscription.updated",subscription,"acct_connected"),f.dependencies);
  if(handled||f.updates.length||f.retrievals())throw Error("Connected event entered platform billing");
});
Deno.test("archived prices still allow authoritative cancellation reconciliation",async()=>{
  const f=fixture({current:{...subscription,status:"canceled",items:{data:[{...subscription.items.data[0],price:{...price,active:false}}]}}});
  await processBusinessBillingEvent(event("customer.subscription.deleted",subscription),f.dependencies);
  if(f.updates[0]?.status!=="canceled")throw Error("Archived price blocked cancellation");
});
