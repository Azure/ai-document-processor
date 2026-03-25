# Guía de Despliegue en Modo AI Landing Zone (AILZ)

> **Audiencia**: Ingenieros de DevOps, Platform Engineers, Arquitectos de Infraestructura  
> **Propósito**: Guía técnica operativa para desplegar AI Document Processor en modo enterprise con red privada (AILZ/VNet)  
> **Última actualización**: Marzo 2026

---

## Tabla de Contenidos

1. [Contexto: ¿Qué es una AI Landing Zone?](#1-contexto-qué-es-una-ai-landing-zone)
2. [Comparación: Modo Básico vs. Modo AILZ-Integrated](#2-comparación-modo-básico-vs-modo-ailz-integrated)
3. [Prerequisitos para el Modo AILZ](#3-prerequisitos-para-el-modo-ailz)
4. [Topología de Red](#4-topología-de-red)
5. [Parámetros de Despliegue](#5-parámetros-de-despliegue)
6. [Cambios por Recurso en Modo AILZ](#6-cambios-por-recurso-en-modo-ailz)
7. [Paso a Paso: Despliegue en Modo AILZ](#7-paso-a-paso-despliegue-en-modo-ailz)
8. [Troubleshooting](#8-troubleshooting)
9. [Validación del Despliegue](#9-validación-del-despliegue)

---

## 1. Contexto: ¿Qué es una AI Landing Zone?

### Definición

Una **AI Landing Zone (AILZ)** es un entorno Azure pre-hardened que aplica los principios de [Azure Landing Zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) al dominio de servicios de Inteligencia Artificial. Establece una base de gobierno, seguridad de red, identidad y cumplimiento normativo _antes_ de que la carga de trabajo sea desplegada.

En términos prácticos, una AILZ provee:

- **Red privada administrada**: VNet corporativa con subredes segmentadas por función
- **DNS privado**: Resolución de nombres de servicios Azure a través de Private Endpoints sin exponer tráfico a Internet
- **Perimetro de identidad Zero Trust**: Todo acceso autenticado via Managed Identity, sin claves compartidas
- **Observabilidad central**: Log Analytics Workspace y Application Insights compartidos entre cargas de trabajo
- **Governance de plataforma**: Azure Policy, RBAC y tagging aplicados a nivel de Management Group

### ¿Por qué es necesaria para despliegues productivos?

| Necesidad empresarial | Sin AILZ | Con AILZ |
|---|---|---|
| Cumplimiento normativo (SOC 2, ISO 27001, PCI-DSS) | Difícil de demostrar | Controles heredados de la plataforma |
| Exfiltración de datos | Posible vía endpoints públicos | Bloqueada por Private Endpoints y NSG |
| Segregación de ambientes | Manual, inconsistente | Subredes NSG-segmentadas por función |
| Acceso a datos | Claves de cuenta expuestas | RBAC + Managed Identity only |
| Auditoría de operaciones | Logs dispersos | Centralizado en Log Analytics Workspace |
| Conectividad on-premises | VPN ad-hoc | ExpressRoute/VPN Gateway en subnet dedicada |

### Diferencia con un despliegue básico

```
MODO BÁSICO                          MODO AILZ-INTEGRATED
──────────────────────               ─────────────────────────────────
Internet                             Internet
    │                                    │
    ▼                                    ▼ (solo HTTPS 443)
Function App ──público──▶ AOAI       Azure Bastion ──▶ VM de Prueba
    │                                    │
    ▼                                    ▼
Storage (público)                    VNet 10.0.0.0/23
Key Vault (público)                      └─ Function App (VNet Integration)
Cosmos DB (público)                          └─ Private Endpoints
                                                 ├─ AI Foundry/AOAI
                                                 ├─ Storage (blob/queue/table/file)
                                                 ├─ Key Vault
                                                 ├─ Cosmos DB
                                                 ├─ App Config
                                                 └─ Log Analytics
```

---

## 2. Comparación: Modo Básico vs. Modo AILZ-Integrated

| Característica | Modo Básico (`networkIsolation=false`) | Modo AILZ-Integrated (`networkIsolation=true`) |
|---|---|---|
| **Parámetro clave** | `AZURE_NETWORK_ISOLATION=false` | `AZURE_NETWORK_ISOLATION=true` |
| **Endpoints de servicio** | Públicos (Internet) | Privados (Private Endpoint) |
| **Virtual Network** | No se crea | VNet `10.0.0.0/23` con 5 subnets |
| **NSG** | No | Sí, uno por subnet |
| **Private Endpoints** | No | Sí, para todos los servicios |
| **Zonas DNS privadas** | No | Sí, 14 zonas DNS privadas vinculadas |
| **Tráfico de salida (Function App)** | Directo a Internet | Rutado por VNet (`WEBSITE_VNET_ROUTE_ALL=1`) |
| **DNS del Function App** | DNS público | Azure DNS interno (`168.63.129.16`) |
| **Acceso a Key Vault** | Público | Solo desde `aiSubnet` |
| **Acceso a Storage** | Público | Default Deny + regla de subnet |
| **Acceso a Cosmos DB** | Público | Solo vía PE en `databaseSubnet` |
| **Acceso a AI Foundry** | Público | Private Endpoint via AVM |
| **Log Analytics** | Ingestión pública | `publicNetworkAccessForIngestion=Disabled` |
| **VM de prueba (Bastion)** | No necesaria | Recomendada (`deployVM=true`) |
| **VPN Gateway** | No | Opcional (`deployVPN=true`) |
| **Azure Bastion** | No | Sí (cuando `deployVM=true`) |
| **Tiempo de despliegue** | ~10-15 min | ~30-45 min |
| **Prerequisitos** | Mínimos | VNet existente o auto-creada, permisos de red |
| **Acceso post-despliegue al portal** | Inmediato | Requiere estar en VNet (VM/VPN/Bastion) |
| **Complejidad operativa** | Baja | Alta |
| **Postura de seguridad** | Media | Alta (Zero Trust) |

---

## 3. Prerequisitos para el Modo AILZ

### Recursos que deben existir ANTES del despliegue

**Opción A — Dejar que el template cree la VNet (recomendado para entornos nuevos)**

En este caso `VNET_REUSE=false` y el template crea toda la infraestructura de red automáticamente. Solo se requiere:

- Suscripción Azure con cuota disponible
- Usuario con rol de **Contributor** o **Owner** en el Resource Group de destino
- Cuota de IPs públicas disponible (para Bastion + VPN Gateway si aplica)

**Opción B — Integrar en VNet existente (AILZ real)**

Cuando `VNET_REUSE=true`, los siguientes recursos deben existir y estar accesibles:

| Recurso | Descripción | Referencia |
|---|---|---|
| Virtual Network | VNet corporativa con espacio de direcciones libre | `VNET_NAME`, `VNET_RESOURCE_GROUP_NAME` |
| Subnet para AI Services | `/26` mínimo, sin delegación | Para Private Endpoints de AOAI, KV, AppConfig, FuncApp |
| Subnet para App Services | `/26` mínimo, delegada a `Microsoft.Web/serverFarms` | VNet Integration de Function App |
| Subnet para Base de Datos | `/26` mínimo, sin delegación | Para PE de Cosmos DB |
| Subnet para App Integration | `/26` mínimo, delegada a `Microsoft.Web/serverFarms` | Subnet de integración alternativa |
| DNS Privado vinculado a la VNet | O delegación a Azure DNS | Para resolución de Private Endpoints |
| Log Analytics Workspace (opcional) | Si se reutiliza | `LOG_ANALYTICS_WORKSPACE_ID` |

### Permisos necesarios en la Landing Zone existente

```bash
# El principal que ejecuta azd up debe tener los siguientes roles:
# En el Resource Group de destino:
az role assignment list --assignee <PRINCIPAL_ID> --resource-group <RG>

# Roles mínimos requeridos:
# - Contributor (para crear recursos)
# - User Access Administrator (para asignar roles RBAC a Managed Identities)
# - Network Contributor (para crear Private Endpoints en la VNet existente)

# Verificar permisos actuales del usuario logueado:
az ad signed-in-user show --query "id" -o tsv
az role assignment list --assignee $(az ad signed-in-user show --query "id" -o tsv) \
  --resource-group <RESOURCE_GROUP> \
  --output table
```

### Comandos para verificar disponibilidad de recursos

```bash
# 1. Verificar cuota de IPs públicas en la región
az network list-usages --location eastus2 \
  --query "[?name.value=='PublicIPAddresses']" \
  --output table

# 2. Verificar espacio disponible en VNet existente
az network vnet show \
  --name <VNET_NAME> \
  --resource-group <VNET_RG> \
  --query "addressSpace.addressPrefixes" \
  --output json

# 3. Listar subnets disponibles en la VNet
az network vnet subnet list \
  --vnet-name <VNET_NAME> \
  --resource-group <VNET_RG> \
  --output table

# 4. Verificar si hay políticas que bloqueen Private Endpoints
az policy assignment list \
  --resource-group <RESOURCE_GROUP> \
  --query "[].{Name:name, Policy:policyDefinitionId}" \
  --output table

# 5. Verificar cuota de Private Endpoints
az network list-usages --location eastus2 \
  --query "[?name.value=='PrivateEndpoints']" \
  --output table

# 6. Verificar disponibilidad de Log Analytics Workspace existente
az monitor log-analytics workspace show \
  --workspace-name <WORKSPACE_NAME> \
  --resource-group <WORKSPACE_RG> \
  --query "{id:id, sku:sku.name, retentionInDays:retentionInDays}" \
  --output json
```

---

## 4. Topología de Red

### Diagrama ASCII de Arquitectura de Red

```
╔══════════════════════════════════════════════════════════════════════════════╗
║  RESOURCE GROUP: rg-<env>                                                    ║
║                                                                              ║
║  ┌───────────────── VNet: vnet-ai-<suffix>  10.0.0.0/23 ─────────────────┐  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ aiSubnet          10.0.0.0/26    NSG: ai-nsg                    │   │  ║
║  │  │                                                                  │   │  ║
║  │  │  PE: Key Vault        ──────────────────▶ privatelink.vaultcore│   │  ║
║  │  │  PE: App Config       ──────────────────▶ privatelink.azconfig │   │  ║
║  │  │  PE: AI Foundry       ──────────────────▶ privatelink.openai   │   │  ║
║  │  │                                           privatelink.cognitiv  │   │  ║
║  │  │                                           privatelink.services  │   │  ║
║  │  │  PE: Function App     ──────────────────▶ privatelink.websites │   │  ║
║  │  │  PE: Log Analytics    ──────────────────▶ privatelink.monitor  │   │  ║
║  │  │  PE: Storage (data)   ──────────────────▶ privatelink.blob     │   │  ║
║  │  │                                           privatelink.queue     │   │  ║
║  │  │                                           privatelink.table     │   │  ║
║  │  │                                           privatelink.file      │   │  ║
║  │  │  Test VM (NIC)                                                   │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ appServicesSubnet  10.0.0.128/26  NSG: appServices-nsg          │   │  ║
║  │  │  Delegada a: Microsoft.Web/serverFarms                           │   │  ║
║  │  │                                                                  │   │  ║
║  │  │  Function App (VNet Integration) ◀── Tráfico saliente rutado    │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ appIntSubnet       10.0.0.64/26   NSG: appInt-nsg               │   │  ║
║  │  │  Delegada a: Microsoft.Web/serverFarms                           │   │  ║
║  │  │  (subnet de integración alternativa)                             │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ databaseSubnet     10.0.1.0/26    NSG: database-nsg             │   │  ║
║  │  │                                                                  │   │  ║
║  │  │  PE: Cosmos DB     ─────────────────────▶ privatelink.documents │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ AzureBastionSubnet 10.0.1.128/26  NSG: bastion-nsg             │   │  ║
║  │  │                                                                  │   │  ║
║  │  │  Azure Bastion Host ◀──── HTTPS 443 desde Internet              │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  │  ┌─────────────────────────────────────────────────────────────────┐   │  ║
║  │  │ gatewaySubnet      10.0.1.64/26   (sin NSG, sin delegación)     │   │  ║
║  │  │                                                                  │   │  ║
║  │  │  VPN Gateway  ◀──── Solo cuando deployVPN=true                  │   │  ║
║  │  └─────────────────────────────────────────────────────────────────┘   │  ║
║  │                                                                         │  ║
║  └─────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
║  Zonas DNS Privadas (vinculadas a la VNet):                                  ║
║  ┌───────────────────────────────────────────────────────────────────────┐  ║
║  │  privatelink.vaultcore.azure.net              (Key Vault)             │  ║
║  │  privatelink.azconfig.io                      (App Configuration)     │  ║
║  │  privatelink.cognitiveservices.azure.com       (AI Services)          │  ║
║  │  privatelink.openai.azure.com                 (Azure OpenAI)          │  ║
║  │  privatelink.services.ai.azure.com            (AI Foundry)            │  ║
║  │  privatelink.documents.azure.com              (Cosmos DB)             │  ║
║  │  privatelink.blob.core.windows.net            (Blob Storage)          │  ║
║  │  privatelink.queue.core.windows.net           (Queue Storage)         │  ║
║  │  privatelink.table.core.windows.net           (Table Storage)         │  ║
║  │  privatelink.file.core.windows.net            (File Storage)          │  ║
║  │  privatelink.azurewebsites.net                (Function App)          │  ║
║  │  privatelink.monitor.azure.com                (Azure Monitor)         │  ║
║  │  privatelink.ods.opinsights.azure.com         (Log Analytics ODS)     │  ║
║  │  privatelink.oms.opinsights.azure.com         (Log Analytics OMS)     │  ║
║  │  privatelink.agentsvc.azure-automation.net    (Automation Agent)      │  ║
║  └───────────────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Tabla de Recursos por Subnet

| Recurso Azure | Subnet | Tipo de Acceso | Puerto | Protocolo |
|---|---|---|---|---|
| Function App (ingress PE) | `aiSubnet` | Private Endpoint | 443 | HTTPS |
| Function App (egress) | `appServicesSubnet` | VNet Integration (delegada) | Saliente | TCP |
| Key Vault | `aiSubnet` | Private Endpoint | 443 | HTTPS |
| App Configuration | `aiSubnet` | Private Endpoint | 443 | HTTPS |
| AI Foundry / AOAI | `aiSubnet` | Private Endpoint (AVM) | 443 | HTTPS |
| Storage (Blob, Queue, Table, File) | `aiSubnet` | Private Endpoint | 443 | HTTPS |
| Cosmos DB | `databaseSubnet` | Private Endpoint | 443 | HTTPS |
| Log Analytics | `aiSubnet` | Private Endpoint (AMPLS) | 443 | HTTPS |
| Test VM | `aiSubnet` | NIC directa | N/A | N/A |
| Azure Bastion | `AzureBastionSubnet` | NIC + IP pública | 443 | HTTPS |
| VPN Gateway | `gatewaySubnet` | NIC + IP pública | UDP 500, 4500 | IKEv2 |

---

## 5. Parámetros de Despliegue

Los parámetros se definen en `infra/main.parameters.json` y se leen como variables de entorno. A continuación se listan todos, agrupados por categoría.

### Categoría: Identidad y Entorno

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `AZURE_ENV_NAME` | `string` | Nombre del ambiente azd, se usa en tags y nombres de recursos | `prod-ailz` | **Sí** |
| `AZURE_LOCATION` | `string` | Región donde se despliegan los recursos de cómputo | `eastus2` | **Sí** |
| `AZURE_RESOURCE_GROUP` | `string` | Nombre del Resource Group (se crea si no existe) | `rg-adp-prod` | **Sí** |
| `AZURE_PRINCIPAL_ID` | `string` | Object ID del usuario/SP que ejecuta azd; asignado a roles RBAC | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | **Sí** |
| `AOAI_LOCATION` | `string` | Región del recurso AI Foundry (con capacidad GPT disponible) | `East US` | **Sí** |

### Categoría: Red (AILZ)

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `AZURE_NETWORK_ISOLATION` | `bool` | **Activa el modo AILZ completo**: Private Endpoints, VNet, DNS | `true` | **Sí** |
| `AZURE_DEPLOY_VM` | `bool` | Despliega VM de prueba con Bastion para acceso a recursos privados | `true` | Recomendado |
| `AZURE_DEPLOY_VPN` | `bool` | Despliega VPN Gateway para conectividad on-premises | `false` | Opcional |
| `VNET_REUSE` | `bool` | Reutiliza una VNet existente en lugar de crear una nueva | `true` | Opcional |
| `VNET_RESOURCE_GROUP_NAME` | `string` | RG donde vive la VNet existente (si `VNET_REUSE=true`) | `rg-networking-hub` | Condicional |
| `VNET_NAME` | `string` | Nombre de la VNet existente (si `VNET_REUSE=true`) | `vnet-spoke-prod` | Condicional |

### Categoría: VM de Prueba (cuando `deployVM=true`)

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `VM_USER_PASSWORD` | `securestring` | Contraseña inicial de la VM (6-72 chars, debe cumplir complejidad) | `P@ssw0rd!2026` | Sí (si deployVM=true) |
| `vmUserName` (directo) | `string` | Usuario de la VM; default: `adp-user` | `adpadmin` | No |
| `vmSize` (directo) | `string` | SKU de la VM | `Standard_D8s_v5` | No |
| `vmImageSku` (directo) | `string` | SKU de la imagen VM | `win11-25h2-ent` | No |

### Categoría: Servicios AI

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `AI_VISION_ENABLED` | `bool` | Habilita Computer Vision / AI Vision en el pipeline | `false` | No |
| `AOAI_MULTI_MODAL` | `bool` | Habilita ingestión multi-modal (PDF/imágenes vía AOAI vision) | `false` | No |
| `AOAI_REUSE` | `bool` | Reutiliza cuenta Azure OpenAI / AI Foundry existente | `false` | Opcional |
| `AOAI_RESOURCE_GROUP_NAME` | `string` | RG del recurso AOAI existente | `rg-aiservices` | Condicional |
| `AOAI_NAME` | `string` | Nombre del recurso AOAI/AI Foundry existente | `aoai-corp-prod` | Condicional |
| `AI_SERVICES_REUSE` | `bool` | Reutiliza cuenta AI Services existente | `false` | Opcional |
| `AI_SERVICES_RESOURCE_GROUP_NAME` | `string` | RG del recurso AI Services existente | `rg-aiservices` | Condicional |
| `AI_SERVICES_NAME` | `string` | Nombre del recurso AI Services existente | `aiservices-corp` | Condicional |

### Categoría: Almacenamiento

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `STORAGE_REUSE` | `bool` | Reutiliza Storage Account existente | `false` | Opcional |
| `STORAGE_RESOURCE_GROUP_NAME` | `string` | RG del Storage Account existente | `rg-storage` | Condicional |
| `STORAGE_NAME` | `string` | Nombre del Storage Account existente | `stprodadp001` | Condicional |
| `ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE` | `bool` | Reutiliza storage del Function App | `false` | Opcional |
| `ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME` | `string` | Nombre del storage del Function App existente | `stprodadpfunc` | Condicional |
| `ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME` | `string` | RG del storage del Function App | `rg-compute` | Condicional |

### Categoría: Cómputo (Function App)

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `FUNCTION_APP_HOST_PLAN` | `string` | Plan de hosting: `Dedicated` o `FlexConsumption` | `Dedicated` | **Sí** |
| `FUNCTION_APP_SKU` | `string` | SKU del plan: `FC1`, `S2`, `B1`, `P1v2`, etc. | `S2` | **Sí** |
| `APP_SERVICE_PLAN_REUSE` | `bool` | Reutiliza App Service Plan existente | `false` | Opcional |
| `APP_SERVICE_PLAN_RESOURCE_GROUP_NAME` | `string` | RG del App Service Plan existente | `rg-compute` | Condicional |
| `APP_SERVICE_PLAN_NAME` | `string` | Nombre del App Service Plan existente | `asp-prod-001` | Condicional |

### Categoría: Base de Datos

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `COSMOS_DB_REUSE` | `bool` | Reutiliza cuenta Cosmos DB existente | `false` | Opcional |
| `COSMOS_DB_RESOURCE_GROUP_NAME` | `string` | RG del Cosmos DB existente | `rg-data` | Condicional |
| `COSMOS_DB_ACCOUNT_NAME` | `string` | Nombre de la cuenta Cosmos DB existente | `cosmos-prod-adp` | Condicional |
| `COSMOS_DB_DATABASE_NAME` | `string` | Nombre de la base de datos existente | `conversationHistoryDB` | Condicional |

### Categoría: Seguridad

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `KEY_VAULT_REUSE` | `bool` | Reutiliza Key Vault existente | `false` | Opcional |
| `KEY_VAULT_RESOURCE_GROUP_NAME` | `string` | RG del Key Vault existente | `rg-security` | Condicional |
| `KEY_VAULT_NAME` | `string` | Nombre del Key Vault existente | `kv-prod-adp-001` | Condicional |

### Categoría: Observabilidad

| Parámetro (env var) | Tipo | Descripción | Ejemplo | Requerido AILZ |
|---|---|---|---|---|
| `APP_INSIGHTS_REUSE` | `bool` | Reutiliza Application Insights existente | `true` | Recomendado |
| `APP_INSIGHTS_RESOURCE_GROUP_NAME` | `string` | RG del Application Insights existente | `rg-monitoring` | Condicional |
| `APP_INSIGHTS_NAME` | `string` | Nombre del Application Insights existente | `appi-prod-ailz` | Condicional |
| `LOG_ANALYTICS_WORKSPACE_REUSE` | `bool` | Reutiliza Log Analytics Workspace existente | `true` | Recomendado |
| `LOG_ANALYTICS_WORKSPACE_ID` | `string` | Resource ID completo del Log Analytics Workspace existente | `/subscriptions/.../workspaces/law-prod` | Condicional |

---

## 6. Cambios por Recurso en Modo AILZ

| Recurso Azure | Cambio en Modo AILZ | Justificación |
|---|---|---|
| **Virtual Network** | Se crea con 5 subnets segmentadas (`10.0.0.0/23`) + NSG por subnet | Perímetro de red Zero Trust; segmentación por función |
| **Azure Bastion Host** | Se despliega con IP pública fija (SKU Standard) cuando `deployVM=true` | Único punto de acceso RDP/SSH seguro a la VM; elimina necesidad de IP pública en la VM |
| **VPN Gateway** | Se crea en `gatewaySubnet` cuando `deployVPN=true` (SKU VpnGw1) | Conectividad privada desde red corporativa on-premises |
| **Function App** | `publicNetworkAccess=Disabled` + VNet Integration en `appServicesSubnet` + `WEBSITE_VNET_ROUTE_ALL=1` + `WEBSITE_DNS_SERVER=168.63.129.16` | Todo el tráfico de salida pasa por la VNet; DNS resuelve Private Endpoints |
| **Function App PE** | Private Endpoint en `aiSubnet` registrado en `privatelink.azurewebsites.net` | El ingreso HTTP a la función solo es accesible desde dentro de la VNet |
| **Key Vault** | `publicNetworkAccess=Disabled` + Private Endpoint en `aiSubnet` | Secretos no accesibles desde Internet; solo Function App con Managed Identity vía PE |
| **App Configuration** | `publicNetworkAccess=Enabled` (excepción en template actual) + PE en `aiSubnet` | Se mantiene accesible para simplificar operaciones; PE disponible para acceso privado |
| **AI Foundry / AOAI** | Private Endpoint manejado internamente por AVM (`avm/ptn/ai-ml/ai-foundry`) en `aiSubnet` + 3 DNS zones | Inferencia y embeddings no expuestos a Internet |
| **Cosmos DB** | `publicNetworkAccess=Disabled` + Private Endpoint en `databaseSubnet` | Historial de conversaciones y configuración de prompts solo accesibles dentro de la VNet |
| **Storage Account (data)** | `defaultAction=Deny` + `allowedVirtualNetworkRule=aiSubnet` + PEs para blob/queue/table/file | Contenedores bronze/silver/gold inaccesibles desde Internet |
| **Storage Account (func)** | `publicNetworkAccess=Disabled` + `defaultAction=Deny` + PEs | Storage de runtime del Function App en red privada |
| **Log Analytics Workspace** | `publicNetworkAccessForIngestion=Disabled` + `publicNetworkAccessForQuery=Disabled` + PE via AMPLS | Logs de diagnóstico solo ingieren dentro de la VNet; previene exfiltración de telemetría |
| **Application Insights** | `publicNetworkAccessForIngestion=Disabled` + `publicNetworkAccessForQuery=Disabled` + vinculado a AMPLS | Idem Log Analytics |
| **Private DNS Zones (x15)** | Creadas y vinculadas a la VNet; una por servicio | Resolución DNS de `*.privatelink.*` a IPs privadas del PE en lugar de IPs públicas |
| **NSGs** | 5 NSGs con reglas de seguridad por grupo de recursos de red | Filtrado de tráfico este-oeste y norte-sur dentro de la VNet |
| **Test VM** | Windows 11 Enterprise en `aiSubnet` con Managed Identity y Custom Script Extension | Permite validar conectividad a recursos privados sin abrir puertos públicos |

---

## 7. Paso a Paso: Despliegue en Modo AILZ

### Paso 1 — Instalar prerequisitos

```bash
# Azure CLI
brew update && brew install azure-cli   # macOS
# o: https://docs.microsoft.com/cli/azure/install-azure-cli

# Azure Developer CLI (azd)
brew tap azure/azd && brew install azd  # macOS
# o: curl -fsSL https://aka.ms/install-azd.sh | bash

# Python 3.11+ y Azure Functions Core Tools
brew install python@3.11
brew tap azure/functions && brew install azure-functions-core-tools@4

# Verificar versiones
az --version
azd version
func --version
```

### Paso 2 — Autenticarse en Azure

```bash
# Login interactivo
az login
azd auth login

# (Opcional) Si se usa Service Principal para CI/CD:
az login --service-principal \
  --username <APP_ID> \
  --password <CLIENT_SECRET> \
  --tenant <TENANT_ID>

export AZURE_SUBSCRIPTION_ID="<subscription-id>"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Verificar identidad
az account show --query "{name:name, id:id, tenantId:tenantId}" --output json
az ad signed-in-user show --query "{id:id, userPrincipalName:userPrincipalName}" --output json
```

### Paso 3 — Clonar el repositorio e inicializar azd

```bash
git clone https://github.com/Azure/ai-document-processor.git
cd ai-document-processor

# Inicializar el entorno azd
azd env new ailz-prod
# o para retomar un entorno existente:
# azd env select ailz-prod
```

### Paso 4 — Configurar variables de entorno para modo AILZ

**Configuración mínima para modo AILZ (VNet nueva):**

```bash
# Identidad y ubicación
azd env set AZURE_ENV_NAME "ailz-prod"
azd env set AZURE_LOCATION "eastus2"
azd env set AZURE_RESOURCE_GROUP "rg-adp-ailz-prod"
azd env set AOAI_LOCATION "East US"

# AILZ: Activar aislamiento de red
azd env set AZURE_NETWORK_ISOLATION "true"

# AILZ: VM de prueba con Bastion (recomendado para validar conectividad)
azd env set AZURE_DEPLOY_VM "true"
# Nota: VM_USER_PASSWORD se establece interactivamente durante azd up
# o explícitamente:
# azd env set VM_USER_PASSWORD "P@ssw0rd!ADP2026"

# Function App: Dedicated recomendado en producción (no FlexConsumption)
azd env set FUNCTION_APP_HOST_PLAN "Dedicated"
azd env set FUNCTION_APP_SKU "S2"

# Características opcionales
azd env set AI_VISION_ENABLED "false"
azd env set AOAI_MULTI_MODAL "false"
```

**Configuración avanzada — Reutilizar VNet existente de Landing Zone:**

```bash
# Reutilizar VNet existente (AILZ real)
azd env set VNET_REUSE "true"
azd env set VNET_RESOURCE_GROUP_NAME "rg-networking-spoke"
azd env set VNET_NAME "vnet-spoke-eastus2"

# Reutilizar Log Analytics Workspace corporativo
azd env set LOG_ANALYTICS_WORKSPACE_REUSE "true"
azd env set LOG_ANALYTICS_WORKSPACE_ID \
  "/subscriptions/<SUB_ID>/resourceGroups/<RG>/providers/Microsoft.OperationalInsights/workspaces/<NAME>"

# Reutilizar Application Insights corporativo
azd env set APP_INSIGHTS_REUSE "true"
azd env set APP_INSIGHTS_RESOURCE_GROUP_NAME "rg-monitoring"
azd env set APP_INSIGHTS_NAME "appi-corp-prod"

# Reutilizar AI Foundry/AOAI existente (si ya hay uno en la AILZ)
azd env set AOAI_REUSE "true"
azd env set AOAI_RESOURCE_GROUP_NAME "rg-aiservices"
azd env set AOAI_NAME "aoai-corp-eastus2"

# VPN Gateway (solo si se necesita conectividad on-premises)
azd env set AZURE_DEPLOY_VPN "true"
```

### Paso 5 — Validar parámetros antes de desplegar

```bash
# Ver todos los valores del entorno azd
azd env get-values

# Validar el template Bicep (sin desplegar)
az deployment group validate \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  --parameters networkIsolation=true \
  --parameters location="eastus2" \
  --output json

# Hacer un what-if para ver qué se creará
az deployment group what-if \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  --output table
```

### Paso 6 — Ejecutar el despliegue

```bash
# Despliegue completo (infraestructura + código)
azd up

# Durante el despliegue se pedirá:
# - AZURE_ENV_NAME (si no está configurado)
# - AZURE_LOCATION
# - vmUserInitialPassword (si deployVM=true) — introducirla de forma segura

# Para desplegar solo infraestructura (sin código):
azd provision

# Para desplegar solo código (si la infra ya existe):
azd deploy
```

> **Tiempo estimado**: 30-45 minutos para modo AILZ con VM y todas las zonas DNS.

### Paso 7 — Comandos post-despliegue para verificar conectividad

El script `scripts/postDeploy.sh` se ejecuta automáticamente después del despliegue. Sin embargo, desde la **VM de prueba** (acceso vía Azure Bastion), ejecutar:

```powershell
# Dentro de la VM de prueba (Windows):
# Verificar resolución DNS de los Private Endpoints

# Key Vault
nslookup <kv-name>.vault.azure.net
# Debe resolver a 10.0.0.x (IP privada del PE)

# Storage Account
nslookup <storage-name>.blob.core.windows.net
# Debe resolver a 10.0.0.x

# Cosmos DB
nslookup <cosmos-name>.documents.azure.com
# Debe resolver a 10.0.1.x

# AI Foundry
nslookup <aiservices-name>.openai.azure.com
# Debe resolver a 10.0.0.x

# Function App
nslookup <funcapp-name>.azurewebsites.net
# Debe resolver a 10.0.0.x

# Test de conectividad HTTPS
Test-NetConnection -ComputerName "<kv-name>.vault.azure.net" -Port 443
Test-NetConnection -ComputerName "<funcapp-name>.azurewebsites.net" -Port 443
```

```bash
# Desde cualquier máquina con acceso a la VNet, verificar configuración de la Function App:
az functionapp show \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{publicNetworkAccess:publicNetworkAccess, vnetRouteAllEnabled:siteConfig.vnetRouteAllEnabled, dnsServer:siteConfig.customDomains}" \
  --output json

# Verificar que el Event Grid Subscription fue creado por postDeploy.sh
az eventgrid system-topic event-subscription list \
  --system-topic-name <BRONZE_SYSTEM_TOPIC_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --output table
```

---

## 8. Troubleshooting

### Problema 1 — Function App no puede acceder a Storage (Error 403/AuthorizationFailure)

**Síntoma**: Los logs de Function App muestran `AuthorizationFailure` o `This request is not authorized to perform this operation using this permission` al acceder al Storage Account.

**Causa**: El Storage Account tiene `defaultAction=Deny` y el tráfico de salida de la Function App no pasa por la subnet autorizada.

**Diagnóstico**:
```bash
# Verificar que la Function App tiene VNet Integration configurada
az functionapp vnet-integration list \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --output table

# Verificar app settings de red
az functionapp config appsettings list \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "[?name=='WEBSITE_VNET_ROUTE_ALL' || name=='WEBSITE_DNS_SERVER']" \
  --output table
```

**Solución**:
```bash
# Asegurarse de que WEBSITE_VNET_ROUTE_ALL=1 esté configurado
az functionapp config appsettings set \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --settings WEBSITE_VNET_ROUTE_ALL=1 WEBSITE_DNS_SERVER=168.63.129.16

# Verificar que la subnet del Function App tiene regla en el Storage
az storage account show \
  --name <STORAGE_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "networkRuleSet" \
  --output json
```

---

### Problema 2 — DNS no resuelve a IP privada (resuelve a IP pública)

**Síntoma**: `nslookup <recurso>.vault.azure.net` devuelve la IP pública, no una IP `10.0.x.x`.

**Causa**: La zona DNS privada no está vinculada a la VNet, o el cliente no usa el DNS de Azure (`168.63.129.16`).

**Diagnóstico**:
```bash
# Verificar que las zonas DNS privadas están creadas
az network private-dns zone list \
  --resource-group <RESOURCE_GROUP> \
  --output table

# Verificar que cada zona tiene un vnet-link
az network private-dns link vnet list \
  --zone-name "privatelink.vaultcore.azure.net" \
  --resource-group <RESOURCE_GROUP> \
  --output table

# Verificar A records en la zona DNS
az network private-dns record-set a list \
  --zone-name "privatelink.vaultcore.azure.net" \
  --resource-group <RESOURCE_GROUP> \
  --output table
```

**Solución**:
```bash
# Agregar VNet link si falta
az network private-dns link vnet create \
  --zone-name "privatelink.vaultcore.azure.net" \
  --resource-group <RESOURCE_GROUP> \
  --name "vnet-link-manual" \
  --virtual-network <VNET_NAME> \
  --registration-enabled false

# En la VM, forzar flush de caché DNS
ipconfig /flushdns          # Windows
sudo systemd-resolve --flush-caches  # Linux
```

---

### Problema 3 — azd up falla al desplegar con `networkIsolation=true` y VNET_REUSE=true

**Síntoma**: Error `SubnetNotFound` o `InvalidSubnet` durante el despliegue.

**Causa**: Las subnets en la VNet existente no tienen las propiedades necesarias (delegación, tamaño correcto).

**Diagnóstico**:
```bash
# Listar subnets y su configuración
az network vnet subnet list \
  --vnet-name <VNET_NAME> \
  --resource-group <VNET_RG> \
  --query "[].{name:name, prefix:addressPrefix, delegations:delegations[0].serviceName}" \
  --output table
```

**Solución**: Asegurarse de que:
1. La subnet para el Function App tiene delegación a `Microsoft.Web/serverFarms`
2. Cada subnet tiene un espacio `/26` o mayor (al menos 64 IPs)
3. No hay NSG con regla que bloquee el puerto 443 entre subnets

```bash
# Agregar delegación a subnet existente
az network vnet subnet update \
  --vnet-name <VNET_NAME> \
  --resource-group <VNET_RG> \
  --name <APP_SERVICES_SUBNET> \
  --delegations Microsoft.Web/serverFarms
```

---

### Problema 4 — Function App no aparece en el portal / funciones no visibles

**Síntoma**: `azd deploy` exitoso, pero el Portal no muestra las funciones.

**Causa más común**: La Function App no puede autenticarse al Storage Account de runtime (`AzureWebJobsStorage`).

**Diagnóstico**:
```bash
# Revisar log stream de la Function App
az webapp log tail \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP>

# Verificar que Managed Identity tiene el rol correcto en el func storage
az role assignment list \
  --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
  --scope "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<FUNC_STORAGE>" \
  --output table
```

**Solución**: Asignar roles faltantes a la Managed Identity del Function App:
```bash
# Storage Blob Data Contributor
az role assignment create \
  --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<FUNC_STORAGE>"

# Storage Queue Data Contributor
az role assignment create \
  --assignee <MANAGED_IDENTITY_PRINCIPAL_ID> \
  --role "Storage Queue Data Contributor" \
  --scope "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<FUNC_STORAGE>"
```

---

### Problema 5 — VPN Gateway tarda demasiado en desplegarse

**Síntoma**: El despliegue se queda bloqueado en `vpnGateway` durante 30-45 minutos.

**Causa**: Los VPN Gateways de Azure tardan entre 25-45 minutos en provisionarse. Es el comportamiento esperado.

**Acción**: Esperar. Si falla, re-ejecutar `azd provision`. Si persiste, verificar cuota de VPN Gateways en la suscripción:

```bash
az network list-usages \
  --location eastus2 \
  --query "[?name.value=='VirtualNetworkGateways']" \
  --output table
```

---

### Problema 6 — Error al crear Private Endpoint: `PrivateEndpointCreationNotAllowedByPolicy`

**Síntoma**: El despliegue falla con error de Azure Policy.

**Causa**: Existe una Azure Policy en la AILZ que bloquea la creación de Private Endpoints sin ciertos tags o en subnets no autorizadas.

**Diagnóstico**:
```bash
# Identificar qué políticas están bloqueando
az policy assignment list \
  --resource-group <RESOURCE_GROUP> \
  --output json | grep -i "privateEndpoint\|private-endpoint"

# Revisar logs de actividad del despliegue
az monitor activity-log list \
  --resource-group <RESOURCE_GROUP> \
  --start-time "2026-03-01T00:00:00Z" \
  --query "[?operationName.value=='Microsoft.Network/privateEndpoints/write' && status.value=='Failed']" \
  --output json
```

**Solución**: Coordinar con el equipo de Platform Engineering para:
- Agregar una excepción de Policy para el Resource Group de destino, o
- Agregar los tags requeridos al parámetro `deploymentTags` en `main.parameters.json`

---

### Problema 7 — Cosmos DB no accesible desde la Function App

**Síntoma**: La Function App devuelve error de conexión a Cosmos DB: `ServiceUnavailable` o `RequestTimedOut`.

**Diagnóstico**:
```bash
# Desde la VM de prueba:
nslookup <cosmos-account>.documents.azure.com
# Debe retornar IP en 10.0.1.x

# Verificar que el PE de Cosmos DB está en estado Approved
az network private-endpoint-connection list \
  --name <cosmos-account> \
  --resource-group <RESOURCE_GROUP> \
  --type "Microsoft.DocumentDB/databaseAccounts" \
  --query "[].{name:name, status:privateLinkServiceConnectionState.status}" \
  --output table
```

**Solución**: Si el PE está en estado `Pending`, aprobarlo manualmente:
```bash
az network private-endpoint-connection approve \
  --resource-name <cosmos-account> \
  --resource-group <RESOURCE_GROUP> \
  --name <PE_CONNECTION_NAME> \
  --type "Microsoft.DocumentDB/databaseAccounts" \
  --description "Approved for AI Document Processor"
```

---

### Problema 8 — Log Analytics no recibe telemetría de Application Insights

**Síntoma**: Los logs de Application Insights están vacíos en modo AILZ.

**Causa**: El AMPLS (Azure Monitor Private Link Scope) requiere que el Log Analytics Workspace y Application Insights estén vinculados a él, y el PE del AMPLS debe estar operativo.

**Diagnóstico**:
```bash
# Verificar el Private Link Scope
az monitor private-link-scope show \
  --name <AMPLS_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{name:name, resources:scopedResources}" \
  --output json

# Verificar PE del AMPLS
az network private-endpoint show \
  --name <LOG_ANALYTICS_PE_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{name:name, provisioningState:provisioningState, customDnsConfigs:customDnsConfigs}" \
  --output json
```

---

## 9. Validación del Despliegue

### Checklist Post-Despliegue

Ejecutar desde dentro de la VNet (VM de prueba via Azure Bastion):

#### Infraestructura de Red

```bash
# [ ] VNet creada con subnets correctas
az network vnet show \
  --name <VNET_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{name:name, addressSpace:addressSpace.addressPrefixes, subnets:subnets[].name}" \
  --output json

# [ ] Zonas DNS privadas creadas y vinculadas (debe mostrar 15 zonas)
az network private-dns zone list \
  --resource-group <RESOURCE_GROUP> \
  --query "length(@)" \
  --output tsv

# [ ] Private Endpoints en estado Succeeded
az network private-endpoint list \
  --resource-group <RESOURCE_GROUP> \
  --query "[].{name:name, state:provisioningState, connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table
```

#### Servicios Azure

```bash
# [ ] Function App en estado Running con VNet Integration
az functionapp show \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{state:state, publicNetworkAccess:publicNetworkAccess, httpsOnly:httpsOnly}" \
  --output json

# [ ] Key Vault: publicNetworkAccess=Disabled
az keyvault show \
  --name <KEY_VAULT_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "properties.{publicNetworkAccess:publicNetworkAccess, enableSoftDelete:enableSoftDelete}" \
  --output json

# [ ] Storage Account: defaultAction=Deny
az storage account show \
  --name <STORAGE_ACCOUNT_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "networkRuleSet.{defaultAction:defaultAction, bypass:bypass}" \
  --output json

# [ ] Cosmos DB: publicNetworkAccess=Disabled
az cosmosdb show \
  --name <COSMOS_ACCOUNT_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{publicNetworkAccess:publicNetworkAccess, consistencyPolicy:consistencyPolicy.defaultConsistencyLevel}" \
  --output json

# [ ] AI Foundry: sin acceso público
az cognitiveservices account show \
  --name <AI_SERVICES_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "{publicNetworkAccess:properties.publicNetworkAccess, provisioningState:properties.provisioningState}" \
  --output json
```

#### Identidad y RBAC

```bash
# [ ] Managed Identity del Function App existe
az identity show \
  --name "uai-<FUNCTION_APP_NAME>" \
  --resource-group <RESOURCE_GROUP> \
  --query "{name:name, principalId:principalId, clientId:clientId}" \
  --output json

# [ ] Role assignments de la Managed Identity
MANAGED_IDENTITY_PRINCIPAL=$(az identity show \
  --name "uai-<FUNCTION_APP_NAME>" \
  --resource-group <RESOURCE_GROUP> \
  --query principalId \
  --output tsv)

az role assignment list \
  --assignee "$MANAGED_IDENTITY_PRINCIPAL" \
  --resource-group <RESOURCE_GROUP> \
  --query "[].{role:roleDefinitionName, scope:scope}" \
  --output table
# Debe incluir: Storage Blob Data Owner, Storage Queue Data Contributor,
# Storage Table Data Contributor, Key Vault Secrets User,
# Cognitive Services User, App Configuration Data Owner, Cosmos DB Built-in Data Contributor
```

#### Conectividad Funcional

```bash
# [ ] Event Grid Subscription activa (desde Azure CLI normal, no requiere VNet)
az eventgrid system-topic event-subscription show \
  --system-topic-name <BRONZE_SYSTEM_TOPIC_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --name "bronze-blob-created-<FUNCTION_APP_NAME>" \
  --query "{name:name, provisioningState:provisioningState, endpointType:destination.endpointType}" \
  --output json

# [ ] Test funcional: subir un archivo a bronze y verificar procesamiento
az storage blob upload \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --container-name "bronze" \
  --name "test-document.pdf" \
  --file "./data/sampleRequest.json" \
  --auth-mode login

# Verificar que el Function App procesó el archivo (esperar ~30 segundos)
az monitor app-insights query \
  --app <APP_INSIGHTS_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --analytics-query "traces | where timestamp > ago(5m) | order by timestamp desc | take 20" \
  --output table
```

#### Resumen de Validación

| Componente | Comando de validación | Estado esperado |
|---|---|---|
| VNet + 5 subnets | `az network vnet show` | `Succeeded` |
| 15 zonas DNS privadas | `az network private-dns zone list` | 15 zonas |
| Todos los PEs | `az network private-endpoint list` | `Succeeded` + `Approved` |
| Function App | `az functionapp show` | `Running` + `Disabled` (public) |
| Key Vault | `az keyvault show` | `publicNetworkAccess=Disabled` |
| Storage | `az storage account show` | `networkRuleSet.defaultAction=Deny` |
| Cosmos DB | `az cosmosdb show` | `publicNetworkAccess=Disabled` |
| RBAC Managed Identity | `az role assignment list` | 7+ roles asignados |
| Event Grid Subscription | `az eventgrid ... show` | `Succeeded` + `EventGridSchema` |
| DNS resolution (VM) | `nslookup` desde VM | IP 10.0.x.x (no IP pública) |
| Test de procesamiento | Upload a `bronze` + query AppInsights | Logs de orquestación visibles |
