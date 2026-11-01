import { MEMBERSHIP_PRICE_ID, validMembershipPrice, membershipPeriodEnd, invoiceSubscriptionId } from "./membership_policy.ts";
const price = {id:MEMBERSHIP_PRICE_ID, active:true, livemode:true, currency:"nzd",unit_amount:4999,recurring:{interval:"month",interval_count:1}};
Deno.test("only the active live NZD 49.99 monthly membership price is accepted",()=>{
  if(!validMembershipPrice({...price,active:false},{requireActive:false}))throw Error("Archived price must still reconcile existing cancellations");
  if(!validMembershipPrice(price))throw Error("Correct price rejected");
  for(const change of [{active:false},{livemode:false},{currency:"usd"},{unit_amount:0},{unit_amount:4998},{id:"wrong"},{recurring:{interval:"year",interval_count:1}},{recurring:{interval:"month",interval_count:2}}]){
    if(validMembershipPrice({...price,...change}))throw Error("Unverified price accepted");
  }
});
Deno.test("renewal dates support item-level Stripe periods and legacy subscriptions",()=>{
  const result=membershipPeriodEnd({current_period_end:1,items:{data:[{current_period_end:2000000000}]}});
  if(result!==new Date(2000000000*1000).toISOString())throw Error("Wrong item period");
  if(membershipPeriodEnd({current_period_end:2000000000,items:{data:[]}})!==result)throw Error("Legacy period unsupported");
  if(membershipPeriodEnd({items:{data:[]}})!==null)throw Error("Fabricated renewal date");
});
Deno.test("invoice events resolve modern and legacy subscription identifiers",()=>{
  if(invoiceSubscriptionId({parent:{subscription_details:{subscription:{id:"sub_current"}}},subscription:"sub_old"})!=="sub_current")throw Error("Wrong authoritative subscription");
  if(invoiceSubscriptionId({subscription:"sub_legacy"})!=="sub_legacy")throw Error("Missing legacy subscription");
  if(invoiceSubscriptionId({})!==null)throw Error("Non-subscription invoice misrouted");
});
