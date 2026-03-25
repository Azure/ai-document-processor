# AI Document Processor — Análisis Completo de Referencia para LLMs

> **Tipo de documento**: Referencia única y exhaustiva para agentes de IA y desarrolladores  
> **Uso**: Puede servir como ÚNICO contexto de un LLM para responder cualquier pregunta técnica sobre el proyecto  
> **Repositorio**: [Azure/ai-document-processor](https://github.com/Azure/ai-document-processor)  
> **Licencia**: MIT  
> **Runtime**: Python 3.11 sobre Azure Functions v4 (Durable Functions)  
> **Última actualización**: Marzo 2026

---

## Tabla de Contenidos

1. [¿Qué es AI Document Processor?](#1-qué-es-ai-document-processor)
2. [Conceptos Clave](#2-conceptos-clave)
3. [Capacidades Completas](#3-capacidades-completas)
4. [Prerrequisitos](#4-prerrequisitos)
5. [Arquitectura Final](#5-arquitectura-final)
6. [Fuera de Alcance](#6-fuera-de-alcance)
7. [Escenarios de Ejemplo](#7-escenarios-de-ejemplo)
8. [Índice de Samples Incluidos](#8-índice-de-samples-incluidos)

---

## 1. ¿Qué es AI Document Processor?

### Descripción en una frase

AI Document Processor (ADP) es un acelerador de Azure que automatiza la extracción, análisis y estructuración de documentos heterogéneos (PDF, Word, imágenes, audio) mediante Azure Durable Functions y modelos de lenguaje de Azure OpenAI, eliminando el procesamiento manual y reduciendo el tiempo de extracción de horas a ~30 segundos.

### Propuesta de valor principal

- **Scaffolding productivo**: No es un producto terminado, sino una base extensible sobre la cual los desarrolladores construyen pipelines personalizados de procesamiento documental.
- **Infraestructura as Code**: Un solo comando (`azd up`) aprovisiona todos los servicios Azure con Bicep, incluyendo RBAC automático con Managed Identities (zero secrets).
- **Dual mode**: Soporta despliegue público simple y despliegue enterprise con red privada (VNet, Private Endpoints, Bastion).
- **Modularidad**: Cada paso del pipeline (OCR, LLM, escritura) es una actividad Durable Function independiente y reemplazable.

### Ficha técnica

| Atributo | Valor |
|---|---|
| **Repositorio** | `https://github.com/Azure/ai-document-processor` |
| **Licencia** | MIT |
| **Lenguaje** | Python 3.11 |
| **Framework** | Azure Durable Functions (function chaining pattern) |
| **IaC** | Bicep + Azure Developer CLI (`azd`) |
| **Modelo LLM** | `gpt-5-mini` (configurable) via Azure AI Foundry |
| **API Version OpenAI** | `2025-08-07` (configurable a `2024-05-01-preview` en runtime) |
| **Orquestación** | Azure Durable Functions v4, Extension Bundle `[4.*, 5.0.0)` |
| **Patrón** | Datos Bronze → Silver → Gold (Medallion Architecture) |

---

## 2. Conceptos Clave

### 2.1 Pipeline (Canal de procesamiento)

Un pipeline es una cadena de actividades Durable Functions que transforma un documento de entrada (bruto) en datos estructurados de salida. El patrón usado es **function chaining**: cada actividad produce un output que alimenta a la siguiente.

```
Blob en "bronze" → [Actividad 1: Extracción] → [Actividad 2: Análisis LLM] → [Actividad 3: Escritura] → Blob en "silver"
```

### 2.2 Activity (Actividad)

Un paso individual dentro del pipeline. Implementada como una Azure Durable Function Activity (`@bp.activity_trigger`). Cada actividad es idempotente, re-intentable, y tiene responsabilidad única.

```python
# Estructura de una actividad (ejemplo: callAiFoundry.py)
import azure.durable_functions as df

name = "callAoai"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="inputData")
def run(inputData: dict):
    text_result = inputData.get('text_result')
    instance_id = inputData.get('instance_id')
    prompt_json = load_prompts()
    full_user_prompt = prompt_json['user_prompt'] + "\n\n" + text_result
    response_content = run_prompt(instance_id, prompt_json['system_prompt'], full_user_prompt)
    return response_content
```

### 2.3 Orchestrator (Orquestador)

Función que coordina la secuencia de actividades, el manejo de errores y los reintentos. Es la función `process_blob` en `function_app.py`. El orquestador usa `yield context.call_activity_with_retry()` para invocar actividades con retry automático.

```python
@app.function_name(name="process_blob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
    blob_input = context.get_input()
    retry_options = RetryOptions(
        first_retry_interval_in_milliseconds=5000,
        max_number_of_attempts=5
    )
    # Paso 1: Extraer texto (según tipo de archivo)
    text_result = yield context.call_activity_with_retry("runDocIntel", retry_options, blob_input)
    # Paso 2: Analizar con LLM
    aoai_output = yield context.call_activity_with_retry("callAoai", retry_options, call_aoai_input)
    # Paso 3: Escribir resultado
    task_result = yield context.call_activity_with_retry("writeToBlob", retry_options, write_input)
    return {"blob": blob_input, "text_result": aoai_output, "task_result": task_result}
```

### 2.4 Triggers (Disparadores)

El pipeline se inicia de dos formas:

| Trigger | Nombre de función | Uso | Mecanismo |
|---|---|---|---|
| **Blob + EventGrid** | `start_orchestrator_on_blob` | Producción | EventGrid System Topic detecta nuevo blob en `bronze` |
| **Blob Polling** | `start_orchestrator_on_blob_local` | Solo desarrollo local | Polling periódico del contenedor `bronze` (sin EventGrid) |
| **HTTP POST** | `start_orchestrator_http` | Testing y API | POST a `/api/client` con `{"name": "...", "container": "bronze", "uri": "..."}` |

### 2.5 Prompts (Instrucciones IA)

Se definen en un archivo YAML (`data/prompts.yaml`) que se sube al contenedor `prompts` del Storage Account. El archivo debe contener dos claves obligatorias:

```yaml
system_prompt: |
  Instrucciones para el modelo (rol, formato de salida, restricciones)

user_prompt: |
  Prefijo antes del texto extraído del documento
```

El texto extraído del documento se concatena al final del `user_prompt` antes de enviarlo al modelo. Los prompts se pueden actualizar sin redesplegar código.

**Fuent de prompts alternativa**: También soporta cargar prompts desde Cosmos DB (cuando `PROMPT_FILE=COSMOS`) para cambio dinámico en runtime.

### 2.6 Bronze / Silver / Gold (Medallion Architecture)

| Capa | Contenedor | Contenido | Estado |
|---|---|---|---|
| **Bronze** | `bronze` | Documentos originales sin procesar (PDF, Word, audio, imágenes) | Implementado |
| **Silver** | `silver` (configurable via `FINAL_OUTPUT_CONTAINER`) | JSON estructurado generado por el pipeline | Implementado |
| **Gold** | `gold` | Datos refinados y consolidados para reportes | Contenedor creado, lógica por implementar |
| **Prompts** | `prompts` | Archivo `prompts.yaml` con instrucciones para el LLM | Implementado |

### 2.7 Configuration (Configuración centralizada)

La clase `Configuration` (`pipeline/configuration/configuration.py`) abstrae el acceso a parámetros:

1. **Prioridad 1**: Variables de entorno locales (cuando `allow_environment_variables=true`)
2. **Prioridad 2**: Azure App Configuration (endpoint URI o connection string)
3. **Prioridad 3**: Key Vault secrets (referenciados desde App Configuration)
4. **Fallback**: Valor default proporcionado en código

```python
from configuration import Configuration
config = Configuration()
endpoint = config.get_value("AI_SERVICES_ENDPOINT")
# Internamente: primero busca env var, luego App Config, luego falla con excepción
```

### 2.8 BlobMetadata (Metadatos de blob)

Dataclass estandarizada para pasar información del blob entre actividades:

```python
@dataclass
class BlobMetadata:
    name: str       # "bronze/document.pdf" o "document.pdf"
    uri: str        # URL completa del blob
    container: str  # "bronze"
```

### 2.9 Conversation History (Historial de conversaciones)

Cada interacción con Azure OpenAI se registra en Cosmos DB con:
- `conversationId`: ID de la instancia de orquestación
- `role`: system, user, o assistant
- `content`: El texto del mensaje
- `promptTokens`, `completionTokens`, `totalTokens`, `model`: Métricas de uso

Esto permite auditar, debuggear y analizar costos por documento procesado.

---

## 3. Capacidades Completas

### 3.1 Actividades del Pipeline

Cada actividad está implementada como un Blueprint Durable Function en `pipeline/activities/`.

| ID Actividad | Archivo | Descripción | Input | Output | Configuración requerida |
|---|---|---|---|---|---|
| `runDocIntel` | `runDocIntel.py` | Extrae texto de documentos usando Azure Document Intelligence (OCR). Modelo: `prebuilt-read`. Soporta PDF, Word, Excel, PowerPoint, imágenes. | `dict{name, container, uri}` | `str` (párrafos concatenados) | `AI_SERVICES_ENDPOINT` |
| `callAoai` | `callAiFoundry.py` | Envía texto extraído + prompts al modelo LLM y obtiene respuesta estructurada (JSON). Limpia marcadores de código Markdown. | `dict{text_result, instance_id}` | `str` (JSON string) | `OPENAI_API_BASE`, `OPENAI_MODEL`, `OPENAI_API_VERSION`, `PROMPT_FILE` |
| `callAoaiMultiModal` | `callFoundryMultiModal.py` | Convierte PDF/PNG a imágenes base64 y las envía al modelo con capacidad de visión. Usa PyMuPDF para renderizar cada página. | `dict{name, container, uri, instance_id}` | `str` (JSON string) | Idem `callAoai` + `AOAI_MULTI_MODAL=true` |
| `speechToText` | `speechToText.py` | Transcribe archivos de audio usando Azure Speech Service Batch API (v2025-10-15). Polling asíncrono hasta completar. | `dict{name, container, uri}` | `str` (texto transcrito) | `AI_SERVICES_ENDPOINT` |
| `writeToBlob` | `writeToBlob.py` | Escribe el resultado JSON al contenedor de salida (por defecto `silver`). Nombra el output como `{sourcefile}-output.json`. | `dict{json_str, blob_name, final_output_container}` | `dict{success, blob_name, output_blob}` | `FINAL_OUTPUT_CONTAINER` |
| `sharepointLookup` | `sharepointLookup.py` | Stub para búsqueda en SharePoint. No implementado (código comentado). | — | — | — |

### 3.2 Tipos de archivo soportados

| Categoría | Extensiones | Actividad utilizada | Notas |
|---|---|---|---|
| **Documentos** | `.pdf`, `.docx`, `.doc`, `.xlsx`, `.pptx` | `runDocIntel` o `callAoaiMultiModal` | MultiModal opcional para PDFs complejos |
| **Imágenes** | `.jpg`, `.jpeg`, `.png`, `.tiff`, `.bmp` | `runDocIntel` o `callAoaiMultiModal` | MultiModal extrae datos visuales directamente |
| **Audio** | `.wav`, `.mp3`, `.opus`, `.ogg`, `.flac`, `.wma`, `.aac`, `.webm` | `speechToText` | Usa Azure Speech Batch API |
| **Otros** | Cualquier otro | — | Retorna status `skipped` con mensaje de error |

### 3.3 Lógica de enrutamiento del orquestador

El orquestador `process_blob` determina la actividad de extracción según esta lógica:

```
1. ¿AOAI_MULTI_MODAL == "true" AND extensión en document_extensions?
   → SÍ: callAoaiMultiModal (visión directa)
   
2. ¿AI_VISION_ENABLED == "true"?
   → SÍ: (no implementado, pass)
   
3. ¿Extensión en audio_extensions?
   → SÍ: speechToText
   
4. ¿Extensión en document_extensions?
   → SÍ: runDocIntel (OCR estándar)
   
5. Ninguna coincidencia
   → Retorna error "Unsupported file type", status: "skipped"
```

Después de la extracción, SIEMPRE se ejecutan `callAoai` → `writeToBlob`.

### 3.4 Utilidades del Pipeline (`pipelineUtils/`)

| Módulo | Funciones | Descripción |
|---|---|---|
| `azure_openai.py` | `run_prompt(pipeline_id, system_prompt, user_prompt)` | Crea cliente AzureOpenAI con token bearer (Managed Identity), ejecuta chat completion, guarda historial en Cosmos DB. Retorna `response.choices[0].message.content`. |
| `blob_functions.py` | `write_to_blob(container, path, data)`, `get_blob_content(container, path)`, `list_blobs(container)`, `delete_all_blobs_in_container(container)` | Operaciones CRUD sobre Azure Blob Storage con `BlobServiceClient` autenticado por Managed Identity. |
| `db.py` | `save_chat_message(conversation_id, role, content, usage)` | Guarda cada mensaje (system, user, assistant) en el contenedor `conversationhistory` de Cosmos DB. Incluye métricas de tokens y modelo. |
| `prompts.py` | `load_prompts()`, `load_prompts_from_blob(prompt_file)` | Carga el archivo de prompts desde blob storage (`prompts` container) o Cosmos DB. Valida que existan las claves `system_prompt` y `user_prompt`. |
| `__init__.py` | `get_month_date()` | Utilidad auxiliar de fecha. |

### 3.5 Sistema de Configuración

| Parámetro (App Config / Env Var) | Uso en el código | Valores posibles |
|---|---|---|
| `AI_SERVICES_ENDPOINT` | Endpoint del servicio AI (Document Intelligence + Speech) | `https://<name>.cognitiveservices.azure.com/` |
| `OPENAI_API_BASE` | Endpoint de Azure OpenAI | `https://<name>.cognitiveservices.azure.com/` |
| `OPENAI_MODEL` | Nombre del modelo desplegado | `gpt-5-mini`, `gpt-4o`, etc. |
| `OPENAI_API_VERSION` | Versión de la API OpenAI | `2024-05-01-preview` |
| `DATA_STORAGE_ENDPOINT` | Endpoint del Storage Account de datos | `https://<name>.blob.core.windows.net` |
| `DATA_STORAGE_ACCOUNT_NAME` | Nombre del Storage de datos | Auto-generado |
| `FUNC_STORAGE_ACCOUNT_NAME` | Nombre del Storage del Function App | Auto-generado |
| `PROMPT_FILE` | Nombre del archivo de prompts a cargar | `prompts.yaml` o `COSMOS` |
| `FINAL_OUTPUT_CONTAINER` | Contenedor de destino para resultados | `silver` (default) |
| `COSMOS_DB_URI` | URI del Cosmos DB | `https://<name>.documents.azure.com:443/` |
| `COSMOS_DB_DATABASE_NAME` | Nombre de la base de datos Cosmos | `conversationHistoryDB` |
| `COSMOS_DB_CONVERSATION_HISTORY_CONTAINER` | Nombre del contenedor de historial | `conversationhistory` |
| `PROCESSING_FUNCTION_APP_NAME` | Nombre del Function App de procesamiento | Auto-generado |
| `PROCESSING_FUNCTION_APP_URL` | URL del Function App | `<name>.azurewebsites.net` |
| `SAS_TOKEN_EXPIRY_HOURS` | Horas de vigencia de tokens SAS | `24` |
| `USE_SAS_TOKEN` | Si usar tokens SAS para acceso a blobs | `false` (usa Managed Identity) |
| `APP_CONFIGURATION_URI` | URI del Azure App Configuration | `https://<name>.azconfig.io` |
| `AZURE_TENANT_ID` | ID del tenant Azure AD | Auto-configurado |
| `AZURE_CLIENT_ID` | Client ID de la Managed Identity | Auto-configurado |
| `AOAI_MULTI_MODAL` | Activar procesamiento multimodal | `true` / `false` |
| `AI_VISION_ENABLED` | Activar Azure AI Vision | `true` / `false` |

### 3.6 Infraestructura Bicep

El template principal `infra/main.bicep` aprovisiona **todos** los recursos con un solo comando. La IaC está modularizada en `infra/modules/`:

| Módulo Bicep | Ruta | Recurso Azure | Notas |
|---|---|---|---|
| **Main** | `infra/main.bicep` | Orquesta todo el despliegue | ~1650 líneas, controla flujo condicional |
| **AI Foundry** | AVM `avm/ptn/ai-ml/ai-foundry:0.6.0` | Azure AI Foundry + AI Services + modelo `gpt-5-mini` (GlobalStandard, 100 TPM) | Módulo AVM público, maneja PEs internamente |
| **Function App** | AVM `avm/res/web/site:0.16.0` | Azure Function App (Linux, Python) | Soporta Dedicated y FlexConsumption |
| **App Service Plan** | AVM `avm/res/web/serverfarm:0.1.1` | Plan de hosting | FC1, S2, B1, P1v2, etc. |
| **Storage Account (func)** | AVM `avm/res/storage/storage-account:0.25.0` | Storage del runtime del Function App | Deployment container para FlexConsumption |
| **Storage Account (data)** | `modules/storage/storage-account.bicep` | Storage de datos (bronze/silver/gold/prompts) | Custom module |
| **Cosmos DB** | `modules/db/cosmos.bicep` | Azure Cosmos DB (conta + DB + contenedores) | Contenedores: prompts, config, conversationhistory |
| **Key Vault** | `modules/security/key-vault.bicep` | Azure Key Vault | Secretos referenciados desde App Config |
| **App Configuration** | `modules/app_config/appconfig.bicep` | Azure App Configuration | Centraliza toda la config del pipeline |
| **Application Insights** | `modules/management_governance/application-insights.bicep` | Application Insights | Telemetría y tracing |
| **Log Analytics Workspace** | `modules/management_governance/log-analytics-workspace.bicep` | Log Analytics | Retención: 30 días |
| **Event Grid System Topic** | AVM `avm/res/event-grid/system-topic:0.6.1` | Event Grid para blob triggers | Source: Storage Account |
| **VNet** | `modules/network/vnet.bicep` | Virtual Network + 5 subnets + NSGs | Solo si `networkIsolation=true` |
| **Private Endpoints** | `modules/network/private-endpoint.bicep` | PEs para cada servicio | Solo si `networkIsolation=true` |
| **Private DNS Zones** | `modules/network/private-dns-zones.bicep` | 15 zonas DNS privadas | Solo si `networkIsolation=true` |
| **Bastion Host** | AVM `avm/res/network/bastion-host:0.8.0` | Azure Bastion (SKU Standard) | Solo si `deployVM=true` y `networkIsolation=true` |
| **Test VM** | AVM `avm/res/compute/virtual-machine:0.15.0` | VM Windows 11 Enterprise | Solo si `deployVM=true` |
| **VPN Gateway** | `modules/network/vnet-vpn-gateway.bicep` | VPN Gateway | Solo si `deployVPN=true` |
| **Managed Identities** | `modules/security/managed-identity.bicep` | User-Assigned Managed Identities | Para Function App y App Config |
| **RBAC (múltiples)** | `modules/rbac/*.bicep` | Role assignments | Storage, CosmosDB, KeyVault, CogServices, AppConfig |
| **Private Link Scope** | `modules/security/private-link-scope.bicep` | Azure Monitor Private Link Scope | Vincula Log Analytics + AppInsights |

### 3.7 Feature Flags

| Flag | Variable | Efecto |
|---|---|---|
| **Network Isolation** | `AZURE_NETWORK_ISOLATION=true` | Despliega VNet, subnets, NSGs, Private Endpoints, DNS zones. Todo recurso pasa a `publicNetworkAccess=Disabled`. |
| **Deploy VM** | `AZURE_DEPLOY_VM=true` | Despliega VM Windows + Bastion para acceso a la red privada. Solo con `networkIsolation=true`. |
| **Deploy VPN** | `AZURE_DEPLOY_VPN=true` | Agrega Gateway Subnet y VPN Gateway para conectividad on-premises. |
| **Multi-Modal** | `AOAI_MULTI_MODAL=true` | Actividades de documentos usan `callAoaiMultiModal` (visión) en lugar de OCR + texto. |
| **AI Vision** | `AI_VISION_ENABLED=true` | Flag para futuro soporte de Azure AI Vision. Actualmente solo `pass`. |
| **Local Development** | `AZURE_FUNCTIONS_ENVIRONMENT=Development` | Registra trigger de blob por polling (sin EventGrid). Usa credenciales de CLI en vez de MI. |

### 3.8 Reuso de Recursos

El template soporta reutilizar **17 tipos de recursos existentes** via parámetros `*_REUSE=true`:

| Recurso reutilizable | Flag | Parámetros adicionales |
|---|---|---|
| Azure OpenAI / AI Foundry | `AOAI_REUSE` | `AOAI_RESOURCE_GROUP_NAME`, `AOAI_NAME` |
| AI Services | `AI_SERVICES_REUSE` | `AI_SERVICES_RESOURCE_GROUP_NAME`, `AI_SERVICES_NAME` |
| Application Insights | `APP_INSIGHTS_REUSE` | `APP_INSIGHTS_RESOURCE_GROUP_NAME`, `APP_INSIGHTS_NAME` |
| Log Analytics Workspace | `LOG_ANALYTICS_WORKSPACE_REUSE` | `LOG_ANALYTICS_WORKSPACE_ID` |
| App Service Plan | `APP_SERVICE_PLAN_REUSE` | `APP_SERVICE_PLAN_RESOURCE_GROUP_NAME`, `APP_SERVICE_PLAN_NAME` |
| AI Search | `AI_SEARCH_REUSE` | `AI_SEARCH_RESOURCE_GROUP_NAME`, `AI_SEARCH_NAME` |
| Cosmos DB | `COSMOS_DB_REUSE` | `COSMOS_DB_RESOURCE_GROUP_NAME`, `COSMOS_DB_ACCOUNT_NAME`, `COSMOS_DB_DATABASE_NAME` |
| Key Vault | `KEY_VAULT_REUSE` | `KEY_VAULT_RESOURCE_GROUP_NAME`, `KEY_VAULT_NAME` |
| Storage Account (data) | `STORAGE_REUSE` | `STORAGE_RESOURCE_GROUP_NAME`, `STORAGE_NAME` |
| Virtual Network | `VNET_REUSE` | `VNET_RESOURCE_GROUP_NAME`, `VNET_NAME` |
| Function App (orchestrator) | `ORCHESTRATOR_FUNCTION_APP_REUSE` | `ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME`, `ORCHESTRATOR_FUNCTION_APP_NAME` |
| Function App (data ingestion) | `DATA_INGESTION_FUNCTION_APP_REUSE` | `DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME`, `DATA_INGESTION_FUNCTION_APP_NAME` |
| App Service | `APP_SERVICE_REUSE` | `APP_SERVICE_NAME`, `APP_SERVICE_RESOURCE_GROUP_NAME` |
| Storage (orchestrator func) | `ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE` | `ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME`, `ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME` |
| Storage (data ingestion func) | `DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE` | `DATA_INGESTION_FUNCTION_APP_STORAGE_NAME`, `DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME` |

### 3.9 Observabilidad y Tracing

El proyecto tiene **enhanced tracing** habilitado en `pipeline/host.json`:

```json
{
  "extensions": {
    "durableTask": {
      "tracing": {
        "traceInputsAndOutputs": true,
        "traceReplayEvents": true,
        "distributedTracingEnabled": true,
        "version": "V2"
      }
    }
  }
}
```

| Capacidad | Detalle |
|---|---|
| `traceInputsAndOutputs` | Logs de datos reales pasados a/desde actividades (prompts, payloads, URIs) |
| `traceReplayEvents` | Logs de reintentos y re-ejecución del orquestador |
| `distributedTracingEnabled` | Correlación de todas las trazas con un solo `operation_Id` end-to-end |
| Historial de conversación | Cada system_prompt, user_prompt y assistant response almacenada en Cosmos DB |
| Token usage tracking | `promptTokens`, `completionTokens`, `totalTokens`, `model` por cada llamada |

**Queries KQL útiles:**

```kusto
// End-to-end trace de un documento
let opId = "<operation_Id>";
union requests, dependencies, traces
| where operation_Id == opId
| project timestamp, itemType, name = coalesce(name, "trace"), message = substring(message, 0, 150)
| order by timestamp asc

// Reintentos y actividades fallidas
traces 
| where message contains "scheduled" or message contains "Retry" or message contains "failed"
| project timestamp, message | order by timestamp desc | take 50

// Inputs/Outputs de actividades
traces 
| where message contains "Input:" or message contains "Output:"
| project timestamp, message | order by timestamp desc
```

### 3.10 Extensibilidad

#### Crear una nueva actividad

1. Crear archivo `pipeline/activities/myActivity.py`:

```python
import azure.durable_functions as df

name = "myActivity"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="inputData")
def run(inputData: dict):
    # Tu lógica aquí
    result = process(inputData)
    return result
```

2. Registrar el Blueprint en `function_app.py`:

```python
from activities import myActivity
app.register_functions(myActivity.bp)
```

3. Invocar desde el orquestador:

```python
result = yield context.call_activity_with_retry("myActivity", retry_options, input_data)
```

#### Modificar los prompts (sin código)

1. Editar `data/prompts.yaml` con las nuevas instrucciones
2. Subir al contenedor `prompts` del Storage Account:

```bash
az storage blob upload \
  --account-name <STORAGE_ACCOUNT> \
  --container-name "prompts" \
  --name prompts.yaml \
  --file ./data/prompts.yaml \
  --auth-mode login
```

#### Cambiar el modelo LLM

Modificar la variable `OPENAI_MODEL` en App Configuration o en las variables de entorno. El despliegue Bicep actual provisiona `gpt-5-mini` con SKU `GlobalStandard` y 100K TPM.

---

## 4. Prerrequisitos

### 4.1 Servicios Azure requeridos

| Servicio | SKU recomendado | Mínimo | Notas |
|---|---|---|---|
| **Azure Function App** | Dedicated S2 (estable) o Flex Consumption FC1 (serverless) | B1 (mínimo para Always On) | FC1 escala a 0, pero tiene cold starts |
| **Azure AI Foundry** | `gpt-5-mini` GlobalStandard, 100K TPM | Cualquier GPT con capacidad disponible | Ubicar en región con cuota disponible |
| **Azure AI Services** | S0 Standard | S0 | Document Intelligence + Speech to Text |
| **Azure Storage Account** | Standard LRS | Standard LRS | Dos cuentas: datos y función |
| **Azure App Configuration** | Free tier | Free | Standard para producción con alto volumen |
| **Azure Key Vault** | Standard | Standard | Sin premium features por defecto |
| **Azure Cosmos DB** | Serverless | Serverless (400 RU/s burst) | Provisioned para producción |
| **Application Insights** | Pay-per-use | — | Incluido en Log Analytics |
| **Log Analytics Workspace** | Pay-per-use | — | 30 días de retención |

### 4.2 Toolchain de desarrollo

| Herramienta | Versión mínima | Comando de verificación |
|---|---|---|
| Azure CLI | 2.55+ | `az --version` |
| Azure Developer CLI (azd) | 1.5+ | `azd version` |
| Python | 3.11+ | `python --version` |
| Azure Functions Core Tools | 4.x | `func --version` |
| Git | 2.x | `git --version` |
| jq (opcional, para scripts) | 1.6+ | `jq --version` |

### 4.3 Permisos y roles necesarios

| Contexto | Rol mínimo | Para qué |
|---|---|---|
| Ejecutar `azd up` | **Contributor** + **User Access Administrator** en el Resource Group | Crear recursos + asignar roles RBAC a Managed Identities |
| Red privada (AILZ) | + **Network Contributor** en la VNet | Crear Private Endpoints en subnets existentes |
| La Managed Identity del Function App recibe automáticamente: | | |
| — Storage | Storage Blob Data Owner, Queue/Table/File Contributor | Acceso a datos y runtime |
| — Key Vault | Key Vault Secrets User | Lectura de secretos |
| — Cosmos DB | Cosmos DB Built-in Data Contributor | Escritura de historial |
| — AI Services | Cognitive Services User, OpenAI User | Llamadas a modelos y OCR |
| — App Configuration | App Configuration Data Owner | Lectura de configuración |

### 4.4 Dependencias Python

Principales dependencias del proyecto (`pipeline/requirements.txt`):

| Paquete | Versión | Propósito |
|---|---|---|
| `azure-functions` | 1.21.3 | SDK de Azure Functions |
| `azure-functions-durable` | 1.4.0 | Durable Functions para orchestration |
| `azure-identity` | 1.19.0 | DefaultAzureCredential (MI + CLI) |
| `azure-ai-documentintelligence` | 1.0.2 | OCR y extracción de documentos |
| `azure-storage-blob` | 12.24.0 | Operaciones con blobs |
| `azure-cosmos` | 4.9.0 | Cosmos DB SDK |
| `azure-keyvault-secrets` | 4.10.0 | Lectura de secretos |
| `azure-appconfiguration-provider` | 2.0.1 | Azure App Configuration client |
| `openai` | 1.70.0 | Azure OpenAI SDK |
| `PyMuPDF` (fitz) | 1.26.6 | Renderización de páginas PDF a imágenes |
| `PyPDF2` | 3.0.1 | Manipulación de PDFs |
| `PyYAML` | 6.0.2 | Parsing de archivos de prompts YAML |
| `requests` | 2.32.3 | HTTP client (Speech to Text Batch API) |
| `tenacity` | 9.0.0 | Retry logic en Configuration |
| `pydantic` | 2.11.2 | Validación de datos |

### 4.5 Cuotas y límites relevantes

| Recurso | Límite | Impacto |
|---|---|---|
| Azure OpenAI TPM (tokens por minuto) | Varía por modelo y región | Puede causar 429 si se procesan muchos documentos en paralelo |
| Azure Document Intelligence | 15 TPS (transacciones por segundo) en S0 | Cola de procesamiento para volúmenes altos |
| Durable Functions max retries | Configurado a 5 intentos | Falla permanente después de 5 intentos |
| Flex Consumption max instances | 100 | Límite superior de escala automática |
| Cosmos DB Serverless | 5000 RU/s burst | Puede limitar en picos de escritura de historial |
| VPN Gateway provisioning | 25-45 minutos | Tiempo de despliegue, no funcional |
| Private Endpoints per subscription | 1000 (default) | Verificar cuota antes de despliegue AILZ |

---

## 5. Arquitectura Final

### 5.1 Diagrama de Componentes

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AZURE RESOURCE GROUP                                 │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │               AZURE FUNCTION APP (Python 3.11)                  │     │
│  │                                                                  │     │
│  │  Triggers                    Orchestrator        Activities      │     │
│  │  ┌──────────────────┐       ┌──────────┐       ┌────────────┐  │     │
│  │  │ start_orch_blob  │──────►│          │──────►│runDocIntel │  │     │
│  │  │ (EventGrid)      │       │ process  │       ├────────────┤  │     │
│  │  ├──────────────────┤       │  _blob   │──────►│callAoai    │  │     │
│  │  │ start_orch_http  │──────►│          │       ├────────────┤  │     │
│  │  │ (HTTP POST)      │       │          │──────►│writeToBlob │  │     │
│  │  └──────────────────┘       └──────────┘       ├────────────┤  │     │
│  │                                                 │speechToText│  │     │
│  │                                                 ├────────────┤  │     │
│  │                                                 │callAoai    │  │     │
│  │                                                 │ MultiModal │  │     │
│  │                                                 └────────────┘  │     │
│  └────────────────────────────────────────────────────────────────┘     │
│           │              │              │               │                │
│           ▼              ▼              ▼               ▼                │
│  ┌──────────────┐ ┌───────────┐ ┌────────────┐ ┌──────────────┐       │
│  │ Blob Storage │ │ Cosmos DB │ │ AI Foundry │ │App Config    │       │
│  │ (Data)       │ │           │ │ + AI Svcs  │ │+ Key Vault   │       │
│  │              │ │           │ │            │ │              │       │
│  │ bronze/      │ │ convHist  │ │ gpt-5-mini │ │ parámetros   │       │
│  │ silver/      │ │ prompts   │ │ Doc Intel  │ │ secretos     │       │
│  │ gold/        │ │ config    │ │ Speech     │ │              │       │
│  │ prompts/     │ │           │ │            │ │              │       │
│  └──────────────┘ └───────────┘ └────────────┘ └──────────────┘       │
│           │                                                              │
│           ▼                                                              │
│  ┌──────────────┐     ┌───────────────────────────┐                     │
│  │ Event Grid   │     │ Application Insights       │                     │
│  │ System Topic │     │ + Log Analytics Workspace  │                     │
│  │ (blob events)│     │ (telemetría y tracing)     │                     │
│  └──────────────┘     └───────────────────────────┘                     │
│                                                                          │
│  ┌──────────────────── Solo si networkIsolation=true ──────────────┐   │
│  │  VNet 10.0.0.0/23                                                │   │
│  │  ├─ aiSubnet (10.0.0.0/26) — PEs + VM                           │   │
│  │  ├─ appServicesSubnet (10.0.0.128/26) — VNet Integration         │   │
│  │  ├─ appIntSubnet (10.0.0.64/26) — integración alternativa        │   │
│  │  ├─ databaseSubnet (10.0.1.0/26) — PE Cosmos DB                  │   │
│  │  ├─ AzureBastionSubnet (10.0.1.128/26) — Bastion Host            │   │
│  │  └─ gatewaySubnet (10.0.1.64/26) — VPN Gateway (opcional)        │   │
│  │  + 15 Private DNS Zones vinculadas                                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Mapa de Comunicación entre Servicios

| Origen | Destino | Protocolo | Puerto | Autenticación | Dirección |
|---|---|---|---|---|---|
| Event Grid | Function App | HTTPS webhook | 443 | `blobs_extension` system key | Event Grid → Function |
| Function App → | AI Foundry (OpenAI API) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | AI Services (Doc Intel) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | AI Services (Speech) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | Blob Storage (data) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | Blob Storage (func) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | Cosmos DB | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | App Configuration | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | Key Vault (via AppConfig) | HTTPS | 443 | Bearer token (MI) | Salida |
| Function App → | Application Insights | HTTPS | 443 | Instrumentation Key | Salida |
| Usuario/API | Function App | HTTPS | 443 | Function Key | Entrada |

### 5.3 Flujo de Datos End-to-End

```
                                                  ┌─────────────┐
                                                  │ prompts.yaml│
                                                  │ (blob:      │
                                                  │  prompts/)  │
                                                  └──────┬──────┘
                                                         │ se carga en paso 2
                                                         ▼
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Archivo  │     │ Event    │     │ Orchestr │     │ Extract  │     │ LLM Call │
│ subido a │────►│ Grid     │────►│ ator     │────►│ Text     │────►│ callAoai │
│ bronze/  │     │ Trigger  │     │(process_ │     │(runDoc/  │     │          │
│          │     │          │     │ blob)    │     │ speech/  │     │          │
└──────────┘     └──────────┘     └──────────┘     │ multi)   │     └────┬─────┘
                                                    └──────────┘          │
                                                                          ▼
                                                    ┌──────────┐     ┌──────────┐
                                                    │ Cosmos DB│◄────│ save_chat│
                                                    │ (hist)   │     │ _message │
                                                    └──────────┘     └──────────┘
                                                                          │
                                                                          ▼
                                  ┌──────────┐     ┌──────────────────────────┐
                                  │ JSON en  │◄────│ writeToBlob              │
                                  │ silver/  │     │ {sourcefile}-output.json  │
                                  └──────────┘     └──────────────────────────┘
```

### 5.4 Ciclo de Vida de una Tarea

| Fase | Evento | Estado (Durable Functions) | Datos |
|---|---|---|---|
| 1. Ingesta | Blob creado en `bronze/` | — | Archivo original |
| 2. Trigger | Event Grid notifica Function App | — | Blob metadata (name, uri) |
| 3. Inicio | Orchestrator crea nueva instancia | `Running` | `instance_id` generado |
| 4. Extracción | Activity extrae texto del documento | `Running` | `text_result` (string) |
| 5. Análisis | Activity envía texto + prompts a LLM | `Running` | `aoai_output` (JSON string) |
| 6. Escritura | Activity escribe JSON a `silver/` | `Running` | `{sourcefile}-output.json` |
| 7. Fin | Orchestrator retorna resultado | `Completed` | `{blob, text_result, task_result}` |
| Alt. Error | Actividad falla después de 5 retries | `Failed` | Exception details |

### 5.5 Esquema de Base de Datos (Cosmos DB)

**Database**: `conversationHistoryDB`

**Contenedores:**

| Contenedor | Partition Key | Uso |
|---|---|---|
| `conversationhistory` | `/conversationId` | Historial de mensajes LLM |
| `promptscontainer` | `/id` | Configuración de prompts (alternativa a YAML) |
| `config` | `/id` | Configuración dinámica del pipeline |

**Esquema de documento — conversationhistory:**

```json
{
  "id": "uuid-v4",
  "conversationId": "orchestration-instance-id",
  "role": "system | user | assistant",
  "content": "texto del mensaje",
  "timestamp": "2026-03-25T12:00:00.000Z",
  "promptTokens": 150,
  "completionTokens": 500,
  "totalTokens": 650,
  "model": "gpt-5-mini"
}
```

**Esquema de documento — promptscontainer:**

```json
{
  "id": "hash1",
  "name": "first_prompt",
  "system_prompt": "...",
  "user_prompt": "..."
}
```

### 5.6 Modos de Despliegue Comparados

| Aspecto | Modo Público | Modo AILZ (Red Privada) |
|---|---|---|
| **Parámetro clave** | `networkIsolation=false` | `networkIsolation=true` |
| **Endpoints** | Públicos (protegidos con Function Key) | Private Endpoints (sin exposición a internet) |
| **VNet** | No se crea | `10.0.0.0/23` con 5 subnets + NSGs |
| **DNS** | DNS público de Azure | 15 Private DNS Zones vinculadas a VNet |
| **Acceso al portal** | Inmediato desde browser | Requiere VM/VPN/Bastion |
| **Plan de hosting** | Dedicated o FlexConsumption | Dedicated recomendado |
| **Tiempo de despliegue** | ~10-15 min | ~30-45 min |
| **Costo adicional** | — | VM ($100-200/mes), Bastion (~$140/mes), VPN Gateway (~$140/mes) |
| **Postura de seguridad** | Media | Alta (Zero Trust) |

| Aspecto | Plan Dedicated | Plan FlexConsumption |
|---|---|---|
| **SKUs** | B1, B2, S1, S2, S3, P1v2, P2v2, P3v2 | FC1 |
| **Scaling** | Manual o Auto-scale | Automático 0-100 instancias |
| **Always On** | Sí | No (cold starts posibles) |
| **SSH / Debug** | Disponible | No disponible |
| **Despliegue** | SCM build o zip deploy | Blob container deployment |
| **Costo** | Fijo mensual | Pay-per-execution |

### 5.7 Modelo de Seguridad

| Capa | Mecanismo | Detalle |
|---|---|---|
| **Identidad** | User-Assigned Managed Identity | La Function App tiene una MI que accede a todos los servicios sin secretos |
| **Autenticación a servicios** | Bearer token via `DefaultAzureCredential` | En producción usa MI; en desarrollo local usa CLI credential |
| **Autenticación de entrada** | Function Key (`AuthLevel.FUNCTION`) | HTTP endpoint protegido con key en query string o header |
| **Autorización RBAC** | 10+ role assignments automáticos | Storage, KeyVault, Cosmos, CogServices, AppConfig |
| **Secretos** | Key Vault (referenciados desde App Config) | Zero hardcoded secrets en código |
| **Red** | VNet + NSGs + Private Endpoints (opcional) | Todo tráfico interno; sin exposición a internet |
| **TLS** | TLS 1.2 mínimo (enforced) | En Storage, Function App, Key Vault |
| **Blob access** | Anónimo deshabilitado (`allowBlobPublicAccess=false`) | Sin acceso público a blobs |

---

## 6. Fuera de Alcance

El siguiente listado documenta lo que ADP **NO** hace nativamente, con estimación de esfuerzo para implementarlo.

| # | Funcionalidad ausente | Descripción | Esfuerzo | Librerías / Enfoque sugerido |
|---|---|---|---|---|
| 1 | **Frontend / UI web** | No incluye interfaz de usuario para subir documentos o ver resultados. Solo API y blob storage. | Media (2-4 días) | React + Azure Static Web Apps, o Power Apps conectado al blob silver |
| 2 | **Procesamiento paralelo de múltiples actividades** | El orquestador ejecuta actividades secuencialmente (chaining). No usa fan-out/fan-in nativo. | Baja (1 día) | `context.task_all()` de Durable Functions para ejecutar actividades en paralelo |
| 3 | **Indexación y búsqueda semántica (RAG)** | No indexa los documentos procesados en un search index. | Media (2-3 días) | Azure AI Search + embeddings, crear actividad `indexToSearch.py` |
| 4 | **Enrutamiento condicional por contenido** | La decisión de actividad se basa solo en la extensión del archivo, no en el contenido. | Baja (1 día) | Agregar actividad de clasificación con LLM antes de la extracción |
| 5 | **Capa Gold de datos** | El contenedor `gold` está creado en storage pero no hay lógica que escriba allí. | Baja (0.5 días) | Agregar actividad de post-procesamiento que lea `silver` y escriba `gold` |
| 6 | **Notificaciones (email, Teams, webhook)** | No notifica al usuario cuando un documento ha sido procesado. | Baja (0.5 días) | Azure Logic App, SendGrid, o webhook en una nueva actividad |
| 7 | **Procesamiento por lotes (batch)** | El HTTP trigger procesa un documento a la vez. No hay endpoint de batch. | Baja (1 día) | Sub-orchestration con `context.task_all()` recibiendo array de blobs |
| 8 | **Versionado de prompts** | Los prompts se sobrescriben en blob. No hay historial de versiones ni A/B testing. | Media (1-2 días) | Cosmos DB con versionado por timestamp, o Git-based prompt management |
| 9 | **Autenticación de usuario (OIDC/Entra ID)** | El endpoint HTTP solo usa Function Key. No hay autenticación de usuario final. | Media (1-2 días) | Azure AD Easy Auth en Function App + bearer token validation |
| 10 | **Manejo de documentos >10MB** | Speech to Text batch API funciona con URLs, pero Document Intelligence tiene límites de tamaño. | Media (1-2 días) | Split de PDFs grandes con PyPDF2 antes de enviar a Doc Intelligence |
| 11 | **Multi-idioma automático** | El Speech to Text usa `locale: "en-US"` hardcoded. No detecta idioma. | Baja (0.5 días) | Usar locale detection de Azure AI Language, o pasar locale como parámetro |
| 12 | **CI/CD pipeline** | No incluye GitHub Actions ni Azure DevOps pipelines. | Media (1 día) | Template de GitHub Actions con `azd deploy` |
| 13 | **Tests unitarios / integración** | No hay test suite automatizada. | Media (2-3 días) | pytest + mocks para actividades; integration tests con Storage emulator |
| 14 | **Rate limiting y throttling** | Depende del retry nativo; no hay circuit breaker explícito. | Baja (1 día) | Tenacity decorators con backoff exponencial en `azure_openai.py` |
| 15 | **Soporte para Terraform** | Solo Bicep. No hay templates de Terraform. | Alta (3-5 días) | Reescribir `infra/` en HCL; los módulos AVM tienen equivalentes Terraform |

---

## 7. Escenarios de Ejemplo

Cada escenario incluye el `prompts.yaml` completo y funcional que se debe subir al contenedor `prompts`. El pipeline de Function App no necesita cambios de código para estos casos — solo cambia el archivo de prompts.

### Escenario 1 — Análisis y estructuración de CVs / Resumes (RRHH)

**Sector**: Recursos Humanos  
**Entrada**: PDFs de currículums  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un asistente de RRHH. Analiza el CV proporcionado y extrae la información en formato JSON.
  Devuelve un objeto JSON con esta estructura exacta:
  {
    "nombre_completo": "...",
    "email": "...",
    "telefono": "...",
    "ubicacion": "...",
    "resumen_profesional": "...",
    "experiencia": [
      {
        "empresa": "...",
        "cargo": "...",
        "periodo": "...",
        "logros": ["...", "..."]
      }
    ],
    "educacion": [
      {"institucion": "...", "titulo": "...", "año": "..."}
    ],
    "habilidades_tecnicas": ["...", "..."],
    "idiomas": [{"idioma": "...", "nivel": "..."}],
    "certificaciones": ["...", "..."]
  }
  Responde SOLO con el JSON, sin texto adicional.

user_prompt: |
  Analiza el siguiente CV y extrae la información estructurada:
```

### Escenario 2 — Transcripción y resumen de reuniones (Corporate)

**Sector**: Corporativo / Gobierno  
**Entrada**: Archivos de audio (MP3, WAV)  
**Actividades**: `speechToText` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un asistente ejecutivo. Recibe la transcripción de una reunión y genera un resumen JSON:
  {
    "titulo_reunion": "...",
    "fecha_estimada": "...",
    "participantes_mencionados": ["...", "..."],
    "temas_discutidos": [
      {
        "tema": "...",
        "resumen": "...",
        "decisiones": ["...", "..."],
        "action_items": [
          {"responsable": "...", "tarea": "...", "fecha_limite": "..."}
        ]
      }
    ],
    "proximos_pasos": ["...", "..."],
    "sentimiento_general": "positivo | neutral | negativo"
  }

user_prompt: |
  Analiza la siguiente transcripción de reunión y genera el resumen estructurado:
```

### Escenario 3 — Extracción de datos de facturas (Finanzas)

**Sector**: Finanzas / Contabilidad  
**Entrada**: PDFs de facturas  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un asistente contable. Extrae datos de facturas en formato JSON:
  {
    "numero_factura": "...",
    "fecha_emision": "YYYY-MM-DD",
    "fecha_vencimiento": "YYYY-MM-DD",
    "emisor": {
      "nombre": "...",
      "rfc": "...",
      "direccion": "..."
    },
    "receptor": {
      "nombre": "...",
      "rfc": "...",
      "direccion": "..."
    },
    "lineas": [
      {
        "descripcion": "...",
        "cantidad": 0,
        "precio_unitario": 0.00,
        "subtotal": 0.00
      }
    ],
    "subtotal": 0.00,
    "impuestos": 0.00,
    "total": 0.00,
    "moneda": "MXN | USD | EUR",
    "metodo_pago": "...",
    "condiciones_pago": "..."
  }
  Responde SOLO con el JSON.

user_prompt: |
  Extrae los datos de la siguiente factura:
```

### Escenario 4 — Procesamiento de formularios médicos con visión (Salud)

**Sector**: Salud  
**Entrada**: PDFs escaneados / imágenes de formularios  
**Actividades**: `callAoaiMultiModal` → `writeToBlob`  
**Requiere**: `AOAI_MULTI_MODAL=true`

```yaml
system_prompt: |
  Eres un asistente médico. Analiza la imagen del formulario médico y extrae:
  {
    "paciente": {
      "nombre": "...",
      "fecha_nacimiento": "YYYY-MM-DD",
      "numero_expediente": "...",
      "genero": "..."
    },
    "fecha_consulta": "YYYY-MM-DD",
    "medico_tratante": "...",
    "diagnostico_principal": "...",
    "diagnosticos_secundarios": ["..."],
    "signos_vitales": {
      "presion_arterial": "...",
      "temperatura": "...",
      "frecuencia_cardiaca": "...",
      "peso": "...",
      "talla": "..."
    },
    "medicamentos_recetados": [
      {"nombre": "...", "dosis": "...", "frecuencia": "...", "duracion": "..."}
    ],
    "estudios_solicitados": ["..."],
    "proxima_cita": "YYYY-MM-DD",
    "notas_adicionales": "..."
  }

user_prompt: |
  Analiza la imagen del formulario médico y extrae toda la información relevante:
```

### Escenario 5 — Clasificación y triaje de emails (Servicio al Cliente)

**Sector**: Retail / Servicios  
**Entrada**: Documentos de texto (emails guardados como .docx o .pdf)  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un agente de clasificación de tickets de soporte. Analiza el email y clasifica:
  {
    "asunto_detectado": "...",
    "categoria": "queja | solicitud | consulta | elogio | urgencia",
    "subcategoria": "...",
    "sentimiento": "positivo | neutral | negativo | muy_negativo",
    "prioridad": "alta | media | baja",
    "idioma": "es | en | fr | pt",
    "entidades_mencionadas": {
      "productos": ["..."],
      "numeros_orden": ["..."],
      "fechas": ["..."],
      "montos": ["..."]
    },
    "resumen": "...",
    "accion_recomendada": "...",
    "departamento_destino": "ventas | soporte_tecnico | facturacion | logistica | rrhh",
    "requiere_escalamiento": true
  }

user_prompt: |
  Clasifica y analiza el siguiente email de soporte:
```

### Escenario 6 — Análisis de contratos legales (Legal)

**Sector**: Legal / Compliance  
**Entrada**: PDFs de contratos  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un asistente legal especializado en revisión de contratos. Extrae:
  {
    "tipo_contrato": "arrendamiento | servicio | compraventa | laboral | NDA | otro",
    "partes": [
      {"nombre": "...", "rol": "arrendador | arrendatario | prestador | cliente", "identificacion": "..."}
    ],
    "fecha_firma": "YYYY-MM-DD",
    "fecha_inicio_vigencia": "YYYY-MM-DD",
    "fecha_fin_vigencia": "YYYY-MM-DD",
    "valor_contrato": {"monto": 0.00, "moneda": "...", "periodicidad": "mensual | anual | unica"},
    "clausulas_clave": [
      {"numero": "...", "titulo": "...", "resumen": "...", "riesgo": "alto | medio | bajo"}
    ],
    "penalizaciones": ["..."],
    "condiciones_de_terminacion": ["..."],
    "ley_aplicable": "...",
    "jurisdiccion": "...",
    "alertas": ["clausulas inusuales o riesgosas detectadas"]
  }

user_prompt: |
  Analiza el siguiente contrato y extrae la información estructurada:
```

### Escenario 7 — Extracción de tablas de informes financieros (Banca)

**Sector**: Banca / Inversiones  
**Entrada**: PDFs de estados financieros  
**Actividades**: `callAoaiMultiModal` → `writeToBlob`  
**Requiere**: `AOAI_MULTI_MODAL=true` (mejor para tablas complejas)

```yaml
system_prompt: |
  Eres un analista financiero. Extrae las tablas financieras del documento:
  {
    "empresa": "...",
    "periodo_reportado": "...",
    "tipo_reporte": "balance_general | estado_resultados | flujo_efectivo",
    "moneda": "...",
    "unidad": "miles | millones",
    "datos": [
      {
        "concepto": "...",
        "periodo_actual": 0.00,
        "periodo_anterior": 0.00,
        "variacion_porcentual": 0.00
      }
    ],
    "ratios_financieros": {
      "margen_operativo": 0.00,
      "margen_neto": 0.00,
      "roe": 0.00,
      "deuda_capital": 0.00
    },
    "notas_relevantes": ["..."]
  }

user_prompt: |
  Extrae las tablas y datos financieros del siguiente documento:
```

### Escenario 8 — Análisis de llamadas de soporte al cliente (Contact Center)

**Sector**: Telecomunicaciones / Retail  
**Entrada**: Grabaciones de audio (MP3, WAV)  
**Actividades**: `speechToText` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un analista de calidad de servicio. Analiza la transcripción de la llamada:
  {
    "duracion_estimada": "...",
    "tipo_llamada": "consulta | queja | solicitud | soporte_tecnico",
    "resumen": "...",
    "sentimiento_cliente": "positivo | neutral | negativo | frustrado",
    "sentimiento_agente": "profesional | empático | indiferente | grosero",
    "problema_principal": "...",
    "resolucion": {
      "fue_resuelto": true,
      "tipo_resolucion": "inmediata | escalada | pendiente",
      "detalle": "..."
    },
    "productos_mencionados": ["..."],
    "score_calidad": {
      "saludo_correcto": true,
      "escucha_activa": true,
      "ofrecio_solucion": true,
      "despedida_correcta": true,
      "score_total": "8/10"
    },
    "action_items": ["..."],
    "palabras_clave": ["..."]
  }

user_prompt: |
  Analiza la siguiente transcripción de llamada de soporte:
```

### Escenario 9 — Procesamiento masivo de documentos de auditoría (Manufactura)

**Sector**: Manufactura / Calidad  
**Entrada**: PDFs de reportes de auditoría  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`

```yaml
system_prompt: |
  Eres un auditor de calidad. Analiza el reporte de auditoría y extrae:
  {
    "numero_auditoria": "...",
    "fecha_auditoria": "YYYY-MM-DD",
    "planta": "...",
    "auditor": "...",
    "estandar_evaluado": "ISO 9001 | ISO 14001 | ISO 45001 | IATF 16949",
    "alcance": "...",
    "hallazgos": [
      {
        "tipo": "no_conformidad_mayor | no_conformidad_menor | observacion | oportunidad_mejora",
        "clausula": "...",
        "descripcion": "...",
        "evidencia": "...",
        "area_afectada": "...",
        "accion_correctiva_propuesta": "...",
        "fecha_limite": "YYYY-MM-DD"
      }
    ],
    "resumen_ejecutivo": "...",
    "recomendacion": "certificar | recertificar | auditar_seguimiento | no_certificar",
    "proxima_auditoria": "YYYY-MM-DD"
  }

user_prompt: |
  Analiza el siguiente reporte de auditoría de calidad:
```

### Escenario 10 — Preparación de corpus para RAG (Tecnología)

**Sector**: Tecnología / Conocimiento  
**Entrada**: PDFs de documentación técnica  
**Actividades**: `runDocIntel` → `callAoai` → `writeToBlob`  
**Nota**: Este escenario prepara datos para un sistema de RAG downstream.

```yaml
system_prompt: |
  Eres un asistente de chunking semántico. Divide el documento en fragmentos para indexación:
  {
    "titulo_documento": "...",
    "tipo_documento": "manual_tecnico | guia_usuario | API_reference | FAQ | politica",
    "idioma": "...",
    "chunks": [
      {
        "chunk_id": 1,
        "titulo_seccion": "...",
        "contenido": "...(máximo 1500 tokens por chunk)...",
        "metadata": {
          "nivel_jerarquia": "h1 | h2 | h3",
          "pagina_aproximada": 1,
          "palabras_clave": ["...", "..."],
          "tipo_contenido": "concepto | procedimiento | tabla | ejemplo | referencia"
        }
      }
    ],
    "total_chunks": 0,
    "resumen_general": "..."
  }
  Cada chunk debe ser autocontenido y comprensible sin contexto adicional.
  Máximo 1500 tokens por chunk. Preserva tablas y listas como un solo chunk.

user_prompt: |
  Divide y estructura el siguiente documento para indexación semántica:
```

---

## 8. Índice de Samples Incluidos

### Archivos de muestra en el repositorio

| Nombre | Ruta | Descripción |
|---|---|---|
| `prompts.yaml` | `data/prompts.yaml` | Prompt de ejemplo: extrae roles de empresa de un CV. Campos: `system_prompt`, `user_prompt`. Se sube al contenedor `prompts` del Storage. |
| `sampleRequest.json` | `data/sampleRequest.json` | JSON de ejemplo para el HTTP trigger: `{"name": "<file>", "uri": "https://<storage>.blob.core.windows.net/bronze/<file>"}` |
| `config.json` | `data/config.json` | Configuración de referencia de prompts en Cosmos DB: `[{"id": "live_prompt_config", "prompt_id": "hash1"}]` |
| `promptscontainer.json` | `data/promptscontainer.json` | Documento de ejemplo para Cosmos DB `promptscontainer`: `[{"id": "hash1", "name": "first_prompt", ...}]` |
| `test_client.ipynb` | `test_client.ipynb` | Notebook Jupyter para probar el pipeline: define payload, envía POST a Function App (local o remota), hace polling del status, muestra resultado JSON. |
| `config-test.py` | `pipeline/config-test.py` | Script mínimo para verificar que `Configuration()` se instancia correctamente contra App Configuration. |

### Scripts de operación

| Script | Ruta | Descripción |
|---|---|---|
| `startLocal.sh` | `scripts/startLocal.sh` | Configura venv, obtiene credenciales remotas, inicia `func start` localmente. Opciones: `--skip-settings`, `--skip-venv`. |
| `startLocal.ps1` | `scripts/startLocal.ps1` | Equivalente PowerShell del anterior. |
| `postprovision.sh` | `scripts/postprovision.sh` | Post-provisioning: sube `prompts.yaml` al Storage. Ejecutado automáticamente por `azd provision`. |
| `postDeploy.sh` | `scripts/postDeploy.sh` | Post-deploy: crea Event Grid Subscription que conecta blob uploads al Function App. Ejecutado automáticamente por `azd deploy`. |
| `deploy.sh` | `infra/deploy.sh` | Script de despliegue Bicep standalone (sin azd): valida prereqs, crea RG, ejecuta `az deployment group create`. |
| `troubleshoot-functions.sh` | `troubleshoot-functions.sh` | Scripts de diagnóstico para problemas comunes de Function App. |
| `createLocalSettings.sh` | `commandUtils/createLocalSettings.sh` | Genera `local.settings.json` para desarrollo local. |

### Scripts de administración (`commandUtils/`)

| Script | Ruta | Descripción |
|---|---|---|
| `az_login.sh` | `commandUtils/admin/az_login.sh` | Autenticación Azure CLI |
| `getPrincipalId.sh` | `commandUtils/admin/getPrincipalId.sh` | Obtiene el Principal ID del usuario logueado |
| `getUPN.sh` | `commandUtils/admin/getUPN.sh` | Obtiene el UPN del usuario |
| `role-assignment.sh` | `commandUtils/admin/role-assignment.sh` | Asigna roles RBAC |
| `listRoleAssignmentsbyObjectId.sh` | `commandUtils/admin/listRoleAssignmentsbyObjectId.sh` | Lista roles por Object ID |
| `listSoftDeleted.sh` | `commandUtils/admin/listSoftDeleted.sh` | Lista recursos soft-deleted |
| `moveResource.sh` | `commandUtils/admin/moveResource.sh` | Mueve recursos entre RGs |
| `functionApp.sh` | `commandUtils/functions/functionApp.sh` | Operaciones sobre Function App |
| `publishFunction.sh` | `commandUtils/functions/publishFunction.sh` | Publica Function App |
| `getDeploymentLogs.sh` | `commandUtils/functions/getDeploymentLogs.sh` | Obtiene logs de deployment |
| `call_process_uploads.sh` | `commandUtils/functions/call_process_uploads.sh` | Invoca el pipeline por HTTP |
| `getQuota.sh` | `commandUtils/aoai/getQuota.sh` | Verifica cuota de Azure OpenAI |

### Documentación

| Documento | Ruta | Descripción |
|---|---|---|
| `README.md` | `README.md` | Documentación principal: overview, prerrequisitos, deployment instructions, troubleshooting |
| `OFFICIAL-DEPLOYMENT-GUIDE.md` | `docs/OFFICIAL-DEPLOYMENT-GUIDE.md` | Guía oficial detallada: arquitectura, componentes, deployment options, Event Grid, local development |
| `customizations.md` | `docs/customizations.md` | Flags de customización: `AI_VISION_ENABLED`, `AOAI_MULTI_MODAL` |
| `promptConfiguration.md` | `docs/promptConfiguration.md` | Cómo configurar prompts en `data/prompts.yaml` y subirlos al Storage |
| `TelemetryMonitoringInfo.md` | `docs/TelemetryMonitoringInfo.md` | Enhanced tracing configuration y KQL queries para App Insights |
| `troubleShootingGuide.md` | `docs/troubleShootingGuide.md` | Problemas comunes y soluciones |

### Análisis generados

| Documento | Ruta | Descripción |
|---|---|---|
| `01-overview.md` | `Analysis/01-overview.md` | Guía general no técnica de la solución |
| `02-architecture-detailed.md` | `Analysis/02-architecture-detailed.md` | Arquitectura detallada para desarrolladores |
| `03-use_cases_examples.md` | `Analysis/03-use_cases_examples.md` | 12 casos de uso con configuración completa |
| `04-ai_lz_options.md` | `Analysis/04-ai_lz_options.md` | Guía de despliegue en modo AI Landing Zone |

### Estructura completa del repositorio

```
ai-document-processor/
├── azure.yaml                          # Definición azd: infra + services + hooks
├── README.md                           # Documentación principal
├── LICENSE                             # MIT License
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── SUPPORT.md
├── contributing.md
├── test_client.ipynb                   # Notebook de prueba del pipeline
├── test.sh                             # (vacío)
├── troubleshoot-functions.sh           # Diagnóstico de Function App
├── troubleshoot-functions.ps1
│
├── data/
│   ├── prompts.yaml                    # Prompts de ejemplo (CV → JSON)
│   ├── config.json                     # Config de prompts para Cosmos
│   ├── promptscontainer.json           # Documento de prompts para Cosmos
│   └── sampleRequest.json              # JSON de prueba para HTTP trigger
│
├── pipeline/                           # Código de la Function App
│   ├── function_app.py                 # Entry point: triggers + orchestrator
│   ├── main.py                         # (Stub: "Hello from pipeline!")
│   ├── host.json                       # Config runtime + enhanced tracing
│   ├── requirements.txt                # Dependencias Python (~85 paquetes)
│   ├── config-test.py                  # Test de Configuration
│   ├── README.md                       # (vacío)
│   │
│   ├── activities/                     # Actividades del pipeline
│   │   ├── callAiFoundry.py            # callAoai: texto → LLM → JSON
│   │   ├── callFoundryMultiModal.py    # callAoaiMultiModal: imagen → LLM → JSON
│   │   ├── runDocIntel.py              # runDocIntel: doc → OCR → texto
│   │   ├── speechToText.py             # speechToText: audio → transcripción
│   │   ├── writeToBlob.py              # writeToBlob: JSON → silver/
│   │   └── sharepointLookup.py         # (Stub, no implementado)
│   │
│   ├── configuration/
│   │   ├── __init__.py
│   │   └── configuration.py            # Clase Configuration: AppConfig + KV + env
│   │
│   └── pipelineUtils/
│       ├── __init__.py                 # get_month_date()
│       ├── azure_openai.py             # run_prompt(): AzureOpenAI chat completion
│       ├── blob_functions.py           # CRUD blobs + BlobMetadata dataclass
│       ├── db.py                       # save_chat_message() en Cosmos DB
│       └── prompts.py                  # load_prompts() desde blob o Cosmos
│
├── infra/                              # Infraestructura as Code (Bicep)
│   ├── main.bicep                      # Template principal (~1650 líneas)
│   ├── main.parameters.json            # Parámetros parametrizados por env vars
│   ├── abbreviations.json              # Prefijos de nombrado Azure
│   ├── roles.json                      # Role definition IDs para RBAC
│   ├── deploy.sh / deploy.ps1          # Scripts de deploy standalone
│   ├── install.ps1                     # Script de instalación para VM
│   ├── README.md                       # Documentación de infra
│   │
│   └── modules/
│       ├── app_config/appconfig.bicep
│       ├── compute/functionApp.bicep, hosting-plan.bicep
│       ├── db/cosmos.bicep
│       ├── management_governance/application-insights.bicep, log-analytics-workspace.bicep
│       ├── network/private-dns-zones.bicep, private-endpoint.bicep, vnet.bicep, vnet-vpn-gateway.bicep
│       ├── rbac/aiservices-user.bicep, appconfig-access.bicep, blob-*.bicep, cogservices-*.bicep, ...
│       ├── security/key-vault.bicep, managed-identity.bicep, private-link-scope.bicep, ...
│       └── storage/storage-account.bicep, storage-private-endpoints.bicep
│
├── scripts/                            # Scripts de operación
│   ├── startLocal.sh / startLocal.ps1
│   ├── postprovision.sh / postprovision.ps1
│   ├── postDeploy.sh / postDeploy.ps1
│   └── getBlobConnectionStrings.sh
│
├── commandUtils/                       # Utilidades CLI
│   ├── createLocalSettings.sh
│   ├── admin/                          # Scripts de administración Azure
│   ├── aoai/                           # Scripts de cuota OpenAI
│   └── functions/                      # Scripts de Function App
│
├── docs/                               # Documentación adicional
│   ├── OFFICIAL-DEPLOYMENT-GUIDE.md
│   ├── customizations.md
│   ├── promptConfiguration.md
│   ├── TelemetryMonitoringInfo.md
│   └── troubleShootingGuide.md
│
├── localScripts/                       # Scripts locales
│   └── grantRole.sh
│
└── Analysis/                           # Análisis generados
    ├── 00-full-analysis.md             # Este documento
    ├── 01-overview.md
    ├── 02-architecture-detailed.md
    ├── 03-use_cases_examples.md
    └── 04-ai_lz_options.md
```
