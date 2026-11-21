import { authenticatedUser, serviceClient } from "../_shared/clients.ts";
import { verifyTransaction } from "../_shared/kkiapay.ts";
import { json, preflight, readJson } from "../_shared/http.ts";

const REFERENCE = /^MTM-[A-Z0-9]{20}$/;
const TRANSACTION_ID = /^[A-Za-z0-9_\-]{4,64}$/;

Deno.serve(async (req: Request) => {
  const early = preflight(req);
  if (early) return early;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const db = serviceClient();

  const user = await authenticatedUser(req, db);
  if (!user) return json({ error: "unauthorized" }, 401);

  const body = await readJson(req);
  const reference = typeof body?.reference === "string" ? body.reference : "";
  const transactionId = typeof body?.transactionId === "string" ? body.transactionId : "";
  if (!REFERENCE.test(reference) || !TRANSACTION_ID.test(transactionId)) {
    return json({ error: "invalid_request" }, 400);
  }

  const { data: intent, error: intentError } = await db
    .from("payment_transactions")
    .select("id, status")
    .eq("reference", reference)
    .eq("user_id", user.id)
    .maybeSingle();

  if (intentError) {
    console.error("payment-verify: lecture intention", intentError);
    return json({ error: "internal_error" }, 500);
  }
  if (!intent) return json({ error: "not_found" }, 404);

  if (intent.status === "succeeded") {
    const { data: sub } = await db
      .from("provider_subscriptions")
      .select("ends_at")
      .eq("transaction_id", intent.id)
      .maybeSingle();
    return json({ status: "succeeded", ends_at: sub?.ends_at ?? null });
  }

  let tx;
  try {
    tx = await verifyTransaction(transactionId);
  } catch (e) {
    console.error("payment-verify: KKiaPay injoignable", e);
    return json({ error: "provider_unreachable" }, 502);
  }

  if (tx.status === "FAILED") {
    await db.rpc("fail_payment", { p_reference: reference, p_reason: "provider_failed", p_raw: tx.raw });
    return json({ status: "failed" });
  }
  if (tx.status === "TRANSACTION_NOT_FOUND" || tx.status === "INVALID_TRANSACTION") {
    return json({ status: "rejected", reason: "transaction_not_found" });
  }
  if (tx.status !== "SUCCESS") {
    return json({ status: "pending" });
  }
  if (tx.echoedReference && tx.echoedReference !== reference) {
    return json({ status: "rejected", reason: "reference_mismatch" });
  }

  const { data, error } = await db.rpc("activate_payment", {
    p_reference: reference,
    p_kkiapay_id: transactionId,
    p_amount: tx.amount,
    p_raw: tx.raw,
  });
  if (error) {
    console.error("payment-verify: activation", error);
    return json({ error: "activation_failed" }, 500);
  }

  return json({
    status: data?.status ?? "rejected",
    ends_at: data?.ends_at ?? null,
    reason: data?.reason ?? null,
  });
});