# 🗺️ Roadmapa rozwoju warsztatu — Foundry Enterprise

> Status: **planowanie** · Ostatnia aktualizacja: 2026-07-08
> Dane zweryfikowane wobec oficjalnej dokumentacji Microsoft (lipiec 2026).

Dokument opisuje kierunki rozwoju warsztatu [WORKSHOP.md](WORKSHOP.md) — od wdrożenia
Foundry w prywatnej sieci (v1.0) do pełnego cyklu życia agentów enterprise (v2.0):
tożsamość, governance danych, control plane, security, observability i skalowanie.

---

## 🎯 Wizja

Ewolucja warsztatu:

```
v1.0 (mamy)                    v2.0 (roadmapa)
──────────────────────         ────────────────────────────────────────
Deploy BYO VNet            →    + Tożsamość agentów (Entra Agent ID)
Private Endpoints          →    + Governance danych (Microsoft Purview)
RBAC izolacja per-projekt  →    + Control plane (Microsoft Agent 365)
APIM AI Gateway            →    + Security & threat (Defender / Content Safety)
Test agentów               →    + Observability & FinOps
                           →    + Zaawansowane wzorce (Hosted/ACR, multi-agent)
                           →    + Delivery (CI/CD, pakowanie jako skill)
```

> 💡 **Punkt zaczepienia:** w testach agentów Foundry widzimy już pola `blueprint`
> (agentIdentityBlueprintObjectId) oraz `instance_identity`. **To jest model Entra Agent ID**
> (Blueprint → Instance). Warsztat już go dotyka — to naturalny most do rozbudowy.

---

## ✅ Stan obecny (v1.0)

| Obszar | Co mamy |
|--------|---------|
| Sieć | BYO VNet (Bicep), delegowany subnet, PE subnet, Private DNS Zones |
| Foundry | Account + Project z network injection, public access Disabled |
| Dane | BYO Storage, CosmosDB, AI Search za Private Endpoints |
| Dostęp | Bastion + Jumpbox, VPN P2S |
| RBAC | Izolacja multi-tenant per-projekt, custom rola „Foundry Model Reader” |
| AI Gateway | APIM Standard v2 + Private Endpoint (Opcja A) / Standalone Proxy (Opcja B) |
| Agenty | Prompt Agents, MCP tools, multi-agent workflow, BYOM |
| Teoria | Networking deep-dive (Data Proxy, Micro-VM), warianty Standard vs Basic |

---

## 🧭 Kierunki rozwoju (tracki)

### 🅰️ Track A — Entra Agent ID (tożsamość agentów) — PRIORYTET

Naturalne rozszerzenie Fazy 7b (RBAC). Odpowiada na pytanie: *kto steruje agentami
i jak wymusić least-privilege oraz kontrolę sieciową na poziomie tożsamości agenta.*

| Moduł | Zawartość | Status MS |
|-------|-----------|:---:|
| A1 | Model Blueprint → Instance (= to co widać w Foundry) | Preview |
| A2 | Managed Identity jako credential blueprintu (FIC, bez sekretów) | Preview |
| A3 | 3 przepływy OAuth: OBO, Autonomous App, User-account | Preview |
| A4 | Conditional Access dla agentów (location/risk) — spójne z VNet | Preview |
| A5 | Owners / Sponsors / Managers — least privilege dla agentów | Preview |

**Dlaczego pierwsze:** minimalny skok koncepcyjny, bezpośrednie rozszerzenie tego,
co już testujemy; Conditional Access location-based ładnie łączy się z BYO VNet.

---

### 🅱️ Track B — Microsoft Purview for AI (governance danych) — PRIORYTET (RODO)

Najlepiej pasuje do wymagań compliance / EU. Governance danych w interakcjach z agentami.

