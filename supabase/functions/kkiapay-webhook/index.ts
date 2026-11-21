import { serviceClient } from "../_shared/clients.ts";
import { verifyTransaction } from "../_shared/kkiapay.ts";
import { json, readJson } from "../_shared/http.ts";

const TRANSACTION_ID = /^[A-Za-z0-9_\-]{4,64}$/;

function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expected = Deno.env.get("KKIAPAY_WEBHOOK_SECRET");
  if (!expected) {
    console.error("kkiapay-webhook: KKIAPAY_WEBHOOK_SECRET manquant");
    return json({ error: "not_configured" }, 500);
  }
  const received = req.headers.get("x-kkiapay-secret") ?? "";
  if (!safeEqual(received, expected)) return json({ error: "unauthorized" }, 401);

  const body = await readJson(req);
  const nested = (body?.data && typeof body.data === "object" ? body.data : {}) as Record<string, unknown>;
  const transactionId = String(body?.transactionId ?? nested.transactionId ?? "");
  if (!TRANSACTION_ID.test(transactionId)) return json({ error: "invalid_request" }, 400);

  // Le contenu du webhook n'est jamais cru : la transaction est revérifiée auprès de KKiaPay.
  let tx;
  try {
    tx = await verifyTransaction(transactionId);
  } catch (e) {
    console.error("kkiapay-webhook: vérification impossible", e);
    return json({ error: "provider_unreachable" }, 502); // KKiaPay rejouera
  }

  const db = serviceClient();

  let reference = tx.echoedReference;
  if (!reference) {
    const { data } = await db
      .from("payment_transactions")
      .select("reference")
      .eq("kkiapay_transaction_id", transactionId)
      .maybeSingle();
    reference = data?.reference ?? null;
  }
  if (!reference) {
    // Le client n'a pas encore rattaché la transaction : payment-verify finalisera.
    return json({ received: true, status: "unmatched" }, 202);
  }

  if (tx.status === "FAILED") {
    await db.rpc("fail_payment", { p_reference: reference, p_reason: "provider_failed", p_raw: tx.raw });
    return json({ received: true, status: "failed" });
  }
  if (tx.status !== "SUCCESS") return json({ received: true, status: "pending" });

  const { data, error } = await db.rpc("activate_payment", {
    p_reference: reference,
    p_kkiapay_id: transactionId,
    p_amount: tx.amount,
    p_raw: tx.raw,
  });
  if (error) {
    console.error("kkiapay-webhook: activation", error);
    return json({ error: "activation_failed" }, 500);
  }
  return json({ received: true, status: data?.status ?? "rejected" });
});