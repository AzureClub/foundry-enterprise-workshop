# Microsoft Foundry dla klientów enterprise
## Foundry BYO VNet Integration Test — Workshop

Warsztat krok po kroku: wdrożenie Microsoft Foundry z BYO VNet (Bring Your Own Virtual Network) przy użyciu Azure CLI, Bicep i GitHub Copilot.

## Co to robi?

1. **Deployuje** całą infrastrukturę przez Bicep + Azure CLI
2. **Testuje** każdy komponent (sieć, PE, DNS, RBAC, tożsamości, portal)
3. **Weryfikuje izolację** — data plane zablokowany z Internetu
4. **Generuje raport** GO/NO-GO z listą co działa a co nie

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
│                                                              │
│  AzureBastionSubnet /26   snet-mgmt /27                      │
│  Azure Bastion            Jumpbox VM (Win11, private IP)     │
│                                                              │
│  GatewaySubnet /27        snet-apim /27 (opcjonalnie)        │
│  VPN P2S Gateway          API Management (Internal VNet)     │
│                                                              │
│  Private DNS Zones (7 linked do VNet)                        │
└──────────────────────────────────────────────────────────────┘
```

## Wymagania wstępne

1. **Azure CLI** zainstalowane i zalogowane (`az login`)
2. **Uprawnienia**: Owner lub Role Based Access Administrator na subskrypcji
3. **Region**: Foundry Agent Service musi być dostępny w wybranym regionie
   - Wspierane: Australia East, East US, East US 2, France Central, Sweden Central, West Europe, West US...

## Szybki start

### Krok 1: Konfiguracja

Edytuj `config/test-config.json` — ustaw swoją subskrypcję, region i nazwy zasobów.

### Krok 2: Ustaw hasło VM

```powershell
$env:VM_ADMIN_PASSWORD = "TwojeHaslo123!"
```

### Krok 3: Uruchom orkiestrator

```powershell
# Wszystko jednym poleceniem:
.\run-all.ps1

# Lub krok po kroku:
.\scripts\00-preflight.ps1          # Pre-flight checks
.\scripts\01-deploy-foundry.ps1     # Deploy (15-30 min, VPN ~25 min)
.\scripts\04-test-network.ps1       # Test VNet/subnety/DNS
.\scripts\05-test-pe.ps1            # Test Private Endpoints
.\scripts\06-test-agent.ps1         # Test Agent Service + izolacja
.\scripts\08-test-identity.ps1      # Test MI/RBAC
.\scripts\10-test-portal-access.ps1 # Test Bastion/VPN/Portal
.\scripts\09-e2e-report.ps1         # Raport GO/NO-GO
```

### Krok 4: Dostęp do portalu ai.azure.com

Portal ai.azure.com ładuje UI z Internetu, ale wszystkie API calls idą przez Private Endpoints.
**Z Internetu portal NIE ZADZIAŁA** (403/404) — i to jest poprawne zachowanie!

**Przez Bastion (do testów):**
1. Azure Portal → `vm-jumpbox` → Connect → Bastion
2. Login: `azureadmin` / hasło z env
3. Otwórz Edge → `https://ai.azure.com`
4. Zaloguj się i sprawdź czy widzisz projekt + możesz tworzyć agentów

**Przez VPN P2S (dla klienta):**
1. Pobierz profil VPN:
   ```powershell
   az network vnet-gateway vpn-client generate \
     --name vpngw-foundry-test \
     --resource-group rg-foundry-byovnet
   ```
2. Zainstaluj profil VPN na laptopie
3. Połącz się → otwórz `https://ai.azure.com`
4. Skonfiguruj DNS forwarding dla Private DNS Zones → `168.63.129.16`

## Ważne lekcje (lessons learned)

### 1. Rola portalu: Azure AI Developer, NIE Azure AI User
- **Azure AI User** = read-only, nie pozwala budować agentów
- **Azure AI Developer** = pełny dostęp do tworzenia agentów i deploymentów
- Nadajemy na **Account** (dziedziczenie na projekty) lub **Project** (izolacja per-zespół)
- Użytkownik portalu potrzebuje też ról na zasobach: Storage Blob Data Contributor, Search Index Data Contributor, Cosmos DB data plane

