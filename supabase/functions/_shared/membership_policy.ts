export const MEMBERSHIP_PRICE_ID = "price_1UWtMV00BuF4kp6TV3uWObsP";
export type MembershipPrice = {
  id: string; active: boolean; livemode: boolean; currency: string;
  unit_amount: number | null; recurring: {interval: string; interval_count: number} | null;
};
export function validMembershipPrice(price: MembershipPrice, {requireActive = true}: {requireActive?: boolean} = {}): boolean {
  return price.id === MEMBERSHIP_PRICE_ID && (!requireActive || price.active) && price.livemode &&
    price.currency === "nzd" && price.unit_amount === 4999 &&
    price.recurring?.interval === "month" && price.recurring.interval_count === 1;
}
export function membershipPeriodEnd(subscription: {current_period_end?: number; items: {data: {current_period_end?: number}[]}}): string | null {
  const epoch = subscription.items.data[0]?.current_period_end ?? subscription.current_period_end;
  return typeof epoch === "number" && Number.isFinite(epoch) && epoch > 0
    ? new Date(epoch * 1000).toISOString() : null;
}
export function invoiceSubscriptionId(invoice: {subscription?: string | {id:string} | null; parent?: {subscription_details?: {subscription?: string | {id:string} | null} | null} | null}): string | null {
  const value = invoice.parent?.subscription_details?.subscription ?? invoice.subscription;
  return typeof value === "string" ? value : value?.id ?? null;
}
