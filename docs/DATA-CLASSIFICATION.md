# Data Classification Guide -- Lugnicca LLM Gateway

This document defines the data classification levels used within the Lugnicca LLM Gateway and provides guidance on which routing tier is appropriate for each classification.

---

## Classification Levels

### PUBLIC

- **Definition:** Non-sensitive information that is publicly available or intended for public release.
- **Impact if disclosed:** None.
- **Allowed tiers:** Any (`prod/`, `sandbox/`, `local/`)
- **Required guardrails:** None

**Examples:**
- Open-source documentation generation
- Public FAQ content
- Marketing copy drafts based on public information
- Code completion for open-source projects

---

### INTERNAL

- **Definition:** Company-internal information not intended for public disclosure but not sensitive enough to cause significant harm if exposed.
- **Impact if disclosed:** Minor business impact, potential embarrassment.
- **Allowed tiers:** `prod/` or `local/` only
- **Required guardrails:** None (recommended: enable PII guardrail as a precaution)

**Examples:**
- Internal process documentation
- Meeting summary generation
- Internal tool code completion
- Non-sensitive business analysis

---

### CONFIDENTIAL

- **Definition:** Sensitive business information whose disclosure could cause material harm to the organization.
- **Impact if disclosed:** Significant business, legal, or competitive damage.
- **Allowed tiers:** `prod/` (with guardrails) or `local/` only
- **Required guardrails:** `presidio-pii-any`

**Examples:**
- Proprietary algorithm analysis
- Unreleased product feature discussions
- Strategic planning documents
- Internal financial summaries (non-PII)
- Code review for proprietary software

---

### RESTRICTED

- **Definition:** Highly sensitive data including PII, financial records, health data, or information subject to regulatory requirements.
- **Impact if disclosed:** Severe legal, regulatory, or financial consequences. Potential GDPR violations.
- **Allowed tiers:** `local/` only, or `prod/` with strict guardrails
- **Required guardrails:** `presidio-pii-any` + `presidio-block-financial` (when using `prod/`)

**Examples:**
- Customer personal data analysis
- Employee records processing
- Credit card or bank account information
- Health/medical data
- Legal documents containing personal information
- Tax or payroll data

---

## Routing Matrix

| Classification | `prod/` (Vertex AI) | `sandbox/` (OpenRouter) | `local/` (Ollama) |
|---------------|:-------------------:|:-----------------------:|:-----------------:|
| **PUBLIC** | Allowed | Allowed | Allowed |
| **INTERNAL** | Allowed | Not allowed | Allowed |
| **CONFIDENTIAL** | With guardrails | Not allowed | Allowed |
| **RESTRICTED** | With strict guardrails | Not allowed | Allowed |

### Legend
- **Allowed** -- Can be used without additional guardrails
- **With guardrails** -- Must enable `presidio-pii-any` guardrail
- **With strict guardrails** -- Must enable both `presidio-pii-any` and `presidio-block-financial`
- **Not allowed** -- Do not use this tier for this classification level

---

## Guardrail Mapping

| Guardrail | Detected Entities | Required For |
|-----------|-------------------|-------------|
| `presidio-pii-any` | Names, emails, phone numbers, addresses, IP addresses, dates of birth | CONFIDENTIAL, RESTRICTED |
| `presidio-block-financial` | Credit card numbers, IBANs, bank account numbers, financial identifiers | RESTRICTED |

### Applying Guardrails

Guardrails are configured in `litellm-config.yaml` and applied per-model or per-request. When making API calls, ensure the appropriate guardrails are active:

```yaml
# Example: prod model with strict guardrails
- model_name: prod/claude-sonnet-restricted
  litellm_params:
    model: vertex_ai/claude-sonnet-4-20250514
    guardrails:
      - presidio-pii-any
      - presidio-block-financial
```

Alternatively, guardrails can be specified per-request via the API:

```json
{
  "model": "prod/claude-sonnet",
  "messages": [{"role": "user", "content": "..."}],
  "guardrails": ["presidio-pii-any", "presidio-block-financial"]
}
```

---

## Decision Flowchart

1. **Does the data contain PII or financial information?**
   - Yes -> Classification: **RESTRICTED**
   - No -> Continue

2. **Is the data confidential business information?**
   - Yes -> Classification: **CONFIDENTIAL**
   - No -> Continue

3. **Is the data intended for internal use only?**
   - Yes -> Classification: **INTERNAL**
   - No -> Classification: **PUBLIC**

---

## Responsibilities

- **Data owners** are responsible for classifying their data before using the LLM Gateway.
- **Developers** must select the appropriate model tier based on the classification of the data in their prompts.
- **Administrators** must ensure guardrails are properly configured and operational.
- **All users** must report any suspected misclassification or data handling incidents immediately.
