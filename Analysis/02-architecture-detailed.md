# AI Document Processor — Referencia Técnica Detallada

> Documento de referencia para desarrolladores senior y arquitectos de sistemas.  
> Cubre stack completo, estructura de código, patrones internos, modelo de datos, seguridad y extensibilidad.

---

## Tabla de Contenidos

1. [Stack Tecnológico Completo](#1-stack-tecnológico-completo)
2. [Estructura de Directorios](#2-estructura-de-directorios)
3. [Arquitectura de Componentes](#3-arquitectura-de-componentes)
4. [Modelo de Datos](#4-modelo-de-datos)
5. [Flujo de Ejecución de Tareas](#5-flujo-de-ejecución-de-tareas)
6. [Motor de Procesamiento / Orquestación](#6-motor-de-procesamiento--orquestación)
7. [Modelo de Seguridad](#7-modelo-de-seguridad)
8. [Comparación de Modos de Despliegue](#8-comparación-de-modos-de-despliegue)
9. [Patrones de Extensibilidad](#9-patrones-de-extensibilidad)

---

## 1. Stack Tecnológico Completo

### Backend — Azure Functions (Python)

| Componente | Versión | Notas |
|---|---|---|
| **Python** | 3.11 (mínimo) | `linuxFxVersion: 'Python\|3.11'` en Bicep |
| **Azure Functions Runtime** | v4 (`~4`) | Extension Bundle `[4.*, 5.0.0)` |
| `azure-functions` | 1.21.3 | Bindings y tipos HTTP/Blob |
| `azure-functions-durable` | 1.4.0 | Orquestación Durable (requiere ≥1.3.0 para `backoff_coefficient`) |
| `openai` | 1.70.0 | SDK oficial OpenAI para Azure OpenAI |
| `azure-ai-documentintelligence` | 1.0.2 | OCR / Document Intelligence |
| `azure-cosmos` | 4.9.0 | SDK Cosmos DB para historial de conversaciones |
| `azure-identity` | 1.19.0 | `DefaultAzureCredential`, MSAL, token federation |
| `azure-appconfiguration` | 1.7.1 | Cliente App Configuration |
| `azure-appconfiguration-provider` | 2.0.1 | Carga de configuración con referencias a Key Vault |
| `azure-storage-blob` | 12.24.0 | Operaciones CRUD en Azure Blob Storage |
| `azure-keyvault-secrets` | 4.10.0 | Acceso a secretos de Key Vault |
| `pydantic` | 2.11.2 | Validación de modelos de datos |
| `tenacity` | 9.0.0 | Política de reintentos con backoff exponencial |
| `PyMuPDF` (fitz) | 1.26.6 | Render de páginas PDF a imágenes (modo multimodal) |
| `PyPDF2` | 3.0.1 | Manipulación de PDFs (trim) |
| `PyYAML` | 6.0.2 | Lectura del archivo `prompts.yaml` |
| `requests` | 2.32.3 | Llamadas REST a Speech-to-Text API |
| `aiohttp` | 3.12.14 | Cliente HTTP asíncrono |

### Infraestructura — IaC y CI/CD

| Herramienta | Versión | Rol |
|---|---|---|
| **Bicep** | API `2024-12-01-preview` | IaC principal, todos los recursos Azure |
| **Azure Developer CLI (azd)** | cualquier | Orquestación de `provision` + `deploy` con hooks |
| **Azure CLI (az)** | cualquier | Scripts post-deploy (EventGrid subscription) |
| **Azure Functions Core Tools** | v4 | Ejecución y debugging local |

### Modelos AI configurados en Bicep

| Variable | Valor hardcoded en Bicep | Notas |
|---|---|---|
| `openaiModel` | `gpt-5-mini` | Nombre del deployment AOAI |
| `openaiApiVersion` | `2025-08-07` | Versión API de preview |
| `OPENAI_API_VERSION` (app setting) | `2024-05-01-preview` | Versión efectiva del SDK |

---

## 2. Estructura de Directorios

```
ai-document-processor-demos/
│
├── azure.yaml                    # Configuración azd: servicios, hooks, IaC
│
├── pipeline/                     # 🏗️  Azure Function App (servicio "processing")
│   ├── function_app.py           # Punto de entrada: triggers + orquestador principal
│   ├── main.py                   # Entry point de Python (no usado en Functions)
│   ├── host.json                 # Configuración del runtime de Functions
│   ├── requirements.txt          # Dependencias Python pinned
│   │
│   ├── activities/               # Actividades Durable Functions (pasos del pipeline)
│   │   ├── callAiFoundry.py      # Activity "callAoai": llama a Azure OpenAI con el texto extraído
│   │   ├── callFoundryMultiModal.py  # Activity "callAoaiMultiModal": envía imágenes base64 a GPT-4o
│   │   ├── runDocIntel.py        # Activity "runDocIntel": OCR con Document Intelligence
│   │   ├── speechToText.py       # Activity "speechToText": transcripción con Azure AI Speech
│   │   ├── writeToBlob.py        # Activity "writeToBlob": guarda JSON en container "silver"
│   │   └── sharepointLookup.py   # Activity stub (no implementada)
│   │
│   ├── configuration/            # Módulo de configuración centralizada
│   │   ├── __init__.py           # Re-exporta Configuration
│   │   └── configuration.py      # Clase Configuration: carga desde App Config + Key Vault
│   │
│   └── pipelineUtils/            # Utilidades reutilizables
│       ├── __init__.py           # Exporta get_month_date()
│       ├── azure_openai.py       # run_prompt(): cliente AzureOpenAI con logging a Cosmos
│       ├── blob_functions.py     # BlobMetadata + CRUD en Blob Storage
│       ├── db.py                 # save_chat_message() → Cosmos DB
│       └── prompts.py            # load_prompts(): carga YAML desde Blob o Cosmos
│
├── infra/                        # 🏛️  Infraestructura Bicep
│   ├── main.bicep                # Template raíz: define todos los módulos y RBAC
│   ├── main.parameters.json      # Parámetros con variables de entorno azd ($AZURE_*)
│   ├── abbreviations.json        # Prefijos de nombres de recursos (ej: "func-", "st-")
│   ├── roles.json                # Mapa de GUIDs de roles RBAC por categoría
│   └── modules/
│       ├── app_config/
│       │   └── appconfig.bicep   # Azure App Configuration Standard con key-values
│       ├── compute/
│       │   ├── functionApp.bicep # Function App Linux con identidad y app settings
│       │   └── hosting-plan.bicep # App Service Plan (Dedicated o FlexConsumption)
│       ├── db/
│       │   └── cosmos.bicep      # Cosmos DB SQL, database, 3 containers, secreto en KV
│       ├── management_governance/
│       │   ├── application-insights.bicep
│       │   └── log-analytics-workspace.bicep
│       ├── network/
│       │   ├── vnet.bicep        # VNet con 6 subnets + NSGs
│       │   ├── private-endpoint.bicep
│       │   ├── private-dns-zones.bicep
│       │   └── vnet-vpn-gateway.bicep
│       ├── rbac/                 # Un archivo Bicep por tipo de rol
│       │   ├── blob-contributor.bicep
│       │   ├── blob-dataowner.bicep
│       │   ├── blob-queue-contributor.bicep
│       │   ├── cosmos-contributor.bicep
│       │   ├── appconfig-access.bicep
│       │   ├── cogservices-openai-user.bicep
│       │   ├── keyvault-access.bicep
│       │   ├── keyvault-access-policy.bicep
│       │   ├── aiservices-user.bicep
│       │   └── role.bicep        # Módulo genérico de role assignment
│       └── security/
│           ├── managed-identity.bicep  # User-Assigned Managed Identity
│           ├── key-vault.bicep
│           ├── key-vault-secret.bicep
│           └── private-link-scope.bicep
│
├── scripts/                      # Scripts post-provision y post-deploy
│   ├── postprovision.sh/.ps1     # Sube prompts.yaml a Blob Storage
│   ├── postDeploy.sh/.ps1        # Crea EventGrid subscription hacia Function
│   └── startLocal.sh/.ps1        # Inicia venv + func host localmente
│
├── data/                         # Datos de configuración por defecto
│   ├── prompts.yaml              # System prompt + user prompt de ejemplo
│   └── config.json               # Configuración live de prompts
│
├── docs/                         # Documentación técnica adicional
│   ├── OFFICIAL-DEPLOYMENT-GUIDE.md
│   ├── customizations.md
│   ├── promptConfiguration.md
│   └── TelemetryMonitoringInfo.md
│
└── commandUtils/                 # Scripts de administración Azure CLI
    ├── admin/                    # Login, roles, soft-delete
    ├── aoai/                     # Consulta de quota AOAI
    └── functions/                # Deploy, logs, zip deploy
```

---

## 3. Arquitectura de Componentes

### 3.1 Function App — `pipeline/function_app.py`

**Responsabilidad**: Punto de entrada de eventos, orquestador de alto nivel del pipeline de procesamiento.

#### Triggers registrados

| Nombre | Tipo | Ruta/Endpoint | Descripción |
|---|---|---|---|
| `start_orchestrator_on_blob` | Blob Trigger (EventGrid) | `bronze/{name}` | Producción: recibe eventos de EventGrid cuando llega un blob |
| `start_orchestrator_on_blob_local` | Blob Trigger (polling) | `bronze/{name}` | Solo en `AZURE_FUNCTIONS_ENVIRONMENT=Development` |
| `start_orchestrator_http` | HTTP Trigger | `GET/POST /api/client` | Invocación manual vía HTTP; acepta `{name, uri}` en body JSON |
| `process_blob` | Orchestration Trigger | — | Sub-orquestador Durable: lógica de routing por tipo de archivo |

#### Endpoint HTTP

```
POST /api/client
Authorization: x-functions-key: <FUNCTION_KEY>
Content-Type: application/json

Body:
{
    "name": "bronze/invoice.pdf",
    "uri": "https://<storage>.blob.core.windows.net/bronze/invoice.pdf"
}

Response:
{
    "id": "<instance_id>",
    "statusQueryGetUri": "...",
    "sendEventPostUri": "...",
    "terminatePostUri": "...",
    "purgeHistoryDeleteUri": "..."
}
```

#### Diagrama ASCII — flujo interno del Function App

```
Evento Blob EventGrid                HTTP Request
       │                                  │
       ▼                                  ▼
start_orchestrator_on_blob       start_orchestrator_http
       │                                  │
       └──────────────┬───────────────────┘
                      │
              BlobMetadata.to_dict()
                      │
                      ▼
              client.start_new("process_blob")
                      │
                      ▼
              ┌───────────────────────────────────┐
              │       process_blob (orchestrador) │
              │                                   │
              │  file_extension ─────────────────►┤
              │                                   │
              │  audio? ─────────► speechToText   │
              │  doc + multimodal?► callAoaiMultiModal
              │  doc?  ──────────► runDocIntel    │
              │                       │           │
              │                       ▼           │
              │                   callAoai        │
              │                       │           │
              │                       ▼           │
              │                   writeToBlob     │
              └───────────────────────────────────┘
```

---

### 3.2 Activity: `runDocIntel` — `pipeline/activities/runDocIntel.py`

**Responsabilidad**: Extrae texto de documentos (PDF, DOCX, imágenes) usando Azure Document Intelligence.

| Parámetro entrada | Tipo | Descripción |
|---|---|---|
| `blob_input.name` | str | Nombre del blob con prefijo de container |
| `blob_input.container` | str | Container de origen (siempre `"bronze"`) |

**Dependencias externas**: Azure AI Services (`prebuilt-read` model), Azure Blob Storage.

**Flujo interno**:
```python
normalize_blob_name(container, raw_name)          # Elimina prefijo "bronze/"
get_blob_content(container_name, blob_path)        # Descarga bytes del blob
DocumentIntelligenceClient.begin_analyze_document( # Envía como bytesSource
    "prebuilt-read",
    AnalyzeDocumentRequest(bytes_source=blob_content)
)
result.paragraphs → "\n".join(paragraph.content)  # Concatena párrafos
```

**Retorna**: `str` — texto concatenado de todos los párrafos.

---

### 3.3 Activity: `callAoai` — `pipeline/activities/callAiFoundry.py`

**Responsabilidad**: Carga prompts, combina con texto extraído, llama a Azure OpenAI y retorna JSON estructurado.

**Flujo interno**:
```python
load_prompts()                                     # Lee prompts.yaml desde Blob "prompts"
full_user_prompt = prompt_json['user_prompt'] + "\n\n" + text_result
run_prompt(instance_id, system_prompt, full_user_prompt)
# Post-procesamiento: strip de bloques ```json ... ```
```

**Retorna**: `str` — JSON válido con los datos estructurados extraídos.

---

### 3.4 Activity: `callAoaiMultiModal` — `pipeline/activities/callFoundryMultiModal.py`

**Responsabilidad**: Procesa documentos visualmente — convierte páginas PDF o imágenes PNG a base64 y las envía a GPT con visión.

**Flujo interno**:
```python
convert_to_base64_images(blob_input)
# Para PDF: fitz.open() → page.get_pixmap() → pix.tobytes("png") → base64
# Para PNG: base64.b64encode(blob_content)
run_prompt(instance_id, system_prompt, user_prompt, base64_images=base64_images)
```

**Habilitación**: Se activa cuando `AOAI_MULTI_MODAL=true` en App Configuration.

---

### 3.5 Activity: `speechToText` — `pipeline/activities/speechToText.py`

**Responsabilidad**: Transcribe audio usando Azure AI Speech REST API.

**Dependencias externas**: Azure AI Services Speech endpoint.

**Flujo interno**:
```python
credential.get_token("https://cognitiveservices.azure.com/.default").token
POST {AI_SERVICES_ENDPOINT}/speechtotext/transcriptions:submit?api-version=2025-10-15
# Polling: wait_for_transcription() cada 10 segundos
GET final_status['links']['files']
# Extrae: content_response['combinedRecognizedPhrases'][0]['display']
```

**Retorna**: `str` — texto transcrito completo.

---

### 3.6 Activity: `writeToBlob` — `pipeline/activities/writeToBlob.py`

**Responsabilidad**: Persiste el JSON de salida en el container `silver`.

**Nombre de archivo de salida**: `{nombre_sin_extension}-output.json`

```python
write_to_blob(
    container_name=FINAL_OUTPUT_CONTAINER,   # "silver"
    blob_path=f"{sourcefile}-output.json",
    data=json_str.encode('utf-8')
)
```

---

### 3.7 Módulo: `Configuration` — `pipeline/configuration/configuration.py`

**Responsabilidad**: Carga centralizada de configuración desde Azure App Configuration con soporte de referencias a Key Vault.

**Estrategia de credenciales**:

| Entorno | Credenciales habilitadas |
|---|---|
| `Development` | Azure CLI, PowerShell, Azure Developer CLI |
| Producción | Managed Identity únicamente |

**Estrategia de carga**:
```
1. Intenta APP_CONFIGURATION_URI  → carga con DefaultAzureCredential
2. Fallback: AZURE_APPCONFIG_CONNECTION_STRING
3. Error fatal si ninguno disponible
```

**Resolución de valores** en `get_value(key, default)`:
```
1. Si allow_environment_variables=true → os.environ.get(key)
2. App Configuration con retry (backoff exponencial, max 5 intentos, max 5s)
3. default si se proporcionó
4. Exception si no se encontró
```

---

### 3.8 Módulo: `pipelineUtils/azure_openai.py`

**Responsabilidad**: Wrapper del cliente AzureOpenAI con logging de conversaciones en Cosmos DB.

```python
def run_prompt(
    pipeline_id: str,          # instance_id del orquestador (correlación)
    system_prompt: str,
    user_prompt: str,
    base64_images: list = None # Solo para modo multimodal
) -> str
```

Cada llamada registra tres mensajes en Cosmos DB: `system`, `user`, `assistant` (con usage tokens).

---

## 4. Modelo de Datos

### Base de datos: `conversationHistoryDB` (Azure Cosmos DB SQL API)

#### Container: `conversationhistory`

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | `string (UUID)` | Identificador único del mensaje. **Partition key: `/id`** |
| `conversationId` | `string` | Correlaciona con el `instance_id` del orquestador Durable |
| `role` | `"system" \| "user" \| "assistant"` | Rol del mensaje en la conversación |
| `content` | `string` | Contenido del mensaje (prompt o respuesta) |
| `timestamp` | `string (ISO 8601 UTC)` | Fecha-hora de creación |
| `promptTokens` | `int \| null` | Solo en mensajes `assistant` |
| `completionTokens` | `int \| null` | Solo en mensajes `assistant` |
| `totalTokens` | `int \| null` | Solo en mensajes `assistant` |
| `model` | `string \| null` | Nombre del modelo usado (ej: `gpt-5-mini`) |

**TTL**: 86400 segundos (24 horas). Los mensajes se eliminan automáticamente.  
**Índices**: todos los paths (`/*`), modo `consistent`.

**Ejemplo de documento — mensaje assistant**:
```json
{
    "id": "3f8a2c1d-4e5b-6f7a-8901-bcdef0123456",
    "conversationId": "a1b2c3d4e5f6789012345678901234ab",
    "role": "assistant",
    "content": "[{\"role\": \"Data Analyst\", \"company\": \"Acme Corp\", ...}]",
    "timestamp": "2026-03-25T14:32:10.123456Z",
    "promptTokens": 1024,
    "completionTokens": 512,
    "totalTokens": 1536,
    "model": "gpt-5-mini"
}
```

#### Container: `promptscontainer`

Almacena configuraciones de prompts referenciables. Estructura libre, partition key: `/id`.

**Ejemplo**:
```json
{
    "id": "live_prompt_config",
    "prompt_id": "hash1"
}
```

#### Container: `config`

Container auxiliar para configuración de la aplicación. Indexación desactivada (`indexingMode: 'none'`), partition key: `/id`.

---

### Blob Storage — Containers

| Container | Propósito | Contenido |
|---|---|---|
| `bronze` | Input | Archivos crudos (PDF, DOCX, MP3, PNG, etc.) |
| `silver` | Output | JSONs de salida `{nombre}-output.json` |
| `prompts` | Configuración | `prompts.yaml` (system + user prompt) |
| `app-package` | Deployment | Paquete ZIP de la Function App |

---

## 5. Flujo de Ejecución de Tareas

### Paso a paso técnico — desde carga de blob hasta resultado

```
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 1: Ingesta                                                          │
│                                                                          │
│  Cliente sube archivo a container "bronze" del Storage Account          │
│  → Azure EventGrid detecta BlobCreated event                            │
│  → Entrega webhook a Function App:                                       │
│     POST https://<funcapp>.azurewebsites.net/runtime/webhooks/blobs     │
│        ?functionName=Host.Functions.start_orchestrator_on_blob          │
│        &code=<blobs_extension_key>                                      │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 2: Inicio de Orquestación                                           │
│                                                                          │
│  Función: start_orchestrator_blob(blob, client)                         │
│  → Crea BlobMetadata(name, container="bronze", uri)                     │
│  → instance_id = await client.start_new(                                │
│        "process_blob", client_input=blob_metadata.to_dict()             │
│     )                                                                    │
│  → Logging: "Started orchestration {instance_id} for blob {blob.name}" │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 3: Orquestador — Routing por tipo de archivo                        │
│                                                                          │
│  Función: process_blob(context)                                          │
│  → context.get_input() → blob_input dict                                │
│  → Extrae extensión: blob_name.lower().split('.')[-1]                   │
│                                                                          │
│  RetryOptions(                                                           │
│      first_retry_interval_in_milliseconds=5000,  # 5s                  │
│      max_number_of_attempts=5                                            │
│  )                                                                       │
│                                                                          │
│  Routing:                                                                │
│  ┌──────────────────────────────────────────────┐                       │
│  │ AOAI_MULTI_MODAL=true AND doc extension?      │──► callAoaiMultiModal│
│  │ audio extension? (wav,mp3,opus,ogg,flac,...)  │──► speechToText      │
│  │ doc extension? (pdf,docx,xlsx,png,jpg,...)    │──► runDocIntel       │
│  │ otro                                          │──► return {skipped}  │
│  └──────────────────────────────────────────────┘                       │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 4: Extracción de texto                                              │
│                                                                          │
│  Activity: runDocIntel o speechToText                                    │
│                                                                          │
│  runDocIntel:                                                            │
│    → normalize_blob_name(container, raw_name)                           │
│    → get_blob_content(container_name, blob_path)   # Descarga bytes     │
│    → DocumentIntelligenceClient.begin_analyze_document(                 │
│          "prebuilt-read",                                               │
│          AnalyzeDocumentRequest(bytes_source=blob_content)              │
│      )                                                                   │
│    → result.paragraphs → str concatenado                                │
│                                                                          │
│  speechToText:                                                           │
│    → credential.get_token("https://cognitiveservices.azure.com/.default")
│    → POST {AI_SERVICES_ENDPOINT}/speechtotext/transcriptions:submit     │
│    → Polling wait_for_transcription() cada 10s hasta "Succeeded"        │
│    → GET files_url → content_url → display text                         │
│                                                                          │
│  Manejo de errores: raise → Durable Functions reintenta (RetryOptions)  │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 5: Procesamiento con Azure OpenAI                                   │
│                                                                          │
│  Activity: callAoai(inputData={text_result, instance_id})               │
│                                                                          │
│  → load_prompts() desde Blob "prompts/prompts.yaml"                     │
│  → full_user_prompt = prompt_json['user_prompt'] + "\n\n" + text_result │
│  → run_prompt(instance_id, system_prompt, full_user_prompt)             │
│      → save_chat_message(pipeline_id, "system", ...)   # Cosmos DB      │
│      → save_chat_message(pipeline_id, "user", ...)     # Cosmos DB      │
│      → openai_client.chat.completions.create(model, messages)           │
│      → save_chat_message(pipeline_id, "assistant", ..., usage)          │
│  → Strip de bloques markdown ```json ... ``` si presentes              │
│  → Retorna JSON string                                                   │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 6: Persistencia del resultado                                       │
│                                                                          │
│  Activity: writeToBlob(args={json_str, blob_name, final_output_container})
│                                                                          │
│  → sourcefile = os.path.splitext(os.path.basename(blob_name))[0]       │
│  → output_blob = f"{sourcefile}-output.json"                            │
│  → write_to_blob("silver", output_blob, json_str.encode('utf-8'))       │
│  → Retorna {success: True, blob_name, output_blob}                      │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PASO 7: Respuesta del orquestador                                        │
│                                                                          │
│  return {                                                                │
│      "blob": blob_input,                                                 │
│      "text_result": aoai_output,   # JSON string                        │
│      "task_result": task_result    # {success, blob_name, output_blob}  │
│  }                                                                       │
│                                                                          │
│  Estado final en Durable: "Completed"                                   │
│  Consultable vía: GET {statusQueryGetUri}                               │
└──────────────────────────────────────────────────────────────────────────┘
```

### Manejo de errores y reintentos

| Escenario | Comportamiento |
|---|---|
| Excepción en activity | Activity lanza `raise` → Durable Functions captura |
| Política de reintentos | 5s inicial, máximo 5 intentos por activity |
| Error de configuración | `Configuration.__init__` lanza `Exception` → Function no arranca |
| Tipo de archivo no soportado | Orquestador retorna `{status: "skipped"}` limpiamente |
| Speech API pendiente | Polling bloqueante con `time.sleep(10)` en el worker |
| Timeout de App Config | `tenacity`: backoff exponencial (1-5s), max 5 intentos |

---

## 6. Motor de Procesamiento / Orquestación

### Framework: Azure Durable Functions v2

El engine de orquestación usa el patrón **Function Chaining** de Azure Durable Functions. Cada paso del pipeline es una *Activity Function* independiente, coordinada por un *Orchestrator Function*.

### Registro de componentes (Blueprint pattern)

Cada activity define su propio blueprint y lo registra en la app principal:

```python
# En pipeline/activities/callAiFoundry.py
import azure.durable_functions as df

name = "callAoai"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="inputData")        # nombre del arg en la función
def run(inputData: dict):
    ...
```

```python
# En pipeline/function_app.py
app = df.DFApp(http_auth_level=func.AuthLevel.FUNCTION)

app.register_functions(runDocIntel.bp)
app.register_functions(callAiFoundry.bp)
app.register_functions(writeToBlob.bp)
app.register_functions(speechToText.bp)
app.register_functions(callFoundryMultiModal.bp)
```

### Firma del orquestador

```python
@app.function_name(name="process_blob")
@app.orchestration_trigger(context_name="context")
def process_blob(context: df.DurableOrchestrationContext):
    blob_input: dict = context.get_input()
    instance_id: str = context.instance_id

    retry_options = RetryOptions(
        first_retry_interval_in_milliseconds=5000,
        max_number_of_attempts=5
    )

    # Llamada a activity con retry:
    result = yield context.call_activity_with_retry(
        "activityName",     # nombre registrado en @bp.function_name
        retry_options,
        input_payload        # objeto serializable a JSON
    )
```

### Ciclo de vida de una activity

```
1. Orchestrator llama call_activity_with_retry("activityName", retry_options, payload)
2. Durable Framework serializa payload a JSON → envía a la cola de activities
3. Worker desencola y ejecuta la función activity
4. Activity retorna valor → serializado como JSON → enviado al orchestrator
5. Si exception: Durable reintenta según RetryOptions
6. Si max_attempts excedido: orquestador recibe Exception → puede propagarse o manejarse
```

### Configuración de host.json para orquestación

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

- `traceInputsAndOutputs: true` — loggea payloads de entrada/salida (útil para debug, cuidado con datos sensibles).
- `distributedTracingEnabled: true` + `version: V2` — integración con Application Insights para trazas distribuidas.

### Configuración de logging

```json
"logLevel": {
    "default": "Warning",
    "Function": "Information",
    "Host.Triggers.DurableTask": "Information",
    "DurableTask.Core": "Warning",
    "DurableTask.AzureStorage": "Warning"
}
```

---

## 7. Modelo de Seguridad

### Identidades

| Identidad | Tipo | Propósito |
|---|---|---|
| **User-Assigned Managed Identity** (`managed-identity.bicep`) | `Microsoft.ManagedIdentity/userAssignedIdentities` | Identidad operacional de la Function App en producción |
| **Signed-in User (Developer)** | User Principal (azd) | Acceso durante despliegue; recibe los mismos roles que la MI |

La Function App configura la identidad así:

```bicep
identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
        '${identityId}': {}
    }
}
```

### Asignaciones RBAC por servicio

| Identidad | Role | Role ID | Scope | Módulo Bicep |
|---|---|---|---|---|
| Function App MI | **Storage Blob Data Contributor** | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` | Storage Account (data) | `blob-contributor.bicep` |
| Function App MI | **Storage Blob Data Owner** | `b7e6dc6d-f1e8-4753-8033-0f276bb0955b` | Storage Account (data) | `blob-dataowner.bicep` |
| Function App MI | **Storage Queue Data Contributor** | `974c5e8b-45b9-4653-ba55-5f855dd0fb88` | Storage Account (func) | `blob-queue-contributor.bicep` |
| Function App MI | **Cosmos DB Built-in Data Contributor** | `00000000-0000-0000-0000-000000000002` | Cosmos DB Account | `cosmos-contributor.bicep` |
| Function App MI | **App Configuration Data Owner** | `5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b` | App Configuration | `appconfig-access.bicep` |
| Function App MI | **Cognitive Services OpenAI User** | `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` | AI Services Account | `cogservices-openai-user.bicep` |
| Function App MI | **Key Vault (custom role)** | via `roleDefinitionId` param | Key Vault | `keyvault-access.bicep` |

### Flujo de autenticación entre servicios

```
Function App (User-Assigned MI)
        │
        │ 1. DFApp startup → Configuration.__init__()
        │
        ▼
DefaultAzureCredential (prod: solo ManagedIdentity)
        │
        │ 2. Obtiene token para App Configuration
        ▼
Azure App Configuration (RBAC: Data Owner)
        │
        │ 3. Lee key-values; referencias KV resueltas automáticamente
        ▼
Azure Key Vault (RBAC secrets)
        │
        │ 4. Tiempo de ejecución: tokens bajo demanda
        ├──► Storage Blob: credential.get_token("https://storage.azure.com/.default")
        ├──► AI Services:  credential.get_token("https://cognitiveservices.azure.com/.default")
        └──► Cosmos DB:    credential directo en CosmosClient(uri, credential=config.credential)
```

**Nota**: No se usan claves de API ni cadenas de conexión en producción — todo es token-based via la Managed Identity.

### Secretos y configuración sensible

| Secreto | Almacenamiento | Referencia |
|---|---|---|
| Clave primaria de Cosmos DB | Key Vault secret `azureDBkey` | Creada en `cosmos.bicep` con `newAccount.listKeys().primaryMasterKey` |
| Password de VM (modo enterprise) | Key Vault secret `vmUserInitialPassword` | Inyectado en tiempo de provisión vía parámetro `@secure()` |
| App settings de la Function | Azure App Configuration | Referenciados como `{\"uri\": \"https://...vault.azure.net/secrets/...\"}` |

**Configuración de la Function App**: El campo `AzureWebJobsStorage__credential=managedidentity` evita que Functions use connection strings para su storage interno, forzando autenticación por MI.

### Acceso de red a los endpoints (modo básico)

| Servicio | Acceso Público | Notas |
|---|---|---|
| Function App | Habilitado | `publicNetworkAccess: 'Enabled'` siempre |
| App Configuration | Configurable | `publicNetworkAccess: 'Disabled'` en modo enterprise |
| Cosmos DB | Configurable | `publicNetworkAccess: 'Disabled'` por defecto en Bicep |
| Key Vault | Configurable | Private endpoint en modo enterprise |
| AI Services | Configurable | Private endpoint en modo enterprise |

---

## 8. Comparación de Modos de Despliegue

### Tabla comparativa

| Característica | Modo Básico (`networkIsolation=false`) | Modo Enterprise (`networkIsolation=true`) |
|---|---|---|
| **Tráfico de red** | Sobre Internet público | Dentro de VNet privada |
| **Private Endpoints** | No | Sí — para todos los servicios |
| **VNet** | No | Sí — `10.0.0.0/23` |
| **DNS privado** | No | Zonas DNS privadas para cada servicio |
| **NSGs** | No | Sí — por subnet |
| **Bastion Host** | No | Sí (con VM) |
| **VM de acceso** | No | Opcional (`deployVM=true`) Windows 11 |
| **VPN Gateway** | No | Opcional (`deployVPN=true`) |
| **Complejidad de despliegue** | Baja | Alta — requiere deploy desde dentro de la red |
| **SSH/Console Debug** | Disponible | No disponible (Flex Consumption) |
| **Cold starts** | Posibles (Flex) | Igual — depende del plan |
| **Log Stream** | Disponible | Disponible |
| **Public network de App Config** | Habilitado | Deshabilitado |
| **Cosmos DB public access** | Habilitado | Deshabilitado |

### Cambios por recurso en modo Enterprise

| Recurso | Cambio | Justificación |
|---|---|---|
| **VNet** | Creada con 6 subnets y NSGs | Aislamiento de red |
| **Function App** | `virtualNetworkSubnetId` asignado; `WEBSITE_VNET_ROUTE_ALL=1`; `WEBSITE_DNS_SERVER=168.63.129.16` | Todo el egress va por VNet |
| **Function App IP restrictions** | Allow `AzureCloud` ServiceTag; default `Deny` | Solo Azure internal traffic |
| **App Configuration** | `publicNetworkAccess: 'Disabled'`; Private Endpoint en `aiSubnet` | No expuesto en internet |
| **Cosmos DB** | Private Endpoint en `databaseSubnet`; DNS Zone `privatelink.documents.azure.com` | Acceso solo desde VNet |
| **Key Vault** | Private Endpoint en `aiSubnet`; DNS Zone `privatelink.vaultcore.azure.net` | Secretos inaccesibles desde internet |
| **AI Services** | Private Endpoint; DNS Zone `privatelink.cognitiveservices.azure.com` y `privatelink.services.ai.azure.com` | Modelos accesibles solo desde VNet |
| **Log Analytics** | `publicNetworkAccess: Disabled`; Private Link Scope; DNS Zones para agentes | Telemetría sobre red privada |
| **Bastion** | NSG con reglas `AllowHttpsInbound` + `AllowGatewayManagerInbound` | Acceso RDP/SSH seguro |

### Diagrama ASCII — Topología de red, modo Enterprise

```
Internet
    │
    │ HTTPS (sólo Bastion)
    ▼
┌─────────────────────────────────────────────────────────────────────┐
│  VNet: 10.0.0.0/23                                                   │
│                                                                       │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐ │
│  │  aiSubnet (10.0.0.0/26)      │  │  appServicesSubnet           │ │
│  │  NSG: ai-nsg                 │  │  (10.0.0.128/26)             │ │
│  │                              │  │  NSG: appServices-nsg        │ │
│  │  [PE: App Config]            │  │                              │ │
│  │  [PE: Key Vault]             │  │  (reservado para futuros     │ │
│  │  [PE: Log Analytics]         │  │   App Services)              │ │
│  │  [PE: AI Services]           │  └──────────────────────────────┘ │
│  └──────────────────────────────┘                                    │
│                                                                       │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐ │
│  │  appIntSubnet (10.0.0.64/26) │  │  databaseSubnet (10.0.1.0/26)│ │
│  │  NSG: appInt-nsg             │  │  NSG: database-nsg           │ │
│  │                              │  │                              │ │
│  │  [Function App VNet          │  │  [PE: Cosmos DB]             │ │
│  │   Integration]               │  │  [PE: Storage Account]       │ │
│  └──────────────────────────────┘  └──────────────────────────────┘ │
│                                                                       │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐ │
│  │  gatewaySubnet               │  │  AzureBastionSubnet          │ │
│  │  (10.0.1.64/26)              │  │  (10.0.1.128/26)             │ │
│  │                              │  │  NSG: bastion-nsg            │ │
│  │  [VPN Gateway]  (opcional)   │  │                              │ │
│  │                              │  │  [Azure Bastion]             │ │
│  └──────────────────────────────┘  │  [Test VM Windows 11]        │ │
│                                    └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘

Flujo de tráfico Enterprise:
  Function App (appIntSubnet) ──► App Config PE (aiSubnet)
  Function App (appIntSubnet) ──► Key Vault PE (aiSubnet)
  Function App (appIntSubnet) ──► AI Services PE (aiSubnet)
  Function App (appIntSubnet) ──► Cosmos DB PE (databaseSubnet)
  Function App (appIntSubnet) ──► Storage PE (databaseSubnet)
  VM / Developer (BastionSubnet) ──► Recursos vía IPs privadas
```

---

## 9. Patrones de Extensibilidad

### 9.1 Cómo añadir una nueva Activity al pipeline

**Paso 1**: Crear el archivo de activity en `pipeline/activities/`

```python
# pipeline/activities/myNewActivity.py
import azure.durable_functions as df
import logging
from configuration import Configuration

config = Configuration()

name = "myNewActivity"           # ← nombre usado en call_activity_with_retry
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="inputData")    # nombre exacto del argumento
def run(inputData: dict) -> dict:
    """
    Procesa ... y retorna ...
    
    Args:
        inputData: dict con campos específicos de este paso
    Returns:
        dict con el resultado
    Raises:
        Exception: se propaga para permitir reintentos de Durable Functions
    """
    try:
        # lógica del activity
        result = do_something(inputData)
        return result
    except Exception as e:
        logging.error(f"Error in myNewActivity: {e}")
        raise   # CRÍTICO: siempre re-raise para habilitar reintentos
```

**Paso 2**: Registrar el blueprint en `pipeline/function_app.py`

```python
# Importar al inicio del archivo
from activities import myNewActivity   # si está en activities/__init__.py
# o
import pipeline.activities.myNewActivity as myNewActivity

# Al final del archivo, junto a los otros registros:
app.register_functions(myNewActivity.bp)
```

**Paso 3**: Invocar desde el orquestador `process_blob`

```python
# En function_app.py, dentro de process_blob():
my_result = yield context.call_activity_with_retry(
    "myNewActivity",          # debe coincidir exactamente con name = "..."
    retry_options,
    {
        "field1": value1,
        "field2": value2,
        "instance_id": sub_orchestration_id
    }
)
```

### 9.2 Contrato de una Activity (interfaz implícita)

No hay clase base abstracta explícita — el contrato es por convención:

```python
# Firma mínima obligatoria
@bp.function_name("nombreActivity")          # str — identificador único global
@bp.activity_trigger(input_name="inputData") # nombre arbitrario pero consistente
def run(inputData: dict) -> any:             # retorno serializable a JSON
    ...
    raise                                    # re-raise en exceptions
```

**Restricciones**:
- El input debe ser serializable a JSON (dict, list, str, int, bool).
- El output debe ser serializable a JSON.
- **No usar `async def`** en activities (el orquestador ya es síncrono en el modelo Durable).
- Si la activity tiene estado, usa globals de módulo con precaución (el worker puede reutilizar el proceso).

### 9.3 Añadir nuevas configuraciones de App Configuration

1. Agregar el key-value en `infra/main.bicep` dentro de `appSettings`:
```bicep
var appSettings = [
  // ... configuraciones existentes ...
  {
    name: 'MY_NEW_CONFIG_KEY'
    value: 'my_value'
  }
]
```

2. Para secretos: usar `secureAppSettings` con referencia a Key Vault:
```bicep
var secureAppSettings = [
  {
    name: 'MY_SECRET_KEY'
    value: '{"uri": "${keyVaultUri}secrets/my-secret-name"}'
  }
]
```

3. Leer en código Python:
```python
from configuration import Configuration
config = Configuration()
value = config.get_value("MY_NEW_CONFIG_KEY")
value_with_default = config.get_value("MY_NEW_CONFIG_KEY", "default")
```

### 9.4 Añadir un nuevo tipo de archivo soportado

En `function_app.py`, extender las listas de extensiones en el orquestador:

```python
# Extensiones de audio
audio_extensions = ['wav', 'mp3', 'opus', 'ogg', 'flac', 'wma', 'aac', 'webm', 'mp4']

# Extensiones de documentos  
document_extensions = ['pdf', 'docx', 'doc', 'xlsx', 'pptx', 'jpg', 'jpeg', 'png', 'tiff', 'bmp']

# Nuevo: extensiones de texto plano
text_extensions = ['txt', 'csv', 'json', 'xml']

# En el routing:
elif file_extension in text_extensions:
    text_result = yield context.call_activity_with_retry(
        "readTextBlob", retry_options, blob_input
    )
```

### 9.5 Paso a paso para contribuir al proyecto

```bash
# 1. Fork y clone
git clone https://github.com/<tu-usuario>/ai-document-processor-demos.git
cd ai-document-processor-demos

# 2. Crear y activar entorno virtual
python3.11 -m venv .venv
source .venv/bin/activate   # Linux/macOS
.venv\Scripts\activate      # Windows

# 3. Instalar dependencias de development
pip install -r pipeline/requirements.txt

# 4. Configurar local.settings.json
# Copiar de un deploy existente:
cd pipeline
func azure functionapp fetch-app-settings <funcapp-name>
# O crear manualmente con las variables necesarias

# 5. Iniciar localmente
cd ..
./scripts/startLocal.sh     # Linux/macOS
./scripts/startLocal.ps1    # Windows

# 6. Probar con el notebook
# Abrir test_client.ipynb y ejecutar las celdas

# 7. Variables de entorno necesarias para desarrollo local
# AZURE_FUNCTIONS_ENVIRONMENT=Development   (activa polling trigger + CLI credential)
# APP_CONFIGURATION_URI o AZURE_APPCONFIG_CONNECTION_STRING
# AZURE_TENANT_ID
```

**Nota sobre local.settings.json**: Este archivo no se versiona (`.gitignore`). Para desarrollo local con aislamiento de red enterprise, la única opción es desplegar desde dentro de la VNet usando la VM de test o una conexión VPN.

---

*Documento generado a partir del análisis estático del repositorio `Azure/ai-document-processor` — rama `main`.*  
*Fecha de análisis: 25 de marzo de 2026.*
