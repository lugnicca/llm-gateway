# User Flows & Connection Guide

## Architecture

```
User (Claude Code / opencode / JetBrains / API)
  |
  | HTTPS + API Key (sk-litellm-xxx)
  v
LiteLLM Gateway (http://localhost:4000 or https://your-domain.example)
  |
  +--> /v1/messages          (format Anthropic natif - Claude Code)
  +--> /v1/chat/completions  (format OpenAI - opencode, JetBrains, n8n)
  +--> /v1/completions       (legacy)
  +--> /v1/models            (liste des modeles)
  |
  | Translation automatique entre formats
  v
+-----------+  +-----------+  +-----------+
| Vertex AI |  | OpenRouter |  |  Ollama   |
| prod/*    |  | openrouter |  | local/*   |
| (EU only) |  | /* (ZDR)   |  | (on-prem) |
+-----------+  +-----------+  +-----------+
```

## Gestion des acces

### Ce qui est dans Secret Manager (GCP)
3 secrets d'infrastructure uniquement :
- `lugnicca-litellm-master-key` -- cle admin pour gerer la gateway
- `lugnicca-litellm-salt-key` -- sel cryptographique pour hasher les virtual keys
- `lugnicca-openrouter-key` -- cle API OpenRouter

### Ce qui est dans PostgreSQL (runtime)
- Teams (id, alias, budget, modeles autorises)
- Virtual keys (hash, alias, team, budget, modeles, metadata)
- Spend tracking (par key, par team, par modele)
- Request logs (metadata seulement, pas les prompts)

### Ce qui est dans litellm-config.yaml (deploiement)
- Definition des modeles et routing
- Guardrails Presidio (MASK, BLOCK, LOG)
- Configuration cache Redis
- Callbacks Prometheus

---

## Onboarding admin

### 1. Creer un team

```bash
GATEWAY_URL="http://localhost:4000"
MASTER_KEY="sk-litellm-master-xxx"

curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "engineering",
    "models": ["prod/*", "openrouter/*", "local/*"],
    "max_budget": 500,
    "budget_duration": "1mo"
  }'
```

Teams typiques :