### 2. CosmosDB wymaga data plane RBAC
- Gdy `disableLocalAuth: true`, samo "Cosmos DB Operator" (control plane) NIE WYSTARCZY
- Trzeba dodać **Cosmos DB Built-in Data Contributor** przez:
  ```
  az cosmosdb sql role assignment create \
    --role-definition-id 00000000-0000-0000-0000-000000000002 \
    --principal-id <MI-principal-id> \
    --scope <cosmos-account-id>
  ```
- Dotyczy zarówno Project MI jak i Account MI

### 3. Storage connection: AzureStorageAccount, NIE AzureBlob
- Capability Host wymaga kategorii `AzureStorageAccount`
- `AzureBlob` powoduje błąd: "Connection is AzureBlob but not AzureStorageAccount"

### 4. Race condition: Account networkInjections + Project
- ARM PUT na konto z `networkInjections` → konto wraca do stanu "Accepted"
- Projekt (child resource) nie może się stworzyć na koncie w stanie "Accepted"
- **Rozwiązanie**: deploy w 2 fazach lub retry z czekaniem na `Succeeded`

### 5. VPN Gateway AZ SKU wymaga zones na Public IP
- `VpnGw1` jest deprecated — użyj `VpnGw1AZ`
- Public IP musi mieć `zones: ['1', '2', '3']`
- Nie można dodać zones do istniejącego PIP — trzeba go usunąć i stworzyć nowy

### 6. subnetArmId — użyj resourceId(), NIE dynamicznych referencji
- `vnet.properties.subnets[0].id` → odrzucane przez API Foundry
- `resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)` → działa

## Raport

Po uruchomieniu `09-e2e-report.ps1` dostaniesz raport:

```
═══════════════════════════════════════════════════════
  FOUNDRY BYO VNet - E2E TEST REPORT
═══════════════════════════════════════════════════════
✅ PASS  [Network] VNet exists: vnet-foundry-test
✅ PASS  [PE] pe-ai-foundry (account): Status: Approved
✅ PASS  [Foundry] Public access: Disabled
✅ PASS  [Portal] Bastion: Succeeded
✅ PASS  [Portal] VPN Gateway: Succeeded
═══════════════════════════════════════════════════════
  VERDICT: GO
  Total: 21 PASS | 0 FAIL | 1 WARN
═══════════════════════════════════════════════════════
```

## Cleanup

```powershell
# 1. Usuń Capability Host (wymagane przed usunięciem konta)
az rest --method DELETE --url "https://management.azure.com/<project-id>/capabilityHosts/default?api-version=2025-04-01-preview"

# 2. Usuń resource group
az group delete --name rg-foundry-byovnet --yes --no-wait

# 3. Purguj Foundry Account (soft-delete protection)
az cognitiveservices account purge --name <account-name> --resource-group <rg> --location <region>
```

## Bazowy template

Inspirowane oficjalnym template Microsoft:
[foundry-samples/15-private-network-standard-agent-setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup)

## Struktura plików

```
foundry-vnet-test/
├── run-all.ps1                 # Orkiestrator (jedno polecenie)
├── skill.md                    # Definicja skilla
├── bicep/
│   ├── main.bicep              # Foundry + BYO VNet + PE + RBAC + Bastion + VPN
│   ├── main.bicepparam         # Parametry
│   ├── apim.bicep              # APIM Internal VNet (opcjonalnie)
│   └── apim.bicepparam         # Parametry APIM
├── scripts/
│   ├── 00-preflight.ps1        # Pre-flight checks
│   ├── 01-deploy-foundry.ps1   # Deploy Bicep (z retry logic)
│   ├── 02-deploy-apim.ps1      # Deploy APIM
│   ├── 03-import-openapi-mcp.ps1 # Import API do APIM
│   ├── 04-test-network.ps1     # Test VNet/subnety/DNS
│   ├── 05-test-pe.ps1          # Test Private Endpoints
│   ├── 06-test-agent.ps1       # Test Agent Service + izolacja
│   ├── 07-test-apim.ps1        # Test APIM
│   ├── 08-test-identity.ps1    # Test MI/RBAC
│   ├── 09-e2e-report.ps1       # E2E raport GO/NO-GO
│   └── 10-test-portal-access.ps1  # Test Bastion/VPN/Portal
├── config/
│   └── test-config.json        # Konfiguracja
└── README.md                   # Ten plik
```
