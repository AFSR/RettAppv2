// Vercel serverless function: création + confirmation d'un PaymentIntent Stripe
// pour un don Apple Pay envoyé depuis l'app iOS RettApp.
//
// L'app iOS appelle POST /api/donate avec :
//   { amountCents: <int>, currency: "eur", paymentMethodId: "pm_...",
//     deviceLocale: "fr_FR", source: "RettApp" }
//
// Réponse 200 :
//   { id: "pi_...", status: "succeeded" | "requires_action", clientSecret: "..." }
// Réponse 400 / 500 :
//   { error: "<code>", message: "<human-readable>" }

import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// CORS minimaliste — l'app iOS ne nécessite pas d'origin, mais on autorise
// les outils de dev (curl, Postman) sans drame.
function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

export default async function handler(req, res) {
  setCors(res);

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }
  if (req.method !== "POST") {
    return res.status(405).json({ error: "method_not_allowed" });
  }

  // Vercel parse automatiquement le JSON via req.body si Content-Type est correct.
  const body = req.body ?? {};
  const { amountCents, currency = "eur", paymentMethodId, deviceLocale, source } = body;

  // Validation stricte des entrées (anti-abus + anti-erreurs).
  if (!Number.isInteger(amountCents) || amountCents < 100 || amountCents > 1_000_000) {
    return res.status(400).json({
      error: "invalid_amount",
      message: "Le montant doit être un entier en centimes entre 100 (1 €) et 1 000 000 (10 000 €)."
    });
  }
  if (typeof paymentMethodId !== "string" || !paymentMethodId.startsWith("pm_")) {
    return res.status(400).json({
      error: "invalid_payment_method",
      message: "paymentMethodId manquant ou invalide."
    });
  }
  if (currency !== "eur") {
    return res.status(400).json({
      error: "unsupported_currency",
      message: "Seul l'euro est supporté pour les dons à l'AFSR."
    });
  }

  try {
    const intent = await stripe.paymentIntents.create({
      amount: amountCents,
      currency,
      payment_method: paymentMethodId,
      payment_method_types: ["card"],
      // confirm:true tente de débiter immédiatement. En cas de 3-D Secure,
      // status sera "requires_action" et l'app utilise le clientSecret pour
      // déclencher la SCA via Stripe SDK.
      confirm: true,
      // Empêche que la même autorisation soit débitée 2× si l'app retry.
      // Idempotence côté Stripe via clé d'idempotence générée à partir du token.
      description: "Don à l'AFSR via RettApp",
      statement_descriptor_suffix: "AFSR DON",
      metadata: {
        source: source ?? "RettApp",
        deviceLocale: deviceLocale ?? "fr_FR"
      }
    }, {
      // Idempotence : si l'app renvoie le même paymentMethodId (ce qui ne devrait
      // pas arriver car Apple Pay regenère un token à chaque sheet), Stripe ne
      // débite qu'une fois.
      idempotencyKey: paymentMethodId
    });

    return res.status(200).json({
      id: intent.id,
      status: intent.status,
      clientSecret: intent.client_secret
    });
  } catch (err) {
    console.error("Stripe error:", err);
    const status = err.statusCode && err.statusCode >= 400 && err.statusCode < 500 ? err.statusCode : 500;
    return res.status(status).json({
      error: err.code ?? "stripe_error",
      message: err.message ?? "Erreur inconnue côté Stripe."
    });
  }
}
