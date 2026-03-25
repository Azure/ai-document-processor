# AI Document Processor — Guía General de la Solución

> **Audiencia**: Arquitectos de soluciones, pre-sales, tomadores de decisiones  
> **Propósito**: Entender el *qué* y el *cómo* sin entrar en detalles de código  
> **Última actualización**: Marzo 2026

---

## Tabla de Contenidos

1. [¿Qué es AI Document Processor?](#1-qué-es-ai-document-processor)
2. [¿Qué problema resuelve?](#2-qué-problema-resuelve)
3. [Conceptos clave](#3-conceptos-clave)
4. [Componentes principales](#4-componentes-principales)
5. [¿Cómo funciona el flujo completo?](#5-cómo-funciona-el-flujo-completo)
6. [Servicios de Azure utilizados](#6-servicios-de-azure-utilizados)
7. [Modos de despliegue](#7-modos-de-despliegue)
8. [Ejemplo práctico](#8-ejemplo-práctico)
9. [Resumen ejecutivo](#9-resumen-ejecutivo)

---

## 1. ¿Qué es AI Document Processor?

**Analogía**: Imagina una fábrica de manufactura donde los documentos entran como materia prima sin procesar (PDFs, audios, imágenes), pasan por estaciones automatizadas que les dan forma, y salen como productos terminados: datos estructurados, resúmenes o reportes listos para usar.

**Propuesta de valor en una frase**:
> AI Document Processor es un acelerador de Azure que automatiza la extracción, análisis y estructuración de documentos mediante Inteligencia Artificial, eliminando el procesamiento manual y reduciendo el tiempo de extracción de información de horas a segundos.

---

## 2. ¿Qué problema resuelve?

| Desafío común | Cómo lo resuelve ADP |
|---|---|
| Revisar documentos manualmente lleva horas o días | El pipeline procesa documentos automáticamente en ~30 segundos |
| Extraer datos de PDFs escaneados es costoso y propenso a errores | Azure Document Intelligence (OCR) extrae el texto con alta precisión |
| Formatos heterogéneos: PDF, Word, audio, imágenes | Detecta el tipo de archivo y aplica el motor correcto automáticamente |
| Configurar infraestructura de IA desde cero toma semanas | Plantillas Bicep aprovisionan todo el entorno con un solo comando |
| Gestión de permisos y secretos es compleja y riesgosa | Identidades administradas y RBAC se configuran automáticamente sin contraseñas expuestas |
| Escalar el procesamiento ante picos de demanda | Opción de plan de consumo flexible (serverless) que escala a cero o a 100 instancias |
| Adaptar el procesamiento a casos de uso específicos | Arquitectura modular donde cada paso del pipeline es reemplazable |

---

## 3. Conceptos clave

### Pipeline (Canal de procesamiento)
Un conjunto de pasos encadenados que transforman un documento de entrada en datos estructurados de salida. Cada paso hace una tarea específica y pasa el resultado al siguiente.

```
Entrada (Blob) → Paso 1: Extraer texto → Paso 2: Analizar con IA → Paso 3: Guardar resultado
```

### Activity (Actividad)
Un paso individual dentro del pipeline. Cada actividad tiene una responsabilidad única: leer un archivo, llamar a un modelo de IA, o escribir un resultado. Son los "operarios" de la fábrica.

```yaml
# Ejemplo conceptual de actividades disponibles
actividades:
  - runDocIntel      # Extrae texto de documentos (OCR)
  - speechToText     # Transcribe audio a texto
  - callAoai         # Analiza texto con Azure OpenAI
  - callAoaiMultiModal  # Procesa imágenes y PDFs directamente con visión
  - writeToBlob      # Escribe el resultado en almacenamiento
```

### Orchestrator (Orquestador)
El "gerente de planta" que coordina en qué orden se ejecutan las actividades, maneja errores y reintentos, y asegura que si algo falla, se intente de nuevo automáticamente (hasta 5 veces).

```
                    ┌─────────────────────┐
                    │    Orchestrator      │
                    │  (process_blob)      │
                    └──────────┬──────────┘
                               │ coordina
              ┌────────────────┼─────────────────┐
              ▼                ▼                  ▼
        runDocIntel        callAoai          writeToBlob
        (extrae texto)   (analiza con IA)   (guarda resultado)
```

### Prompts (Instrucciones para la IA)
Las instrucciones escritas en lenguaje natural que le dicen al modelo de IA qué hacer con el texto extraído. Se almacenan en un archivo YAML y son fáciles de modificar sin tocar código.

```yaml
# data/prompts.yaml — ejemplo simplificado
system_prompt: |
  Extrae las entidades clave del documento y devuelve un JSON estructurado
  con: título, fecha, participantes, y puntos clave.

user_prompt: |
  Lee el siguiente texto y genera la tabla solicitada.
  Texto:
```

### Bronze / Silver / Gold (Capas de datos)
Metáfora del ciclo de vida de los datos:
- **Bronze**: Documentos originales sin procesar (entrada)
- **Silver**: Datos estructurados generados por el pipeline (salida)
- **Gold**: (Extensión futura) Datos refinados y consolidados para reportes

---

## 4. Componentes principales

| Componente | Propósito | Tecnología | Puerto / Endpoint |
|---|---|---|---|
| **Function App** | Orquesta y ejecuta el pipeline | Azure Durable Functions (Python) | HTTP `POST /api/client` |
| **Almacenamiento de datos** | Contiene los documentos en todas sus etapas | Azure Blob Storage | Interno (SDK) |
| **Motor de IA** | Analiza y estructura el contenido extraído | Azure OpenAI via AI Foundry | Interno (SDK) |
| **Extractor de documentos** | Lee texto de PDFs, Word, imágenes | Azure Document Intelligence | Interno (SDK) |
| **Configuración centralizada** | Gestiona parámetros sin redesplegar | Azure App Configuration | Interno (SDK) |
| **Observabilidad** | Monitoreo, logs y alertas | Application Insights + Log Analytics | Portal Azure |

### Cómo se interconectan

```
                          ┌─────────────────────────────────────────┐
  Usuario / Sistema   ──► │          Azure Function App              │
  (HTTP o evento)         │  ┌─────────────┐  ┌──────────────────┐  │
                          │  │ Orquestador │  │    Actividades   │  │
                          │  └──────┬──────┘  └────────┬─────────┘  │
                          └─────────│───────────────────│────────────┘
                                    │                   │
              ┌─────────────────────┼───────────────────┼──────────────┐
              ▼                     ▼                   ▼              ▼
     App Configuration      Document Intelligence   Azure OpenAI   Blob Storage
     (lee configuración)     (extrae texto)         (analiza)      (lee/escribe)
```

---

## 5. ¿Cómo funciona el flujo completo?

### Flujo automático (iniciado por un nuevo documento)

```
1. Usuario sube un archivo        2. Event Grid detecta          3. Function App
   al contenedor "bronze"  ──────►  el nuevo blob y notifica ──► se activa
   del Storage Account               a la Function App
                                                                      │
                                                                      ▼
7. Resultado listo en             6. AI escribe JSON           4. Orquestador evalúa
   contenedor "silver"  ◄───────    estructurado al blob ◄──── el tipo de archivo
   Storage Account                                                    │
                                                                      ▼
                                  5a. PDF/Word → Document Intelligence (OCR)
                                  5b. Audio → Speech to Text
                                  5c. Imagen → Visión multimodal de OpenAI
```

### Paso a paso detallado

1. **Carga del documento**: El usuario (o sistema externo) deposita un archivo en el contenedor `bronze` del Storage Account.
2. **Detección del evento**: Azure Event Grid detecta el nuevo archivo y envía una notificación a la Function App sin necesidad de que nadie monitoree manualmente.
3. **Inicio del pipeline**: El orquestador recibe la notificación, identifica el archivo (nombre, ruta, URI) y determina el tipo de archivo por su extensión.
4. **Extracción de contenido**:
   - Si es PDF, Word, imagen → se llama a Azure Document Intelligence para extraer el texto.
   - Si es audio (MP3, WAV) → se llama a Azure Speech to Text para transcribir.
   - Si es una imagen y el modo multimodal está activo → se envía directamente a Azure OpenAI con capacidades de visión.
5. **Análisis con IA**: El texto extraído se combina con las instrucciones del archivo `prompts.yaml` y se envía a Azure OpenAI, que devuelve un JSON estructurado con las entidades e insights relevantes.
6. **Almacenamiento del resultado**: El JSON generado se escribe en el contenedor `silver` del Storage Account.
7. **Consumo del resultado**: Una interfaz de usuario, un reporte, u otro sistema downstream lee el resultado estructurado.

---

## 6. Servicios de Azure utilizados

| Servicio | Propósito en la solución | SKU / Nivel recomendado |
|---|---|---|
| **Azure Function App** | Ejecuta el pipeline de procesamiento | Dedicated (B2/S1) o Flex Consumption (FC1) |
| **Azure AI Foundry** | Aloja y gestiona el modelo de lenguaje | GPT-4o mini (para inicio), GPT-4o (producción) |
| **Azure AI Services** | OCR (Document Intelligence) y Speech to Text | Standard S0 |
| **Azure Blob Storage (datos)** | Almacena documentos bronze/silver/gold | Standard LRS o ZRS |
| **Azure Blob Storage (funciones)** | Almacenamiento interno de la Function App | Standard LRS |
| **Azure App Configuration** | Gestión centralizada de parámetros | Free o Standard |
| **Azure Key Vault** | Gestión de secretos y certificados | Standard |
| **Azure Cosmos DB** | Historial de conversaciones y prompts | Serverless (inicio) o Provisioned |
| **Application Insights** | Monitoreo y trazas de la aplicación | Incluido con Log Analytics |
| **Log Analytics Workspace** | Almacén centralizado de logs y consultas | Pay-per-use |
| **Event Grid System Topic** | Trigger confiable ante nuevos blobs | Incluido en Storage |
| **Virtual Network** | Aislamiento de red (modo enterprise) | Varios subnets dedicados |
| **Private Endpoints** | Acceso privado a todos los servicios | Por servicio habilitado |

---

## 7. Modos de despliegue

### Comparación de modos

| Aspecto | Modo Básico (Público) | Modo Enterprise (Red Privada) |
|---|---|---|
| **Conectividad** | Internet pública con autenticación | Red virtual privada (VNet) |
| **Endpoints** | Públicos protegidos con API keys | Privados, no expuestos a internet |
| **Acceso a recursos** | Directo desde cualquier lugar | Solo desde dentro de la VNet |
| **Implementación** | Simple, un solo comando | Requiere VM o VPN para el despliegue |
| **Depuración** | Fácil (SSH, portal, logs directos) | Requiere conectarse a la VM |
| **Cumplimiento normativo** | Básico | Alto (apto para sectores regulados) |
| **Tiempo de implementación** | ~15 minutos | ~30-45 minutos |
| **Costo adicional** | Ninguno | VM, Bastion, VPN Gateway |

### Topología de red — Modo Enterprise

```
  Internet / Usuario                    Azure Virtual Network
  ──────────────                        ─────────────────────────────────────
                                        │                                    │
  Desarrollador ──► VM Bastion ────────►│  Subnet: App Services              │
  (solo durante)    (Jump Host)         │  ┌────────────────────────────┐    │
  el despliegue                         │  │  Function App              │    │
                                        │  │  (Private Endpoint)        │    │
                                        │  └───────────┬────────────────┘    │
                                        │              │ (tráfico interno)   │
                                        │  Subnet: AI  │  Subnet: Datos      │
                                        │  ┌──────────┐│  ┌──────────────┐   │
                                        │  │ AI Svcs  ││  │ Storage      │   │
                                        │  │ OpenAI   ││  │ CosmosDB     │   │
                                        │  │ Doc Intel││  │ Key Vault    │   │
                                        │  └──────────┘│  └──────────────┘   │
                                        │              │                     │
                                        └─────────────────────────────────────┘
                                         (Todo el tráfico es interno, nunca
                                          atraviesa internet pública)
```

---

## 8. Ejemplo práctico

**Caso de uso**: Una empresa de recursos humanos quiere procesar automáticamente CVs en PDF para extraer datos estructurados (nombre, empresa, ubicación, habilidades, responsabilidades).

### Configuración del prompt (`data/prompts.yaml`)

```yaml
system_prompt: |
  Genera un objeto JSON estructurado que represente los roles dentro de una empresa.
  Cada rol debe incluir: título del cargo, empresa, ubicación, calificaciones
  requeridas y responsabilidades clave.
  Devuelve el resultado como un array JSON con esta estructura:
  [
    {
      "role": "Nombre del Cargo",
      "company": "Nombre de la Empresa",
      "location": "Ubicación",
      "qualifications": ["Calificación 1", "Calificación 2"],
      "responsibilities": ["Responsabilidad 1", "Responsabilidad 2"]
    }
  ]

user_prompt: |
  Lee el siguiente texto y genera la tabla solicitada.
  Texto:
```

### Qué hace cada paso

| Paso | Actividad | Qué sucede en lenguaje natural |
|---|---|---|
| 1 | *Upload* | El departamento de RRHH sube `cv_candidato.pdf` al contenedor `bronze` |
| 2 | *Event Detection* | Event Grid detecta el archivo nuevo y avisa a la Function App automáticamente |
| 3 | *runDocIntel* | Azure Document Intelligence lee el PDF (incluso si está escaneado) y extrae todo el texto |
| 4 | *callAoai* | Azure OpenAI recibe el texto del CV más las instrucciones del prompt y genera un JSON estructurado con los datos del candidato |
| 5 | *writeToBlob* | El JSON resultante se guarda en el contenedor `silver` con el mismo nombre base del archivo original |
| 6 | *Consumo* | La aplicación de RRHH lee el JSON del `silver` y lo muestra en su interfaz o lo importa a su base de datos |

**Resultado esperado** (en el contenedor `silver`):

```json
[
  {
    "role": "Gerente de Proyectos",
    "company": "Contoso S.A.",
    "location": "Ciudad de México (Híbrido)",
    "qualifications": ["PMP Certificado", "Inglés avanzado", "5+ años de experiencia"],
    "responsibilities": ["Gestionar equipo de 10 personas", "Reportar KPIs al CTO"]
  }
]
```

---

## 9. Resumen ejecutivo

| Aspecto | Detalle |
|---|---|
| **Tipo de solución** | Acelerador / plantilla de referencia (*accelerator*) — no un producto terminado |
| **Patrón de arquitectura** | Pipeline de función encadenada (*function chaining*) con Durable Functions |
| **Nube** | Microsoft Azure (100%) |
| **Modelo de despliegue** | Infraestructura como Código con Bicep + Azure Developer CLI (`azd up`) |
| **Formatos soportados** | PDF, Word (.docx/.doc), Excel, PowerPoint, imágenes (JPG/PNG/TIFF), audio (MP3/WAV/OGG/AAC) |
| **Seguridad** | Identidades administradas, RBAC automático, sin contraseñas hardcodeadas, opción de red privada total |
| **Escalabilidad** | Manual (plan dedicado) o automática 0–N instancias (Flex Consumption serverless) |
| **Observabilidad** | Application Insights para trazas, Log Analytics para consultas avanzadas, Log Stream en tiempo real |
| **Tiempo de despliegue** | ~15 min (público) / ~30–45 min (red privada) |
| **Actores esperados** | 1 desarrollador para despliegue inicial; no se requiere equipo de infraestructura dedicado |
| **Casos de uso típicos** | Procesamiento de CVs, contratos, facturas, reportes médicos, transcripción de reuniones |
| **Personalización** | Prompts modificables sin código; lógica de pipeline extensible por actividades Python |
