# JetBrains AI Assistant Setup -- Lugnicca LLM Gateway

This guide explains how to configure JetBrains AI Assistant to use the Lugnicca LLM Gateway as a custom LLM provider.

---

## Prerequisites

Before starting, ensure you have:

1. **Gateway URL** -- The base URL of your LLM Gateway instance (e.g., `https://llm-gateway.your-domain.example`)
2. **API Key** -- A valid LiteLLM API key (obtain from your gateway administrator)
3. **JetBrains IDE** -- IntelliJ IDEA, PyCharm, WebStorm, or any JetBrains IDE (2024.1+)
4. **AI Assistant Plugin** -- The JetBrains AI Assistant plugin installed and enabled

---

## Step-by-Step Configuration

### Step 1: Open AI Assistant Settings

1. Open your JetBrains IDE
2. Navigate to **Settings** (Ctrl+Alt+S on Windows/Linux, Cmd+, on macOS)
3. In the left panel, go to **Tools** -> **AI Assistant**

### Step 2: Select Custom Provider

1. In the AI Assistant settings panel, find the **Provider** section
2. Click the provider dropdown and select **"OpenAI API Compatible"** or **"Custom"**
3. This will reveal fields for custom endpoint configuration

### Step 3: Enter Gateway Details

Configure the following fields:

| Field | Value |
|-------|-------|
| **API URL / Base URL** | `https://llm-gateway.your-domain.example/v1` |
| **API Key** | Your LiteLLM API key (e.g., `sk-...`) |
| **Model** | `prod/claude-sonnet` (recommended) |

> **Note:** The `/v1` suffix is required. The gateway exposes an OpenAI-compatible API at this path.

### Step 4: Select a Model

Choose a model from the available options:

| Model ID | Provider | Best For |
|----------|----------|----------|
| `prod/claude-sonnet` | Vertex AI (EU) | Production code, sensitive projects |
| `prod/claude-haiku` | Vertex AI (EU) | Fast completions, simple tasks |
| `prod/gemini-flash` | Vertex AI (EU) | Very fast, cheap |
| `openrouter/anthropic/claude-sonnet-4` | OpenRouter (ZDR) | Experimentation, non-sensitive work |
| `openrouter/openai/gpt-4o-mini` | OpenRouter (ZDR) | Alternative model, cheap |
| `openrouter/google/gemini-2.0-flash-001` | OpenRouter (ZDR) | Fast experimentation |
| `local/llama` | Ollama (local) | Offline use, maximum privacy |
| `local/codestral` | Ollama (local) | Code-specific tasks, offline |

For most development work, **`prod/claude-sonnet`** is recommended as it provides the best balance of capability and data privacy (EU data residency via Vertex AI). For experimentation, use any `openrouter/*` model -- all 80+ OpenRouter models are available with Zero Data Retention.

### Step 5: Apply and Test

1. Click **Apply** or **OK** to save the settings
2. The AI Assistant should now connect to your gateway

---

## Testing the Connection

1. Open any file in your project
2. Select a block of code
3. Right-click and choose **AI Actions** -> **Explain Code** (or press the AI Assistant shortcut)
4. If the response appears, the connection is working correctly

Alternatively, open the AI Assistant chat panel (usually in the right sidebar) and send a test message like:

```
Hello, which model are you?
```

The response should indicate the model configured in your settings.

---

## Troubleshooting

### Connection Refused / Timeout

- Verify the gateway URL is correct and accessible from your network
- Ensure the URL includes the `/v1` suffix
- Check if a VPN connection is required to reach the gateway
- Test connectivity: open `https://llm-gateway.your-domain.example/health` in a browser

### 401 Unauthorized

- Verify your API key is correct and has not expired
- Ensure the API key has not been revoked by the gateway administrator
- Check that there are no extra spaces or newline characters in the API key field

### 403 Forbidden / Model Not Found

- Verify the model name is spelled correctly (e.g., `prod/claude-sonnet`, not `prod/claude_sonnet`)
- Check that your API key has access to the requested model
- Contact your gateway administrator to verify model availability

### Slow Responses

- If using `local/` models, performance depends on your machine's hardware (GPU recommended)
- Try switching to `prod/claude-haiku` for faster responses
- Check the gateway's Grafana dashboard for latency metrics

### SSL/TLS Errors

- Ensure your IDE trusts the gateway's SSL certificate
- If using a self-signed certificate, add it to your IDE's trust store:
  **Settings** -> **Tools** -> **Server Certificates** -> **Accept non-trusted certificates automatically** (for testing only)

### Responses Cut Off / Incomplete

- The gateway may have a max token limit configured. Contact your administrator to adjust if needed.
- Some JetBrains AI features have their own token limits independent of the provider.

---

## Available Models

For a complete and up-to-date list of available models, query the gateway:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://llm-gateway.your-domain.example/v1/models
```

Or check the `litellm-config.yaml` file in the gateway repository for the full model configuration.

---

## Tips

- **Use `prod/` for all work projects** to ensure EU data residency and compliance
- **Use `sandbox/` only for personal experimentation** with non-sensitive content
- **Use `local/` when working offline** or with highly restricted data
- **Check the Data Classification Guide** (`docs/DATA-CLASSIFICATION.md`) to determine which tier is appropriate for your data