| Team | Modeles | Budget/mois | Usage |
|------|---------|-------------|-------|
| dx | prod/*, openrouter/*, local/* | illimite | Admins |
| engineering | prod/*, openrouter/*, local/* | 500 | Devs |
| product | prod/gemini-flash, openrouter/* | 200 | PM, design |
| ops | prod/* | 300 | Finance, ops |
| guests | openrouter/* | 30 | Externes |

### 2. Creer une cle utilisateur

```bash
# Script automatise
./scripts/onboard-dev.sh --user alice@lugnicca.com --team engineering --budget 100

# Ou manuellement
curl -s "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "alice",
    "team_id": "<team-uuid>",
    "models": ["prod/*", "openrouter/*", "local/*"],
    "max_budget": 100,
    "budget_duration": "1mo",
    "metadata": {"user": "alice@lugnicca.com", "role": "developer"}
  }'
```

### 3. Batch onboarding

```bash
# CSV format: user_email,team_id,budget,models
./scripts/batch-onboard.sh users.csv
```

---

## Connexion utilisateur

### Claude Code

Claude Code utilise le format **Anthropic natif** (`/v1/messages` avec header `x-api-key`).

**Configuration** (`~/.claude/settings.json`) :

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4000",
    "ANTHROPIC_API_KEY": "sk-litellm-votre-cle"
  }
}
```

**Usage** :

```bash
# Utiliser Claude via OpenRouter
claude --model openrouter/anthropic/claude-sonnet-4 -p "Hello"

# Utiliser Gemini via la gateway (meme format!)
claude --model openrouter/google/gemini-2.0-flash-001 -p "Hello"

# Utiliser un modele prod Vertex AI
claude --model prod/claude-sonnet -p "Hello"
```

**Points cles** :
- Claude Code passe par `/v1/messages` (format Anthropic)
- LiteLLM traduit automatiquement vers le format du provider cible
- **Tous les modeles fonctionnent** : Claude, Gemini, GPT-4o, DeepSeek, Mistral, etc.
- Le tool use, streaming, system prompts fonctionnent sans modification
- Le header `x-api-key` est utilise (pas `Authorization: Bearer`)

**Modeles Claude disponibles via OpenRouter** :
- `openrouter/anthropic/claude-sonnet-4` -- Claude Sonnet 4
- `openrouter/anthropic/claude-sonnet-4.6` -- Claude Sonnet 4.6
- `openrouter/anthropic/claude-opus-4.6` -- Claude Opus 4.6
- `openrouter/anthropic/claude-haiku-4.5` -- Claude Haiku 4.5
- `openrouter/anthropic/claude-3-haiku` -- Claude 3 Haiku (le moins cher)

### opencode

opencode utilise le format **OpenAI** (`/v1/chat/completions` avec `Authorization: Bearer`).

**Configuration** (`.opencode.json` ou variables d'env) :

```json
{
  "provider": {
    "type": "openai",
    "api_key": "sk-litellm-votre-cle",
    "base_url": "http://localhost:4000/v1"
  },
  "model": "openrouter/anthropic/claude-sonnet-4"
}
```

Ou via variables d'environnement :

```bash
export OPENAI_API_KEY="sk-litellm-votre-cle"
export OPENAI_BASE_URL="http://localhost:4000/v1"
opencode --model openrouter/anthropic/claude-sonnet-4
```

**Points cles** :
- opencode passe par `/v1/chat/completions` (format OpenAI)
- Le tool use utilise le format OpenAI (`tools[].function`)
- Streaming via SSE avec `data:` chunks et `[DONE]`
- Le header `Authorization: Bearer` est utilise

### JetBrains AI Assistant

1. **Settings** > **Tools** > **AI Assistant**
2. Provider: **OpenAI API Compatible**
3. Base URL: `http://localhost:4000/v1`
4. API Key: `sk-litellm-votre-cle`
5. Model: `openrouter/anthropic/claude-sonnet-4`

### n8n / HTTP API direct

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-litellm-votre-cle" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openrouter/anthropic/claude-sonnet-4",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

---

## Modeles disponibles

### Prod (Vertex AI, EU-hosted)
| ID | Modele | Usage |
|----|--------|-------|
| `prod/claude-sonnet` | Claude Sonnet 4.6 | Code, analyse |
| `prod/claude-haiku` | Claude Haiku 4.5 | Rapide, pas cher |
| `prod/gemini-flash` | Gemini 2.0 Flash | Tres rapide |
| `prod/gemini-pro` | Gemini 2.5 Pro | Raisonnement |

### OpenRouter (80+ modeles, ZDR)
Format: `openrouter/<provider>/<model>`

| ID | Modele |
|----|--------|
| `openrouter/anthropic/claude-sonnet-4` | Claude Sonnet 4 |
| `openrouter/anthropic/claude-opus-4.6` | Claude Opus 4.6 |
| `openrouter/google/gemini-2.0-flash-001` | Gemini Flash |
| `openrouter/openai/gpt-4o-mini` | GPT-4o mini |
| `openrouter/deepseek/deepseek-chat` | DeepSeek V3 |

Pour la liste complete :
```bash
curl -s http://localhost:4000/v1/models -H "Authorization: Bearer VOTRE_CLE"
```

### Local (Ollama, air-gapped)
| ID | Modele |
|----|--------|
| `local/llama` | Llama 3.1 |
| `local/mistral` | Mistral |
| `local/codestral` | Codestral |

---

## Guardrails

Les guardrails Presidio sont actives par header `x-litellm-guardrail` :

```bash
# Masquer PII (email, nom, telephone)
curl ... -H "x-litellm-guardrail: presidio-sandbox-mask"

# Bloquer donnees financieres (CB, IBAN, SSN)
curl ... -H "x-litellm-guardrail: presidio-block-financial"

# Logger uniquement (pas de modification)
curl ... -H "x-litellm-guardrail: presidio-log-only"
```

---

## Gestion des cles

### Voir ses infos (utilisateur)
```bash
curl http://localhost:4000/key/info \
  -H "Authorization: Bearer VOTRE_CLE"
```

### Operations admin
```bash
# Lister les cles
curl http://localhost:4000/key/list -H "Authorization: Bearer $MASTER_KEY"

# Revoquer une cle
curl -X POST http://localhost:4000/key/delete \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"keys": ["sk-xxx"]}'

# Modifier budget/rate limit
curl -X POST http://localhost:4000/key/update \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key": "sk-xxx", "max_budget": 200, "rpm_limit": 60}'

# Voir le spend d un team
curl "http://localhost:4000/team/info?team_id=UUID" \
  -H "Authorization: Bearer $MASTER_KEY"
```

---

## FAQ

**Q: Claude Code peut-il utiliser des modeles non-Anthropic via la gateway ?**
Oui. LiteLLM traduit automatiquement entre les formats Anthropic et OpenAI. Claude Code avec `--model openrouter/google/gemini-2.0-flash-001` fonctionne parfaitement.

**Q: Ou sont stockes les prompts ?**
Par defaut, les prompts ne sont PAS stockes. Seules les metadonnees sont enregistrees (timestamp, modele, tokens, cout, latence).

**Q: Que se passe-t-il quand le budget est atteint ?**
La requete est rejetee avec un message d'erreur clair. Le budget se reset selon la duree configuree (1mo par defaut).

**Q: Comment voir ma consommation ?**
```bash
curl http://localhost:4000/key/info -H "Authorization: Bearer VOTRE_CLE"
# Retourne: spend, max_budget, budget_reset_at
```

**Q: Les donnees transitent-elles par des serveurs tiers ?**
- `prod/*` : Non, tout reste dans GCP europe-west9 (Vertex AI)
- `openrouter/*` : Les donnees passent par OpenRouter MAIS avec ZDR (Zero Data Retention)
- `local/*` : Non, tout reste sur votre machine (Ollama)
