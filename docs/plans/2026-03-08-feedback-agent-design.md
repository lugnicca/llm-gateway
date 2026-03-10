# Lugnicca Feedback Agent — Design

## Overview

Bouton feedback intégrable dans toute app React. L'utilisateur sélectionne un élément UI, décrit le problème, et un agent autonome crée un ticket Jira détaillé puis ouvre une MR GitLab avec le fix.

## Architecture

```
App React + @lugnicca/feedback-button
  → POST /api/feedback (screenshot + react-grab context + description)
    → Feedback Agent Service (Node)
      → Claude Code headless (claude -p)
        → Phase 1 (claude-sonnet-4.5): analyse + ticket Jira via MCP
        → Phase 2 (qwen3.5-35b-a3b): fix code
        → Phase 3 (claude-sonnet-4.5): review + MR GitLab via MCP
```

## Model routing via gateway

| Tâche | Modèle | Raison |
|-------|--------|--------|
| Analyse + ticket + plan + review | openrouter/anthropic/claude-sonnet-4.5 | Compréhension fine |
| Fix code | openrouter/qwen/qwen3.5-35b-a3b | Rapide, pas cher |

## Stack

- Monorepo pnpm workspaces
- App demo: React 19 + Vite + Tailwind
- Feedback button: react-grab primitives + html2canvas
- Service: Node + Express + simple-git
- Agent: Claude Code CLI headless
- MCP: Jira Cloud + GitLab.com
- Gateway: LiteLLM (localhost:4000)

## Continuité de session

Option 2: le contexte vit dans le repo (.feedback/<ticket-id>.md).
Un dev peut checkout la branche et reprendre avec tout le contexte.

## Cibles

- Jira Cloud
- GitLab.com
