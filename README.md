# Microsoft Foundry dla klientów enterprise
## Foundry BYO VNet Integration Test — Workshop

Warsztat krok po kroku: wdrożenie Microsoft Foundry z BYO VNet (Bring Your Own Virtual Network) przy użyciu Azure CLI i Bicep.

> 📘 Pełna instrukcja warsztatu: [WORKSHOP.md](WORKSHOP.md)

## Co to robi?

1. **Deployuje** infrastrukturę Foundry w prywatnej sieci przez Bicep + Azure CLI
2. **Testuje** każdy komponent (sieć, PE, DNS, RBAC, tożsamości, portal)
3. **Weryfikuje izolację** — data plane zablokowany z Internetu
4. **Konfiguruje APIM** jako AI Gateway (Standard v2) lub Standalone Proxy
5. **Sprawdza multi-tenant RBAC** — izolacja per-projekt z Custom Role
6. **Generuje raport** GO/NO-GO z listą co działa a co nie

## Architektura

```
┌──────────────────────────────────────────────────────────────┐
│  Customer BYO VNet (192.168.0.0/16)                          │
│                                                              │
│  snet-agent /24           snet-pe /24                        │
│  Delegacja:               PE: Foundry (CognitiveServices)    │
│  Microsoft.App/           PE: Storage (blob)                 │
│    environments           PE: CosmosDB (sql)                 │
│  Foundry Agent Service    PE: AI Search                      │
│  (Data Proxy + Micro-VMs) PE: APIM Standard v2 (gateway)     │
│                                                              │
│  AzureBastionSubnet /26   snet-mgmt /27                      │
│  Azure Bastion            Jumpbox VM (Win11, private IP)     │
│                                                              │
│  GatewaySubnet /27                                           │
│  VPN P2S Gateway (opcjonalnie)                               │
│                                                              │
│  Private DNS Zones (7 linked do VNet)                        │
└──────────────────────────────────────────────────────────────┘
```

## Nowe funkcje (2025)

- **BYO VNet bez BYO Storage** — wariant Basic (bez obowiązkowego CosmosDB/Storage/Search)
- **Foundry AI Gateway** — natywna integracja APIM v2 z Foundry (token limits, governance)
- **Nowe nazwy ról Foundry** — Foundry User, Foundry Owner, Foundry Account Owner, Foundry Project Manager
- **Fabric IQ przez prywatną sieć** — tool call do Fabric Data Agent
- **Agent publish do M365/Teams** z VNet — wymaga dodatkowej konfiguracji

## Wymagania wstępne

1. **Azure CLI** zainstalowane i zalogowane (`az login`)
2. **Uprawnienia**: Owner na subskrypcji
3. **Region**: Sweden Central, East US, East US 2, France Central, West Europe, Australia East

## Szybki start

```powershell
# 1. Klonuj i konfiguruj
git clone https://github.com/AzureClub/foundry-enterprise-workshop.git
cd foundry-enterprise-workshop
cp .env.example .env    # Uzupełnij wartości
. .\scripts\load-env.ps1

# 2. Deploy infrastruktury
.\scripts\00-preflight.ps1
.\scripts\01-deploy-foundry.ps1     # 15-30 min

# 3. Testy
.\scripts\04-test-network.ps1       # VNet/subnety/DNS
.\scripts\05-test-pe.ps1            # Private Endpoints
.\scripts\06-test-agent.ps1         # Agent Service
.\scripts\08-test-identity.ps1      # MI/RBAC
.\scripts\10-test-portal-access.ps1 # Bastion/Portal

# 4. APIM (opcjonalnie)
.\scripts\02-deploy-apim.ps1        # Standard v2 (5-15 min)
.\scripts\03-import-openapi-mcp.ps1
.\scripts\14-test-ai-gateway.ps1    # Test z Jumpboxa
.\scripts\15-test-foundry-ai-gateway.ps1  # Test Foundry AI Gateway

# 5. Raport
.\scripts\09-e2e-report.ps1         # GO/NO-GO
```

