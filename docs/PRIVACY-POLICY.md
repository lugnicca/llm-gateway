# Privacy Policy -- Lugnicca LLM Gateway

**Last Updated:** 2026-03-08
**Version:** 1.0

---

## 1. Data Controller

The **Lugnicca** organization is the data controller responsible for the processing of personal data through the LLM Gateway infrastructure.

**Contact:**
- Email: `[privacy@your-domain.example]`
- Data Protection Officer: `[dpo@your-domain.example]`
- Address: `[Your organization address]`

---

## 2. Data Processed

The LLM Gateway processes the following categories of data:

| Data Type | Description | Retention |
|-----------|-------------|-----------|
| **LLM Prompts** | Text input sent to language models by users | See Section 5 |
| **LLM Responses** | Text output returned by language models | See Section 5 |
| **Request Metadata** | Timestamps, model used, token counts, latency, API key alias | Stored in Cloud SQL |
| **Spend Data** | Cost per request, aggregated per key/model | Stored in Cloud SQL |
| **User Identifiers** | API key alias (no personal usernames stored) | Stored in Cloud SQL |

The gateway does **not** collect or store passwords, authentication tokens to third-party services, or browser cookies.

---

## 3. Routing Tiers and Data Handling

The gateway routes requests to different LLM providers based on the model prefix. Each tier has distinct data handling characteristics:

### 3.1 Prod Tier (`prod/` prefix) -- Vertex AI

- **Provider:** Google Cloud Vertex AI
- **Region:** `europe-west9` (Paris, EU)
- **Data Residency:** All prompt and response data stays within the EU
- **Terms of Service:** Subject to [Google Cloud Terms of Service](https://cloud.google.com/terms)
- **Data Usage by Provider:** Google does not use customer data to train models under the Vertex AI terms. Data is processed solely to provide the service.
- **Guardrails:** Presidio PII detection is available and recommended for sensitive workloads

### 3.2 OpenRouter Tier (`openrouter/` prefix) -- OpenRouter with Zero Data Retention

- **Provider:** OpenRouter
- **Zero Data Retention (ZDR):** Enabled via `data_collection: "deny"`. OpenRouter does not log or retain prompt/response data when ZDR is active.
- **Data Residency:** Requests may be processed outside the EU depending on the upstream model provider
- **Use Case:** Experimentation and non-sensitive workloads only
- **Note:** While ZDR prevents OpenRouter from retaining data, the upstream model provider's policies also apply

### 3.3 Local Tier (`local/` prefix) -- Ollama

- **Provider:** Self-hosted Ollama instance
- **Data Residency:** All data remains on the local machine. No data is transmitted to any external service.
- **Use Case:** Maximum privacy workloads, offline usage, restricted data processing

---

## 4. PII Protection

The gateway integrates **Microsoft Presidio** as a guardrail to detect and block personally identifiable information (PII) before it reaches any LLM provider.

- **Presidio Anonymizer** can detect and redact: names, email addresses, phone numbers, credit card numbers, IBAN codes, IP addresses, and other PII entities
- **Guardrail Modes:**
  - `presidio-sandbox-mask`: Masks PII (emails, names, phones) and blocks financial data (credit cards, IBANs)
  - `presidio-block-financial`: Blocks requests containing financial data (credit cards, IBANs, SSN, crypto)
  - `presidio-log-only`: Masks PII in logs only (no modification to requests)
- **Scope:** Guardrails are applied at the gateway level before data is forwarded to any provider
- **Logging:** Guardrail trigger events are logged (without the PII content) for audit purposes

---

## 5. Data Retention

| Data Category | Storage Location | Retention Period |
|--------------|-----------------|------------------|
| Request/response logs | Cloud SQL (PostgreSQL) | 90 days (configurable) |
| Spend tracking data | Cloud SQL (PostgreSQL) | 1 year |
| Prometheus metrics | Prometheus/Grafana | 30 days |
| Guardrail trigger logs | Cloud SQL (PostgreSQL) | 90 days |
| Local tier data | Local machine only | User-managed |

Data retention periods are configurable and can be adjusted to meet organizational or regulatory requirements.

---

## 6. User Rights (GDPR)

In accordance with the General Data Protection Regulation (GDPR), data subjects have the following rights:

1. **Right of Access (Art. 15):** You may request a copy of the personal data we process about you.
2. **Right to Rectification (Art. 16):** You may request correction of inaccurate personal data.
3. **Right to Erasure (Art. 17):** You may request deletion of your personal data ("right to be forgotten").
4. **Right to Restriction (Art. 18):** You may request restriction of processing in certain circumstances.
5. **Right to Data Portability (Art. 20):** You may request your data in a structured, machine-readable format.
6. **Right to Object (Art. 21):** You may object to processing based on legitimate interests.

To exercise any of these rights, contact the Data Protection Officer at `[dpo@your-domain.example]`.

We will respond to all legitimate requests within **30 days**. In complex cases, this period may be extended by an additional 60 days, with prior notification.

---

## 7. Security Measures

- All external API communications use TLS 1.2+
- API keys are managed through LiteLLM's key management and are never logged in plaintext
- Cloud SQL connections use Cloud SQL Auth Proxy with IAM authentication
- Infrastructure is managed via Terraform with state stored in encrypted GCS buckets
- Access to the gateway admin interface is restricted by API key with role-based permissions

---

## 8. Third-Party Sub-Processors

| Sub-Processor | Purpose | Data Location |
|---------------|---------|---------------|
| Google Cloud (Vertex AI) | LLM inference for prod tier | EU (europe-west9) |
| OpenRouter | LLM inference for sandbox tier (ZDR enabled) | Variable |
| Google Cloud SQL | Request logging and spend tracking | EU |
| Google Cloud Run | Gateway hosting | EU |

---

## 9. Changes to This Policy

We may update this privacy policy from time to time. Changes will be communicated through the repository changelog and take effect upon publication.

---

## 10. Contact

For questions or concerns regarding this privacy policy or data processing:

- **Email:** `[privacy@your-domain.example]`
- **Data Protection Officer:** `[dpo@your-domain.example]`
- **Supervisory Authority:** You have the right to lodge a complaint with your local data protection authority.
