# 🏗️ Workshop: Microsoft Foundry dla klientów enterprise
## Wdrożenie AI Foundry z BYO VNet — krok po kroku

---

## 📋 O warsztacie

| | |
|---|---|
| **Czas trwania** | ~3-3.5 godziny |
| **Poziom** | Intermediate |
| **Wymagania** | Azure CLI, subskrypcja Azure, uprawnienia Owner |
| **Rezultat** | Działające środowisko AI Foundry w prywatnej sieci VNet z pełną izolacją |

### Czego się nauczysz

1. Jak wdrożyć Microsoft AI Foundry w prywatnej sieci klienta (BYO VNet)
2. Jak skonfigurować Private Endpoints dla pełnej izolacji sieciowej
3. Jak przetestować, że dane nigdy nie opuszczają sieci prywatnej
4. Jak uzyskać dostęp do portalu ai.azure.com z wnętrza VNet
5. Jak wystawić modele przez API Management w sieci wewnętrznej
6. Jakie role RBAC są wymagane i dlaczego
7. Jak zbudować izolację multi-tenant per-projekt
8. Jak skonfigurować Foundry AI Gateway (Opcja A, APIM v2) lub APIM Standalone Proxy (Opcja B)

### 💰 Szacunkowe koszty warsztatu

| Zasób | Koszt/h (est.) | Uwagi |
|-------|---------------|-------|
| AI Services (gpt-4.1 GlobalStandard) | Pay-per-token | ~$0.01 per 1K tokens |
| Storage Account | ~$0.02/GB/mies. | Minimalny ruch na warsztacie |
| AI Search (Basic) | ~$1/h | Wymagany tier Basic minimum |
| CosmosDB (Serverless) | Pay-per-RU | Minimalny ruch na warsztacie |
| Bastion (Basic) | ~$0.19/h | Dostęp do portalu |
| VPN Gateway (VpnGw1AZ) | ~$0.19/h | Opcjonalny, zdalny dostęp |
| Jumpbox VM (B2s) | ~$0.05/h | Windows Server |
| APIM Standard v2 (Opcja A) | ~$0.38/h | Foundry AI Gateway — wymaga v2 |
| APIM Developer (Opcja B) | ~$0.07/h | Standalone proxy — tańsza opcja |

> 💡 **Szacowany koszt: ~$2-4/h** za całe środowisko. Po warsztacie **natychmiast uruchom Cleanup!**

### 🕐 Timeline

| Czas | Faza | Opis |
|------|------|------|
| 0:00 | Przygotowanie | Konfiguracja, `az login` |
| 0:10 | Faza 1 | Pre-flight checks |
| 0:15 | Faza 2 | Deploy infrastruktury (~30 min, można omawiać teorię) |
| 0:45 | Faza 3-6 | Testy walidacyjne (sieć, PE, agent, RBAC) |
| 1:00 | Faza 7 | **⭐ Test portalu przez Bastion** |
| 1:15 | Faza 7 | Tworzenie agenta, test izolacji |
| 1:30 | **Faza 7b** | **⭐ Multi-tenant izolacja per-projekt** |
| 2:00 | Faza 8 | APIM deploy (opcja, 45 min) |
| 2:45 | **Faza 8b** | **⭐ APIM + AI — wybierz ścieżkę** (20 min) |
| | ↳ Opcja A | Foundry AI Gateway (APIM v2) — natywna integracja |
| | ↳ Opcja B | APIM Standalone Proxy (wszystkie tiery) |
| 3:00 | Faza 9 | Raport GO/NO-GO |
| 3:15 | Cleanup | Usunięcie zasobów |
| 3:30 | Q&A | Pytania i odpowiedzi |

---

## 📖 Teoria: Opcje sieciowe Microsoft Foundry

Zanim zaczniemy budować, zrozummy jakie opcje sieciowe oferuje Microsoft Foundry.

### Dwa modele izolacji sieciowej

Microsoft Foundry oferuje **dwa modele** konfiguracji sieci:

| | **Managed VNet** | **BYO VNet (ten warsztat)** |
|---|---|---|
| **Kto zarządza siecią?** | Microsoft | Klient |
| **Kontrola nad routingiem** | Ograniczona | Pełna |
| **Widoczność PE i NIC** | Niewidoczne dla klienta | Pełna widoczność |
| **Integracja z siecią firmową** | Ograniczona | Pełna (ExpressRoute, VPN, hub-spoke) |
| **Compliance / regulacje** | Ogólne | Enterprise, finanse, zdrowie, gov |
| **Złożoność wdrożenia** | Niska | Wysoka |
| **Rekomendacja** | PoC, dev/test, start-upy | Produkcja, klienci enterprise |

> 📘 **Managed VNet** — Microsoft tworzy i zarządza VNetem za Ciebie. Dwa tryby izolacji:
> - *Allow Internet Outbound* — agent może łączyć się z Internetem
> - *Allow Only Approved Outbound* — ruch tylko do zatwierdzonych serwisów
>
> 📗 **BYO VNet** — Ty tworzysz VNet, subnety, PE, DNS. Pełna kontrola.
> Agent runtime jest "wstrzykiwany" do Twojego subnetu (VNet injection).

