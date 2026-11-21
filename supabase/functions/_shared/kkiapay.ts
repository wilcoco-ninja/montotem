import * as sdk from "npm:@kkiapay-org/nodejs-sdk";

export interface VerifiedTransaction {
  /** SUCCESS, FAILED, TRANSACTION_NOT_FOUND, INVALID_TRANSACTION... */
  status: string;
  amount: number | null;
  /** Référence MONTOTEM renvoyée par KKiaPay si elle est exposée (champ `data` du widget). */
  echoedReference: string | null;
  raw: Record<string, unknown>;
}

// deno-lint-ignore no-explicit-any
function buildClient(): any {
  const privatekey = Deno.env.get("KKIAPAY_PRIVATE_KEY");
  const publickey = Deno.env.get("KKIAPAY_PUBLIC_KEY");
  const secretkey = Deno.env.get("KKIAPAY_SECRET");
  if (!privatekey || !publickey || !secretkey) throw new Error("kkiapay_not_configured");

  // deno-lint-ignore no-explicit-any
  const mod = sdk as any;
  const factory = mod.kkiapay ?? mod.default?.kkiapay ?? mod.default;
  return factory({
    privatekey,
    publickey,
    secretkey,
    sandbox: (Deno.env.get("KKIAPAY_SANDBOX") ?? "true") === "true",
  });
}

function asPositiveInt(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
}

function asNonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

export async function verifyTransaction(transactionId: string): Promise<VerifiedTransaction> {
  const raw = (await buildClient().verify(transactionId)) as Record<string, unknown>;
  const nested = (raw?.data && typeof raw.data === "object" ? raw.data : {}) as Record<string, unknown>;

  return {
    status: String(raw?.status ?? nested.status ?? "UNKNOWN").toUpperCase(),
    amount: asPositiveInt(raw?.amount ?? nested.amount),
    echoedReference:
      asNonEmptyString(raw?.stateData) ??
      asNonEmptyString(raw?.state_data) ??
      asNonEmptyString(nested.stateData) ??
      asNonEmptyString(raw?.data),
    raw,
  };
}