# Phone-code delivery: SMS and WhatsApp providers (2026-11-23)

Proposed by Lorenz for the team (Notion CC-TASK-75). Status: **proposal, not built**. The citizen login of contract
v0.5 already sends six-digit codes through the `SmsProvider` protocol (`backend/api/app/services/sms.py`); today only
`NullSmsProvider` (refuses) and the development `ConsoleSmsProvider` exist. See
[citizen-login.md](citizen-login.md) for the privacy rules that stay binding.

## Prices found (USD per delivered message, list prices, November 2026)

| Channel | Guatemala (+502) | Colombia (+57) | Source |
|---|---|---|---|
| SMS, Twilio | 0.2498 | 0.0592 | Twilio country pages (GT, CO); carrier fees may apply |
| SMS, cheaper aggregators (BulkGate, Plivo, D7) | about 0.04–0.26 | about 0.01–0.05 | Reseller price lists, not verified with carriers |
| WhatsApp authentication template, Meta Cloud API | about 0.011 | about 0.0008 | Meta rate card since 2026-07-01, via aggregators; confirm on Meta's page |

For 10,000 logins a month in Guatemala: Twilio SMS about 2,500 USD, WhatsApp about 110 USD.

## Constraints

- **Guatemala SMS:** alphanumeric sender IDs need registration with the carriers (at least Claro; rules of the
  Superintendencia de Telecomunicaciones), generic IDs such as `INFO` are refused, approval takes from days to
  about four weeks. Delivery and price differ by carrier (Claro, Tigo).
- **WhatsApp:** needs a Meta business account with a verified business, a phone number for the sender, and an
  approved *authentication* template (code, expiry, optional copy button). Only people with WhatsApp receive it;
  Meta bills per delivered template message by the recipient's country code.
- **Privacy:** both routes give the phone number and the code to a US provider (Twilio or Meta). The API never
  sends report data, coordinates or photos with the code.

## Proposal

1. **WhatsApp first, SMS as fallback.** WhatsApp is the usual channel in Guatemala and costs about 1/20 of SMS
   there. The login sheet offers "Recibir código por WhatsApp" and, after a failed or slow delivery,
   "Enviar por SMS".
2. **WhatsApp through Meta's Cloud API directly**, not through a reseller, to avoid per-message markups.
3. **SMS through Twilio Programmable Messaging** for the pilot (simple API, both countries, test credentials and
   delivery receipts); compare one cheaper aggregator once real volumes are known.
4. **Code side (small):** two classes behind the existing `SmsProvider` protocol (`WhatsAppCloudProvider`,
   `TwilioSmsProvider`) selected by configuration, plus a `channel` field on the code request. No change to the
   rate limits, hashing or expiry rules of contract v0.5. Test with fake transports; no real messages in CI.

## Needs from the team

- Who owns the Meta business account and the Twilio account (company, payment method), and the sender number.
- Budget approval for the pilot volume.
- Copy for the WhatsApp authentication template and the consent text in the app (Spanish, Guatemala).

## Sources

- Twilio SMS pricing: [Guatemala](https://www.twilio.com/en-us/sms/pricing/gt), [Colombia](https://www.twilio.com/en-us/sms/pricing/co)
- WhatsApp rates by country (aggregators of Meta's rate card): [formbeep](https://formbeep.com/whatsapp-api-pricing/), [getmanifest](https://blog.getmanifest.ai/whatsapp-business-api-pricing-2026/), [whautomate](https://whautomate.com/whatsapp-business-api-pricing)
- Guatemala sender rules and reseller prices: [Bird](https://bird.com/sms-api/features/destinations/guatemala), [BulkGate](https://www.bulkgate.com/en/pricing/sms/gt/guatemala/), [Miatel](https://docs.miatel.com/docs/country-specific-features-and-restrictions/americas/guatemala), [sent.dm](https://www.sent.dm/resources/sms-pricing/guatemala-sms-pricing)
