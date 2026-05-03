# RettApp donations backend

Endpoint serverless pour traiter les dons Apple Pay envoyés par l'app iOS RettApp via Stripe.

## Architecture

```
iPhone (RettApp)              Vercel (this repo)            Stripe API
       │                              │                          │
       │ 1. Apple Pay sheet           │                          │
       │ 2. STPApplePayContext        │                          │
       │    crée un PaymentMethod ────┐                          │
       │                              │                          │
       │ 3. POST /api/donate ─────────►                          │
       │    {amountCents, pmId, …}    │ 4. paymentIntents.create ►
       │                              │                          │
       │                              │ 5. {id, status, secret} ◄
       │ 6. {id, status, clientSecret}◄                          │
       │                              │                          │
       │ 7. SDK Stripe confirme       │                          │
       │    la SCA si requise         │                          │
```

Aucune information bancaire ne transite par RettApp ni par ce backend en clair —
le `paymentMethod` Stripe est un identifiant opaque.

## Setup local

```bash
npm install
cp .env.example .env
# édite .env, mets STRIPE_SECRET_KEY=sk_test_…
npm install -g vercel
vercel dev
```

L'endpoint local : http://localhost:3000/api/donate

Test rapide :

```bash
curl -X POST http://localhost:3000/api/donate \
  -H "Content-Type: application/json" \
  -d '{"amountCents": 2500, "currency": "eur", "paymentMethodId": "pm_card_visa"}'
```

(`pm_card_visa` est un PaymentMethod de test fourni par Stripe.)

## Déploiement Vercel

1. Push ce dossier sur GitHub (ou import depuis Vercel CLI).
2. Sur https://vercel.com → New Project → import du repo.
3. **Settings → Environment Variables** :
   - `STRIPE_SECRET_KEY` = `sk_test_…` pour Preview/Development
   - `STRIPE_SECRET_KEY` = `sk_live_…` pour Production (uniquement)
4. Deploy.

URL finale : `https://<projet>.vercel.app/api/donate` — à mettre dans
`ApplePayDonationCoordinator.backendURL` côté iOS.

## Sécurité

- **`STRIPE_SECRET_KEY`** ne quitte jamais Vercel. La clé `pk_live_…` (publishable)
  va dans le binaire iOS — c'est OK, elle est faite pour être publique.
- **CORS** : `Access-Control-Allow-Origin: *` est OK ici car l'endpoint ne lit
  rien d'autre que des PaymentMethods opaques de l'app. Si un attaquant appelle
  l'endpoint, il déclenche un débit sur la carte qu'il a déjà tokenisée (donc
  sa propre carte) — sans intérêt.
- **Idempotence** : `paymentMethodId` sert de clé d'idempotence Stripe — un
  retry réseau ne provoque pas de double débit.
- **Validation** : montant entre 1 € et 10 000 €, devise EUR uniquement,
  `pm_…` exigé.

## Webhook reçu fiscal (futur — non implémenté)

Pour générer automatiquement le Cerfa n°11580*04 :

1. Créer un endpoint `/api/webhook` qui reçoit `payment_intent.succeeded` de Stripe.
2. Vérifier la signature avec `STRIPE_WEBHOOK_SECRET`.
3. Générer un PDF (via `pdf-lib`) avec les coordonnées du donateur, le montant,
   la date, le numéro RUP de l'AFSR.
4. Envoyer le PDF par e-mail (Mailjet / SendGrid / Resend).

À implémenter quand le bénévolat manuel devient ingérable (>30 dons/mois).

## Tarifs Stripe non-profit

Stripe applique 1.4% + 0.25 € par défaut en France. Demander la tarification
non-profit (0.8% + 0.25 €) au support :

- E-mail : nonprofit@stripe.com
- Joindre : statuts AFSR, justificatif RUP, RIB de l'association
- Délai : ~1 semaine