> 📎 **Dokumentacja:**
> - [Managed VNet — konfiguracja](https://learn.microsoft.com/en-us/azure/foundry/how-to/managed-virtual-network)
> - [BYO VNet — prywatna sieć dla Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)
> - [Porównanie opcji sieciowych](https://learn.microsoft.com/en-us/azure/ai-services/agents/concepts/networking)

### Kiedy wybrać BYO VNet?

✅ Klient **powinien** wybrać BYO VNet gdy:
- Wymaga integracji z istniejącą siecią firmową (hub-spoke, ExpressRoute)
- Podlega regulacjom (finanse, zdrowie, sektor publiczny)
- Potrzebuje audytu ruchu sieciowego (Azure Firewall, NVA)
- Chce pełnej kontroli nad DNS, NSG, route tables
- Wymaga certyfikacji compliance (ISO 27001, SOC 2, HIPAA)

❌ Managed VNet jest **wystarczający** gdy:
- Szybkie PoC / prototypowanie
- Brak wymagań compliance
- Nie ma istniejącej infrastruktury sieciowej

### 🆕 Warianty BYO VNet — Standard vs Basic

Od czerwca 2025 Microsoft udostępnił **dwa warianty** BYO VNet:

| | **Standard Setup** (ten warsztat) | **Basic Setup** (nowość!) |
|---|---|---|
| **BYO Data Resources** | ✅ Wymagane (CosmosDB, Storage, AI Search) | ❌ Nie wymagane — multi-tenant |
| **Dane** | Zostają w Twojej subskrypcji | Shared Microsoft infra |
| **Kontrola danych** | Pełna | Ograniczona |
| **Złożoność** | Wyższa (więcej zasobów, RBAC, PE) | Niższa |
| **Koszty** | Wyższe (własne DB, Storage) | Niższe |
| **Dla kogo** | Enterprise, compliance, finanse | Dev/test, PoC w sieci prywatnej |
| **Template** | `15-private-network-standard-agent-setup` | `11-private-network-basic-vnet` |

> 💡 **Kiedy wybrać Basic?** Klient chce prywatną sieć (BYO VNet), ale **nie potrzebuje** pełnej kontroli nad danymi.
> Np. Hosted Agent z własnym kodem, który łączy się z API klienta — nie potrzebuje BYO CosmosDB.
>
> ⚠️ **W wariancie Basic** dane agentów (wątki, pliki) są przechowywane w zasobach zarządzanych przez Microsoft.
> Dla regulowanych sektorów (finanse, zdrowie) wybierz **Standard**.

> 📎 **Dokumentacja:**
> - [Basic VNet template](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/11-private-network-basic-vnet)
> - [Agent tools z network isolation](https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link#agent-tools-with-network-isolation)

### 🔍 Deep Dive: Jak działa sieć w Foundry Agent Service

Zanim zagłębimy się w konfigurację, warto zrozumieć **jak agent runtime komunikuje się z Twoimi zasobami**.

> 📎 **Źródło:** [Deep dive into Foundry Agent Service networking](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive)

#### Dwie strefy sieciowe

Architektura Foundry Agent Service dzieli się na **dwie strefy**:

```
┌─────────────────────────────────┐    ┌──────────────────────────────────┐
│  FOUNDRY PLATFORM NETWORK       │    │  TWÓJ VNet (BYO)                 │
│  (zarządza Microsoft)            │    │  (zarządzasz Ty)                 │
│                                  │    │                                  │
│  ┌───────────────────────┐       │    │  ┌────────────────────────────┐  │
│  │ Foundry Endpoint      │       │    │  │ Delegowany Subnet          │  │
│  │ (HTTPS API gateway)   │       │    │  │ (snet-agent)               │  │
│  └───────────┬───────────┘       │    │  │                            │  │
│              │                   │    │  │  Micro-VMs (Hosted Agents) │  │
│  ┌───────────┴───────────┐       │    │  │  Data Proxy (ACA)          │  │
│  │ Micro-VM Host Layer   │◄──────┼────┼──│  (konsumują IP z subnetu)  │  │
│  │ (zarządza Micro-VMs)  │       │    │  └────────────────────────────┘  │
│  └───────────┬───────────┘       │    │                                  │
│              │                   │    │  ┌────────────────────────────┐  │
│  ┌───────────┴───────────┐       │    │  │ PE Subnet                  │  │
│  │ Tools Service         │       │    │  │ (snet-pe)                  │  │
│  │ (tool calls, shared)  │       │    │  │                            │  │
│  └───────────┬───────────┘       │    │  │  PE: Storage               │  │
│              │                   │    │  │  PE: CosmosDB              │  │
│  ┌───────────┴───────────┐       │    │  │  PE: AI Search             │  │
│  │ Data Proxy Host Layer │◄──────┼────┼──│  PE: Key Vault             │  │
│  │ (orkiestracja proxy)  │       │    │  └────────────────────────────┘  │
│  └───────────────────────┘       │    │                                  │
└─────────────────────────────────┘    └──────────────────────────────────┘
```

#### Kluczowe komponenty

| Komponent | Gdzie | Co robi |
|-----------|-------|---------|
| **Foundry Endpoint** | Microsoft | Przyjmuje HTTPS, auth, routing do agenta |
| **Micro-VM Host Layer** | Microsoft | Zarządza Micro-VMs w Twoim VNet (lifecycle, skalowanie) |
| **Micro-VM** | Twój VNet | Lekka VM z **Twoim kontenerem** (ACR) — tylko Hosted Agents |
| **Tools Service** | Microsoft | Wykonuje tool calls — shared dla obu typów agentów |
| **Data Proxy Host Layer** | Microsoft | Zarządza Data Proxy (orkiestracja, routing) |
| **Data Proxy (ACA)** | Twój VNet | Sieciowy pośrednik — most między Foundry a Twoimi zasobami |

#### Data Proxy — kluczowy element

**Data Proxy** to Azure Container App w Twoim delegowanym subnecie, dedykowany **per projekt**:

- Wszystkie tool calls (MCP, OpenAPI, function calls) przechodzą przez Data Proxy
- Łączy się z Twoimi zasobami **wyłącznie** przez Private Endpoints
- Nie ma dostępu do internetu — widzi **tylko** Twój VNet
- Skaluje się automatycznie z ruchem (~1 IP na 10 podów)

#### Dwa typy agentów = dwie ścieżki ruchu

##### Prompt Agent (Microsoft zarządza compute)

```
Klient → Foundry Endpoint → Tools Service → Data Proxy (ACA) → PE → Twoje zasoby
                             (w Microsoft)    (w Twoim VNet)
```

- **Brak Micro-VM** — compute zarządzany przez Microsoft
- Ty definiujesz zachowanie przez prompt/konfigurację
- IP zużywane tylko przez Data Proxy

##### Hosted Agent (Twój kontener z ACR)

```
Klient → Foundry Endpoint → Micro-VM Host Layer → Micro-VM (Twój VNet)
                                                       │
                                          Twój kod chce tool call
                                                       │
                              Tools Service ← ─ ─ ─ ─ ┘
                                    │
                              Data Proxy (ACA) → PE → Twoje zasoby
```

- **Micro-VM** w Twoim VNet — uruchamia **Twój kontener** z ACR
- Host Layer orkiestruje: wysyła `/invoke`, odbiera tool call requests
- Tool calls **zawsze** przechodzą przez Data Proxy (nawet z Micro-VM)
- Micro-VM ma własną kartę sieciową (zużywa IP)

#### Sizing subnetu delegowanego

| Subnet | IP usable | Sesji jednocz. | Rekomendacja |
|--------|-----------|---------------|-------------|
| **/27** | ~27 | ~17 | ⚠️ Dev/test — ryzykowne |
| **/26** | ~59 | ~50 (max) | ✅ Minimum produkcyjne |
| **/24** | ~251 | 50 (limit) | ✅ **Rekomendowane** — zapas na upgrade'y |

> ⚠️ **Utrzymuj max 80% wykorzystania** — platformowe upgrade'y uruchamiają stare i nowe repliki równolegle.
>
> ⚠️ **Portal NIE pokazuje zużycia IP** w delegowanym subnecie. Monitoruj: Data Proxy 5xx = brak IP.

#### Pojemność projektów vs ruch

| Ruch | Projektów | Dlaczego |
|------|----------|---------|
| Niski (1 replika/projekt) | ~250 | Data Proxy na minimum |
| Wysoki (10 replik/projekt) | ~25 | Każdy projekt skaluje, zjada IP |

#### Bezpieczeństwo sieci

- ✅ Micro-VMs i Data Proxy widzą **TYLKO** Twój VNet
- ✅ Platform NIC jest **ukryty** — workload go nie widzi
- ✅ Egress **TYLKO** przez Private Endpoints
- ✅ Izolacja **per projekt** — każdy projekt ma własny Data Proxy
- ✅ Żaden ruch nie wychodzi do publicznego internetu

### 🆕 Ograniczenia Network Isolation

#### Publikowanie agentów do Microsoft 365 / Teams

> ⚠️ Gdy **Network Isolation jest włączona**, publikowanie agentów do Microsoft 365 Copilot lub Teams
> wymaga **dodatkowej konfiguracji**. Nie działa "out of the box".

> 📎 [Publish a virtual network agent to Microsoft 365 and Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/agent-applications-vnet)

#### Fabric IQ przez prywatną sieć

> 🆕 Od czerwca 2025 tool call z Foundry do **Fabric Data Agent** działa przez prywatną sieć.
> Wymaga skopiowania nowego private endpoint z portalu Fabric.

> 📎 [Fabric IQ z VNet support](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/fabric-iq?tabs=azd&pivots=python#virtual-network-support)

### Wymagania sieciowe BYO VNet

#### Wspierane zakresy adresów IP

| Klasa | Zakres | Status |
|-------|--------|--------|
| **Class A** | `10.0.0.0/8` | ✅ GA (wybrane regiony) |
| **Class B** | `172.16.0.0/12` | ✅ GA (wszystkie regiony) |
| **Class C** | `192.168.0.0/16` | ✅ GA (wszystkie regiony) |

> ⚠️ **Zarezerwowane zakresy — NIE UŻYWAJ:**
> - `169.254.0.0/16` — Link-local (Azure internal)
> - `172.30.0.0/16` — Azure internal
> - `172.31.0.0/16` — Azure internal
> - `100.64.0.0/10` — Shared address space
> - `168.63.129.16/32` — Azure DNS / wireserver

#### Wymagania subnetów

| Subnet | Min. rozmiar | Delegacja | Uwagi |
|--------|-------------|-----------|-------|
| **Agent** (snet-agent) | /26 (min), /24 (rekomendowany) | `Microsoft.App/environments` | **Wyłączny** — żadne inne zasoby! |
| **PE** (snet-pe) | /27 (min), /24 (rekomendowany) | **Brak** (żadna delegacja!) | Private Endpoints |
| **AzureBastionSubnet** | /26 | - | Nazwa MUSI być dokładnie `AzureBastionSubnet` |
| **GatewaySubnet** | /27 | - | Nazwa MUSI być dokładnie `GatewaySubnet` |
| **snet-apim** | /27 | - | Opcjonalnie, dla API Management |

> ⚠️ **Krytyczne:**
> - Subnet agentów MUSI mieć delegację do `Microsoft.App/environments`
> - Subnet PE **NIE MOŻE** mieć żadnej delegacji
> - **Wszystkie zasoby MUSZĄ być w tym samym regionie** — Foundry nie wspiera cross-region

#### Wymagane Private DNS Zones

Do poprawnego rozwiązywania nazw wewnątrz VNet potrzeba **6 stref DNS**:

| Strefa DNS | Dla jakiego zasobu |
|------------|-------------------|
| `privatelink.cognitiveservices.azure.com` | AI Services (control plane) |
| `privatelink.openai.azure.com` | OpenAI endpoints |
| `privatelink.services.ai.azure.com` | Agent Service endpoints |
| `privatelink.blob.core.windows.net` | Storage Account |
| `privatelink.documents.azure.com` | CosmosDB |
| `privatelink.search.windows.net` | AI Search |

> 📎 Każda strefa musi być **zlinkowana z VNetem** aby DNS działał.

#### Model RBAC — kto potrzebuje jakich ról?

Microsoft Foundry używa trzech typów tożsamości, każdy wymaga innych ról:

##### 1. Managed Identity konta (Account MI)

Tożsamość systemowa konta AI Services — używana przez platformę do zarządzania zasobami.

| Rola | Scope | Cel |
|------|-------|-----|
| **Storage Blob Data Owner** | Storage Account | Zarządzanie plikami agentów |
| **Storage Queue Data Contributor** | Storage Account | Kolejki komunikatów |
| **Search Index Data Contributor** | AI Search | Indeksowanie danych |

##### 2. Managed Identity projektu (Project MI)

Tożsamość systemowa projektu — używana przez Agent Runtime do operacji data plane.

| Rola | Scope | Cel |
|------|-------|-----|
| **Storage Blob Data Owner** | Storage Account | Pliki agentów (blob) |
| **Storage Queue Data Contributor** | Storage Account | Kolejki komunikatów |
| **Search Index Data Contributor** | AI Search | Vector store (RAG) |
| **Search Service Contributor** | AI Search | Zarządzanie indeksami |
| **Cosmos DB Operator** | CosmosDB | Control plane |
| **Cosmos DB Built-in Data Contributor** | CosmosDB (data plane!) | Odczyt/zapis wątków |

> ⚠️ **Pułapka: CosmosDB data plane RBAC**
>
> Gdy `disableLocalAuth: true` (co jest wymagane dla bezpieczeństwa), samo nadanie "Cosmos DB Operator" **NIE WYSTARCZY**.
> Trzeba dodać **Cosmos DB Built-in Data Contributor** przez osobne API:
> ```
> az cosmosdb sql role assignment create \
>   --role-definition-id 00000000-0000-0000-0000-000000000002 \
>   --principal-id <MI-principal-id> \
>   --scope <cosmos-account-id>
> ```
> Jest to częsty błąd — w portalu widać "Request blocked by Auth cosmos".

##### 3. Użytkownicy portalu (human users)

> 🔬 **PRZETESTOWANE! Konfiguracja zgodna z [oficjalną dokumentacją Microsoft — Full access isolation](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#access-isolation-examples):**

> ⚠️ **Role zostały przemianowane** (czerwiec 2025): Azure AI User → **Foundry User**, Azure AI Owner → **Foundry Owner**,
> Azure AI Account Owner → **Foundry Account Owner**, Azure AI Project Manager → **Foundry Project Manager**.
> ID ról się nie zmieniły. W portalu mogą nadal pojawiać się stare nazwy.

##### Role Foundry — porównanie

| Rola | Tworzenie agentów | Publikowanie agentów | Tworzenie projektów | Zarządzanie modelami | Przypisywanie ról |
|------|:---:|:---:|:---:|:---:|:---:|
| **Foundry User** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Foundry Project Manager** | ✅ | ✅ | ❌ | ❌ | ✅ ¹ |
| **Foundry Account Owner** | ❌ | ❌ | ✅ | ✅ | ✅ ² |
| **Foundry Owner** | ✅ | ✅ | ✅ | ✅ | ✅ ² |

¹ Tylko rola Foundry User  
² Foundry User, ACR, monitoring

> ⚠️ **NIE używaj** ról `Cognitive Services *` — nie są przeznaczone do Foundry.
> **NIE używaj** `Azure AI Developer` — dotyczy Azure ML, nie Foundry.

##### ID ról (do automatyzacji — nazwy mogą się jeszcze zmieniać)

| Rola | GUID |
|------|------|
| Foundry User | `53ca6127-db72-4b80-b1b0-d745d6d5456d` |
| Foundry Owner | `c883944f-8b7b-4483-af10-35834be79c4a` |
| Foundry Account Owner | `e47c6f54-e4a2-4754-9501-8e0985b135e1` |
| Foundry Project Manager | `eadc314b-1a2d-4efa-be10-5d325db5065e` |

##### Rekomendowane mapowanie per persona

| Persona | Rola | Scope | Cel |
|---------|------|-------|-----|
| **IT Admin** | Owner | Subskrypcja | Pełne zarządzanie |
| **Platform / Manager** | Foundry Account Owner | Foundry Account | Tworzenie projektów, deploy modeli |
| **Team Lead** | Foundry Project Manager | Foundry Account | Tworzenie projektów, publikowanie agentów |
| **Developer** | Foundry User + Foundry Model Reader (custom) | Projekt + Account | Budowanie agentów, widok modeli |

Dla użytkowników portalu ai.azure.com potrzebujesz **dwóch ról**:

| Rola | Scope | Cel | Wymagana? |
|------|-------|-----|-----------|
| **Foundry User** (dawniej Azure AI User) | **Project** | Data plane — tworzenie agentów, praca z modelem | ✅ TAK |
| **Foundry Model Reader** (custom) | **Account** (Foundry resource) | Control plane — widoczność modeli, bez widoku innych projektów | ✅ TAK |

> 📎 **Źródło:** Sekcja [Sample enterprise RBAC mappings for projects](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#sample-enterprise-rbac-mappings-for-projects):
> *"Team members or developers — Foundry User on Foundry project scope and Reader on the Foundry resource scope"*
>
> W naszym warsztacie używamy **Foundry Model Reader** zamiast Reader — daje widoczność modeli **bez** widoku nazw innych projektów.

**NIE potrzeba** (portal używa MI projektu, nie tożsamości usera):

| Rola | Potrzebna? | Dlaczego NIE |
|------|-----------|--------------|
| Storage Blob Data Contributor | ❌ | Portal → MI projektu → Storage |
| Search Index Data Contributor | ❌ | Portal → MI projektu → Search |
| Cosmos DB Operator | ❌ | Portal → MI projektu → CosmosDB |
| Cognitive Services OpenAI User | ❌ | Dokumentacja nie wymienia tej roli |
| Azure AI Developer | ❌ | Azure AI User wystarczy do "build and develop" |

##### Izolacja per-projekt — jak to działa

Konfiguracja zgodna z oficjalnym wzorcem **"Full access isolation"**:

```
# 1. Azure AI User na PROJEKCIE — data plane access
az role assignment create --role "Azure AI User" \
  --assignee "userA@firma.com" \
  --scope ".../accounts/{account}/projects/{projekt-A}"

# 2. Reader na KONCIE — control plane read (widoczność modeli)
az role assignment create --role "Reader" \
  --assignee "userA@firma.com" \
  --scope ".../accounts/{account}"
```

> 🔬 **Przetestowane wyniki:**
>
> ✅ UserA **widzi nazwy** wszystkich projektów (Reader na Account = ARM list/read)
> ✅ UserA **może tworzyć agentów** i rozmawiać z nimi w projekt-A
> ✅ UserA **widzi modele** w dropdown (Reader daje control plane read)
> ✅ UserA **NIE MA dostępu** do zakładki Agents w innych projektach (data plane izolacja!)
> ✅ Bez dodatkowych ról na CosmosDB/Storage/Search — wszystko działa
>
> ⚠️ **UWAGA:** NIE nadawaj `Azure AI User` na scope **Account** — to daje dostęp do WSZYSTKICH projektów!
> Portal wyświetla mylący komunikat sugerujący Account scope — **ignoruj go**, Project scope wystarczy.
>
> ⚠️ **Widoczność nazw projektów:** Oficjalny wzorzec MS z Reader na Account pozwala widzieć **nazwy** projektów.
> Rozwiązanie: użyj **Custom Role "Foundry Model Reader"** zamiast Reader → patrz **Faza 7b, Krok 7b.9**.

##### Przykład: 2 zespoły — pełna izolacja z Custom Role (⭐ rekomendowane)

```
Foundry Account: ai-foundry-enterprise
│
├── projekt-zespol-A:
│   ├── UserA1 → Azure AI User (scope: projekt-zespol-A)
│   └── UserA2 → Azure AI User (scope: projekt-zespol-A)
│
└── projekt-zespol-B:
    ├── UserB1 → Azure AI User (scope: projekt-zespol-B)
    └── UserB2 → Azure AI User (scope: projekt-zespol-B)

Wszyscy: "Foundry Model Reader" (custom, scope: Account)
         → accounts/read + deployments/read + models/read
         → BEZ accounts/projects/read!

Wynik:
• Zespół A NIE WIDZI nazw projektów zespołu B ✅
• Zespół A widzi modele w dropdown ✅
• Agent Service, Agents, pliki — izolacja per-projekt ✅
• Dane w CosmosDB/Storage/Search oddzielone przez MI projektu ✅
```

> 📘 **Poziomy izolacji — porównanie (przetestowane):**
>
> | Metoda | Widzi nazwy projektów? | Widzi modele? | Data plane izolacja? | Kiedy stosować |
> |--------|----------------------|--------------|---------------------|---------------|
> | ⭐ **Custom Role + AI User** | ✅ **Nie widzi!** | ✅ Tak | ✅ Pełna | Najlepsza opcja w jednym Account |
> | **Reader + AI User** | ⚠️ Tak (nazwy widoczne) | ✅ Tak | ✅ Pełna | Oficjalny wzorzec MS |
> | **Tylko AI User** (bez Reader) | ❌ Nie widzi | ❌ Nie widzi | ✅ Pełna | Nie zalecane — nie można tworzyć agentów |
> | **AI User na Account** | ✅ Widzi wszystko | ✅ Tak | ❌ BRAK izolacji | NIE UŻYWAJ w multi-tenant! |
> | **Osobne Foundry Accounts** | ✅ Nie widzi nic | ✅ Tak | ✅ Pełna | Osobne zarządzanie, regulacje |
>
> Szczegóły Custom Role → patrz **Faza 7b, Krok 7b.9**

##### Autentykacja — Entra ID vs API keys

| Funkcja | API key | Entra ID |
|---------|---------|----------|
| Agent Service | ❌ NIE działa | ✅ Wymagany |
| Evaluations | ❌ | ✅ Wymagany |
| Model inference | ✅ | ✅ |
| Per-user auditing | ❌ | ✅ |
| Managed Identity | ❌ | ✅ |
| Least privilege RBAC | ❌ (all-or-nothing) | ✅ |

> ⚠️ **Agent Service wymaga Entra ID** — API keys nie działają z agentami!
> W BYO VNet z `disableLocalAuth: true` API keys są w ogóle wyłączone.
>
> Token scope: `https://ai.azure.com/.default`

> 📎 [Autentykacja i autoryzacja w Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/authentication-authorization-foundry)
> 📎 [RBAC dla Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)
> 📎 [Built-in roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/ai-machine-learning)

### Architektura docelowa warsztatu

```
┌──────────────────────────────────────────────────────────────────┐
│  Twoja sieć VNet (192.168.0.0/16)                                │
│                                                                  │
│  ┌─────────────┐    ┌─────────────────────────────────────────┐  │
│  │ snet-agent   │    │ snet-pe (Private Endpoints)             │  │
│  │ /24          │    │ /24                                     │  │
│  │              │    │ PE → AI Foundry (CognitiveServices)     │  │
│  │ Delegacja:   │    │ PE → Storage Account (blob)             │  │
│  │ Microsoft.   │    │ PE → CosmosDB (documents)               │  │
│  │ App/envs     │    │ PE → AI Search                          │  │
│  │              │    │                                         │  │
│  │ Agent        │    │ Cały ruch AI zostaje w Twojej sieci     │  │
│  │ Runtime      │    │                                         │  │
│  └─────────────┘    └─────────────────────────────────────────┘  │
│                                                                  │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐        │
│  │ Bastion     │    │ Jumpbox VM   │    │ VPN Gateway   │        │
│  │ /26         │    │ Windows      │    │ P2S           │        │
│  │ Bezpieczny  │    │ Dostęp do    │    │ Zdalny dostęp │        │
│  │ RDP/SSH     │    │ ai.azure.com │    │ dla zespołu   │        │
│  └─────────────┘    └──────────────┘    └───────────────┘        │
│                                                                  │
│  Private DNS Zones (6 stref) → rozwiązują nazwy na prywatne IP  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Przygotowanie (10 min)

### Krok 1: Sklonuj repozytorium

```powershell
git clone https://github.com/AzureClub/foundry-enterprise-workshop.git
cd foundry-enterprise-workshop
```

### Krok 2: Skonfiguruj środowisko (.env)

```powershell
# Skopiuj szablon
cp .env.example .env
```

Otwórz `.env` i uzupełnij wartości:

```env
# Azure Subscription
AZURE_SUBSCRIPTION_ID=twoja-subskrypcja-id
AZURE_RESOURCE_GROUP=rg-foundry-byovnet
AZURE_LOCATION=swedencentral

# VM Jumpbox
VM_ADMIN_PASSWORD=TwojeHaslo123!

# Lab User (Faza 7b)
LAB_USER_PASSWORD=HasloLabUser123!
LAB_USER_UPN=userlab01@twoja-domena.onmicrosoft.com
```

> ⚠️ **Plik `.env` jest w `.gitignore` — nigdy nie zostanie wypchnięty do repozytorium!**
> Hasła i subscription ID są bezpieczne.

Załaduj konfigurację:

```powershell
. .\scripts\load-env.ps1
```

> 💡 **Wspierane regiony**: Sweden Central, East US, East US 2, West Europe, France Central, Australia East

### Krok 3: Zaloguj się do Azure

```powershell
az login
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
az account show --query "{name:name, id:id}" -o table
```

> ⚠️ Hasło musi spełniać wymagania Azure: min. 12 znaków, wielkie i małe litery, cyfra, znak specjalny.

---

## ✅ Faza 1: Pre-flight (2 min)

Sprawdzamy czy Twoje środowisko jest gotowe do wdrożenia.

```powershell
.\scripts\00-preflight.ps1
```

### Co sprawdza pre-flight?

> 📘 **Dlaczego pre-flight?** Azure wymaga rejestracji "providerów zasobów" w subskrypcji zanim można tworzyć zasoby.
> Np. `Microsoft.CognitiveServices` musi być zarejestrowany aby stworzyć konto AI Foundry.
> Pre-flight sprawdza 10 wymaganych providerów i powie które trzeba zarejestrować.

| Test | Opis |
|------|------|
| Azure CLI | Czy jest zainstalowane i zalogowane |
| Subskrypcja | Czy zgadza się z konfiguracją |
| Providery | Czy 10 wymaganych providerów jest zarejestrowanych |
| Region | Czy Foundry jest dostępny w wybranym regionie |
| Uprawnienia | Czy masz prawa do tworzenia zasobów |
| Bicep | Czy szablon się kompiluje |

### Oczekiwany wynik

```
✅ 15/15 Pre-flight checks PASSED
```

> ❌ Jeśli coś nie przejdzie — skrypt powie co naprawić (np. `az provider register --namespace Microsoft.CognitiveServices`)

---

## 🚀 Faza 2: Wdrożenie infrastruktury (25-35 min)

Teraz deployujemy wszystkie zasoby Azure jednym poleceniem.

```powershell
.\scripts\01-deploy-foundry.ps1
```

### Co się tworzy?

> 📘 **Jak to działa pod spodem?**
> Deployment używa **Bicep** (deklaratywny język IaC od Microsoft). ARM (Azure Resource Manager)
> analizuje szablon, buduje graf zależności i tworzy zasoby równolegle tam gdzie to możliwe.
> Jedyny zasób który wymaga sekwencyjnego tworzenia to: Account → Model → Project → Connections → RBAC → Capability Host.
>
> 📘 **Co to jest networkInjections?**
> Parametr `networkInjections` na koncie AI Services mówi Azure: "wstrzyknij agent runtime do MOJEGO subnetu".
> To jest kluczowa różnica między BYO VNet a Managed VNet — ruch agenta nigdy nie opuszcza Twojej sieci.

| Zasób | Cel | Czas |
|-------|-----|------|
| VNet + 5 subnetów | Sieć prywatna z izolacją | ~1 min |
| AI Services Account | Konto Foundry z networkInjections | ~3 min |
| Storage Account | Pliki agentów (blob) | ~1 min |
| AI Search | Vector store dla agentów | ~2 min |
| CosmosDB | Thread storage (konwersacje) | ~3 min |
| 4× Private Endpoints | Izolacja sieciowa | ~2 min |
| 6× Private DNS Zones | Rozwiązywanie nazw wewnątrz VNet | ~1 min |
| Model gpt-4.1 | Deployment modelu GlobalStandard | ~1 min |
| Project + Connections | Projekt z 3 połączeniami | ~2 min |
| Capability Host | Agent runtime | ~2 min |
| 11× RBAC Assignments | Tożsamości zarządzane (control + data plane) | ~1 min |
| Bastion + Jumpbox VM | Dostęp do portalu | ~5 min |
| VPN Gateway P2S | Zdalny dostęp | ~25 min |

> ⏱️ **Łączny czas: ~25-35 min** (VPN Gateway jest najdłuższy)

> 💡 Skrypt ma wbudowany retry logic — jeśli konto AI potrzebuje więcej czasu na provisioning (networkInjections), automatycznie poczeka na stan `Succeeded` i ponowi próbę.

> 📘 **Dlaczego Storage, CosmosDB i AI Search?**
> Agent Service potrzebuje tych trzech usług:
> - **Storage Account** — przechowuje pliki uploadowane do agenta (blob) i kolejki komunikatów
> - **CosmosDB** — przechowuje wątki konwersacji (thread storage) i stany agentów
> - **AI Search** — vector store dla RAG (Retrieval-Augmented Generation), file search
>
> W trybie BYO VNet wszystkie trzy są w Twojej sieci za Private Endpoints.

### Oczekiwany wynik

```
✅ Deployment SUCCEEDED
```

---

## 🔍 Faza 3: Walidacja sieci (3 min)

Sprawdzamy czy sieć jest poprawnie skonfigurowana.

> 📎 **Dokumentacja:** [BYO VNet — wymagania sieciowe](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)

```powershell
.\scripts\04-test-network.ps1
```

### Na co patrzymy?

- ✅ VNet z prawidłową przestrzenią adresową
- ✅ Subnet agentów z delegacją `Microsoft.App/environments`
- ✅ Subnet PE **bez** delegacji
- ✅ AzureBastionSubnet z prawidłowym CIDR
- ✅ GatewaySubnet z prawidłowym CIDR
- ✅ 6 Private DNS Zones zlinkowanych z VNetem
- ✅ Wszystkie zasoby w tym samym regionie

### Oczekiwany wynik

```
--- Summary: 14 PASS, 0 FAIL, 0 WARN ---
```

> ℹ️ 1 WARN o DNS zone `azure-api.net` jest OK — to zona APIM, którą dodamy później.

---

## 🔒 Faza 4: Walidacja Private Endpoints (3 min)

Sprawdzamy czy wszystkie Private Endpoints działają i public access jest wyłączony.

> 📘 **Co to jest Private Endpoint?**
> Private Endpoint tworzy prywatny interfejs sieciowy (NIC) w Twoim VNecie, który "mapuje" publiczny
> endpoint usługi Azure na prywatny adres IP. Np. zamiast łączyć się z `mystorageaccount.blob.core.windows.net`
> przez publiczny Internet (np. 52.239.x.x), ruch idzie na prywatny IP (np. 192.168.1.4) wewnątrz Twojej sieci.
>
> W połączeniu z **Private DNS Zones**, aplikacje nawet nie wiedzą że używają prywatnego adresu —
> DNS automatycznie rozwiązuje nazwę na prywatny IP.

```powershell
.\scripts\05-test-pe.ps1
```

### Na co patrzymy?

- ✅ 4 Private Endpoints ze statusem **Approved**
- ✅ Każdy PE ma prywatny adres IP z zakresu snet-pe
- ✅ **Public access: Disabled** na wszystkich zasobach
- ✅ **SharedKey disabled** na Storage (tylko AAD)
- ✅ **Local auth disabled** na CosmosDB (tylko AAD)
- ✅ DNS A-records rozwiązują się na prywatne IP

### Oczekiwany wynik

```
--- Summary: 22 PASS, 0 FAIL, 0 WARN ---
```

> 🔐 To jest kluczowy test — potwierdza, że żaden ruch nie wychodzi poza Twoją sieć.

---

## 🤖 Faza 5: Walidacja Agent Service (3 min)

Sprawdzamy konfigurację agentów i izolację data plane.

> 📎 **Dokumentacja:** [Agent Service — environment setup](https://learn.microsoft.com/en-us/azure/ai-services/agents/environment-setup) |
> [Network injection concepts](https://learn.microsoft.com/en-us/azure/ai-services/agents/concepts/networking)

```powershell
.\scripts\06-test-agent.ps1
```

### Na co patrzymy?

- ✅ Network Injection (BYO VNet) skonfigurowany
- ✅ Public network access: Disabled
- ✅ Capability Host: Agents z 3 połączeniami
- ✅ Model gpt-4.1 deployed i gotowy
- ✅ Connections: Storage (AzureStorageAccount), Search, CosmosDB
- ✅ **OpenAI API: 403 z Internetu** (izolacja działa!)
- ✅ **Agent API: 404 z Internetu** (izolacja działa!)

### Oczekiwany wynik

```
--- Summary: 9 PASS, 0 FAIL, 1 WARN ---
```

> 🎯 Najważniejszy test: endpointy zwracają **403/404 z Internetu** — dane są bezpieczne.

---

## 👤 Faza 6: Walidacja tożsamości (3 min)

Sprawdzamy Managed Identity i role RBAC.

> 📎 **Dokumentacja:** [RBAC dla AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/rbac-azure-ai-foundry?pivots=hub-project) |
> [CosmosDB data plane RBAC](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac)

```powershell
.\scripts\08-test-identity.ps1
```

### Na co patrzymy?

- ✅ Account MI (System-assigned) z rolami na Storage, Search
- ✅ Project MI (System-assigned) z rolami na Storage, Search, CosmosDB
- ✅ CosmosDB: AAD only (local auth disabled)
- ✅ Storage: SharedKey disabled (AAD only)

### Oczekiwany wynik

```
--- Summary: 13 PASS, 0 FAIL, 1 WARN ---
```

---

## 🖥️ Faza 7: Test portalu przez Bastion (10 min)

To jest kluczowy moment warsztatu — sprawdzamy dostęp do portalu AI Foundry z wnętrza sieci.

> 📘 **Jak działa portal ai.azure.com z BYO VNet?**
>
> Portal AI Foundry to aplikacja webowa hostowana przez Microsoft na publicznym Internecie.
> **UI się załaduje** — ale wszystkie **API calls** (tworzenie agentów, odczyt zasobów, chat)
> idą bezpośrednio do Twoich endpointów Azure, które są za Private Endpoints.
>
> Dlatego:
> - **Z Internetu**: UI się ładuje, ale API zwraca 403/404 → nie da się pracować
> - **Z wnętrza VNet**: UI + API działają → pełny dostęp do agentów
>
> 📘 **Opcje dostępu do portalu:**
>
> | Metoda | Opis | Kiedy używać |
> |--------|------|-------------|
> | **Azure Bastion** | RDP/SSH przez przeglądarkę, bez publicznego IP | Testy, szybki dostęp, workshop |
> | **VPN Point-to-Site** | VPN klient na laptopie, Azure AD auth | Zespół deweloperski, codzienne użycie |
> | **ExpressRoute** | Dedykowane łącze do Azure | Produkcja, duże firmy |
> | **Azure Virtual Desktop** | Wirtualne desktopy w chmurze | Wielu użytkowników, thin clients |
>
> 📎 [Portal access z prywatnej sieci](https://learn.microsoft.com/en-us/azure/foundry/how-to/managed-virtual-network#access-the-portal)

### Krok 7.1: Najpierw przetestuj z Internetu (powinno NIE działać)

Otwórz przeglądarkę na swoim komputerze:
1. Wejdź na **https://ai.azure.com**
2. Zaloguj się
3. Wybierz projekt → **Agents**

**Oczekiwany wynik:** ❌ Błąd dostępu / "nie można załadować"

> ✅ To potwierdza, że portal jest niedostępny z Internetu!

### Krok 7.2: Połącz się przez Bastion

1. Otwórz **Azure Portal** → Resource Group `rg-foundry-byovnet`
2. Kliknij na **vm-jumpbox** → **Connect** → **Connect via Bastion**
3. Zaloguj się:
   - Username: `azureadmin`
   - Password: hasło które ustawiłeś w `$env:VM_ADMIN_PASSWORD`
4. Otworzy się sesja RDP w przeglądarce

### Krok 7.2b: Przygotuj Jumpbox do testów

> 🔧 **Ważne:** Od tego momentu część testów (Faza 7, 8b, 13-14) musi być uruchamiana
> **z wnętrza VNet** — czyli z Jumpbox VM. Przygotuj środowisko:

Na Jumpbox VM otwórz **PowerShell** i wykonaj:

```powershell
# 1. Zaloguj się do Azure CLI
az login

# 2. Sklonuj repozytorium warsztatu
git clone https://github.com/AzureClub/foundry-enterprise-workshop.git
cd foundry-enterprise-workshop

# 3. Skopiuj plik .env z głównego komputera (lub utwórz nowy)
#    Możesz przekopiować przez Bastion clipboard lub wpisać ręcznie:
Copy-Item .env.example .env
notepad .env
#    Uzupełnij wartości: AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, AZURE_LOCATION, VM_ADMIN_PASSWORD

# 4. Załaduj zmienne środowiskowe
. .\scripts\load-env.ps1
```

> 💡 **Tip:** Bastion obsługuje kopiowanie tekstu między komputerem a VM.
> Użyj ikony schowka w panelu Bastion aby przeklejać wartości z `.env`.
>
> 📋 **Które skrypty uruchamiać z Jumpbox?**
>
> | Skrypt | Z komputera | Z Jumpbox (VNet) |
> |--------|:-----------:|:----------------:|
> | `01-deploy-foundry.ps1` | ✅ | ✅ |
> | `02-deploy-apim.ps1` | ✅ | ✅ |
> | `03-import-openapi-mcp.ps1` | ✅ | ✅ |
> | `04-08` testy walidacyjne | ✅ | ✅ |
> | `09-e2e-report.ps1` | ✅ | ✅ |
> | `10-test-portal-access.ps1` | ⚠️ częściowo | ✅ |
> | `11-configure-byom.ps1` | ✅ | ✅ |
> | `12-test-byom.ps1` | ✅ | ✅ |
> | `13-test-byom-e2e.ps1` | ❌ | ✅ **wymagany** |
> | `14-test-ai-gateway.ps1` | ❌ | ✅ **wymagany** |

### Krok 7.3: Otwórz portal AI Foundry na VM

Na Jumpbox VM:
1. Otwórz **Microsoft Edge**
2. Wejdź na **https://ai.azure.com**
3. Zaloguj się swoim kontem Azure
4. Wybierz projekt `project-agent-test`
5. Przejdź do **Agents**

**Oczekiwany wynik:** ✅ Portal ładuje się, widzisz projekt, możesz tworzyć agentów!

### Krok 7.4: Stwórz testowego agenta

1. Kliknij **+ New Agent**
2. Wybierz model: `gpt-4.1`
3. Nazwa: `test-agent-workshop`
4. Instructions: `Jesteś pomocnym asystentem. Odpowiadaj po polsku.`
5. Kliknij **Create**
6. W panelu czatu napisz: `Cześć, czy działasz?`

**Oczekiwany wynik:** ✅ Agent odpowiada — cały ruch przechodzi przez Private Endpoints!

> 🎉 **Gratulacje!** Masz działającego agenta AI w pełni izolowanym środowisku sieciowym.

### Krok 7.5: Opcjonalnie — test z CLI na VM

Na Jumpbox VM otwórz PowerShell:

```powershell
# Zaloguj się
az login

# Pobierz token
$token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv

# Test OpenAI (powinien zwrócić odpowiedź)
curl -X POST "https://ai-foundry-byovnet-UNIQUEID.cognitiveservices.azure.com/openai/deployments/gpt-4.1/chat/completions?api-version=2024-12-01-preview" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d '{"messages":[{"role":"user","content":"Powiedz cześć"}],"max_tokens":50}'

# Test Agent API (powinien zwrócić listę agentów)
curl "https://ai-foundry-byovnet-UNIQUEID.services.ai.azure.com/agents?api-version=2025-05-01-preview" `
  -H "Authorization: Bearer $token"
```

**Oczekiwany wynik:** ✅ Odpowiedzi zwracane poprawnie — z wnętrza VNet API działa!

---

## 🔐 Faza 7b: Multi-tenant izolacja per-projekt (30 min)

W tej fazie testujemy izolację między zespołami w jednym Foundry Account. Stworzymy testowego użytkownika, osobny projekt i sprawdzimy, że użytkownik ma dostęp **tylko** do swojego projektu.

> 📘 **Dlaczego to ważne?**
>
> W środowisku enterprise wielu zespołów korzysta z jednego Foundry Account. Każdy zespół powinien
> pracować w swoim projekcie, widzieć swoje dane i **nie mieć dostępu** do danych innych zespołów.
> Microsoft oferuje trzy poziomy izolacji — przetestujemy najbardziej zalecaną opcję: **Full access isolation**.
>
> 📎 [RBAC dla Foundry — Access Isolation Examples](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#access-isolation-examples)
> 📎 [RBAC dla Foundry — Sample enterprise RBAC mappings](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#sample-enterprise-rbac-mappings-for-projects)

### Krok 7b.1: Stwórz testowego użytkownika

> ⚠️ Wymaga roli **User Administrator** w Entra ID (lub Global Admin).

```powershell
# Pobierz domenę tenanta
$domain = az ad signed-in-user show --query userPrincipalName -o tsv | ForEach-Object { $_.Split('@')[1] }

# Stwórz testowego użytkownika
az ad user create \
  --display-name "Lab User 01" \
  --user-principal-name "userlab01@$domain" \
  --password "WybierzSilneHaslo123!" \
  --force-change-password-next-sign-in false
```

Zapisz UPN i ID użytkownika:
```powershell
$labUser = az ad user show --id "userlab01@$domain" --query id -o tsv
Write-Host "User ID: $labUser"
```

### Krok 7b.2: Stwórz osobny projekt dla testowego użytkownika

```powershell
$sub = (Get-Content config/test-config.json | ConvertFrom-Json).subscription_id
$rg = (Get-Content config/test-config.json | ConvertFrom-Json).resource_group
$account = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv
$projectName = "project-lab01"

$token = az account get-access-token --query accessToken -o tsv

$body = @{
    location = "swedencentral"
    kind = "AIProject"
    sku = @{ name = "S0" }
    identity = @{ type = "SystemAssigned" }
    properties = @{
        friendlyName = "Lab 01 Project"
        description = "Isolation test project for lab user"
    }
} | ConvertTo-Json -Depth 5

$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/${projectName}?api-version=2025-04-01-preview"

Invoke-RestMethod -Uri $uri -Method PUT -Headers @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
} -Body $body
```

> ⏱️ Projekt tworzy się w ~30 sekund.

### Krok 7b.3: Nadaj role RBAC — konfiguracja "Full access isolation"

Zgodnie z oficjalną dokumentacją Microsoft — dwie role:

```powershell
# 1. Azure AI User na PROJEKCIE (data plane access)
$projectScope = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/$projectName"
az role assignment create --role "Azure AI User" --assignee $labUser --scope $projectScope

# 2. Reader na KONCIE (control plane read — widoczność modeli)
$accountScope = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account"
az role assignment create --role "Reader" --assignee $labUser --scope $accountScope
```

> 📘 **Dlaczego Reader na Account?**
>
> Rola `Reader` na koncie Foundry daje `Microsoft.CognitiveServices/*/read` — pozwala:
> - Widzieć listę modeli (deployments) w dropdown przy tworzeniu agenta
> - Widzieć nazwy projektów w nawigacji portalu
>
> **Bez Reader** użytkownik nie widzi modeli i nie może tworzyć agentów!
>
> 📎 Oficjalne źródło: [Sample enterprise RBAC mappings](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#sample-enterprise-rbac-mappings-for-projects)
> → wiersz "Team members or developers": *"Azure AI User on Foundry project scope and Reader on the Foundry resource scope"*

### Krok 7b.4: Sprawdź nadane role

```powershell
az role assignment list --assignee $labUser --all --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

**Oczekiwany wynik:**
```
Role           Scope
-------------  -------------------------
Azure AI User  .../projects/project-lab01
Reader         .../accounts/{account}
```

### Krok 7b.5: Test w portalu — zaloguj się jako userlab01

Na Jumpbox VM (przez Bastion):

1. Otwórz **nowe okno InPrivate/Incognito** w Edge
2. Wejdź na **https://ai.azure.com**
3. Zaloguj się jako: `userlab01@{TWOJA-DOMENA}` / hasło ustawione w kroku 7b.1

> ⚠️ **MFA:** Jeśli tenant wymaga MFA, użytkownik musi najpierw zarejestrować MFA.
> Może to wymagać tymczasowego wyłączenia Conditional Access lub rejestracji z VPN do sieci korporacyjnej.

### Krok 7b.6: Weryfikacja izolacji — checklist

Sprawdź poniższe punkty i zanotuj wyniki:

| # | Test | Oczekiwany wynik | Twój wynik |
|---|------|-----------------|------------|
| 1 | Widzisz `project-lab01`? | ✅ Tak | ☐ |
| 2 | Widzisz nazwy innych projektów na liście? | ⚠️ Tak (Reader = ARM read) | ☐ |
| 3 | Możesz kliknąć **Agents** w `project-lab01`? | ✅ Tak | ☐ |
| 4 | Możesz stworzyć agenta w `project-lab01`? | ✅ Tak | ☐ |
| 5 | Widzisz modele w dropdown? | ✅ Tak (Reader daje listę modeli) | ☐ |
| 6 | Agent odpowiada na wiadomości? | ✅ Tak | ☐ |
| 7 | Możesz kliknąć **Agents** w innych projektach? | ❌ Nie — brak data access! | ☐ |
| 8 | Widzisz dane/pliki innych projektów? | ❌ Nie — izolacja data plane! | ☐ |

### Krok 7b.7: Stwórz agenta jako userlab01

Będąc zalogowanym jako userlab01 na portalu:

1. Wybierz **project-lab01**
2. Przejdź do **Agents** → **+ New Agent**
3. Model: `gpt-4.1`
4. Nazwa: `mój-agent-testowy`
5. Instructions: `Odpowiadaj krótko i po polsku.`
6. Napisz: `Cześć, kim jesteś?`

**Oczekiwany wynik:** ✅ Agent odpowiada — izolacja data plane działa, a użytkownik ma pełny dostęp do swojego projektu!

### Krok 7b.8: Próba dostępu do innego projektu

Nadal zalogowany jako userlab01:

1. Kliknij na inny projekt (np. `project-agent-test`)
2. Spróbuj otworzyć **Agents**

**Oczekiwany wynik:** ❌ Brak dostępu do zakładki Agents — data plane zablokowany!

> ✅ **To jest prawidłowe zachowanie!** Użytkownik widzi nazwy projektów (Reader na Account),
> ale **nie ma dostępu do danych** w projektach, do których nie ma roli Azure AI User.

### Podsumowanie izolacji

```
┌─────────────────────────────────────────────────────────────┐
│  Foundry Account: ai-foundry-byovnet-xxxxx                  │
│  userlab01: Reader (widzi nazwy, widzi modele)              │
│                                                             │
│  ┌──────────────────────┐  ┌──────────────────────┐         │
│  │ project-lab01        │  │ project-agent-test   │         │
│  │                      │  │                      │         │
│  │ userlab01:           │  │ userlab01:           │         │
│  │ ✅ Azure AI User     │  │ ❌ BRAK RÓL          │         │
│  │ ✅ Agents: DOSTĘP    │  │ ❌ Agents: ZABLOKOW. │         │
│  │ ✅ Modele: WIDOCZNE  │  │ ❌ Data plane: BRAK  │         │
│  └──────────────────────┘  └──────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

> 📘 **Poziomy izolacji — porównanie (przetestowane):**
>
> | Metoda | Widzi nazwy projektów? | Widzi modele? | Data plane izolacja? | Kiedy stosować |
> |--------|----------------------|--------------|---------------------|---------------|
> | **Custom Role + AI User na Project** | ✅ **Nie widzi!** | ✅ Tak | ✅ Pełna | ⭐ **Najlepsza izolacja w jednym Account** |
> | **Reader + AI User na Project** | ⚠️ Tak (nazwy widoczne) | ✅ Tak | ✅ Pełna | Oficjalny wzorzec MS, większość scenariuszy |
> | **Tylko AI User na Project** (bez Reader) | ❌ Nie widzi | ❌ Nie widzi | ✅ Pełna, ale nie można tworzyć agentów | Nie zalecane |
> | **AI User na Account** | ✅ Widzi wszystko | ✅ Tak | ❌ BRAK izolacji! | NIE UŻYWAJ w multi-tenant! |
> | **Osobne Foundry Accounts** | ✅ Nie widzi nic | ✅ Tak | ✅ Pełna | Regulacje, osobne zarządzanie |
>
> ⭐ **Custom Role to najlepsza opcja** — ukrywa nazwy projektów, zachowuje widoczność modeli, działa w jednym Account!
>
> 📎 [Access Isolation Examples](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry#access-isolation-examples)
> 📎 [Create custom roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles-cli)

---

### Krok 7b.9: ⭐ Pełna izolacja — Custom Role (ukrycie nazw projektów)

W poprzednich krokach użyliśmy `Reader` na Account — zgodnie z oficjalną dokumentacją Microsoft.
Jednak `Reader` daje `*/read` co pozwala widzieć **nazwy wszystkich projektów**.

Teraz stworzymy **Custom Role**, która daje dostęp do modeli, ale **ukrywa nazwy projektów**.

> 📘 **Jak to działa?**
>
> Operacje ARM w Azure są granularne. Zamiast `*/read` (Reader), nadajemy TYLKO:
> - `accounts/read` — odczyt konta (portal musi załadować kontekst)
> - `accounts/deployments/read` — lista modeli (dropdown przy tworzeniu agenta)
> - `accounts/models/read` — katalog dostępnych modeli
>
> Celowo **pomijamy** `accounts/projects/read` — użytkownik nie widzi nazw innych projektów!
>
> 📎 [Custom roles w Azure](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles-cli)

#### Krok A: Stwórz definicję Custom Role

```powershell
$sub = (Get-Content config/test-config.json | ConvertFrom-Json).subscription_id

# Definicja roli — zamiast Reader, tylko potrzebne uprawnienia
$roleDef = @{
    Name = "Foundry Model Reader"
    Description = "Read AI Foundry account and model deployments without listing projects. Use instead of Reader for full project isolation."
    Actions = @(
        "Microsoft.CognitiveServices/accounts/read"
        "Microsoft.CognitiveServices/accounts/deployments/read"
        "Microsoft.CognitiveServices/accounts/models/read"
        "Microsoft.CognitiveServices/accounts/connections/read"
        "Microsoft.Authorization/*/read"
    )
    NotActions = @()
    DataActions = @()
    NotDataActions = @()
    AssignableScopes = @("/subscriptions/$sub")
} | ConvertTo-Json -Depth 3

$roleDef | Out-File -FilePath custom-role.json -Encoding utf8
az role definition create --role-definition custom-role.json
```

> ⏱️ Tworzenie custom role zajmuje ~30 sekund.

#### Krok B: Zamień Reader na Custom Role

```powershell
$rg = (Get-Content config/test-config.json | ConvertFrom-Json).resource_group
$account = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv
$accountScope = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account"

# Usuń Reader
az role assignment delete --assignee $labUser --role "Reader" --scope $accountScope

# Nadaj Custom Role
az role assignment create --role "Foundry Model Reader" \
  --assignee-object-id $labUser \
  --assignee-principal-type User \
  --scope $accountScope
```

#### Krok C: Zweryfikuj role

```powershell
az role assignment list --assignee $labUser --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

**Oczekiwany wynik:**
```
Role                  Scope
--------------------  --------------------------------
Azure AI User         .../projects/project-lab01
Foundry Model Reader  .../accounts/{account}
```

#### Krok D: Test w portalu (po ~5 min propagacji RBAC)

> ⚠️ RBAC propaguje się ~5 minut. Poczekaj przed testem lub wyloguj/zaloguj użytkownika.

Na Jumpbox VM, jako userlab01 (InPrivate):

| # | Test | Oczekiwany wynik | Twój wynik |
|---|------|-----------------|------------|
| 1 | Widzisz `project-lab01`? | ✅ Tak | ☐ |
| 2 | Widzisz **nazwy** innych projektów? | ✅ **NIE!** (brak `projects/read`) | ☐ |
| 3 | Widzisz modele w dropdown? | ✅ Tak (`deployments/read`) | ☐ |
| 4 | Możesz stworzyć agenta? | ✅ Tak | ☐ |
| 5 | Agent odpowiada? | ✅ Tak | ☐ |

> 🎉 **Pełna izolacja w jednym Foundry Account!** Użytkownik nie widzi nazw projektów,
> widzi modele, może pracować w swoim projekcie. To lepsza izolacja niż oficjalny wzorzec z `Reader`.

#### Diagram — Custom Role vs Reader

```
┌─────────────────────────────────────────────────────────────┐
│  Foundry Account: ai-foundry-byovnet-xxxxx                  │
│                                                             │
│  userlab01: Foundry Model Reader (custom)                   │
│  ✅ accounts/read           — portal ładuje konto           │
│  ✅ accounts/deployments/read — widzi modele                │
│  ✅ accounts/models/read    — katalog modeli                │
│  ❌ accounts/projects/read  — NIE WIDZI nazw projektów!     │
│                                                             │
│  ┌──────────────────────┐  ┌──────────────────────┐         │
│  │ project-lab01        │  │ project-agent-test   │         │
│  │                      │  │                      │         │
│  │ userlab01:           │  │ userlab01:           │         │
│  │ ✅ Azure AI User     │  │ ❌ BRAK RÓL          │         │
│  │ ✅ PEŁNY DOSTĘP      │  │ ❌ NIEWIDOCZNY!      │         │
│  └──────────────────────┘  └──────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

#### Definicja roli — co zawiera i dlaczego

| Uprawnienie | Cel | Dlaczego potrzebne |
|-------------|-----|-------------------|
| `accounts/read` | Odczyt konta Foundry | Portal musi załadować kontekst konta |
| `accounts/deployments/read` | Lista model deployments | Dropdown przy tworzeniu agenta |
| `accounts/models/read` | Katalog modeli | Lista dostępnych modeli do deploy |
| `accounts/connections/read` | Odczyt połączeń | Portal może sprawdzać shared connections |
| `Authorization/*/read` | Odczyt uprawnień | Portal sprawdza co user może robić |

> ⚠️ **Uwaga:** Custom Role nie jest oficjalnie dokumentowana przez Microsoft jako wzorzec izolacji.
> Microsoft rekomenduje `Reader` na Account. Custom Role jest naszym rozwiązaniem, które działa
> z portalem ai.azure.com — ale może wymagać aktualizacji gdy portal doda nowe wymagania.
>
> Zalecamy: **przetestuj w swoim środowisku** przed wdrożeniem produkcyjnym.

### Cleanup użytkownika testowego (opcjonalnie)

```powershell
# Usuń role
az role assignment delete --assignee $labUser --scope $projectScope
az role assignment delete --assignee $labUser --scope $accountScope

# Usuń projekt testowy (opcjonalnie)
$sub = (Get-Content config/test-config.json | ConvertFrom-Json).subscription_id
$rg = (Get-Content config/test-config.json | ConvertFrom-Json).resource_group
$account = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv
az rest --method DELETE --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account/projects/project-lab01?api-version=2025-04-01-preview"

# Usuń custom role (opcjonalnie)
az role definition delete --name "Foundry Model Reader"

# Usuń użytkownika testowego
az ad user delete --id $labUser
```

---

## 🌐 Faza 8: APIM — API Gateway w sieci prywatnej (45 min)

> ℹ️ Ta faza jest opcjonalna — dodaje API Management jako bramkę do modeli AI.

> 📘 **Po co APIM?** API Management pozwala wystawiać modele AI jako standardowe API (OpenAPI/REST)
> z dodatkową warstwą kontroli: rate limiting, autentykacja, monitoring, transformacje.
> W trybie **Internal VNet** APIM jest wstrzykiwany bezpośrednio do Twojego VNetu —
> endpoint jest dostępny TYLKO z wnętrza sieci.
>
> 📎 **Dokumentacja:** [APIM Internal VNet](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet) |
> [APIM + Azure OpenAI](https://learn.microsoft.com/en-us/azure/api-management/api-management-authenticate-authorize-azure-openai)

### Krok 8.1: Deploy APIM

```powershell
.\scripts\02-deploy-apim.ps1
```

> ⏱️ APIM Developer tier: **30-45 minut**. To dobry moment na przerwę ☕

### Krok 8.2: Import API do APIM

```powershell
.\scripts\03-import-openapi-mcp.ps1
```

### Krok 8.3: Test APIM

```powershell
.\scripts\07-test-apim.ps1
```

---

## 🔗 Faza 8b: APIM jako AI Gateway — wybierz ścieżkę (20 min)

> ℹ️ Ta faza wymaga ukończenia Fazy 8 (APIM musi być wdrożony).

W zależności od wymagań klienta, budżetu i tieru APIM, wybierz jedną ze ścieżek:

### Która opcja dla Ciebie?

| | **Opcja A: Foundry AI Gateway** | **Opcja B: APIM Standalone Proxy** |
|---|---|---|
| **Opis** | APIM zintegrowany z Foundry — **cały ruch** z Foundry automatycznie przechodzi przez APIM | APIM jako samodzielny proxy — klienci wołają APIM bezpośrednio |
| **APIM Tier** | **Tylko v2** (Basic v2, Standard v2, Premium v2) | **Wszystkie** (Developer, Basic, Standard, Premium, v2) |
| **Konfiguracja** | Foundry Portal → Admin Console → AI Gateway | Import API z portalu Azure + policies |
| **Co daje** | Token limits per projekt, governance, BYOM dla agentów | Rate limiting, caching, monitoring — ręczne policies |
| **Kto konsumuje** | Foundry (modele, agenty, narzędzia) — automatycznie | Aplikacje klienckie (bezpośrednie wywołania API) |
| **Private Network** | Standard v2 (PE) lub Premium v2 (VNet injection) | Developer (Internal VNet), Premium (VNet), Standard v2 (PE) |
| **Koszt APIM** | Od ~$280/mies. (Standard v2) | Od ~$50/mies. (Developer) |
| **Scenariusz** | Enterprise governance, multi-team, produkcja | PoC, dev/test, standalone API gateway |

> 📎 **Dokumentacja:**
> - [Foundry AI Gateway — konfiguracja z portalu](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal) — **Wymaga: v2 tiers**
> - [AI Gateway capabilities in APIM](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities) — **Applies to: All tiers**
> - [Import Microsoft Foundry API to APIM](https://learn.microsoft.com/en-us/azure/api-management/azure-ai-foundry-api) — **Applies to: All tiers**
> - [BYOM / AI Gateway w Foundry Agents](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/ai-gateway) — **Wymaga: Standard v2 / Premium**
> - [APIM + ModelGateway Integration Guide](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim-and-modelgateway-integration-guide.md)
> - [Template 16: Private APIM + BYO VNet](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/16-private-network-standard-agent-apim-setup)

---

### 🅰️ Opcja A: Foundry AI Gateway (wymaga APIM v2)

> 📘 **Co to jest?** Foundry AI Gateway to natywna integracja APIM z Foundry.
> Po włączeniu, **cały ruch z Foundry** (modele, agenty, narzędzia) automatycznie
> przechodzi przez APIM. Daje token limits per projekt, governance i monitoring.
>
> ⚠️ **Wymaga APIM w tierze v2** (Basic v2, Standard v2, Premium v2).
> APIM Developer/Classic **nie pojawi się** w portalu Foundry.
>
> Dla private network (BYO VNet): **Standard v2** z Private Endpoint
> lub **Premium v2** z VNet injection.
>
> 📎 [Konfiguracja AI Gateway](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)

> 🖥️ **Wymagane:** Konfiguracja AI Gateway odbywa się z **portalu Foundry** (`ai.azure.com`).
> Dla BYO VNet musisz to robić z **Jumpbox VM** przez Bastion.
> Jeśli nie masz przygotowanego Jumpboxa, wróć do **Krok 7.2b**.

#### Architektura Foundry AI Gateway

```
┌──────────────────────────────────────────────────────────────────┐
│  Foundry                                                         │
│                                                                   │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐│
│  │ Model / Agent│───►│ AI Gateway       │───►│ AI Backend       ││
│  │ (projekt)    │    │ (APIM Std v2)    │    │ (OpenAI, inne)   ││
│  │              │    │ Token limits     │    │                  ││
│  │              │    │ Governance       │    │                  ││
│  └──────────────┘    └──────────────────┘    └──────────────────┘│
│                                                                   │
│  Automatycznie: cały ruch z Foundry → APIM → backend             │
│  Per-projekt: token limits (TPM), quotas, monitoring              │
└──────────────────────────────────────────────────────────────────┘
```

#### Wymagania APIM tier dla AI Gateway

| Tier | AI Gateway | Private Endpoint | VNet injection | Koszt |
|------|:----------:|:----------------:|:--------------:|-------|
| Developer (v1) | ❌ | ❌ | Internal* | ~$50/mies. |
| Basic (v1) | ❌ | ❌ | ❌ | ~$50/mies. |
| Standard (v1) | ❌ | ❌ | ❌ | ~$225/mies. |
| Premium (v1) | ❌ | ❌ | ✅ | ~$2800/mies. |
| **Basic v2** | ✅ | ❌ | ❌ | ~$280/mies. |
| **Standard v2** | ✅ | ✅ | ❌ | ~$280/mies. |
| **Premium v2** | ✅ | ✅ | ✅ | ~$700/mies.+ |

> \* Developer Internal VNet jest do dev/test, nie produkcji.
> Dla BYO VNet z private network potrzebujesz **Standard v2** (minimum) lub **Premium v2**.

#### Krok A.1: Deploy APIM Standard v2

Warsztat zmienia APIM z Developer na **Standard v2** z Private Endpoint:

```powershell
# Deploy APIM Standard v2 (Gateway V2)
# UWAGA: zmiana APIM z Developer na Standard v2 może trwać 30-45 minut
.\scripts\02-deploy-apim.ps1 -ApimSku "StandardV2"
```

> ⚠️ **Jeśli klient nie chce kosztów Standard v2 (~$280/mies.)**, zostań przy Developer
> i przejdź do **Opcji B** (standalone proxy). AI Gateway wymaga v2.

#### Krok A.2: Włącz AI Gateway w portalu Foundry

Na **Jumpbox VM** (przez Bastion):

1. Otwórz **https://ai.azure.com** → zaloguj się
2. Przejdź do **Operate** → **Admin console**
3. Otwórz zakładkę **AI Gateway**
4. Kliknij **Add AI Gateway**
5. Wybierz swój Foundry resource
6. Wybierz **Use existing** → wybierz APIM Standard v2
7. Nadaj nazwę gateway i kliknij **Add**
8. Poczekaj na status **Enabled** (5-10 min)

#### Krok A.3: Włącz AI Gateway dla projektu

1. W zakładce AI Gateway kliknij na nazwę gateway
2. Na liście projektów znajdź `project-agent-test`
3. Kliknij **Add project to gateway**
4. Status zmieni się na **Enabled**

#### Krok A.4: Weryfikacja

1. Azure Portal → APIM → **Monitoring** → **Metrics** → **Requests**
2. Wyślij test z portalu Foundry (agent lub playground)
3. Sprawdź czy request count rośnie w metrykach APIM
4. Opcjonalnie: **Monitoring** → **Logs** → query `GatewayLogs`

#### Krok A.5: Skonfiguruj token limits (opcjonalnie)

W Foundry Admin Console → AI Gateway:
- Ustaw TPM (tokens per minute) limit per projekt
- Ustaw quotę dzienną/tygodniową per projekt
- Po przekroczeniu limitu APIM zwraca `429 Too Many Requests`

---

### 🅱️ Opcja B: APIM Standalone Proxy (działa na wszystkich tierach)

> 📘 **Kiedy wybrać?** Gdy nie potrzebujesz natywnej integracji Foundry AI Gateway
> lub masz APIM Developer/Classic tier i nie chcesz kosztów v2.
> APIM działa jako **samodzielny proxy** do AI API — klienci wołają APIM bezpośrednio.

> 🖥️ **Wymagane:** Testy (skrypt `14-test-ai-gateway.ps1`) muszą być uruchomione
> **z Jumpbox VM** przez Bastion — APIM w trybie Internal VNet jest dostępny tylko z wnętrza sieci.
> Jeśli nie masz jeszcze przygotowanego Jumpboxa, wróć do **Krok 7.2b**.

#### Architektura Standalone Proxy

```
┌──────────────────────────────────────────────────────────────────┐
│  VNet (BYO)                                                      │
│                                                                   │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐│
│  │ Klient /     │───►│ APIM             │───►│ Foundry OpenAI   ││
│  │ Aplikacja    │    │ (Internal VNet)  │    │ (Private Endpt)  ││
│  │ (Jumpbox/VM) │    │ + AI policies    │    │                  ││
│  └──────────────┘    └──────────────────┘    └──────────────────┘│
│                                                                   │
│  Policies: token-limit, semantic-cache, content-safety,           │
│            load-balancer, emit-token-metric                       │
└──────────────────────────────────────────────────────────────────┘
```

#### Krok B.1: Import API (już wykonany w Fazie 8)

API OpenAI zostało już zaimportowane w Fazie 8 przez skrypt `03-import-openapi-mcp.ps1`.

#### Krok B.2: Test APIM Standalone Proxy

Z Jumpboxa:

```powershell
.\scripts\14-test-ai-gateway.ps1
```

#### Oczekiwany wynik (6 testów)

```
========================================
  AI Gateway Test (Option B)
  APIM as gateway to AI models
========================================
  ✅ PASS: DNS resolves apim-xxx.azure-api.net (IP: 192.168.2.4)
  ✅ PASS: TCP 443 to APIM
  ✅ PASS: Chat Completions via APIM (Model: gpt-4.1, Tokens: 70, Latency: 4293ms)
  ✅ PASS: Streaming response (22 chunks)
  ✅ PASS: Error on invalid model (HTTP 404)
  ✅ PASS: Rejected without subscription key (HTTP 401)
========================================
  ✅ PASS: 6   Total: 6
✅ AI Gateway dziala poprawnie!
  Flow: Klient -> APIM (Internal VNet) -> Foundry OpenAI (PE)
```

#### Krok B.3: Sprawdź metryki w APIM

1. Azure Portal → APIM → **Analytics**
2. Sprawdź: liczba requestów, latency, token usage
3. Jeśli skonfigurowałeś App Insights — sprawdź logi w Application Insights

---

### Znane ograniczenia

> 📋 **Źródła:**
> - [Foundry AI Gateway — konfiguracja](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)
> - [APIM & ModelGateway Integration Guide](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim-and-modelgateway-integration-guide.md#-current-limitations)

#### 1. Foundry AI Gateway wymaga APIM v2

Portal Foundry → Admin Console → AI Gateway:
- ✅ Widzi tylko APIM w tierach **v2** (Basic v2, Standard v2, Premium v2)
- ❌ **NIE widzi** APIM Developer, Basic, Standard, Premium (tiery classic/v1)
- ❌ NIE widzi APIM już skojarzonego z innym AI Gateway

#### 2. Private Network wymaga Standard v2+

Jeśli Foundry ma wyłączony public access (BYO VNet):
- ❌ Basic v2 — brak Private Endpoint
- ✅ **Standard v2** z Private Endpoint — najtańsza opcja
- ✅ **Premium v2** z VNet injection lub Private Endpoint

#### 3. APIM Internal VNet mode a BYOM

Foundry Agent Service runtime łączy się z APIM przez **Private Endpoint**, nie VNet:
- ❌ **APIM Internal VNet mode NIE działa** z BYOM (agent nie rozwiąże DNS)
- ✅ APIM z **Private Endpoint** (Standard v2/Premium v2) — wspierane
- ✅ APIM **publiczny** — działa, ale ruch wychodzi z VNet

Błąd przy Internal VNet:
```
model_error: Name or service not known (apim-xxx.azure-api.net:443)
```

#### 4. Portal "Admin connected models" a Internal VNet APIM

Portal Foundry → Admin console → Admin-connected models:
- ❌ **Nie widzi APIM w trybie Internal VNet** (brak publicznego data-plane)
- ✅ Widzi APIM bez VNet lub z External VNet mode
- ✅ CLI/Bicep działa niezależnie od trybu VNet

#### 5. Referencyjny template dla pełnej izolacji

📎 [Template 16: Private Network Standard Agent + APIM Setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/16-private-network-standard-agent-apim-setup)

**Wymagania:**
- APIM **Standard v2** lub **Premium v2** (Private Endpoint support)
- Private DNS zone: `privatelink.azure-api.net` zlinkowana do VNet
- RBAC: Foundry Account MI + Project MI → `API Management Service Reader` na APIM

---

## 📊 Faza 9: Raport końcowy (2 min)

Generujemy podsumowanie wszystkich testów.

```powershell
.\scripts\09-e2e-report.ps1
```

### Oczekiwany wynik

```
═══════════════════════════════════════════════════════════
  FOUNDRY BYO VNet - END-TO-END TEST REPORT
═══════════════════════════════════════════════════════════
✅ PASS  [Network] VNet exists
✅ PASS  [Network] Agent subnet delegation
✅ PASS  [PE] 4 Private Endpoints Approved
✅ PASS  [DNS] 6 zones linked
✅ PASS  [Foundry] Public access: Disabled
✅ PASS  [Foundry] Network injection (BYO VNet)
✅ PASS  [Portal] Bastion: Succeeded
✅ PASS  [Portal] VPN Gateway: Succeeded
═══════════════════════════════════════════════════════════
  VERDICT: GO ✅
  Total: 21 PASS | 0 FAIL | 1 WARN
═══════════════════════════════════════════════════════════
```

Raport zapisywany jest do pliku `report.txt`.

---

## 🧹 Cleanup (5 min)

Po zakończeniu warsztatu — usuń zasoby żeby nie generować kosztów.

```powershell
# Krok 1: Usuń Capability Host (wymagane przed usunięciem konta AI)
$sub = (Get-Content config/test-config.json | ConvertFrom-Json).subscription_id
$rg = (Get-Content config/test-config.json | ConvertFrom-Json).resource_group
$aiName = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv

az rest --method DELETE `
  --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$aiName/projects/project-agent-test/capabilityHosts/default?api-version=2025-04-01-preview"

# Krok 2: Poczekaj 2 minuty
Start-Sleep -Seconds 120

# Krok 3: Usuń resource group (wszystkie zasoby)
az group delete --name $rg --yes --no-wait
Write-Host "Usuwanie w toku. Zajmie ~10 min."

# Krok 4: Po usunięciu RG — purguj konto AI (soft-delete protection)
# Poczekaj aż RG się usunie, potem:
az cognitiveservices account purge --name $aiName --resource-group $rg --location swedencentral
```

---

## ⚠️ Znane pułapki i rozwiązania

| Problem | Przyczyna | Rozwiązanie |
|---------|-----------|-------------|
| "Account in state Accepted" | networkInjections provisionuje się asynchronicznie | Skrypt ma retry logic — poczeka i ponowi |
| "You don't have permission to build agents" | Rola Azure AI User = read-only | Nadaj **Azure AI Developer** na Account lub Project |
| "Request blocked by Auth cosmos" | Brak CosmosDB data plane RBAC | Dodaj `Cosmos DB Built-in Data Contributor` przez `az cosmosdb sql role assignment create` |
| "Connection is AzureBlob not AzureStorageAccount" | Zła kategoria storage connection | Kategoria MUSI być `AzureStorageAccount` |
| Portal nie ładuje się z Internetu | Public access = Disabled | ✅ To poprawne zachowanie! Użyj Bastion lub VPN |
| VPN Gateway: "must have zones" | AZ SKU wymaga zone-redundant PIP | Public IP musi mieć `zones: ['1','2','3']` |
| Deploy trwa >30 min | VPN Gateway jest powolny | To normalne — Gateway tworzy się 25 min |

---

## 📚 Materiały dodatkowe i dokumentacja

### Oficjalna dokumentacja Microsoft

| Temat | Link |
|-------|------|
| **AI Foundry — przegląd** | [learn.microsoft.com/azure/foundry](https://learn.microsoft.com/en-us/azure/foundry/) |
| **Agent Service — BYO VNet** | [Prywatna sieć dla agentów](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks) |
| **Agent Service — Managed VNet** | [Zarządzana sieć wirtualna](https://learn.microsoft.com/en-us/azure/foundry/how-to/managed-virtual-network) |
| **Opcje sieciowe — porównanie** | [Networking concepts](https://learn.microsoft.com/en-us/azure/ai-services/agents/concepts/networking) |
| **Konfiguracja środowiska agentów** | [Environment setup](https://learn.microsoft.com/en-us/azure/ai-services/agents/environment-setup) |
| **RBAC dla AI Foundry** | [Role-based access control](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/role-based-access-control) |
| **Private Endpoints — ogólnie** | [Azure Private Link](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) |
| **Private DNS Zones** | [DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns) |
| **Azure Bastion** | [Bastion overview](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview) |
| **VPN P2S — konfiguracja** | [Point-to-Site VPN](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-resource-manager-portal) |
| **APIM Internal VNet** | [VNet integration](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet) |
| **BYOM — Bring Your Own Model** | [Agent z modelem przez APIM](https://learn.microsoft.com/en-us/azure/ai-services/agents/how-to/bring-your-own-model) |
| **APIM AI Gateway (v2)** | [AI Gateway integration](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal) |
| **CosmosDB data plane RBAC** | [RBAC for Cosmos DB](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac) |

### Oficjalny template Bicep

- [foundry-samples / 15-private-network-standard-agent-setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup)

### Znane problemy i ograniczenia (stan: maj 2025)

| Problem | Opis | Obejście |
|---------|------|----------|
| **Race condition przy deploy** | Account z `networkInjections` przechodzi przez stan `Accepted` — child resources fail | Retry logic w skrypcie deploy |
| **CosmosDB data plane** | `disableLocalAuth: true` + brak RBAC data plane = 403 w portalu | `az cosmosdb sql role assignment create` |
| **VpnGw1 deprecated** | SKU VpnGw1 zastąpiony przez VpnGw1AZ | Użyj VpnGw1AZ + PIP z zones |
| **Storage connection** | Kategoria musi być `AzureStorageAccount` (nie `AzureBlob`) | Sprawdź Bicep template |
| **subnetArmId** | Dynamiczne `subnet[0].id` odrzucane | Użyj `resourceId()` |
| **Class A addresses** | `10.0.0.0/8` może nie działać we wszystkich regionach | Użyj `192.168.0.0/16` lub `172.16.0.0/12` |
| **BYOM connection propagation** | Connection `ApiManagement` potrzebuje ~2 min na propagację | Odczekaj przed tworzeniem agenta z BYOM modelem |
| **BYOM vs AI Gateway** | AI Gateway wymaga APIM v2, BYOM działa z v1 | Użyj BYOM dla dev/test na APIM Developer |

---

---

*Warsztat opracowany na podstawie testów przeprowadzonych w maju 2025, zaktualizowany w maju 2026 o sekcję BYOM. Sprawdź dokumentację Microsoft pod kątem zmian.*