| Moduł | Zawartość | Uwaga |
|-------|-----------|------|
| B1 | Natywna integracja: toggle w Foundry (Operate → Compliance → Security posture) | Zero-code |
| B2 | DSPM for AI — one-click policies (capture prompts/responses) | Audyt |
| B3 | DLP dla agentów — wymaga Entra-registered app + user-context token | ⚠️ Kluczowe |
| B4 | Sensitivity labels + RAG (AI Search honoruje etykiety przy query-time) | RODO |
| B5 | Communication Compliance + eDiscovery + Insider Risk dla interakcji | Audyt |
| B6 | Purview SDK / Agent Framework middleware (ścieżka deweloperska) | Kod |

> ⚠️ **Pułapka do pokazania:** Purview Data Security Policies dla Foundry działają
> **tylko** z tokenem user-context (`userSecurityContext`). App-only token → tylko audyt,
> bez enforcement DLP. Native toggle = audyt/governance; pełne DLP + ochrona przed
> oversharingiem wymaga rejestracji aplikacji w Entra + Purview SDK/Graph API.

---

### 🅲 Track C — Microsoft Agent 365 (control plane) — STRATEGICZNE

Governance agentów w skali całej organizacji (cross-platform).

| Moduł | Zawartość | Status |
|-------|-----------|:---:|
| C1 | Agent Registry — inwentarz agentów (M365 Admin Center) | GA |
| C2 | Agent Map — Foundry jako klaster (Foundry LOB / non-LOB / hosted) | GA |
| C3 | 3 filary: Observe / Govern / Secure | GA |
| C4 | Network controls — Entra rozszerza kontrole sieciowe na agentów | GA |
| C5 | Registry sync (Amazon Bedrock, Google Vertex AI) — multi-cloud | Preview |
| C6 | Shadow AI discovery (Defender + Intune) | Preview |

> ⚠️ **Model licencyjny:** Agent 365 to usługa **tenantowa M365** (licencja E7 lub
> standalone, per-user, wymaga min. M365 E5) — **inny model niż subskrypcja Azure**
> naszego warsztatu. Może wymagać osobnego tenanta demo z licencjami M365.
> GA: 1 maja 2026.

---

### 🅳 Track D — Security & Threat Protection

| Moduł | Zawartość |
|-------|-----------|
| D1 | Content Safety w AI Gateway (jailbreak, prompt injection, groundedness) |
| D2 | Defender for Cloud — AI threat protection, onboarding Purview |
| D3 | Policies APIM: content-safety, PII detection, token limits |

### 🅴 Track E — Observability & FinOps

| Moduł | Zawartość |
|-------|-----------|
| E1 | App Insights + tracing agentów (OpenTelemetry) |
| E2 | Monitoring Data Proxy / Micro-VM — wykrywanie IP exhaustion (5xx) |
| E3 | Token metrics przez APIM (podstawy w teście `15-test-foundry-ai-gateway.ps1`) |
| E4 | FinOps — koszty per projekt / agent, quota governance |

### 🅵 Track F — Zaawansowane wzorce agentów

| Moduł | Zawartość |
|-------|-----------|
| F1 | Hosted Agents (własny kontener z ACR) — Micro-VM w VNet |
| F2 | Multi-agent workflows (bazujemy na przykładzie FactoryDiagnostic) |
| F3 | Fabric IQ przez prywatną sieć (nowy feature) |
| F4 | MCP tools w VNet (doświadczenie z machine-wiki / AI Search) |
| F5 | Evaluations & red-teaming agentów |

### 🅶 Track G — Delivery & pakowanie

| Moduł | Zawartość |
|-------|-----------|
| G1 | CI/CD agentów (azd, GitHub Actions, wersjonowanie) |
| G2 | Modularyzacja Bicep (Basic vs Standard VNet) |
| G3 | Pakowanie jako Copilot CLI skill dla klienta (pierwotny cel projektu) |

---

## 📅 Proponowany timeline