## Dostęp do portalu ai.azure.com

Portal wymaga dostępu z wnętrza VNet (`publicNetworkAccess: Disabled`):

**Przez Bastion:** Azure Portal → `vm-jumpbox` → Connect → Bastion → Edge → `ai.azure.com`

**Przez VPN P2S:** Pobierz profil VPN → Połącz → `ai.azure.com`

## Ważne lekcje (lessons learned)

| # | Lekcja |
|---|--------|
| 1 | **Foundry User** (dawniej Azure AI User) na **Project scope** — minimum do tworzenia agentów |
| 2 | **Foundry Model Reader** (custom role) zamiast Reader — ukrywa nazwy innych projektów |
| 3 | CosmosDB wymaga **data plane RBAC** (`Cosmos DB Built-in Data Contributor`) gdy `disableLocalAuth: true` |
| 4 | Storage connection musi być `AzureStorageAccount`, nie `AzureBlob` |
| 5 | Account `networkInjections` → stan "Accepted" → retry logic na projekt |
| 6 | APIM Standard v2 wymagany dla Foundry AI Gateway; Developer OK dla standalone proxy |
| 7 | `publicNetworkAccess: Disabled` = portal działa TYLKO z VNet (Bastion/VPN) |

## Struktura plików

```
foundry-enterprise-workshop/
├── WORKSHOP.md                    # Pełna instrukcja warsztatu (krok po kroku)
├── README.md                      # Ten plik
├── .env.example                   # Szablon konfiguracji
├── run-all.ps1                    # Orkiestrator
├── bicep/
│   ├── main.bicep                 # Foundry + BYO VNet + PE + RBAC + Bastion
│   ├── main.bicepparam
│   ├── apim.bicep                 # APIM Standard v2 + Private Endpoint
│   └── apim.bicepparam
├── scripts/
│   ├── 00-preflight.ps1           # Pre-flight checks
│   ├── 01-deploy-foundry.ps1      # Deploy Foundry + VNet
│   ├── 02-deploy-apim.ps1         # Deploy APIM Standard v2
│   ├── 03-import-openapi-mcp.ps1  # Import API do APIM
│   ├── 04-test-network.ps1        # Test VNet/subnety/DNS
│   ├── 05-test-pe.ps1             # Test Private Endpoints
│   ├── 06-test-agent.ps1          # Test Agent Service
│   ├── 07-test-apim.ps1           # Test APIM
│   ├── 08-test-identity.ps1       # Test MI/RBAC
│   ├── 09-e2e-report.ps1          # Raport GO/NO-GO
│   ├── 10-test-portal-access.ps1  # Test Bastion/Portal
│   ├── 11-configure-byom.ps1      # BYOM konfiguracja
│   ├── 12-test-byom.ps1           # BYOM testy
│   ├── 13-test-byom-e2e.ps1       # BYOM E2E test
│   ├── 14-test-ai-gateway.ps1     # APIM Standalone Proxy test (6 testów)
│   ├── 15-test-foundry-ai-gateway.ps1  # Foundry AI Gateway test
│   └── load-env.ps1               # Ładowanie .env
├── config/
│   └── test-config.json           # Konfiguracja zasobów
└── docs/                          # Dokumentacja dodatkowa
```

## Cleanup

```powershell
# Usuń resource group (wszystko w środku)
az group delete --name rg-foundry-byovnet --yes --no-wait

# Purguj Foundry Account (soft-delete protection)
az cognitiveservices account purge --name <account-name> --resource-group <rg> --location <region>

# Purguj APIM (soft-delete)
az rest --method DELETE --uri "https://management.azure.com/subscriptions/<sub>/providers/Microsoft.ApiManagement/locations/<region>/deletedservices/<apim-name>?api-version=2024-06-01-preview"
```

## Dokumentacja

- [Foundry BYO VNet](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)
- [Foundry Networking Deep Dive](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive)
- [Foundry AI Gateway](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)
- [Foundry RBAC](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)
- [foundry-samples templates](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep)
