# 🐙 LLM Gateway — Lugnicca / Polyp DX

> LiteLLM self-hosted sur GCP + OpenRouter ZDR sandbox + Vertex AI production.
> Un seul endpoint pour Claude Code, JetBrains AI, n8n, et tous les outils internes.

-----

## Table des matières

- [Phase 0 — Pré-requis](#phase-0--pré-requis)
- [Phase 1 — PoC local](#phase-1--poc-local-1-2h)
- [Phase 2 — Compte OpenRouter](#phase-2--compte-openrouter-15-min)
- [Phase 3 — Infrastructure GCP Terraform](#phase-3--infrastructure-gcp-terraform-demi-journée)
- [Phase 4 — Déploiement production](#phase-4--déploiement-production-2-3h)
- [Phase 5 — Authentification & RBAC](#phase-5--authentification--rbac-2-3h)
- [Phase 6 — Équipes, budgets & clés](#phase-6--équipes-budgets--clés-1h)
- [Phase 7 — Intégration outils dev](#phase-7--intégration-outils-dev-2h)
- [Phase 8 — Monitoring & alerting](#phase-8--monitoring--alerting-demi-journée)
- [Phase 9 — Sécurité & privacy hardening](#phase-9--sécurité--privacy-hardening-2h)
- [Phase 10 — Documentation & onboarding](#phase-10--documentation--onboarding-1h)
- [Structure du repo](#structure-du-repo)
- [Architecture](#architecture)

-----

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   UTILISATEURS                       │
│  Claude Code · JetBrains AI · n8n · Apps internes   │
└──────────────────────┬──────────────────────────────┘
                       │ HTTPS
                       ▼
          ┌────────────────────────┐
          │   Cloud Run (eu-west9) │
          │   LiteLLM Proxy        │
          │   ┌──────────────────┐ │
          │   │ Auth JWT/OIDC    │ │◄── Google Workspace
          │   │ RBAC + Budgets   │ │
          │   │ Presidio PII     │ │◄── Masque/bloque les PII
          │   │ Rate Limiting    │ │
          │   │ Spend Tracking   │ │
          │   └──────────────────┘ │
          └──┬───────┬────────┬───┘
             │       │        │
     ┌───────┘       │        └────────┐
     ▼               ▼                 ▼
┌─────────┐  ┌──────────────┐  ┌────────────┐
│Vertex AI │  │ OpenRouter   │  │  Ollama     │
│(prod)    │  │ (sandbox)    │  │  (local)    │
│          │  │              │  │             │
│ Claude   │  │ ZDR activé   │  │ Air-gapped  │
│ Gemini   │  │ EU routing   │  │ Llama, etc. │
│ Mistral  │  │ 500+ modèles │  │             │
└─────────┘  └──────────────┘  └────────────┘
     │               │
     ▼               ▼
┌─────────┐  ┌──────────────┐
│Cloud SQL │  │ Memorystore  │
│Postgres  │  │ Redis        │
│(keys,    │  │(cache, rate  │
│ spend)   │  │ limiting)    │
└─────────┘  └──────────────┘
```

-----

## Phase 0 — Pré-requis

### 0.1 — Outils à installer sur ton poste

```bash
# Vérifier les outils
gcloud version          # Google Cloud CLI
terraform version       # Terraform >= 1.5
docker --version        # Docker >= 24
docker compose version  # Docker Compose v2
node --version          # Node >= 18 (pour Claude Code CLI)
```

**✅ Vérification :**

```bash
# Tout doit retourner une version, aucune erreur
gcloud version | head -1
terraform version | head -1
docker compose version
```

### 0.2 — Accès GCP

```bash
# S'authentifier
gcloud auth login
gcloud auth application-default login

# Vérifier le projet
gcloud config set project VOTRE_PROJET_GCP
gcloud config get-value project
```

**✅ Vérification :**

```bash
# Doit afficher le nom de votre projet
gcloud projects describe $(gcloud config get-value project) --format="value(name)"
```

### 0.3 — APIs GCP à activer

```bash
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  secretmanager.googleapis.com \
  aiplatform.googleapis.com \
  vpcaccess.googleapis.com \
  iap.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com
```

**✅ Vérification :**

```bash
# Doit lister toutes les APIs ci-dessus comme ENABLED
gcloud services list --enabled --filter="
  name:(run OR sqladmin OR redis OR secretmanager OR aiplatform OR vpcaccess)"
```

### 0.4 — Activer les modèles Vertex AI

Aller dans la console GCP → Vertex AI → Model Garden et activer :

- [ ] Claude Sonnet 4.6 (ou le dernier disponible)
- [ ] Claude Haiku 4.5
- [ ] Gemini 2.0 Flash
- [ ] Gemini 2.5 Pro
- [ ] (Optionnel) Mistral Large

**✅ Vérification :**

```bash
# Tester un appel Vertex AI simple
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://europe-west9-aiplatform.googleapis.com/v1/projects/$(gcloud config get-value project)/locations/europe-west9/publishers/google/models/gemini-2.0-flash:generateContent" \
  -d '{"contents":[{"role":"user","parts":[{"text":"Hello"}]}]}'
```

### 0.5 — Cloner ce repo

```bash
git clone https://github.com/lugnicca/llm-gateway.git
cd llm-gateway
cp .env.example .env
```

-----

## Phase 1 — PoC local (1-2h)

> Objectif : valider que LiteLLM route correctement vers Vertex AI et OpenRouter, en local, avant de toucher à l'infra GCP.

### 1.1 — Préparer le .env local

```bash
# Éditer .env
nano .env
```

Remplir les variables suivantes :

```env
# === LITELLM ===
LITELLM_MASTER_KEY=sk-master-local-$(openssl rand -hex 16)
LITELLM_SALT_KEY=$(openssl rand -base64 32)

# === OPENROUTER ===
OPENROUTER_API_KEY=sk-or-v1-xxxxx  # À récupérer en Phase 2

# === GCP (pour Vertex AI) ===
GOOGLE_APPLICATION_CREDENTIALS=/app/gcp-sa-key.json
GCP_PROJECT_ID=votre-projet-gcp
GCP_REGION=europe-west9

# === POSTGRES (local) ===
POSTGRES_DB=litellm
POSTGRES_USER=litellm
POSTGRES_PASSWORD=$(openssl rand -hex 16)
DATABASE_URL=postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm
```

### 1.2 — Créer un service account GCP pour le dev local

```bash
# Créer le SA
gcloud iam service-accounts create litellm-local \
  --display-name="LiteLLM Local Dev"

# Donner les permissions Vertex AI
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:litellm-local@$(gcloud config get-value project).iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# Télécharger la clé
gcloud iam service-accounts keys create gcp-sa-key.json \
  --iam-account=litellm-local@$(gcloud config get-value project).iam.gserviceaccount.com

# ⚠️ Ne JAMAIS commit ce fichier
echo "gcp-sa-key.json" >> .gitignore
```

**✅ Vérification :**

```bash
# Le fichier doit exister et contenir un JSON valide
cat gcp-sa-key.json | python3 -c "import sys,json; json.load(sys.stdin); print('OK')"
```

### 1.3 — Lancer le stack local

```bash
docker compose -f docker-compose.local.yml up -d
```

Attendre ~30 secondes que PostgreSQL et LiteLLM démarrent.

**✅ Vérification santé :**

```bash
# Health check
curl -s http://localhost:4000/health | python3 -m json.tool

# Doit retourner : {"status": "healthy", ...}
```

### 1.4 — Tester chaque route

```bash
# === Test 0 : Presidio PII Detection (standalone) ===
curl -s http://localhost:5001/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Mon email est antoine@lugnicca.com et mon IBAN est FR76 3000 4000 0300 0000 1234 567",
    "language": "fr"
  }' | python3 -m json.tool

# ✅ Doit retourner une liste d'entités détectées (EMAIL_ADDRESS, IBAN_CODE)

# === Test 0b : Presidio Anonymization ===
curl -s http://localhost:5002/anonymize \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Mon email est antoine@lugnicca.com",
    "anonymizers": {"DEFAULT": {"type": "replace", "new_value": "<ANONYMIZED>"}},
    "analyzer_results": [{"start": 16, "end": 38, "score": 0.95, "entity_type": "EMAIL_ADDRESS"}]
  }' | python3 -m json.tool

# ✅ Doit retourner le texte avec l'email remplacé

# === Test 1 : Vertex AI (Gemini) ===
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "prod/gemini-flash",
    "messages": [{"role": "user", "content": "Dis juste OK"}],
    "max_tokens": 10
  }' | python3 -m json.tool

# ✅ Doit retourner une réponse avec "OK" ou similaire

# === Test 2 : Vertex AI (Claude via Vertex) ===
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "prod/claude-sonnet",
    "messages": [{"role": "user", "content": "Dis juste OK"}],
    "max_tokens": 10
  }' | python3 -m json.tool

# ✅ Doit retourner une réponse Claude

# === Test 3 : OpenRouter sandbox (ZDR) ===
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openrouter/anthropic/claude-sonnet-4",
    "messages": [{"role": "user", "content": "Dis juste OK"}],
    "max_tokens": 10
  }' | python3 -m json.tool

# ✅ Doit retourner une réponse via OpenRouter

# === Test 4 : Lister les modèles disponibles ===
curl -s http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -m json.tool

# ✅ Doit lister tous les modèles configurés

# === Test 5 : Presidio PII masking via LiteLLM (end-to-end) ===
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "prod/gemini-flash",
    "messages": [{"role": "user", "content": "Mon email est test@example.com et mon numéro est 06 12 34 56 78. Dis OK."}],
    "max_tokens": 50,
    "guardrails": ["presidio-sandbox-mask"]
  }' | python3 -m json.tool

# ✅ Le LLM doit recevoir le prompt avec les PII masqués
# ✅ Vérifier dans les logs LiteLLM que le masquage a eu lieu

# === Test 6 : Presidio BLOCK sur données financières ===
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "prod/gemini-flash",
    "messages": [{"role": "user", "content": "Ma carte bancaire est 4111-1111-1111-1111"}],
    "max_tokens": 50,
    "guardrails": ["presidio-sandbox-mask"]
  }' | python3 -m json.tool

# ✅ Doit retourner une erreur 400 — requête bloquée (CREDIT_CARD → BLOCK)

# === Test 7 : Lister les guardrails disponibles ===
curl -s http://localhost:4000/guardrails/list \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -m json.tool

# ✅ Doit lister les 3 guardrails : presidio-sandbox-mask, presidio-block-financial, presidio-log-only
```

### 1.5 — Tester l'UI admin

Ouvrir http://localhost:4000/ui dans le navigateur.

- Login avec le master key
- Vérifier la liste des modèles
- Vérifier le dashboard de spend

**✅ Vérification :**

- [ ] L'UI s'ouvre sans erreur
- [ ] Les modèles prod/* et openrouter/* sont visibles
- [ ] On peut créer une virtual key depuis l'UI

### 1.6 — Arrêter le stack local

```bash
docker compose -f docker-compose.local.yml down
# Garder les données pour plus tard :
# docker compose -f docker-compose.local.yml down -v  # pour nettoyer complètement
```

-----

## Phase 2 — Compte OpenRouter (15 min)

### 2.1 — Créer le compte

1. Aller sur https://openrouter.ai/
1. Créer un compte (email professionnel Lugnicca)
1. Ajouter un moyen de paiement
1. Charger 50-100€ de crédit initial

### 2.2 — Configurer la privacy

Aller dans **Settings → Privacy** :

- [ ] **Activer "ZDR Only"** (Zero Data Retention) → ON
- [ ] **Disable prompt logging** → S'assurer que c'est OFF
- [ ] **Training opt-out** → S'assurer que "Allow training" est OFF pour paid ET free models

### 2.3 — Récupérer l'API key

Settings → API Keys → Create Key

- Nom : `lugnicca-litellm-gateway`
- Copier la clé et la stocker dans le .env

**✅ Vérification :**

```bash
# Tester directement l'API OpenRouter avec ZDR
curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic/claude-sonnet-4",
    "messages": [{"role": "user", "content": "Dis OK"}],
    "max_tokens": 10,
    "provider": {"zdr": true}
  }' | python3 -m json.tool

# ✅ Doit retourner une réponse
# ✅ Si ZDR global est activé, ça marche même sans le param provider.zdr
```

### 2.4 — (Optionnel) EU Routing

Si vous avez un plan Enterprise OpenRouter, tester avec l'endpoint EU :

```bash
curl -s https://eu.openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic/claude-sonnet-4",
    "messages": [{"role": "user", "content": "Dis OK"}],
    "max_tokens": 10
  }' | python3 -m json.tool
```

-----

## Phase 3 — Infrastructure GCP Terraform (demi-journée)

### 3.1 — Configurer les variables Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Remplir :

```hcl
project_id     = "votre-projet-gcp"
region         = "europe-west9"
environment    = "prod"

# Sizing (ajuster selon usage)
db_tier          = "db-f1-micro"    # Monter à db-g1-small si > 50 users
redis_memory_gb  = 1
cloud_run_min_instances = 1
cloud_run_max_instances = 5
```

### 3.2 — Initialiser et planifier

```bash
terraform init
terraform plan -out=tfplan
```

**✅ Vérification :**

```bash
# Le plan doit montrer ~15-20 ressources à créer
terraform show tfplan | grep "# " | wc -l

# Vérifier que les ressources critiques sont là
terraform show tfplan | grep -E "(google_sql_database|google_redis|google_cloud_run|google_secret_manager)"
```

Ressources attendues dans le plan :

- [ ] `google_sql_database_instance.litellm`
- [ ] `google_sql_database.litellm`
- [ ] `google_sql_user.litellm`
- [ ] `google_redis_instance.litellm`
- [ ] `google_secret_manager_secret` × 3 (master_key, salt_key, openrouter_key)
- [ ] `google_secret_manager_secret_version` × 3
- [ ] `google_vpc_access_connector.litellm`
- [ ] `google_cloud_run_v2_service.litellm`
- [ ] `google_service_account.litellm`
- [ ] Bindings IAM

### 3.3 — Appliquer

```bash
terraform apply tfplan
```

Attendre ~5-10 minutes (Cloud SQL est le plus lent).

**✅ Vérification post-apply :**

```bash
# Cloud SQL running
gcloud sql instances describe lugnicca-litellm-db --format="value(state)"
# ✅ Doit retourner : RUNNABLE

# Redis running
gcloud redis instances describe lugnicca-litellm-cache --region=europe-west9 --format="value(state)"
# ✅ Doit retourner : READY

# Secrets créés
gcloud secrets list --filter="name~litellm"
# ✅ Doit lister 3 secrets

# Cloud Run déployé
gcloud run services describe lugnicca-litellm-gateway --region=europe-west9 --format="value(status.url)"
# ✅ Doit retourner une URL https://lugnicca-litellm-gateway-xxxxx.europe-west9.run.app
```

### 3.4 — Stocker les secrets

```bash
# Master key
echo -n "sk-master-$(openssl rand -hex 24)" | \
  gcloud secrets versions add lugnicca-litellm-master-key --data-file=-

# Salt key (ATTENTION : ne peut PAS être changé après ajout d'un modèle)
echo -n "$(openssl rand -base64 32)" | \
  gcloud secrets versions add lugnicca-litellm-salt-key --data-file=-

# OpenRouter API key
echo -n "sk-or-v1-xxxxx" | \
  gcloud secrets versions add lugnicca-openrouter-key --data-file=-
```

**✅ Vérification :**

```bash
# Chaque secret doit avoir au moins 1 version active
for s in lugnicca-litellm-master-key lugnicca-litellm-salt-key lugnicca-openrouter-key; do
  echo "$s: $(gcloud secrets versions list $s --format='value(state)' --limit=1)"
done
# ✅ Doit afficher : ENABLED pour chacun
```

-----

## Phase 4 — Déploiement production (2-3h)

### 4.1 — Pousser le config.yaml dans le déploiement

Le fichier `litellm-config.yaml` à la racine du repo est monté dans le container Cloud Run. Pour le mettre à jour :

```bash
# Redéployer avec la nouvelle config
gcloud run services update lugnicca-litellm-gateway \
  --region=europe-west9 \
  --update-env-vars="CONFIG_HASH=$(md5sum litellm-config.yaml | cut -d' ' -f1)"
```

Ou via Terraform si vous montez la config via un ConfigMap / volume.

### 4.2 — Premier health check production

```bash
GATEWAY_URL=$(gcloud run services describe lugnicca-litellm-gateway --region=europe-west9 --format="value(status.url)")

curl -s "$GATEWAY_URL/health" | python3 -m json.tool
```

**✅ Vérification :**

```bash
# Health
curl -s "$GATEWAY_URL/health"
# ✅ {"status": "healthy"}

# Modèles
MASTER_KEY=$(gcloud secrets versions access latest --secret=lugnicca-litellm-master-key)
curl -s "$GATEWAY_URL/v1/models" -H "Authorization: Bearer $MASTER_KEY" | python3 -m json.tool
# ✅ Liste tous les modèles configurés
```

### 4.3 — Tests de bout en bout en production

```bash
MASTER_KEY=$(gcloud secrets versions access latest --secret=lugnicca-litellm-master-key)

# Test Vertex AI prod
curl -s "$GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"prod/gemini-flash","messages":[{"role":"user","content":"Dis OK"}],"max_tokens":10}'

# Test OpenRouter sandbox ZDR
curl -s "$GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openrouter/anthropic/claude-sonnet-4","messages":[{"role":"user","content":"Dis OK"}],"max_tokens":10}'

# Test Anthropic pass-through (pour Claude Code)
curl -s "$GATEWAY_URL/anthropic/v1/messages" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"prod/claude-sonnet","messages":[{"role":"user","content":"Dis OK"}],"max_tokens":10}'
```

**✅ Vérification :**

- [ ] Réponse 200 pour chaque test
- [ ] Les réponses contiennent du contenu généré
- [ ] L'UI admin est accessible à `$GATEWAY_URL/ui`
- [ ] Le spend tracking montre les requêtes de test

### 4.4 — Configurer le domaine custom (optionnel mais recommandé)

```bash
# Mapper un domaine custom
gcloud run domain-mappings create \
  --service=lugnicca-litellm-gateway \
  --domain=llm-gateway.lugnicca.com \
  --region=europe-west9
```

Puis ajouter les enregistrements DNS indiqués par la commande.

**✅ Vérification :**

```bash
curl -s https://llm-gateway.lugnicca.com/health
# ✅ {"status": "healthy"}
```

-----

## Phase 5 — Authentification & RBAC (2-3h)

### 5.1 — Option A : Clés statiques (simple, pour commencer)

Chaque utilisateur reçoit une virtual key avec des permissions et un budget :

```bash
# Créer une clé pour un dev
curl -s "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "models": ["prod/claude-sonnet", "prod/gemini-flash", "openrouter/*"],
    "max_budget": 150,
    "budget_duration": "1mo",
    "key_alias": "antoine-dx",
    "metadata": {"team": "dx", "user": "antoine"}
  }' | python3 -m json.tool

# ✅ Retourne une clé sk-xxxxx — la noter pour l'utilisateur
```

### 5.2 — Option B : JWT/OIDC via Google Workspace (recommandé)

#### 5.2.1 — Créer un OAuth Client ID dans GCP

1. Console GCP → APIs & Services → Credentials
1. Create Credentials → OAuth client ID
1. Application type : Web application
1. Authorized redirect URIs : `https://llm-gateway.lugnicca.com/sso/callback`
1. Noter le Client ID et Client Secret

#### 5.2.2 — Configurer LiteLLM

Ajouter dans `litellm-config.yaml` :

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  enable_jwt_auth: true
  litellm_jwtauth:
    user_id_jwt_field: "email"
    team_id_jwt_field: "hd"           # domaine Google Workspace = team
    enforce_rbac: true
    role_mappings:
      - role: "litellm.api.consumer"
        internal_role: "team"
    role_permissions:
      - role: team
        models: ["prod/*", "openrouter/*"]
        routes: ["/v1/chat/completions", "/v1/models", "/anthropic/*"]
  environment_variables:
    JWT_PUBLIC_KEY_URL: "https://www.googleapis.com/oauth2/v3/certs"
    JWT_AUDIENCE: "VOTRE_CLIENT_ID.apps.googleusercontent.com"
```

**✅ Vérification :**

```bash
# Obtenir un token Google
TOKEN=$(gcloud auth print-identity-token)

# Tester avec le JWT
curl -s "$GATEWAY_URL/v1/models" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

# ✅ Doit lister les modèles (si le token est valide et le domaine est autorisé)
```

### 5.3 — Créer les équipes

```bash
# Équipe DX (admin)
curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "dx",
    "models": ["prod/*", "openrouter/*", "local/*"],
    "max_budget": 999999,
    "budget_duration": "1mo"
  }'

# Équipe Engineering
curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "engineering",
    "models": ["prod/*", "openrouter/*", "local/*"],
    "max_budget": 500,
    "budget_duration": "1mo"
  }'

# Équipe Product/Design
curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "product",
    "models": ["prod/gemini-flash", "openrouter/*"],
    "max_budget": 200,
    "budget_duration": "1mo"
  }'

# Équipe Ops/Finance (prod only, pas de sandbox)
curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "ops-finance",
    "models": ["prod/*"],
    "max_budget": 300,
    "budget_duration": "1mo"
  }'

# Invités/Stagiaires
curl -s "$GATEWAY_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_alias": "guests",
    "models": ["openrouter/*"],
    "max_budget": 30,
    "budget_duration": "1mo"
  }'
```

**✅ Vérification :**

```bash
curl -s "$GATEWAY_URL/team/list" \
  -H "Authorization: Bearer $MASTER_KEY" | python3 -m json.tool

# ✅ Doit lister les 5 équipes créées
```

-----

## Phase 6 — Équipes, budgets & clés (1h)

### 6.1 — Générer les clés par utilisateur

Script d'automatisation `scripts/create-user-key.sh` :

```bash
./scripts/create-user-key.sh --user antoine --team dx --budget 150
# Output : Clé créée pour antoine (team: dx, budget: 150€/mois)
# sk-litellm-xxxxxxxx
```

### 6.2 — Script de batch onboarding

```bash
# Depuis un CSV : user_email,team,budget,models
./scripts/batch-onboard.sh users.csv
```

Format du CSV (`users.csv`) :

```csv
user_email,team,budget,models
antoine,dx,150,prod/*,openrouter/*
marie,engineering,150,prod/*,openrouter/*
paul,product,80,prod/gemini-flash,openrouter/*
sophie,ops-finance,100,prod/*
intern-01,guests,30,openrouter/*
```

**✅ Vérification :**

```bash
# Lister toutes les clés
curl -s "$GATEWAY_URL/key/list" \
  -H "Authorization: Bearer $MASTER_KEY" | python3 -c "
import sys, json
keys = json.load(sys.stdin)
for k in keys.get('keys', []):
    print(f\"{k.get('key_alias', 'N/A'):20s} team={k.get('team_id', 'N/A'):12s} budget={k.get('max_budget', 'N/A')}\")
"

# ✅ Doit lister tous les utilisateurs avec leurs budgets
```

### 6.3 — Tester les restrictions

```bash
# Tester qu'un guest NE PEUT PAS utiliser prod/*
GUEST_KEY="sk-litellm-guest-key"

curl -s "$GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $GUEST_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"prod/claude-sonnet","messages":[{"role":"user","content":"test"}],"max_tokens":5}'

# ✅ Doit retourner une erreur 403 ou "model not allowed"

# Tester que le guest PEUT utiliser openrouter/*
curl -s "$GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $GUEST_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openrouter/anthropic/claude-sonnet-4","messages":[{"role":"user","content":"test"}],"max_tokens":5}'

# ✅ Doit retourner une réponse 200
```

-----

## Phase 7 — Intégration outils dev (2h)

### 7.1 — Claude Code CLI

```bash
# Installer Claude Code
npm install -g @anthropic-ai/claude-code

# Configurer pour utiliser le gateway
mkdir -p ~/.claude
cat > ~/.claude/settings.json << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://llm-gateway.lugnicca.com",
    "ANTHROPIC_AUTH_TOKEN": "sk-litellm-ta-cle-perso"
  }
}
EOF

# Ou avec JWT dynamique (recommandé) :
cat > ~/.claude/settings.json << 'EOF'
{
  "apiKeyHelper": "bash -c 'gcloud auth print-identity-token'",
  "env": {
    "ANTHROPIC_BASE_URL": "https://llm-gateway.lugnicca.com"
  }
}
EOF
```

**✅ Vérification :**

```bash
# Lancer Claude Code et vérifier qu'il se connecte
claude --model prod/claude-sonnet --print "Dis juste OK"

# ✅ Doit retourner "OK" via le gateway

# Tester un modèle sandbox
claude --model openrouter/openai/gpt-4o --print "Dis juste OK"

# ✅ Doit retourner "OK" via OpenRouter
```

### 7.2 — Plugin Claude Code JetBrains

1. Ouvrir IntelliJ/PyCharm/WebStorm
1. Settings → Plugins → Marketplace → Chercher "Claude Code [Beta]"
1. Installer et redémarrer l'IDE
1. Ouvrir le terminal intégré de l'IDE
1. Taper `claude` — le plugin s'active automatiquement

**✅ Vérification :**

- [ ] Cmd+Esc (Mac) / Ctrl+Esc (Windows/Linux) ouvre Claude Code
- [ ] Les diffs apparaissent dans le diff viewer JetBrains
- [ ] La sélection de code est automatiquement partagée avec Claude

### 7.3 — JetBrains AI Assistant (OpenAI-compatible endpoint)

1. Settings → Tools → AI Assistant → Providers & API keys
1. Third-party AI providers → "OpenAI-compatible"
1. Configurer :
   - **URL** : `https://llm-gateway.lugnicca.com/v1`
   - **API Key** : ta clé LiteLLM personnelle
1. Click "Test Connection"
1. Dans Models Assignment, assigner les modèles :
   - Core features : `prod/claude-sonnet`
   - Instant helpers : `prod/gemini-flash`

**✅ Vérification :**

- [ ] "Test Connection" retourne un succès
- [ ] Les modèles apparaissent dans le sélecteur de l'AI Chat
- [ ] L'AI Chat répond avec le modèle sélectionné
- [ ] La complétion de code fonctionne dans l'éditeur

### 7.4 — n8n

Pour les workflows n8n, utiliser le node "HTTP Request" ou le node "OpenAI" avec :

- Base URL : `https://llm-gateway.lugnicca.com/v1`
- API Key : une clé LiteLLM dédiée au service n8n (team: dx, budget élevé)

```json
{
  "model": "prod/claude-sonnet",
  "messages": [{"role": "user", "content": "{{ $json.prompt }}"}],
  "max_tokens": 1000
}
```

**✅ Vérification :**

- [ ] Créer un workflow n8n de test qui appelle le gateway
- [ ] Vérifier que la requête apparaît dans le spend tracking LiteLLM

### 7.5 — Script d'onboarding dev automatisé

```bash
# Pour un nouveau dev :
./scripts/onboard-dev.sh --user antoine --team engineering

# Ce script :
# 1. Crée une virtual key LiteLLM
# 2. Génère le ~/.claude/settings.json
# 3. Affiche les instructions pour JetBrains AI Assistant
# 4. Envoie un message Slack avec les infos
```

-----

## Phase 8 — Monitoring & alerting (demi-journée)

### 8.1 — Prometheus metrics

LiteLLM expose `/metrics` nativement. Configurer le scrape dans votre Prometheus ou Cloud Monitoring :

```yaml
# prometheus.yml (déjà fourni dans le repo)
scrape_configs:
  - job_name: 'litellm'
    scrape_interval: 30s
    static_configs:
      - targets: ['lugnicca-litellm-gateway:4000']
```

**✅ Vérification :**

```bash
curl -s "$GATEWAY_URL/metrics" | head -20
# ✅ Doit retourner des métriques Prometheus formatées
```

### 8.2 — Alertes Slack via n8n

Créer un workflow n8n qui :

1. **Trigger** : Cron toutes les heures
1. **HTTP Request** : `GET $GATEWAY_URL/global/spend/report` avec master key
1. **IF node** : budget consommé > 80%
1. **Slack node** : notification dans #llm-alerts

Alertes à configurer :

- [ ] Budget équipe > 80% du plafond mensuel
- [ ] Erreurs 5xx > 5 en 10 min
- [ ] Latence P95 > 30s
- [ ] (Optionnel) PII détecté dans requête sandbox

### 8.3 — Dashboard spend

Utiliser l'UI LiteLLM (`/ui`) pour le suivi quotidien, ou exporter vers BigQuery/Looker Studio :

```bash
# Export des logs de spend
curl -s "$GATEWAY_URL/global/spend/logs?start_date=2026-03-01&end_date=2026-03-31" \
  -H "Authorization: Bearer $MASTER_KEY" > spend-march.json
```

**✅ Vérification :**

- [ ] Le dashboard UI montre les requêtes de test
- [ ] Le spend par utilisateur/modèle est visible
- [ ] Les alertes Slack se déclenchent sur le workflow n8n de test

-----

## Phase 9 — Sécurité & privacy hardening (2h)

### 9.1 — Checklist sécurité infra

- [ ] Cloud Run n'est PAS public → utiliser IAP ou VPN

  ```bash
  # Vérifier si l'accès est restreint
  gcloud run services describe lugnicca-litellm-gateway --region=europe-west9 \
    --format="value(spec.template.metadata.annotations['run.googleapis.com/ingress'])"
  # ✅ Doit retourner "internal" ou "internal-and-cloud-load-balancing"
  ```

- [ ] Cloud SQL n'a PAS d'IP publique

  ```bash
  gcloud sql instances describe lugnicca-litellm-db --format="value(settings.ipConfiguration.ipv4Enabled)"
  # ✅ Doit retourner "False"
  ```

- [ ] Les secrets sont dans Secret Manager, pas en variables d'env en clair
- [ ] Le service account Cloud Run a les permissions minimales (Vertex AI User, Secret Accessor)
- [ ] TLS activé partout (Cloud Run le fait par défaut)

### 9.2 — Checklist privacy

- [ ] OpenRouter ZDR activé au niveau du compte
  - Vérifier sur https://openrouter.ai/settings/privacy
- [ ] `zdr: true` et `data_collection: deny` dans le config.yaml pour openrouter/*
- [ ] Prompt logging désactivé sur OpenRouter
- [ ] Les modèles Vertex AI sont en region `europe-west9`
- [ ] Pas de logging des prompts en production (ou hashé)

  ```yaml
  # Dans litellm-config.yaml
  general_settings:
    disable_spend_logs: false   # On garde le spend tracking
    # Les prompts ne sont PAS stockés par défaut, seulement les métadonnées
  ```

### 9.3 — Presidio PII Detection (intégré)

L'intégration Presidio est déjà configurée dans `litellm-config.yaml`. Trois guardrails sont disponibles :

| Guardrail | Mode | Quand l'utiliser |
|-----------|------|-----------------|
| `presidio-sandbox-mask` | `pre_call`, MASK/BLOCK | Par défaut sur toutes les requêtes. Masque emails, noms, téléphones. Bloque IBAN et cartes. |
| `presidio-block-financial` | `pre_call`, BLOCK | Opt-in. Bloque toute requête contenant des données financières ou PII. |
| `presidio-log-only` | `logging_only`, MASK | Opt-in. Masque les PII dans les logs uniquement (Langfuse, etc.), pas dans la requête. |

### 9.4 — Rotation des clés

```bash
# Rotation du master key (ne pas oublier de mettre à jour les références)
./scripts/rotate-master-key.sh

# Rotation des virtual keys utilisateurs (tous les 90 jours)
./scripts/rotate-user-keys.sh --days 90
```

**✅ Vérification finale sécurité :**

```bash
./scripts/security-audit.sh
# ✅ Doit passer tous les checks sans WARNING ni FAIL
```

-----

## Phase 10 — Documentation & onboarding (1h)

### 10.1 — Wiki interne

Créer une page dans votre wiki (Notion, Confluence, etc.) avec :

- [ ] URL du gateway : `https://llm-gateway.lugnicca.com`
- [ ] Comment obtenir sa clé : contacter le DX team ou `./scripts/onboard-dev.sh`
- [ ] Liste des modèles disponibles (prod vs sandbox)
- [ ] Guide de config Claude Code (copier/coller le settings.json)
- [ ] Guide de config JetBrains AI Assistant (captures d'écran)
- [ ] Règles de classification des données (Confidentiel / Interne / Public)
- [ ] Qui contacter en cas de problème : #dx-support sur Slack

### 10.2 — Message d'annonce Slack

```
*LLM Gateway disponible !*

L'équipe DX a déployé un gateway centralisé pour accéder à tous les modèles IA :

*Comment l'utiliser :*
- Claude Code : configurez votre `~/.claude/settings.json` (guide : [lien wiki])
- JetBrains AI : Settings -> AI Assistant -> OpenAI-compatible (guide : [lien wiki])
- n8n : utilisez le node HTTP Request avec l'endpoint gateway

*Modèles disponibles :*
- `prod/claude-sonnet` — Claude Sonnet 4.6 via Vertex AI
- `prod/gemini-flash` — Gemini 2.0 Flash via Vertex AI
- `openrouter/*` — 500+ modèles via OpenRouter (ZDR activé)

*Pour obtenir votre clé :* demandez sur #dx-support

*Privacy :* toutes les requêtes sandbox sont en Zero Data Retention.
Les données confidentielles (clients, finance) ne doivent passer QUE par les modèles prod/*.
```

### 10.3 — Workshop d'onboarding

Planifier une session de 30 min :

1. Démo live : Claude Code dans le terminal (5 min)
1. Démo live : JetBrains AI Assistant avec le gateway (5 min)
1. Explication des préfixes prod/* vs openrouter/* (5 min)
1. Règles de privacy : ce qui peut / ne peut pas aller dans le sandbox (5 min)
1. Q&A (10 min)

-----

## Structure du repo

```
llm-gateway/
├── README.md                          <- Ce fichier
├── .env.example                       <- Template des variables d'environnement
├── .gitignore
│
├── litellm-config.yaml                <- Configuration LiteLLM (modèles, settings)
├── docker-compose.local.yml           <- Stack local pour dev/test
├── prometheus.yml                     <- Config Prometheus
│
├── terraform/                         <- Infrastructure GCP
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── database/
│       ├── redis/
│       ├── secrets/
│       ├── cloudrun/
│       └── networking/
│
├── presidio/                          <- Presidio PII detection
│   └── custom_recognizers.json        <- Patterns custom (Player IDs, clés API, SSN FR)
│
├── scripts/                           <- Scripts d'administration
│   ├── create-user-key.sh
│   ├── batch-onboard.sh
│   ├── onboard-dev.sh
│   ├── rotate-master-key.sh
│   ├── rotate-user-keys.sh
│   └── security-audit.sh
│
├── monitoring/                        <- Dashboards & alertes
│   ├── grafana-dashboard.json
│   └── n8n-alerts-workflow.json
│
└── docs/                              <- Documentation
    ├── PRIVACY-POLICY.md
    ├── DATA-CLASSIFICATION.md
    └── JETBRAINS-SETUP.md
```

-----

## Commandes utiles au quotidien

```bash
# Lister tous les modèles
curl -s "$GATEWAY_URL/v1/models" -H "Authorization: Bearer $KEY" | jq '.data[].id'

# Voir le spend d'une équipe
curl -s "$GATEWAY_URL/team/info?team_id=xxx" -H "Authorization: Bearer $MASTER_KEY" | jq '.spend'

# Créer une clé rapide
curl -s "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"key_alias":"test","max_budget":10,"budget_duration":"1d"}'

# Révoquer une clé
curl -s "$GATEWAY_URL/key/delete" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"keys":["sk-litellm-xxx"]}'

# Voir les logs de spend récents
curl -s "$GATEWAY_URL/global/spend/logs?limit=20" -H "Authorization: Bearer $MASTER_KEY" | jq '.'
```