```
┌─ FAZA 2 (najbliższa) ──────────────────────────────┐
│  Track A (Entra Agent ID)   ← most z Fazy 7b        │
│  Track B (Purview)          ← RODO / compliance     │
│  Cel: identity + governance danych                  │
└─────────────────────────────────────────────────────┘
┌─ FAZA 3 ───────────────────────────────────────────┐
│  Track C (Agent 365)        ← wymaga tenanta M365   │
│  Track D (Security / Defender)                       │
│  Track E (Observability / FinOps)                    │
└─────────────────────────────────────────────────────┘
┌─ FAZA 4 ───────────────────────────────────────────┐
│  Track F (Hosted agents, multi-agent, Fabric IQ)    │
│  Track G (CI/CD, pakowanie jako skill)              │
└─────────────────────────────────────────────────────┘
```

---

## 🎯 Rekomendowana kolejność

1. **Track A (Entra Agent ID)** — najmniejszy skok, rozwija Fazę 7b, pokazuje „kto steruje agentami”.
2. **Track B (Purview)** — focus RODO/EU, natywny toggle = szybki demo, mocny argument dla sektora regulowanego.
3. **Track C (Agent 365)** — strategiczne, wymaga osobnego planowania (licencje M365).

---

## 🇪🇺 Uwaga: compliance & data residency (RODO)

Agent 365 i Purview to usługi **tenantowe M365** — dane audytu i interakcji mogą lądować
poza Azure region warsztatu. Do warsztatu warto dodać sekcję **„compliance boundaries”**:
gdzie fizycznie przechowywane są dane audytu/interakcji i jak to pogodzić z wymogiem EU-only.

Powiązanie z wariantami VNet:
- **Standard VNet** (BYO Storage/CosmosDB/Search) → dane agentów w tenancie Azure klienta (EU).
- **Basic VNet** (multi-tenant) → dane w infrastrukturze zarządzanej przez Microsoft — zweryfikuj residency.

---

## 📎 Referencje (zweryfikowane, lipiec 2026)

### Microsoft Agent 365
- Overview: https://learn.microsoft.com/en-us/microsoft-agent-365/overview
- Agent Registry: https://learn.microsoft.com/en-us/microsoft-365/admin/manage/agent-registry
- Agent Map: https://learn.microsoft.com/en-us/microsoft-365/admin/manage/agent-map
- Zarządzanie / licencje: https://learn.microsoft.com/en-us/microsoft-365/admin/manage/agent-365-overview

### Microsoft Entra Agent ID
- Agent identities: https://learn.microsoft.com/en-us/entra/agent-id/agent-identities
- Agent blueprint: https://learn.microsoft.com/en-us/entra/agent-id/agent-blueprint
- OAuth protocols: https://learn.microsoft.com/en-us/entra/agent-id/agent-oauth-protocols
- Conditional Access (workload identity): https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity
- Owners/Sponsors/Managers: https://learn.microsoft.com/en-us/entra/agent-id/agent-owners-sponsors-managers

### Microsoft Purview for AI
- Purview for AI (overview): https://learn.microsoft.com/en-us/purview/ai-microsoft-purview
- Purview for Azure Foundry: https://learn.microsoft.com/en-us/purview/ai-azure-foundry
- Entra-registered AI apps: https://learn.microsoft.com/en-us/purview/ai-entra-registered
- DSPM for AI: https://learn.microsoft.com/en-us/purview/dspm-for-ai
- Purview developer / SDK: https://learn.microsoft.com/en-us/purview/developer/
- Query-time sensitivity labels (AI Search): https://learn.microsoft.com/en-us/azure/search/search-query-sensitivity-labels

### Foundry — sieć prywatna
- Configure Private Link: https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link
- Networking deep dive: https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive
- Control plane — compliance & security: https://learn.microsoft.com/en-us/azure/foundry/control-plane/how-to-manage-compliance-security

### Przykłady (GitHub)
- Purview + AI Search (RAG): https://github.com/Azure-Samples/azure-search-openai-demo-purviewdatasecurity
- Agent Framework + Purview (Python): https://github.com/microsoft/agent-framework/tree/main/python/samples/05-end-to-end/purview_agent
- foundry-samples (infra Bicep): https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep
