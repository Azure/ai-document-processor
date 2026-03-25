# AI Document Processor — Catálogo de Casos de Uso

> **Audiencia**: Desarrolladores, arquitectos de soluciones, pre-sales  
> **Propósito**: Catálogo de escenarios implementables con configuración completa y funcional  
> **Última actualización**: Marzo 2026

---

## Tabla de Contenidos

1. [Criterios de Selección de Casos de Uso](#1-criterios-de-selección-de-casos-de-uso)
2. [Catálogo de Casos de Uso](#2-catálogo-de-casos-de-uso)
   - [CU-01: Análisis y estructuración de CVs](#cu-01-análisis-y-estructuración-de-cvs)
   - [CU-02: Transcripción de reuniones y juntas](#cu-02-transcripción-de-reuniones-y-juntas)
   - [CU-03: Extracción de datos de facturas](#cu-03-extracción-de-datos-de-facturas)
   - [CU-04: Procesamiento de formularios médicos (multimodal)](#cu-04-procesamiento-de-formularios-médicos-multimodal)
   - [CU-05: Clasificación y triaje de emails](#cu-05-clasificación-y-triaje-de-emails)
   - [CU-06: Análisis de contratos legales](#cu-06-análisis-de-contratos-legales)
   - [CU-07: Extracción de tablas de informes financieros](#cu-07-extracción-de-tablas-de-informes-financieros)
   - [CU-08: Análisis de llamadas de soporte al cliente](#cu-08-análisis-de-llamadas-de-soporte-al-cliente)
   - [CU-09: Procesamiento masivo de documentos de auditoría](#cu-09-procesamiento-masivo-de-documentos-de-auditoría)
   - [CU-10: Enrutamiento condicional por tipo de documento](#cu-10-enrutamiento-condicional-por-tipo-de-documento)
   - [CU-11: Preparación de corpus para RAG (búsqueda semántica)](#cu-11-preparación-de-corpus-para-rag-búsqueda-semántica)
   - [CU-12: Comparación y reconciliación de documentos múltiples](#cu-12-comparación-y-reconciliación-de-documentos-múltiples)
3. [Tabla Resumen de Componentes por Caso de Uso](#3-tabla-resumen-de-componentes-por-caso-de-uso)
4. [Índice de Samples Oficiales Incluidos en el Repositorio](#4-índice-de-samples-oficiales-incluidos-en-el-repositorio)
5. [Combinaciones de Componentes Recomendadas](#5-combinaciones-de-componentes-recomendadas)

---

## 1. Criterios de Selección de Casos de Uso

### Qué tipos de problemas puede resolver ADP

ADP es la opción correcta cuando el problema tiene una o más de estas características:

| Señal | Descripción |
|---|---|
| **Documentos no estructurados** | El dato está en PDFs, Word, imágenes o audio, no en una base de datos |
| **Volumen repetitivo** | El mismo tipo de documento se procesa regularmente (diario, semanal) |
| **Extracción de entidades** | Se necesitan datos específicos dentro de un texto más extenso |
| **Clasificación o enrutamiento** | Los documentos deben categorizarse para decidir qué acción ejecutar |
| **Resumen o síntesis** | El documento es largo y el usuario necesita un resumen ejecutivo |
| **Transformación de formato** | El resultado debe estar en JSON, CSV o tabla estructurada para otro sistema |

### Cómo mapear un caso de negocio a componentes del proyecto

```
1. ¿Cuál es el formato de entrada?
   ├── PDF, Word, Excel, imagen  →  runDocIntel (OCR estándar)
   ├── PDF con tablas complejas  →  callAoaiMultiModal (visión directa)
   └── MP3, WAV, OGG, AAC       →  speechToText

2. ¿Qué quiero obtener?
   └── Entidades, resumen, clasificación → callAoai (configura en prompts.yaml)

3. ¿Dónde va el resultado?
   └── Siempre → writeToBlob (contenedor silver o gold)
```

---

## 2. Catálogo de Casos de Uso

---

### CU-01: Análisis y estructuración de CVs

**Sector/Industria**: Recursos Humanos

**Descripción del problema**: El equipo de RRHH recibe cientos de CVs en PDF cada semana. Leer y extrae manualmente los datos de cada candidato (cargo, empresa, habilidades, años de experiencia) consume 5-10 minutos por documento.

**Solución con AI Document Processor**:
1. RRHH sube el archivo `cv_candidato.pdf` al contenedor `bronze`
2. Event Grid detecta el nuevo blob y activa el pipeline
3. `runDocIntel` extrae el texto completo del CV
4. `callAoai` recibe el texto y el prompt con instrucciones de extracción estructurada
5. `writeToBlob` guarda el JSON resultante en `silver` con el nombre `cv_candidato-output.json`
6. El sistema de ATS (Applicant Tracking System) consume el JSON

**Actividades utilizadas**:
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un asistente especializado en análisis de perfiles profesionales.
  Dado un texto extraído de un CV o currículum vitae, extrae las entidades
  relevantes y devuelve un objeto JSON con exactamente esta estructura:

  {
    "nombre_completo": "string",
    "email": "string o null",
    "telefono": "string o null",
    "ubicacion": "string",
    "resumen_profesional": "string de máximo 3 oraciones",
    "experiencia": [
      {
        "cargo": "string",
        "empresa": "string",
        "periodo": "string",
        "responsabilidades": ["string"]
      }
    ],
    "educacion": [
      {
        "titulo": "string",
        "institucion": "string",
        "anio": "string o null"
      }
    ],
    "habilidades_tecnicas": ["string"],
    "idiomas": ["string"],
    "certificaciones": ["string"]
  }

  Devuelve únicamente el objeto JSON, sin explicaciones adicionales.

user_prompt: |
  Analiza el siguiente texto extraído de un CV y genera el perfil estructurado:

  Texto:
```

**Variables de entorno requeridas** (`azd env set`):

```bash
azd env set PROMPT_FILE "prompts.yaml"
azd env set FINAL_OUTPUT_CONTAINER "silver"
azd env set AOAI_MULTI_MODAL "false"
```

**Notas de implementación**:
- Soporta PDFs, DOCX y archivos escaneados (TIFF, JPG)
- Para CVs con tablas de habilidades en formato gráfico complejo, activar `AOAI_MULTI_MODAL=true`
- El campo `email` puede ser `null` si el candidato no lo incluyó; el prompt debe manejarlo explícitamente
- Extensión posible: integrar con Azure Logic Apps para enviar el JSON a un ATS (SmartRecruiters, Workday)

---

### CU-02: Transcripción de reuniones y juntas

**Sector/Industria**: Corporativo / Todos los sectores

**Descripción del problema**: Las reuniones de equipo, demos con clientes o juntas de directivos se graban en audio pero nadie tiene tiempo de escuchar grabaciones de 1-2 horas para extraer los acuerdos y puntos de acción.

**Solución con AI Document Processor**:
1. Al terminar la reunión, el sistema sube el archivo `meeting_2026-03-25.mp3` a `bronze`
2. `speechToText` llama a la API de Azure AI Speech y transcribe el audio completo
3. `callAoai` recibe la transcripción y genera un resumen ejecutivo con puntos de acción
4. `writeToBlob` escribe el resumen en `silver`

**Actividades utilizadas**:
- `speechToText` → `callAoai` → `writeToBlob`

**Activación correcta de la ruta de audio** (automática en `function_app.py`):

```python
# El orquestador detecta la extensión .mp3 y enruta automáticamente:
audio_extensions = ['wav', 'mp3', 'opus', 'ogg', 'flac', 'wma', 'aac', 'webm']
# ...
elif file_extension in audio_extensions:
    text_result = yield context.call_activity_with_retry("speechToText", ...)
```

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un asistente experto en análisis de reuniones de negocios.
  Dada la transcripción de una reunión, genera un informe estructurado en JSON
  con el siguiente formato:

  {
    "titulo_reunion": "string inferido del contexto",
    "fecha": "string o null si no se menciona",
    "duracion_estimada": "string",
    "participantes": ["string"],
    "resumen_ejecutivo": "string de 3-5 oraciones",
    "temas_discutidos": [
      {
        "tema": "string",
        "puntos_clave": ["string"]
      }
    ],
    "decisiones_tomadas": ["string"],
    "puntos_de_accion": [
      {
        "tarea": "string",
        "responsable": "string o 'No asignado'",
        "fecha_limite": "string o null"
      }
    ],
    "proxima_reunion": "string o null"
  }

user_prompt: |
  Analiza la siguiente transcripción de reunión y genera el informe estructurado:

  Transcripción:
```

**Variables de entorno requeridas**:

```bash
azd env set PROMPT_FILE "meeting-prompts.yaml"
azd env set FINAL_OUTPUT_CONTAINER "silver"
```

**Notas de implementación**:
- La API de Speech transcribe en `en-US` por defecto; para reuniones en español cambiar `locale` a `es-MX` o `es-ES` en `speechToText.py`
- Los archivos de audio grandes (>1 hora) pueden tardar varios minutos; los reintentos automáticos (5 intentos) manejan timeouts transitorios
- Limitación: la identificación de hablantes (diarización) no está activada por defecto; activar `wordLevelTimestampsEnabled: true` y postprocesar
- Extensión: integrar con Microsoft Teams para capturar grabaciones automáticamente via Graph API

---

### CU-03: Extracción de datos de facturas

**Sector/Industria**: Finanzas / Cuentas por Pagar

**Descripción del problema**: El equipo de contabilidad procesa cientos de facturas de proveedores cada mes. Ingresar manualmente los datos (proveedor, RFC, importes, fechas, conceptos) a SAP o al ERP es lento y propenso a errores.

**Solución con AI Document Processor**:
1. Las facturas en PDF se depositan automáticamente en `bronze` (desde email, desde portal de proveedores)
2. `runDocIntel` extrae el texto y los datos tabulares de la factura
3. `callAoai` estructra los campos en un JSON listo para importar al ERP
4. `writeToBlob` escribe en `silver`; el conector del ERP lee el JSON periódicamente

**Actividades utilizadas**:
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un asistente especializado en procesamiento de facturas fiscales.
  Dado el texto extraído de una factura (puede ser CFDI mexicano, factura europea
  o norteamericana), extrae todos los campos relevantes y devuelve un objeto JSON
  con esta estructura:

  {
    "numero_factura": "string",
    "fecha_emision": "YYYY-MM-DD o null",
    "fecha_vencimiento": "YYYY-MM-DD o null",
    "moneda": "MXN | USD | EUR",
    "emisor": {
      "nombre": "string",
      "rfc_nif_ein": "string o null",
      "direccion": "string o null"
    },
    "receptor": {
      "nombre": "string",
      "rfc_nif_ein": "string o null"
    },
    "conceptos": [
      {
        "descripcion": "string",
        "cantidad": "number",
        "precio_unitario": "number",
        "importe": "number"
      }
    ],
    "subtotal": "number",
    "impuestos": "number",
    "total": "number",
    "metodo_pago": "string o null",
    "notas": "string o null"
  }

  Si un campo no está presente en el documento, usa null.
  Devuelve únicamente el objeto JSON.

user_prompt: |
  Extrae todos los datos de la siguiente factura:

  Texto:
```

**Variables de entorno requeridas**:

```bash
azd env set PROMPT_FILE "invoice-prompts.yaml"
azd env set FINAL_OUTPUT_CONTAINER "silver"
```

**Notas de implementación**:
- `runDocIntel` usa el modelo `prebuilt-read` que extrae texto + tablas; para facturas muy estructuradas se puede cambiar a `prebuilt-invoice` de Azure Document Intelligence para mayor precisión en campos estándar
- Para activar el modelo especializado, modificar `runDocIntel.py`: cambiar `"prebuilt-read"` por `"prebuilt-invoice"`
- Limitación: facturas en idiomas con alfabeto no latino (árabe, chino) requieren configuración adicional del endpoint de Document Intelligence
- Extensión posible: añadir validación en `callAoai` comparando RFC/NIF con una lista maestra en Cosmos DB

---

### CU-04: Procesamiento de formularios médicos (multimodal)

**Sector/Industria**: Salud

**Descripción del problema**: Los hospitales reciben formularios de admisión, historiales clínicos escaneados y órdenes médicas en imágenes o PDFs con letra manuscrita o layouts complejos que los OCR tradicionales no leen bien.

**Solución con AI Document Processor**:
1. El formulario escaneado (PDF o PNG) llega al contenedor `bronze`
2. Con `AOAI_MULTI_MODAL=true`, el pipeline usa `callAoaiMultiModal` que convierte cada página del PDF a imágenes base64
3. Azure OpenAI (GPT-4o con visión) interpreta directamente las imágenes, incluidas tablas visuales y texto manuscrito
4. `writeToBlob` guarda el JSON estructurado en `silver`

**Actividades utilizadas**:
- `callAoaiMultiModal` → `writeToBlob`

**Activación del modo multimodal**:

```bash
# Activar procesamiento de visión directa (saltea runDocIntel)
azd env set AOAI_MULTI_MODAL "true"
```

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un asistente en extracción de datos médicos de formularios clínicos.
  Analiza las imágenes proporcionadas del formulario y extrae todos los datos
  visibles, incluyendo texto impreso y manuscrito.
  Devuelve un objeto JSON con esta estructura:

  {
    "tipo_formulario": "Admisión | Historia Clínica | Orden Médica | Otro",
    "paciente": {
      "nombre": "string o null",
      "fecha_nacimiento": "YYYY-MM-DD o null",
      "id_paciente": "string o null",
      "genero": "string o null",
      "alergias": ["string"]
    },
    "medico_responsable": "string o null",
    "fecha_atencion": "YYYY-MM-DD o null",
    "diagnostico_principal": "string o null",
    "diagnosticos_secundarios": ["string"],
    "medicamentos": [
      {
        "nombre": "string",
        "dosis": "string",
        "frecuencia": "string"
      }
    ],
    "procedimientos": ["string"],
    "notas_clinicas": "string o null",
    "campos_adicionales": {}
  }

  Si no puedes leer claramente un campo, usa null. Nunca inventes datos médicos.

user_prompt: |
  Analiza este formulario médico y extrae los datos estructurados:
```

**Notas de implementación**:
- Requiere que el modelo desplegado en AI Foundry sea GPT-4o (con capacidades de visión); GPT-4o-mini tiene soporte limitado de visión
- Cada página del PDF se convierte a imagen PNG en memoria (PyMuPDF/fitz); para formularios de más de 10 páginas considerar dividir el PDF
- **Consideración de privacidad crítica**: datos de salud (PHI/HIPAA) requieren que todos los servicios tengan Private Endpoints activados (`networkIsolation=true`)
- Extensión posible: escribir al contenedor `gold` después de pasar por una segunda validación contra ICD-10

---

### CU-05: Clasificación y triaje de emails

**Sector/Industria**: Retail / Atención al Cliente / Cualquier sector

**Descripción del problema**: El buzón de soporte recibe miles de correos diariamente con consultas, quejas, solicitudes de devolución y preguntas de ventas, todos mezclados. El equipo pierde tiempo clasificando manualmente antes de atender.

**Solución con AI Document Processor**:
1. Un exportador de emails (Logic Apps, Power Automate) guarda el cuerpo del email como `.txt` en `bronze`
2. `runDocIntel` o un handler de texto plano lee el contenido
3. `callAoai` clasifica el email y extrae entidades relevantes
4. `writeToBlob` guarda el JSON de clasificación en `silver`
5. Un receptor (Logic Apps) lee el JSON y enruta al agente correcto en el CRM

**Actividades utilizadas**:
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un clasificador experto de correos de atención al cliente.
  Dado el contenido de un email, analiza su intención y urgencia,
  y devuelve un objeto JSON con exactamente esta estructura:

  {
    "categoria": "Queja | Consulta | Solicitud_Devolucion | Pedido_Nuevo |
                  Soporte_Tecnico | Facturacion | Otro",
    "subcategoria": "string descriptivo",
    "urgencia": "Alta | Media | Baja",
    "sentimiento": "Positivo | Neutro | Negativo | Muy_Negativo",
    "cliente": {
      "nombre": "string o null",
      "numero_pedido": "string o null",
      "producto_mencionado": "string o null"
    },
    "resumen": "string de máximo 2 oraciones describiendo el problema",
    "respuesta_sugerida": "string con un borrador de respuesta apropiada",
    "requiere_escalamiento": true,
    "tags": ["string"]
  }

user_prompt: |
  Clasifica el siguiente email de cliente:

  Correo:
```

**Variables de entorno requeridas**:

```bash
azd env set PROMPT_FILE "email-classification-prompts.yaml"
azd env set FINAL_OUTPUT_CONTAINER "silver"
```

**Notas de implementación**:
- Los archivos `.txt` son procesados por `runDocIntel` con el modelo `prebuilt-read` sin problema
- Para alta velocidad considera el plan Flex Consumption que escala automáticamente ante picos
- Limitación: el pipeline actual es sincrónico; si el volumen supera 100 emails/minuto considerar Event Grid con múltiples instancias
- Extensión: usar `pipelineUtils/db.py` → `save_chat_message()` para mantener historial de clasificaciones por conversationId en Cosmos DB

---

### CU-06: Análisis de contratos legales

**Sector/Industria**: Legal / Finanzas / Corporativo

**Descripción del problema**: El equipo legal revisa docenas de contratos cada mes buscando cláusulas de riesgo, fechas de vencimiento, obligaciones de las partes y penalizaciones. Cada revisión manual toma 2-4 horas por contrato.

**Solución con AI Document Processor**:
1. El contrato en PDF se carga en `bronze`
2. `runDocIntel` extrae todo el texto (incluyendo paginación, numeración de cláusulas)
3. `callAoai` hace análisis legal estructurado identificando entidades y riesgos
4. `writeToBlob` escribe el análisis en `silver`

**Actividades utilizadas**:
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un asistente de análisis legal especializado en contratos mercantiles.
  Dado el texto completo de un contrato, extrae y estructura la información
  clave en el siguiente formato JSON:

  {
    "tipo_contrato": "Servicios | Compraventa | Arrendamiento | NDA | Laboral | Otro",
    "partes": [
      {
        "rol": "Vendedor | Comprador | Prestador | Cliente | Empleador | Empleado | Otro",
        "nombre": "string",
        "representante_legal": "string o null"
      }
    ],
    "fecha_firma": "YYYY-MM-DD o null",
    "fecha_inicio_vigencia": "YYYY-MM-DD o null",
    "fecha_vencimiento": "YYYY-MM-DD o null",
    "renovacion_automatica": true,
    "monto_contrato": "string con moneda o null",
    "clausulas_clave": [
      {
        "numero_clausula": "string",
        "titulo": "string",
        "resumen": "string",
        "nivel_riesgo": "Alto | Medio | Bajo"
      }
    ],
    "penalizaciones": ["string"],
    "obligaciones_parte_a": ["string"],
    "obligaciones_parte_b": ["string"],
    "ley_aplicable": "string o null",
    "jurisdiccion": "string o null",
    "banderas_rojas": ["string"],
    "recomendaciones": ["string"]
  }

  Sé objetivo y preciso. No interpretes más allá de lo que dice el texto.

user_prompt: |
  Analiza el siguiente contrato y genera el informe legal estructurado:

  Texto del contrato:
```

**Notas de implementación**:
- Contratos largos (>50 páginas) pueden exceder el contexto del modelo; considerar dividir por secciones usando `list_blobs` para procesar páginas en paralelo (ver CU-12)
- El campo `banderas_rojas` es más útil cuando el prompt incluye ejemplos específicos de cláusulas riesgosas para el sector del cliente
- Extensión: conectar con Azure AI Search para indexar los contratos analizados y hacer búsqueda semántica (ver CU-11)
- Limitación legal: el análisis es una ayuda de primera revisión; siempre requiere validación de un abogado

---

### CU-07: Extracción de tablas de informes financieros

**Sector/Industria**: Finanzas / Banca / Inversiones

**Descripción del problema**: Los analistas financieros extraen manualmente datos de estados de resultados, balances y reportes anuales (10-K, 20-F) para cargarlos en Excel o en sistemas de modelado financiero.

**Solución con AI Document Processor**:
1. El informe financiero (PDF) se deposita en `bronze`
2. Con `AOAI_MULTI_MODAL=true`, las páginas con tablas financieras se procesan como imágenes
3. `callAoaiMultiModal` interpreta visualmente las tablas y extrae los datos numéricos
4. `writeToBlob` guarda el JSON con los valores financieros en `silver`

**Actividades utilizadas**:
- `callAoaiMultiModal` → `writeToBlob`

**Activación del modo multimodal**:

```bash
azd env set AOAI_MULTI_MODAL "true"
```

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un analista financiero experto en extracción de datos de reportes corporativos.
  Analiza las imágenes del informe financiero y extrae todos los datos numéricos
  relevantes, prestando atención especial a tablas, gráficas y estados financieros.

  Devuelve un objeto JSON con esta estructura:

  {
    "empresa": "string",
    "periodo_reportado": "string (ej. FY2025, Q3 2025)",
    "moneda": "string",
    "estado_resultados": {
      "ingresos_totales": "number o null",
      "costo_ventas": "number o null",
      "utilidad_bruta": "number o null",
      "gastos_operativos": "number o null",
      "ebitda": "number o null",
      "utilidad_neta": "number o null"
    },
    "balance_general": {
      "activos_totales": "number o null",
      "pasivos_totales": "number o null",
      "capital_contable": "number o null",
      "efectivo": "number o null",
      "deuda_total": "number o null"
    },
    "flujo_efectivo": {
      "operativo": "number o null",
      "inversion": "number o null",
      "financiamiento": "number o null"
    },
    "indicadores_clave": {
      "eps": "number o null",
      "margen_bruto_pct": "number o null",
      "margen_neto_pct": "number o null",
      "roe_pct": "number o null"
    },
    "notas_importantes": ["string"],
    "unidad_cifras": "millones | miles | unidades"
  }

user_prompt: |
  Extrae todos los datos financieros de las siguientes páginas del informe:
```

**Notas de implementación**:
- El modo multimodal es superior al OCR estándar para tablas con formato complejo, colores y logos superpuestos
- Si el informe tiene >20 páginas, considerar procesar solo las páginas relevantes (balance, resultados) usando PyMuPDF para extraer páginas específicas antes de subir a `bronze`
- Extensión: comparar múltiples periodos en paralelo (ver patrón fan-out en CU-10)

---

### CU-08: Análisis de llamadas de soporte al cliente

**Sector/Industria**: Telecomunicaciones / Servicios / Contact Center

**Descripción del problema**: Los contact centers graban miles de llamadas al día. Los supervisores solo pueden monitorear una fracción manualmente. Se pierde retroalimentación valiosa sobre problemas recurrentes, incumplimientos y oportunidades de mejora.

**Solución con AI Document Processor**:
1. Las grabaciones de llamadas (`.wav` o `.mp3`) se suben automáticamente a `bronze` al finalizar cada llamada
2. `speechToText` transcribe la llamada con identificación de pausas y contexto
3. `callAoai` hace análisis de calidad, sentimiento y cumplimiento
4. `writeToBlob` guarda el análisis en `silver`; un dashboard de Power BI consume los JSONs

**Actividades utilizadas**:
- `speechToText` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un supervisor experto en calidad de atención al cliente y análisis de llamadas.
  Dada la transcripción de una llamada de soporte, realiza un análisis completo
  y devuelve un objeto JSON con esta estructura:

  {
    "duracion_estimada_min": "number",
    "tipo_contacto": "Queja | Consulta | Soporte_Tecnico | Retencion | Venta | Otro",
    "problema_principal": "string",
    "resolucion": "Resuelto | Parcialmente_Resuelto | Escalado | Sin_Resolucion",
    "satisfaccion_estimada": "Alta | Media | Baja",
    "sentimiento_cliente": {
      "inicio": "Positivo | Neutro | Negativo",
      "final": "Positivo | Neutro | Negativo",
      "cambio": "Mejoró | Se_Mantuvo | Empeoró"
    },
    "agente": {
      "saludo_correcto": true,
      "empatia_demostrada": true,
      "solucion_ofrecida": true,
      "despedida_correcta": true,
      "tono_general": "Profesional | Neutral | Poco_Profesional"
    },
    "frases_problematicas": ["string"],
    "compromisos_adquiridos": ["string"],
    "oportunidades_mejora": ["string"],
    "palabras_clave": ["string"],
    "requiere_seguimiento": true,
    "score_calidad": "number entre 0 y 100"
  }

user_prompt: |
  Analiza la siguiente transcripción de llamada de soporte:

  Transcripción:
```

**Notas de implementación**:
- Para diarización (identificar agente vs. cliente), modificar `speechToText.py` para usar el parámetro `diarizationEnabled: true` en el payload de la API
- El idioma de transcripción se configura en `speechToText.py` con el campo `locale`; para México usar `es-MX`
- Extensión: agregar análisis de tendencias en Cosmos DB para detectar problemas recurrentes usando los campos `palabras_clave` y `tipo_contacto`
- Limitación: llamadas muy largas (>2 horas) pueden requierir tiempo de transcripción adicional; el timeout de los reintentos está configurado en 5 intentos con espera inicial de 5 segundos

---

### CU-09: Procesamiento masivo de documentos de auditoría

**Sector/Industria**: Finanzas / Consultoría / Gobierno

**Descripción del problema**: Durante una auditoría externa, se reciben cientos o miles de documentos soporte (facturas, contratos, comprobantes) que deben revisarse en un plazo ajustado. El procesamiento secuencial toma días.

**Solución con AI Document Processor**:
El pipeline nativo de ADP ya procesa cada blob de forma independiente. El escalado horizontal se obtiene configurando el Function App correctamente:

1. Se suben todos los documentos al contenedor `bronze` (carga masiva via Azure Storage Explorer o AzCopy)
2. Event Grid emite un evento por cada blob → cada evento lanza una instancia independiente del pipeline
3. El plan Flex Consumption escala automáticamente hasta 100 instancias simultáneas
4. Todos los JSONs de salida se escriben en `silver` con su nombre de archivo correspondiente

**Script de carga masiva (`AzCopy`)**:

```bash
# Subir carpeta completa de documentos de auditoría a bronze
azcopy copy "./documentos_auditoria/*" \
  "https://{STORAGE_ACCOUNT}.blob.core.windows.net/bronze{SAS_TOKEN}" \
  --recursive=true \
  --include-pattern="*.pdf;*.docx;*.xlsx"
```

**Actividades utilizadas** (igual que CU-03, pero ejecutado en paralelo automáticamente):
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un auditor financiero experto. Dado el contenido de un documento soporte
  (puede ser factura, contrato, comprobante de pago, nota de crédito u otro),
  determina su tipo y extrae los datos relevantes para auditoría.

  Devuelve un JSON con esta estructura:

  {
    "tipo_documento": "Factura | Contrato | Comprobante_Pago | Nota_Credito |
                       Estado_Cuenta | Expediente | Otro",
    "fecha_documento": "YYYY-MM-DD o null",
    "monto": "number o null",
    "moneda": "string o null",
    "partes_involucradas": ["string"],
    "numero_referencia": "string o null",
    "descripcion_operacion": "string",
    "hallazgos_auditoria": ["string"],
    "nivel_riesgo": "Alto | Medio | Bajo | Sin_Riesgo",
    "requiere_revision_manual": true,
    "motivo_revision": "string o null si no requiere revision"
  }

user_prompt: |
  Revisa el siguiente documento de soporte para auditoría:

  Contenido:
```

**Variables de entorno para escalado máximo**:

```bash
# Usar plan Flex Consumption para escalar automáticamente
# (seleccionar FlexConsumption durante azd up)
azd env set PROMPT_FILE "audit-prompts.yaml"
azd env set FINAL_OUTPUT_CONTAINER "silver"
```

**Notas de implementación**:
- Con Flex Consumption, cada invocación de Event Grid lanza una instancia independiente; no hay cuello de botella en el orquestador
- El throttling de Azure OpenAI (rate limits) puede ser el factor limitante; solicitar incremento de cuota o usar múltiples deployments en regiones diferentes
- Monitorear el progreso en Application Insights con la query: `requests | where name contains "process_blob" | summarize count() by bin(timestamp, 1m)`
- Extensión: agregar un segundo paso de agregación que lea todos los JSONs del `silver` y genere un reporte consolidado de la auditoría

---

### CU-10: Enrutamiento condicional por tipo de documento

**Sector/Industria**: Multi-industria (Banca, Seguros, Gobierno)

**Descripción del problema**: Una empresa recibe documentos heterogéneos en un solo canal (portal web, email): facturas, contratos, formularios, identificaciones, etc. Cada tipo requiere un prompt de extracción diferente y la carga manual de separar y enrutar es costosa.

**Solución con AI Document Processor**:
Se extiende el orquestador para hacer un paso de clasificación previo y luego seleccionar el prompt dinámicamente antes de llamar a `callAoai`.

**Modificación del orquestador (`function_app.py`)**:

```python
@app.function_name(name="process_blob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
    blob_input = context.get_input()
    retry_options = RetryOptions(first_retry_interval_in_milliseconds=5000,
                                  max_number_of_attempts=5)

    # Paso 1: Extraer texto (igual que siempre)
    text_result = yield context.call_activity_with_retry(
        "runDocIntel", retry_options, blob_input)

    # Paso 2 (NUEVO): Clasificar el documento para seleccionar prompt
    classification_input = {"text_result": text_result,
                             "instance_id": context.instance_id}
    doc_type = yield context.call_activity_with_retry(
        "classifyDocument", retry_options, classification_input)

    # Paso 3: Seleccionar el prompt según tipo detectado
    prompt_map = {
        "factura":   "invoice-prompts.yaml",
        "contrato":  "contract-prompts.yaml",
        "formulario": "form-prompts.yaml",
        "otro":      "general-prompts.yaml"
    }
    # Actualizar PROMPT_FILE dinámicamente en el contexto
    aoai_input = {
        "text_result": text_result,
        "instance_id": context.instance_id,
        "prompt_override": prompt_map.get(doc_type, "general-prompts.yaml")
    }

    aoai_output = yield context.call_activity_with_retry(
        "callAoai", retry_options, aoai_input)

    yield context.call_activity_with_retry("writeToBlob", retry_options, {
        "json_str": aoai_output,
        "blob_name": blob_input["name"],
        "final_output_container": doc_type  # Escribe en contenedor por tipo
    })
```

**Prompt de clasificación (`classify-prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un clasificador de documentos. Dado el texto de un documento,
  determina su tipo y devuelve ÚNICAMENTE una de estas palabras:
  factura | contrato | formulario | identificacion | otro

  No agregues explicaciones. Solo la palabra.

user_prompt: |
  Clasifica este documento:

  Texto:
```

**Actividades utilizadas**:
- `runDocIntel` → `classifyDocument` (nueva) → `callAoai` → `writeToBlob`

**Notas de implementación**:
- `classifyDocument` es una nueva actividad a crear en `pipeline/activities/` siguiendo el mismo patrón de `callAiFoundry.py` pero apuntando a un prompt de clasificación muy simple y económico (GPT-4o-mini)
- Los contenedores de salida (`factura`, `contrato`, etc.) deben crearse en el Storage Account previamente o usar el nombre `silver` con subcarpetas
- Extensión: el campo `doc_type` puede escribirse en Cosmos DB como metadato para análisis de volumen por tipo

---

### CU-11: Preparación de corpus para RAG (búsqueda semántica)

**Sector/Industria**: Enterprise / Knowledge Management

**Descripción del problema**: Una empresa tiene miles de documentos internos (manuales, políticas, informes) que los empleados necesitan consultar en lenguaje natural. Construir un índice de búsqueda semántica requiere primero extraer y estructurar el texto de cada documento.

**Solución con AI Document Processor**:
ADP actúa como la capa de ingestión del pipeline RAG: preprocesa cada documento, extrae texto limpio en chunks y genera metadatos que Azure AI Search indexará.

1. Documentos se suben a `bronze`
2. `runDocIntel` extrae el texto completo preservando la estructura de párrafos
3. `callAoai` genera un JSON con chunks de texto + resumen + palabras clave para indexación
4. `writeToBlob` escribe en `silver`
5. (Paso adicional externo) Azure AI Search indexa los JSONs del `silver`

**Actividades utilizadas**:
- `runDocIntel` → `callAoai` → `writeToBlob`

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un especialista en preparación de datos para sistemas de búsqueda semántica (RAG).
  Dado el texto completo de un documento, prepara los datos de indexación
  en el siguiente formato JSON:

  {
    "documento_id": "string hash o nombre del archivo",
    "titulo": "string inferido del contenido",
    "tipo_documento": "string",
    "fecha_estimada": "YYYY o null",
    "idioma": "es | en | fr | otro",
    "resumen": "string de 3-5 oraciones capturando la esencia del documento",
    "palabras_clave": ["string - máximo 10 términos relevantes"],
    "entidades": {
      "personas": ["string"],
      "organizaciones": ["string"],
      "lugares": ["string"],
      "fechas": ["string"],
      "productos": ["string"]
    },
    "chunks": [
      {
        "chunk_id": "number secuencial",
        "contenido": "string - sección de ~500 palabras del documento",
        "titulo_seccion": "string o null",
        "relevancia": "Alta | Media | Baja"
      }
    ],
    "metadata_adicional": {}
  }

  Divide el documento en chunks de aproximadamente 500 palabras cada uno,
  respetando párrafos y secciones cuando sea posible.

user_prompt: |
  Prepara los datos de indexación para el siguiente documento:

  Texto:
```

**Notas de implementación**:
- Para indexar en Azure AI Search después de escribir en `silver`, agregar un Event Grid trigger adicional o una Logic App que llame a la API de indexación de Azure AI Search cuando aparezca un nuevo JSON en `silver`
- Documentos muy largos pueden generar JSONs grandes; Azure Blob Storage maneja hasta 5TB por objeto, no hay límite práctico
- **Anti-patrón**: no usar `callAoaiMultiModal` para RAG en documentos de texto; el OCR de `runDocIntel` preserva mejor la estructura de párrafos
- Extensión: agregar el campo `embedding` en el JSON llamando a Azure OpenAI Embeddings API desde `writeToBlob.py` antes de escribir

---

### CU-12: Comparación y reconciliación de documentos múltiples

**Sector/Industria**: Legal / Finanzas / Procurement

**Descripción del problema**: El equipo de compras necesita comparar oferta de proveedor vs. contrato firmado vs. factura recibida para detectar discrepancias en precios, cantidades o términos antes de aprobar el pago.

**Solución con AI Document Processor**:
Se extiende el orquestador con el patrón fan-out/fan-in de Durable Functions: se procesan los tres documentos en paralelo y luego se consolida en una actividad de reconciliación.

**Modificación del orquestador (`function_app.py`) — patrón fan-out/fan-in**:

```python
@app.function_name(name="reconcile_documents")
@app.orchestration_trigger(context_name="context")
def reconcile_documents(context):
    """
    Orquestador especial para comparar múltiples documentos.
    Entrada HTTP esperada: lista de blobs a comparar.
    """
    blob_list = context.get_input()  # Lista de {name, container, uri, tipo}
    retry_options = RetryOptions(first_retry_interval_in_milliseconds=5000,
                                  max_number_of_attempts=5)

    # FAN-OUT: Procesar todos los documentos en paralelo
    extraction_tasks = []
    for blob in blob_list:
        task = context.call_activity_with_retry(
            "runDocIntel", retry_options, blob)
        extraction_tasks.append(task)

    # Esperar a que todos terminen (fan-in)
    extracted_texts = yield context.task_all(extraction_tasks)

    # Consolidar todos los textos para comparación
    reconciliation_input = {
        "documents": [
            {"tipo": blob_list[i]["tipo"], "texto": extracted_texts[i]}
            for i in range(len(blob_list))
        ],
        "instance_id": context.instance_id
    }

    # Un solo llamado a AOAI con todos los documentos
    comparison_result = yield context.call_activity_with_retry(
        "callAoai", retry_options, reconciliation_input)

    yield context.call_activity_with_retry("writeToBlob", retry_options, {
        "json_str": comparison_result,
        "blob_name": f"reconciliation_{context.instance_id}",
        "final_output_container": "silver"
    })
```

**Invocación via HTTP** (`POST /api/client`):

```json
{
  "documents": [
    {"name": "oferta_proveedor.pdf", "container": "bronze", "uri": "https://...", "tipo": "oferta"},
    {"name": "contrato_firmado.pdf", "container": "bronze", "uri": "https://...", "tipo": "contrato"},
    {"name": "factura_120345.pdf",   "container": "bronze", "uri": "https://...", "tipo": "factura"}
  ]
}
```

**Configuración completa (`prompts.yaml`)**:

```yaml
system_prompt: |
  Eres un auditor experto en reconciliación de documentos de compras.
  Se te proporcionarán el texto de varios documentos relacionados a la misma
  transacción (oferta, contrato, factura). Compara su contenido y detecta
  discrepancias.

  Devuelve un objeto JSON con esta estructura:

  {
    "transaccion_id": "string inferido o null",
    "proveedor": "string",
    "documentos_analizados": ["oferta", "contrato", "factura"],
    "concordancias": [
      {
        "campo": "string (ej. precio_unitario, cantidad, plazo)",
        "valor": "string",
        "presente_en": ["string"]
      }
    ],
    "discrepancias": [
      {
        "campo": "string",
        "documento_origen": "string",
        "valor_origen": "string",
        "documento_destino": "string",
        "valor_destino": "string",
        "severidad": "Bloqueante | Mayor | Menor",
        "recomendacion": "string"
      }
    ],
    "aprobacion_recomendada": true,
    "motivo": "string",
    "resumen_ejecutivo": "string de 3-5 oraciones"
  }

user_prompt: |
  Compara los siguientes documentos de la misma transacción y detecta discrepancias:

  Documentos:
```

**Notas de implementación**:
- Este caso usa un nuevo trigger HTTP (`start_reconciliation_http`) a diferencia del blob trigger estándar; requiere agregar una nueva función al `function_app.py`
- El patrón `context.task_all()` es nativo de Azure Durable Functions y garantiza que las tareas paralelas se manejen de forma transaccional
- Limitación del contexto: si los 3 documentos son muy extensos, la suma de sus textos puede superar el límite de contexto del modelo (128K tokens para GPT-4o); mitigar extrayendo solo las secciones relevantes en el prompt
- Extensión: escalar a N documentos (comparativas de múltiples proveedores) cambiando `blob_list` a un array dinámico

---

## 3. Tabla Resumen de Componentes por Caso de Uso

| Caso de Uso | Actividades Requeridas | Servicios Azure | Complejidad |
|---|---|---|---|
| CU-01: CVs | `runDocIntel` → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage | ⭐ Baja |
| CU-02: Reuniones | `speechToText` → `callAoai` → `writeToBlob` | AI Services (Speech), OpenAI, Storage | ⭐ Baja |
| CU-03: Facturas | `runDocIntel` → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage | ⭐ Baja |
| CU-04: Formularios médicos | `callAoaiMultiModal` → `writeToBlob` | OpenAI (GPT-4o vision), Storage | ⭐⭐ Media |
| CU-05: Clasificación emails | `runDocIntel` → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage | ⭐ Baja |
| CU-06: Contratos legales | `runDocIntel` → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage, Cosmos DB | ⭐⭐ Media |
| CU-07: Tablas financieras | `callAoaiMultiModal` → `writeToBlob` | OpenAI (GPT-4o vision), Storage | ⭐⭐ Media |
| CU-08: Llamadas soporte | `speechToText` → `callAoai` → `writeToBlob` | AI Services (Speech), OpenAI, Storage | ⭐⭐ Media |
| CU-09: Auditoría masiva | `runDocIntel` → `callAoai` → `writeToBlob` (×N paralelo) | AI Services, OpenAI, Storage, Event Grid | ⭐⭐ Media |
| CU-10: Enrutamiento condicional | `runDocIntel` → `classifyDocument`* → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage | ⭐⭐⭐ Alta |
| CU-11: Preparación RAG | `runDocIntel` → `callAoai` → `writeToBlob` + AI Search* | AI Services, OpenAI, Storage, AI Search* | ⭐⭐ Media |
| CU-12: Comparación multi-doc | `runDocIntel` (×N fan-out) → `callAoai` → `writeToBlob` | AI Services, OpenAI, Storage | ⭐⭐⭐ Alta |

> `*` = requiere actividad o servicio adicional no incluido en el repositorio base

---

## 4. Índice de Samples Oficiales Incluidos en el Repositorio

El repositorio AI Document Processor es un **acelerador base** (*accelerator*), no un repositorio de samples independientes. No existe un directorio `samples/` o `examples/`. En su lugar, el repositorio incluye los siguientes artefactos funcionales de referencia:

| Artefacto | Tipo | Descripción | Componentes demostrados | Ruta |
|---|---|---|---|---|
| `prompts.yaml` | Configuración YAML funcional | Ejemplo de extracción de perfiles de empresa a JSON | `callAoai`, `load_prompts` | [data/prompts.yaml](../data/prompts.yaml) |
| `test_client.ipynb` | Notebook Jupyter | Cliente HTTP para probar el endpoint de la Function App | Trigger HTTP, `start_orchestrator_http` | [test_client.ipynb](../test_client.ipynb) |
| `function_app.py` | Código Python funcional | Orquestador completo con detección de tipo de archivo y enrutamiento | Todos los activities, orquestador, triggers | [pipeline/function_app.py](../pipeline/function_app.py) |
| `callAiFoundry.py` | Activity Python | Ejemplo de llamada a Azure OpenAI con carga de prompts desde blob | `callAoai`, `load_prompts`, `run_prompt` | [pipeline/activities/callAiFoundry.py](../pipeline/activities/callAiFoundry.py) |
| `callFoundryMultiModal.py` | Activity Python | Ejemplo de procesamiento de PDF como imágenes con visión | `callAoaiMultiModal`, PyMuPDF | [pipeline/activities/callFoundryMultiModal.py](../pipeline/activities/callFoundryMultiModal.py) |
| `runDocIntel.py` | Activity Python | Ejemplo de OCR con Document Intelligence API | `runDocIntel`, `DocumentIntelligenceClient` | [pipeline/activities/runDocIntel.py](../pipeline/activities/runDocIntel.py) |
| `speechToText.py` | Activity Python | Ejemplo de transcripción asíncrona de audio | `speechToText`, Speech REST API | [pipeline/activities/speechToText.py](../pipeline/activities/speechToText.py) |
| `writeToBlob.py` | Activity Python | Ejemplo de escritura de resultado a blob storage | `writeToBlob`, `BlobServiceClient` | [pipeline/activities/writeToBlob.py](../pipeline/activities/writeToBlob.py) |
| `sampleRequest.json` | JSON de prueba | Payload de ejemplo para el trigger HTTP | Trigger HTTP | [data/sampleRequest.json](../data/sampleRequest.json) |
| `config-test.py` | Script Python | Prueba de conectividad a Azure App Configuration | `Configuration`, App Config | [pipeline/config-test.py](../pipeline/config-test.py) |

---

## 5. Combinaciones de Componentes Recomendadas

### Patrones frecuentes

**Patrón 1 — "OCR + Extracción" (el más común)**
```
runDocIntel → callAoai → writeToBlob
```
*Usar para*: facturas, contratos, CVs, formularios, reportes, cualquier documento de texto.

**Patrón 2 — "Audio a Insight"**
```
speechToText → callAoai → writeToBlob
```
*Usar para*: reuniones, llamadas de soporte, entrevistas, podcasts corporativos.

**Patrón 3 — "Visión directa" (documentos visualmente complejos)**
```
callAoaiMultiModal → writeToBlob
```
*Usar para*: formularios con layout visual complejo, tablas financieras con formato, documentos con texto manuscrito, imágenes de productos.

**Patrón 4 — "Clasificar y enrutar"**
```
runDocIntel → callAoai[clasificar] → callAoai[extraer según tipo] → writeToBlob
```
*Usar para*: portales de documentos mixtos, bandeja de entrada de múltiples tipos.

**Patrón 5 — "Fan-out paralelo"**
```
[runDocIntel × N] → callAoai[consolidar] → writeToBlob
```
*Usar para*: comparación de versiones de contrato, reconciliación de documentos, análisis de portfolio.

---

### Anti-patrones a evitar

| Anti-patrón | Problema | Alternativa |
|---|---|---|
| Usar `callAoaiMultiModal` para documentos de texto plano | Usa más tokens (imagen vs. texto), más caro y más lento | Usar `runDocIntel` para texto; multimodal solo cuando el layout visual importa |
| Subir documentos enormes (>100 páginas) sin dividir | El contexto del modelo tiene límite; el texto truncado produce extracciones incompletas | Dividir con PyMuPDF antes de subir, o procesar por secciones |
| Poner toda la lógica de negocio en el `system_prompt` | Los prompts demasiado complejos producen salidas inconsistentes | Dividir en pasos: un prompt clasifica, otro extrae específicamente |
| Usar blob trigger de polling en producción (no EventGrid) | El polling puede tardar hasta 10 minutos en detectar nuevos blobs | Siempre usar `source="EventGrid"` en producción (ya configurado por defecto) |
| Hardcodear el nombre del prompt en el código | Imposible cambiar instrucciones sin redesplegar | Configurar `PROMPT_FILE` en Azure App Configuration y cambiar el YAML en el blob `prompts/` |
| Llamar directamente a Azure OpenAI sin los reintentos de Durable Functions | Un rate limit o error transitorio aborta el pipeline completo | Siempre usar `call_activity_with_retry` con `RetryOptions` configurado |
| Escribir directamente al contenedor `gold` sin pasar por `silver` | Se pierde la trazabilidad del dato intermedio para debugging | Seguir el patrón bronze → silver → gold; cada capa tiene su propósito |
