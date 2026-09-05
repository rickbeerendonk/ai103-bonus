---
marp: true
# Copyright © 2026 Rick Beerendonk
theme: oblicum-marp-theme
footer: "![](../../../marp/glasspaper-logo.svg) ![](../../../marp/oblicum-logo.svg)"
---

<!-- _class: lead -->

# Extract Insights from Visual Data on Azure

## Vision, image & video generation, content understanding, and search

#### Rick Beerendonk<br>rick@oblicum.com

---

## What You'll Learn

- Send an image to a model and ask questions about it
- Generate images and video, and edit part of an image
- Pull named fields out of forms, invoices, and mixed media
- Choose between a model, an analyzer, and a document model
- Turn a pile of files into something searchable

---

<!-- _class: fit-28 -->

## Problem: 90% of Company Content Is Not a Database Row

Scanned invoices. Photos from the field. Recorded meetings. Slide decks in a share.

- ❌ You cannot query a PDF
- ❌ You cannot filter a photo
- ❌ Someone retypes the invoice total into the finance system by hand

**Need:** turn pixels and pages into fields, text, and searchable records.

This presentation is four different tools for that one job — and knowing which to reach for is most of the skill.

---

<!-- _class: fit-24 -->

## Which Tool for Which Job?

```text
  What do you have, and what do you want back?

    "Describe / reason about this image"        ━━▶ multimodal model  (gpt-4.1)
         open-ended answer, no fixed schema

    "Give me these exact fields"                ━━▶ Document Intelligence
         invoice total, IBAN, signature box        forms and documents

    "Same, but the input might be audio,        ━━▶ Content Understanding
    video, or an image too"                        one analyzer, many media types

    "Make me a picture / a video"               ━━▶ gpt-image-1 / FLUX / Sora

    "Let people search 100,000 of these"        ━━▶ AI Search + skillset
```

**The dividing line:** a _model_ gives you an answer; an _analyzer_ gives you the same fields every time.

---

<!-- _class: fit-28 -->

## Everything Big Is Asynchronous

Image analysis, video generation, and document analysis all take longer than one HTTP request.

```text
  1  you submit the job        begin_analyze(...) / videos.create(...)
         ┃
         ▼                     you get back an operation id, not a result
  2  service works in the background
         ┃
  3  you poll                  "is it done yet?"   status: running
         ┃                     "is it done yet?"   status: running
         ┃                     "is it done yet?"   status: succeeded
         ▼
  4  you fetch the result      poller.result()  /  download the file
```

**That is why the SDK calls start with `begin_` and return a _poller_.** When you see `Operation-Location` in a response header, you are in step 3.

---

<!-- _class: lead -->

# Vision-Enabled Generative AI

---

## Multimodal Models

| Model                       | Provider  | Notes                                      |
| --------------------------- | --------- | ------------------------------------------ |
| `gpt-4.1`                   | OpenAI    | Supports Responses API and ChatCompletions |
| `gpt-4.1-mini`              | OpenAI    | Lighter, cost-effective variant            |
| `Phi-4-multimodal-instruct` | Microsoft | ChatCompletions API only                   |

**Image input formats:** web URL or Base64 data URL: `data:image/{format};base64,{data}`

---

<!-- _class: fit-28 -->

## Responses API (gpt-4.1, gpt-4.1-mini)

**_[EXAM]_**

```python
from openai import AzureOpenAI
import base64

client = AzureOpenAI(azure_endpoint=ENDPOINT, api_key=KEY, api_version="2025-01-01-preview")

with open("image.jpg", "rb") as f:
    b64 = base64.b64encode(f.read()).decode("utf-8")

response = client.responses.create(
    model=DEPLOYMENT,
    input=[
        {
            "role": "developer",
            "content": [
                {"type": "input_text", "text": "What is in this image?"},
                {"type": "input_image", "image_url": f"data:image/jpeg;base64,{b64}"},
            ],
        }
    ],
)
print(response.output_text)
```

**Note:** role is `"developer"`; image type is `"input_image"`

---

<!-- _class: fit-24 -->

## ChatCompletions API (gpt-4.1, Phi-4)

**_[EXAM]_**

```python
response = client.chat.completions.create(
    model=DEPLOYMENT,
    messages=[
        {"role": "system", "content": "You analyze images."},
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What is in this image?"},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ],
        },
    ],
)
print(response.choices[0].message.content)
```

**Note:** role is `"system"`; image type is `"image_url"` (nested `{"url": ...}`)

**Multimodal request shape:** the image belongs in the **user message content array** as an `image_url` item, alongside the `text` item. Base64-encoding it into the content **string**, putting the URL in request metadata, or placing it in the system message are all rejected.

**Phi-4-multimodal-instruct** — ChatCompletions API only; does not support Responses API

---

## Retrieval Practice — Lab 1

Pause here and complete [Lab 1](../lab/lab%201/lab.md) before continuing.

---

<!-- _class: lead -->

# Image Generation

---

## Image Generation — gpt-image-1 and FLUX

**_[EXAM]_**

**Models:**

| Model                | Provider                           |
| -------------------- | ---------------------------------- |
| `gpt-image-1`        | OpenAI                             |
| `FLUX.1-Kontext-pro` | Black Forest Labs (Serverless API) |

```python
import base64
from openai import AzureOpenAI

client = AzureOpenAI(azure_endpoint=ENDPOINT, api_key=KEY, api_version=API_VERSION)

img_results = client.images.generate(
    model=MODEL_DEPLOYMENT,
    prompt="A golden retriever running through autumn leaves, photorealistic",
    n=1,
    size="1024x1024",
)

image_bytes = base64.b64decode(img_results.data[0].b64_json)
with open("output.png", "wb") as f:
    f.write(image_bytes)
```

**Response:** `data[0].b64_json` — always returned as base64; decode to get raw bytes

---

<!-- _class: fit-24 -->

## Keeping a Real Product Recognisable

**_[EXAM]_**

Generating a marketing scene around a real product usually distorts it — the label, shape, or colour drifts. Raise **`input_fidelity`** to preserve the reference:

```python
result = client.images.edit(
    model="gpt-image-1",
    image=open("product.png", "rb"),
    prompt="Place the bottle on a marble kitchen counter, morning light",
    input_fidelity="high",     # keep the product identity
)
```

| Setting                 | Effect                                                        |
| ----------------------- | ------------------------------------------------------------- |
| `input_fidelity="high"` | Faces and distinctive product details stay close to the input |
| Default fidelity        | More creative freedom, weaker identity preservation           |

**Not a substitute:** a groundedness filter checks text claims, prompt wording alone does not lock appearance, and temperature controls variability rather than fidelity.

---

<!-- _class: fit-20 -->

## Detecting Brands and Reading Bounding Boxes

**_[EXAM]_**

Azure Vision returns a `brands` collection with a confidence score and a rectangle per detection:

```csharp
foreach (var brand in analysis.Brands)
{
    if (brand.Confidence >= 0.75)
        Console.WriteLine($"{brand.Name} at {brand.Rectangle.X},{brand.Rectangle.Y}");
}
```

**The rectangle gives the top-left corner plus a size — not two corners:**

```text
  (X, Y) ●━━━━━━━━━━━━━━━┓
         ┃               ┃  H
         ┃               ┃
         ┗━━━━━━━━━━━━━━━┛
             W        ● (X + W, Y + H)  ◀━ bottom-right, calculated
```

| Property | Meaning                         |
| -------- | ------------------------------- |
| `X`, `Y` | **Top-left** corner coordinates |
| `W`, `H` | Width and height in pixels      |

**Trap:** `X` and `Y` are never the bottom-right corner.

---

<!-- _class: fit-24 -->

## Image Editing — Inpainting with a Mask

**_[EXAM]_**

**Use case:** an existing image contains something to remove (competitor logo in the background, unwanted object) — edit only that region instead of regenerating the whole image.

**API:** `client.images.edit()` (not `generate`) — supplies the source image plus a **mask PNG** where transparent pixels mark the region to be re-painted.

```python
result = client.images.edit(
    model="gpt-image-1",
    image=open("product-photo.png", "rb"),
    mask=open("mask.png", "rb"),       # transparent region = paint here; opaque = keep
    prompt="Replace the logo with a plain wooden wall, matching the existing lighting",
    size="1024x1024",
)
image_bytes = base64.b64decode(result.data[0].b64_json)
```

**Mask rules:** same dimensions as source; PNG with alpha channel; only transparent pixels are repainted — the rest stays pixel-identical.

**Not the same as `generate`:** `generate` makes a new image; `edit` preserves the original everywhere except the masked area.

---

## Retrieval Practice — Lab 2

Pause here and complete [Lab 2](../lab/lab%202/lab.md), then check its solution.

---

<!-- _class: lead -->

# Video Generation

---

<!-- _class: fit-20 -->

## Sora Video Generation

**_[EXAM]_**

**Models:** `sora-2` (standard), `sora-2-pro`

**Sizes:** `"1280x720"` (landscape) or `"720x1280"` (portrait)  
**Durations:** `"4"`, `"8"`, or `"12"` (seconds, as string value)  
**Concurrency limit:** max 2 jobs at a time

**Pattern: Create → Poll → Download**

```python
video = client.videos.create(
    model="sora-2",
    prompt="Ocean waves at sunrise, cinematic slow motion",
    size="1280x720",
    seconds="8",
)

# Poll until done
while video.status not in ["completed", "failed", "cancelled"]:
    video = client.videos.retrieve(video.id)

# Download
content = client.videos.download_content(video.id, variant="video")
content.write_to_file("output.mp4")
```

**Expiry:** Completed videos expire after **24 hours**

---

<!-- _class: fit-24 -->

## Sora — Remix and Reference Image

**Video remix** (modify an existing video):

```python
remixed = client.videos.remix(
    video_id=original_video.id,
    prompt="Change the setting to winter, keep the same scene composition",
)
```

**Reference image** (constrain the generated scene):

```python
video = client.videos.create(
    model="sora-2",
    prompt="A cat walks through this landscape",
    size="1280x720",
    seconds="8",
    input_reference=open("landscape.png", "rb"),
)
```

**Constraint:** Reference images must not contain human faces

---

<!-- _class: fit-24 -->

## Editing Video Without Regenerating It

**_[EXAM]_**

A finished clip contains an unwanted watermark or object. Regenerating produces a **different video** — instead, apply a **mask-based inpainting edit** to that region, exactly as with images.

| Approach                     | Result                                                     |
| ---------------------------- | ---------------------------------------------------------- |
| **Mask-based inpainting**    | Removes the artifact, keeps the rest of the footage intact |
| Change the prompt and re-run | New generation, so the approved scene is lost              |
| Crop the frame               | Removes wanted content and changes the aspect ratio        |
| Adjust the guidance scale    | Changes generation behavior, not an existing artifact      |

**Rule:** to change _part_ of an existing asset, edit with a mask. To change _the whole_ asset, generate again.

---

<!-- _class: lead -->

# Azure Content Understanding

---

<!-- _class: fit-20 -->

## ContentUnderstandingClient

**_[EXAM]_**

**Package:** `azure-ai-contentunderstanding`; **API version:** `2025-11-01`

**Prerequisite:** Foundry resource must have these deployed:

- `GPT-4.1` or `GPT-4.1-mini`
- `text-embedding-3-large`

```python
from azure.ai.contentunderstanding import ContentUnderstandingClient
from azure.ai.contentunderstanding.models import AnalysisInput
from azure.core.credentials import AzureKeyCredential

client = ContentUnderstandingClient(
    endpoint=ENDPOINT,
    credential=AzureKeyCredential(KEY),
    api_version="2025-11-01"
)

poller = client.begin_analyze(
    analyzer_id="prebuilt-invoice",
    inputs=[AnalysisInput(data=open("invoice.pdf", "rb").read())],
)
result = poller.result()
print(result.contents[0].markdown)          # full content as markdown
print(result.contents[0].fields)            # extracted fields dict
```

---

<!-- _class: fit-20 -->

## Prebuilt Analyzers

**_[EXAM]_**

| Analyzer                  | Purpose                                      |
| ------------------------- | -------------------------------------------- |
| `prebuilt-image`          | General image analysis                       |
| `prebuilt-receipt`        | Merchant, items, totals                      |
| `prebuilt-invoice`        | Vendor, line items, tax, totals              |
| `prebuilt-idDocument`     | Passport, driver's license                   |
| `prebuilt-documentSearch` | Semantic Markdown optimized for RAG indexing |
| `prebuilt-layout`         | Tables, structure, QR codes, spatial layout  |

**Supported media:** Images, documents, audio, video

**Choosing between the document analyzers:**

| Requirement                                       | Analyzer                  |
| ------------------------------------------------- | ------------------------- |
| Tables, QR codes, and where things sit on a page  | `prebuilt-layout`         |
| Search-ready semantic Markdown for a RAG pipeline | `prebuilt-documentSearch` |
| Just the text                                     | `prebuilt-read`           |
| Known invoice fields                              | `prebuilt-invoice`        |

---

<!-- _class: fit-24 -->

## Single-File and Multi-File Tasks

**_[EXAM]_**

**Task type decides how many documents the analyzer can reason over at once.**

| Task            | Mode         | Reasoning                                                    |
| --------------- | ------------ | ------------------------------------------------------------ |
| **Single-file** | **standard** | One document analyzed in isolation — high volume, low cost   |
| **Multi-file**  | **pro**      | Several documents **plus reference data**, compared together |

```text
    Single-file / standard      each invoice ━▶ fields

  Multi-file / pro            invoice + purchase order
                                 + vendor contracts (reference data)
                              ━▶ validated, reconciled result
```

**Use pro mode when the requirement is cross-document:** matching an invoice to its purchase order, or validating it against contract terms. Standard mode cannot compare documents, so it cannot answer “does this invoice agree with the PO?”

**Both can run in one solution:** bulk extraction in single-file standard, exception validation in multi-file pro.

---

<!-- _class: fit-20 -->

## Field Schema and Confidence Thresholds

**_[EXAM]_**

**Field extraction methods:**

| Method     | Description                 | Example                                |
| ---------- | --------------------------- | -------------------------------------- |
| `extract`  | Pull value as-is            | `InvoiceTotal: "€1,245.00"`            |
| `classify` | Categorize into enum values | `DocumentType: "Invoice" \| "Receipt"` |
| `generate` | Derive via AI reasoning     | Summary: 2-sentence description        |

**Confidence thresholds:**

| Score range | Action                      |
| ----------- | --------------------------- |
| ≥ 0.9       | Automate (no review needed) |
| 0.7 – 0.9   | Route to human review       |
| < 0.7       | Manual processing           |

**Field properties:** `valueString`, `confidence`, `source` (bounding polygon for grounding)

For scanned troubleshooting documents, enable `estimateFieldSourceAndConfidence` to return per-field confidence and source location for review.

**Generated descriptions** — for example a color scheme for a video segment — need field type **`string`** with method **`generate`**. `extract` and `classify` read or label existing content, and a non-string type cannot hold the generated text.

---

<!-- _class: fit-20 -->

## Custom Analyzers

**_[EXAM]_**

**Create via SDK:**

```python
poller = client.begin_create_analyzer(
    "expense-report-analyzer",
    body={
        "description": "Extracts expense report totals and categories",
        "baseAnalyzerId": "prebuilt-invoice",
        "fieldSchema": {
            "fields": {
                "ExpenseCategory": {"type": "string", "method": "classify",
                                    "enum": ["Travel", "Meals", "Software", "Other"]},
                "TotalAmount": {"type": "number", "method": "extract"},
                "Justification": {"type": "string", "method": "generate"},
            }
        },
        "models": {"completion": {"modelId": "gpt-4.1"},
                   "embedding": {"modelId": "text-embedding-3-large"}},
    }
)
```

**Create via REST:** `PUT {endpoint}/contentunderstanding/analyzers/{name}?api-version=2025-11-01`  
Poll result via `Operation-Location` response header

---

<!-- _class: fit-24 -->

## Content Understanding: Build vs. Consume

**Two complementary workflows:**

| Workflow                | Purpose                                         | Typical tool                               |
| ----------------------- | ----------------------------------------------- | ------------------------------------------ |
| **Build an analyzer**   | Define fields and extraction/generation methods | Content Understanding Studio, SDK, or REST |
| **Consume an analyzer** | Submit files and process structured results     | Python SDK or REST client application      |

**Prerequisites:**

- A Microsoft Foundry resource or project
- The resource endpoint and an API key, or Microsoft Entra ID authentication
- `GPT-4.1` or `GPT-4.1-mini` completion deployment
- `text-embedding-3-large` embedding deployment
- Python 3.9+ for the Python SDK

**Studio is useful for:** visually creating schemas, testing sample content, and inspecting extracted fields before moving the definition into code.

---

<!-- _class: fit-24 -->

## Content Understanding Client Workflow

```python
from azure.ai.contentunderstanding import ContentUnderstandingClient
from azure.ai.contentunderstanding.models import AnalysisInput
from azure.core.credentials import AzureKeyCredential

client = ContentUnderstandingClient(
    endpoint=ENDPOINT,
    credential=AzureKeyCredential(KEY),
    api_version="2025-11-01",
)

poller = client.begin_analyze(
    analyzer_id="expense-report-analyzer",
    inputs=[AnalysisInput(data=open("expense.pdf", "rb").read())],
)
result = poller.result()

for content in result.contents:
    print(content.markdown)
    print(content.fields)
```

**REST alternative:** submit the file to the analyzer endpoint, poll the returned operation URL, then process the JSON result. Use REST when the client language has no SDK or when direct HTTP control is required.

**Result handling:** preserve the extracted value, confidence, and source grounding so low-confidence fields can be routed to human review.

---

<!-- _class: fit-20 -->

## When the Answer Is Content Understanding

**_[EXAM]_**

Reach for an analyzer when the requirement combines **structure**, **more than one modality**, and **no model training**.

| Requirement in the scenario                      | Why Content Understanding                         |
| ------------------------------------------------ | ------------------------------------------------- |
| Preserve structure across mixed-format documents | An analyzer returns a schema, not free-form prose |
| Multipage tables **without training a model**    | Prebuilt reasoning, no labeled dataset needed     |
| Judge visual **and** textual evidence together   | Multimodal analysis in one pass                   |
| Page citations with bounding polygons            | Grounding metadata is returned with the fields    |
| Named business fields from **varied layouts**    | A custom analyzer generalizes beyond one template |

| Rejected alternative                     | Why                                              |
| ---------------------------------------- | ------------------------------------------------ |
| Azure Language text analysis             | Text only — no layout, no tables                 |
| Chat completions or multimodal Responses | Free-form output, not structure-aware extraction |
| An Azure Machine Learning model          | Requires building and training your own model    |
| Document Layout / Document Extraction    | Layout only, or no multimodal citation metadata  |
| GenAI Prompt                             | Generates content instead of extracting it       |
| `prebuilt-layout`                        | Returns structure, but not named business fields |

---

<!-- _class: lead -->

# Azure Document Intelligence

---

<!-- _class: fit-24 -->

## Document Intelligence Models

**_[EXAM]_**

**Document Analysis:**

| Model    | Extracts                                          |
| -------- | ------------------------------------------------- |
| `read`   | Text + language detection (printed + handwritten) |
| `layout` | Text + tables + selection marks + key-value pairs |

**Prebuilt:** Invoice, Receipt, Bank statement, W-2, 1040, ID document, Health insurance card, and more

**Custom:**

| Type              | Use Case                                       |
| ----------------- | ---------------------------------------------- |
| Custom Template   | Fixed-layout forms; supports 100+ languages    |
| Custom Neural     | Variable-layout documents                      |
| Composed          | Multiple custom models auto-classify and route |
| Custom Classifier | Classifies document types before extraction    |

**Input limits:** < 500 MB, 50×50 to 10,000×10,000 px; PDF ≤ 17×17 in; no password-protected files

---

## Retrieval Practice — Lab 3

Pause here and complete [Lab 3](../lab/lab%203/lab.md), then check its solution.

---

<!-- _class: fit-24 -->

## DocumentAnalysisClient

```python
from azure.ai.formrecognizer import DocumentAnalysisClient
from azure.core.credentials import AzureKeyCredential

client = DocumentAnalysisClient(
    endpoint=ENDPOINT,
    credential=AzureKeyCredential(KEY)
)

poller = client.begin_analyze_document_from_url(
    model_id="prebuilt-invoice",
    document_url="https://example.com/invoice.pdf"
)
result = poller.result()

for doc in result.documents:
    for name, field in doc.fields.items():
        print(f"{name}: {field.content} (confidence: {field.confidence:.2f})")
```

**Document: `begin_analyze_document(model_id, document=bytes)` for binary input**

**Studio:** `documentintelligence.ai.azure.com` — label training data; test prebuilt models

---

<!-- _class: fit-20 -->

## Layout Model: Markdown Output and Page Chunks

**_[EXAM]_**

**Use case:** Extract structured text preserving layout — for RAG chunking, search indexing

**SDK (v4):** `azure-ai-documentintelligence` → `DocumentIntelligenceClient`

```python
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import (
    AnalyzeDocumentRequest, ContentFormat
)
from azure.core.credentials import AzureKeyCredential

client = DocumentIntelligenceClient(ENDPOINT, AzureKeyCredential(KEY))

# Analyze pages 1–3 only; output as Markdown
poller = client.begin_analyze_document(
    "prebuilt-layout",
    AnalyzeDocumentRequest(url_source="https://example.com/report.pdf"),
    pages="1-3",
    output_content_format=ContentFormat.MARKDOWN,
)
result = poller.result()

# result.content = full Markdown string
# Chunk by page:
for page in result.pages:
    print(f"--- Page {page.page_number} ---")
    for line in page.lines:
        print(line.content)
```

**`pages="1-3"`** — analyze a page range from a multi-page PDF/TIFF  
**`output_content_format=ContentFormat.MARKDOWN`** — tables rendered as HTML markdown; headings, sections preserved

**Parameter trap:** `output=figures` returns figure data, `content=markdown` is not a supported parameter, and raising the confidence threshold filters results rather than changing the output format.

**This combination is what "advanced data parsing" means** for RAG ingestion: layout-aware chunks that keep tables, headings, and page numbers. Reingesting scanned PDFs this way fixes retrieval that basic parsing broke.

| Ingestion approach                            | Result                                      |
| --------------------------------------------- | ------------------------------------------- |
| **Advanced data parsing** (layout + Markdown) | Tables, headings, and page metadata survive |
| Basic parsing + fixed-size chunks             | Table structure and page numbers lost       |
| One chunk per page                            | Too coarse to retrieve a single table row   |

---

## Retrieval Practice — Lab 4

Pause here and complete [Lab 4](../lab/lab%204/lab.md), then check its solution.

---

<!-- _class: lead -->

# Azure AI Search

---

<!-- _class: fit-24 -->

## Two Timelines, Not One

The most common confusion with AI Search: enrichment does **not** happen when a user searches.

```text
  INDEX TIME   (scheduled, slow, expensive, happens once per document)

    blob  ━▶  indexer cracks the file  ━▶  skillset enriches
                                              OCR, language, entities
                                                     ┃
                                                     ▼
                                            index  +  knowledge store

  QUERY TIME   (per user, milliseconds)

    user query  ━▶  search the index  ━▶  ranked results  ━▶  answer
```

**Consequence:** adding a skill changes nothing until you re-run the indexer. Everything a user can search for had to be computed at index time.

---

<!-- _class: fit-24 -->

## Enrichment Pipeline

**_[EXAM]_**

```text
Data Source → Indexer → Skillset → Index ─→ Knowledge Store
                                       ↓
                                   Search
```

**Components:**

| Component           | Purpose                                                                  |
| ------------------- | ------------------------------------------------------------------------ |
| **Data source**     | Blob Storage, SQL Database, Cosmos DB, SharePoint                        |
| **Indexer**         | Cracks documents; orchestrates enrichment; runs on schedule or on-demand |
| **Skillset**        | AI enrichment pipeline; chains built-in + custom skills                  |
| **Index**           | Searchable store with typed, filterable/sortable fields                  |
| **Knowledge store** | Side-output of enriched projections (JSON, tables, images)               |

**Enrichment tracks produced by indexer:**

- `metadata` (file name, URL, type)
- `content` (extracted text)
- `normalized_images` (decoded images for OCR/captioning)
- `language`, `merged_content` (text + OCR combined)

For embedded PDF images that must be OCR-ready while retaining source citations, extract them into the indexer's `normalized_images` collection.

---

<!-- _class: fit-24 -->

## Built-in AI Skills (Foundry Tools)

**_[EXAM]_**

**Requires:** Azure AI Foundry Tools (multi-service) resource in the same region as AI Search

| Skill                        | Output                                              |
| ---------------------------- | --------------------------------------------------- |
| Language detection           | `languageCode`                                      |
| Entity extraction            | People, organizations, locations, dates, quantities |
| Key phrase extraction        | Main topics                                         |
| Translation                  | Translated content                                  |
| PII detection                | Redacted or flagged sensitive text                  |
| OCR                          | `text` from images within documents                 |
| Image caption/tag generation | `caption`, `tags` for visual content                |
| **Text Split**               | Chunks long documents into passages                 |
| **Azure OpenAI Embedding**   | Vectors for each chunk                              |

**Free tier limit:** ≤ 20 documents per indexer run with AI enrichment

**For semantic and vector retrieval you need exactly two skills:**

```text
    long product sheet ━━━▶ Text Split ━━━▶ chunks
                                                                                        ┃
                                                                                        ▼
                                                         Azure OpenAI Embedding ━━━▶ vectors ━▶ index
```

Entity extraction, language detection, and key phrase extraction enrich text but produce **no vectors**; Merge combines fields rather than chunking.

**For scanned invoices, the skill that makes the text searchable is OCR.** Text Split chunks text that already exists, Translation converts language, and Image Analysis describes visual content instead of extracting the invoice text.

---

<!-- _class: fit-24 -->

## Build a Knowledge Mining Solution

**Typical Azure AI Search workflow:**

1. Store source documents in Azure Blob Storage
2. Create a data source that connects the storage account
3. Define an index with searchable, filterable, and vector fields
4. Add a skillset for OCR, language, entities, key phrases, PII, or captions
5. Create an indexer to crack, enrich, and load the documents
6. Query with keyword, semantic, vector, or hybrid search

**Hybrid search is usually the best default for RAG:** lexical matching finds exact terms while vector search captures semantic similarity.

**Grounding loop:** search → select relevant chunks → provide citations and context → generate a response → evaluate groundedness.

---

<!-- _class: fit-20 -->

## Choosing a Retrieval Mode

**_[EXAM]_**

| Requirement                                        | Mode                |
| -------------------------------------------------- | ------------------- |
| Search **private** product sheets at all           | **Azure AI Search** |
| Match a question to differently worded source text | **Vector search**   |
| Exact codes **and** natural-language descriptions  | **Hybrid search**   |
| Reorder results that were already retrieved        | Semantic ranking    |
| Autocomplete while the user types                  | Suggesters          |
| Tokenize and normalize text for lexical matching   | Analyzers           |

**Traps:** semantic ranking only reranks what retrieval already returned, keyword-only search misses paraphrases, and vector-only search weakens exact code matching. Bing queries the public web, Translator converts languages, and Document Intelligence extracts content — none of them provide a private search index.

---

## Knowledge Store

**_[EXAM]_**

**Persists enriched content outside the search index — for downstream analytics or export**

**Projection types:**

| Type                   | Use Case                                  |
| ---------------------- | ----------------------------------------- |
| **Object projections** | Full enriched JSON document per file      |
| **Table projections**  | Normalized → queryable in Excel, Power BI |
| **File projections**   | Extracted images → stored as blobs        |

**Why knowledge store?** Enriched data survives index rebuilds; enables custom analytics pipelines; images can be exported separately from text content

**Choosing a projection:** unstructured enriched JSON → **object** projection; scanned text destined for rows and analytics → **table** projection. Reversing them stores tabular rows as loose JSON objects and forces unstructured content into a relational shape it does not fit.

---

<!-- _class: fit-20 -->

## Search Security Operations

**_[EXAM]_**

**Document-level filtering** — three steps, all required:

1. Add the **allowed groups** to every indexed document as a filterable field
2. Retrieve the signed-in user's **group memberships**
3. Pass those groups as a **filter** on each search request

```text
filter=groups/any(g: search.in(g, 'sales,finance'))
```

One index per group does not scale, an Entra access token authenticates but does not filter documents, and fetching _all_ groups returns memberships that are not the user's.

**Rotating a compromised query key** — order matters, or the app goes down:

```text
  1  point the app at the SECONDARY admin key   app keeps running
  2  regenerate the PRIMARY key                 compromised key dies
  3  move the app back to the NEW primary key
```

Regenerating the key the app is currently using breaks it immediately.

---

<!-- _class: lead -->

## Retrieval Practice — Lab 10

Pause here and complete [Lab 10](../lab/lab%2010/lab.md), then check its solution.

---

<!-- _class: lead -->

# Multimodal and Extraction Exam Gaps

Extend visual and extraction workflows with accessibility, safety, evidence, and cross-topic controls.

---

<!-- _class: fit-24 -->

## Visual Evidence and Accessibility

- **Alt-text:** concise, purposeful, and validated in context
- **Bounding regions:** preserve coordinates, confidence, and source references
- **Video:** retain timestamps, speakers, objects, and segment evidence
- **Safety:** screen visual content and protect against indirect prompt injection

Use a multimodal model for prose, and an extraction or detection workflow when automation needs evidence.

---

<!-- _class: fit-24 -->

## Extraction and Search Operations

- Use `prebuilt-layout` for document structure, tables, and Markdown
- Keep embedded figures with `AnalyzeOutputOption.FIGURES`
- Use object, table, or file projections for the required downstream shape
- Use hybrid search when lexical and semantic evidence both matter
- Filter document results by the user's allowed groups

**Cross-topic controls:** streaming audio, server VAD, `silence_duration_ms`, and `input_audio_buffer.speech_started` support low-latency voice; `Not(IsBlank(Local.Var1))` tests a workflow value.

---

## Retrieval Practice — Lab 5

Pause here and complete [Lab 5](../lab/lab%205/lab.md), then check its solution.

---

## Key Takeaways

1. **Responses API** — role `"developer"`, type `"input_image"`; result `response.output_text`
2. **ChatCompletions API** — role `"system"`, type `"image_url"` (nested `{"url": ...}`); **Phi-4 only supports this**
3. **Image generation** — `client.images.generate(model=, prompt=, n=, size=)` → `data[0].b64_json`
4. **Sora video** — create → poll → download; `seconds` as string; 24-hour expiry; max 2 concurrent
5. **Content Understanding** — `ContentUnderstandingClient`, `begin_analyze()`, `AnalysisInput(data=bytes)`; field methods: extract/classify/generate; thresholds: 0.9/0.7/<0.7
6. **Document Intelligence** — `read`, `layout`, prebuilt, custom template/neural/composed/classifier; `DocumentAnalysisClient`; ≤500 MB
7. **AI Search** — indexer + skillset enrichment pipeline; knowledge store for persisted projections; built-in skills require Foundry Tools resource
8. **Retrieval mode** — vector for paraphrase, hybrid for codes **and** prose, semantic ranking only reranks
9. **Projections** — object for unstructured JSON, table for rows and analytics, file for binary media
10. **Custom Vision** — create project → upload and tag → train; precision 100% means 0% false positives

---

<!-- _class: fit-20 -->

## Moderating Uploaded Images

**_[EXAM]_**

Users upload photos to an agent. The requirement is to **classify harmful visual content and block by severity** — that is **image moderation** in Azure AI Content Safety.

```python
from azure.ai.contentsafety import ContentSafetyClient
from azure.ai.contentsafety.models import AnalyzeImageOptions, ImageData

request = AnalyzeImageOptions(image=ImageData(content=image_bytes))
response = client.analyze_image(request)   # severity per harm category
```

| Control              | What it inspects                                    |
| -------------------- | --------------------------------------------------- |
| **Image moderation** | The **picture itself** — harm category and severity |
| OCR keyword scanning | Only text extracted from the image                  |
| Prompt shields       | Injected instructions, not visual harm              |
| Blocklists           | Configured phrases, reactive and text-only          |

**Two different image risks:** moderation stops a harmful _picture_; prompt shields stop _hidden instructions_ inside it. A solution that accepts uploads usually needs both.

---

<!-- _class: fit-24 -->

## Retrieval Practice — Lab 6

Pause here and complete [Lab 6](../lab/lab%206/lab.md), then check its solution.

---

<!-- _class: fit-24 -->

## Problem: Everyone Says "Analyse the Image"

Four people say the same sentence and mean four different things.

```text
  "analyse this image"
      ┃
      ┣━━ marketing wants   a caption          one nice sentence
      ┣━━ accessibility     alt-text           purpose, in context
      ┣━━ finance           the invoice total  a field + confidence
      ┗━━ safety            a bounding box     class + coordinates
```

**Need:** name the required _output_ first. The service then follows almost automatically.

Picking a service before naming the output is the most common mistake in this area — on the exam and in practice.

---

<!-- _class: fit-24 -->

## Prose or Evidence?

The deepest split in this topic is not "which product", it is **what the answer is made of**.

```text
  PROSE                              EVIDENCE
  a model describes                  an extractor locates

  "The invoice total is 1,240 EUR"   total: 1240.00
                                     confidence: 0.94
                                     page 2, polygon [x,y,...]

  great for humans                   required for automation,
  cannot be verified automatically   review queues, and audits
```

**Ask:** will a human read this, or will a system act on it? Only the second needs coordinates, confidence, and citations.

---

<!-- _class: fit-24 -->

## Visual Understanding Patterns

**_[EXAM]_**

**A multimodal solution may need several distinct outputs:**

| Output                    | Example                                             |
| ------------------------- | --------------------------------------------------- |
| Caption                   | “A delivery truck is parked beside a loading dock.” |
| Alt-text                  | A concise description usable by a screen reader     |
| Visual question answering | “What color is the truck?”                          |
| Grounded extraction       | Field value plus location or bounding region        |
| Object detection          | Object class plus coordinates and confidence        |
| Video understanding       | Events, timestamps, speakers, or segment summaries  |

**Choose the service by output:**

- Multimodal model: flexible reasoning over images
- Content Understanding: configurable multimodal extraction
- Document Intelligence: document layout, tables, and fields
- Computer vision detection APIs: objects, tags, faces, or regions

---

<!-- _class: fit-24 -->

## Custom Vision — Train a Classifier

**_[EXAM]_**

Classifying manufactured components as faulty or acceptable:

1. **Create a project** — choose **classification**, not object detection
2. **Upload and tag images** — this **is** how the training dataset is created
3. **Train the model**

| Distractor                           | Why it is wrong                                                            |
| ------------------------------------ | -------------------------------------------------------------------------- |
| “Initialize the training dataset”    | Not a step — the dataset comes from uploading and tagging images           |
| Train the **object detection** model | Object detection locates objects with bounding boxes; this assigns a label |

---

<!-- _class: fit-24 -->

## Precision and Recall

**_[EXAM]_**

```text
  precision = TP / (TP + FP)     of what I predicted, how much was correct
  recall    = TP / (TP + FN)     of what existed, how much did I find
```

| In a training summary | Means                                            |
| --------------------- | ------------------------------------------------ |
| **Precision 100%**    | No prediction was wrong → **0% false positives** |
| **Recall 100%**       | Every actual instance was found                  |

**Trap:** `TP / (TP + FP)` computes **precision**, so it is not the answer when the question asks for recall.

---

## Accessibility and Alt-Text

**_[EXAM]_**

**Alt-text is not the same as a marketing caption.**

Good alt-text should:

- Convey the purpose or information of the image
- Be concise and specific
- Identify relevant text, people, objects, and relationships
- Avoid guessing sensitive attributes
- Avoid “image of” unless it improves clarity
- Respect the surrounding page context

**Example:**

```text
Poor: An image.
Caption: A modern office with people working.
Alt-text: Three people review a dashboard beside a wall display showing monthly sales.
```

**Validate generated descriptions:** a model can omit important visual information or invent details. Accessibility review remains part of the application design.

**MSLearn status:** accessibility appears in responsible-AI material, but this applied visual workflow is not a dedicated lesson.

---

<!-- _class: fit-24 -->

## Video and Region-Level Analysis

**_[EXAM]_**

**For video, process the right unit of content:**

1. Identify the relevant time range
2. Sample frames or use a video analyzer
3. Detect speech, objects, scene changes, and actions
4. Preserve timestamps and confidence values
5. Summarize or extract fields with source references

**For images, region-level results may include:**

- Object label and confidence
- Bounding box or polygon
- Text location from OCR
- A field value grounded to a page or region

**Exam distinction:** a generative model can describe what it sees, but a detection or extraction workflow should return structured coordinates and evidence when the application needs them.

---

## Visual Safety and Policy Controls

**_[EXAM]_**

**Safety must cover both the prompt and the visual content.**

| Risk                                    | Possible control                                       |
| --------------------------------------- | ------------------------------------------------------ |
| Unsafe generated image                  | Content filters, moderation, human review              |
| Hidden instruction in an image          | Indirect prompt-injection detection and prompt shields |
| Prohibited symbol or brand misuse       | Vision classifier, policy rules, review workflow       |
| Missing disclosure                      | Watermark or “AI-generated” label                      |
| Inaccurate visual claim                 | Grounding, confidence threshold, abstention            |
| Sensitive person or attribute inference | Minimize collection and refuse unsupported inference   |

**Layer the controls:** model choice → input screening → prompt protections → output screening → user disclosure → monitoring.

**MSLearn status:** prompt shields and responsible AI are covered; this specific visual-policy checklist is an exam-oriented synthesis.

---

## Retrieval Practice — Lab 7

Pause here and complete [Lab 7](../lab/lab%207/lab.md), then check its solution.

---

<!-- _class: fit-24 -->

## Document Intelligence vs. Content Understanding

**_[EXAM]_**

| Requirement                                                  | Prefer                               |
| ------------------------------------------------------------ | ------------------------------------ |
| Read printed or handwritten text                             | Document Intelligence `read`         |
| Tables, layout, selection marks, key-value pairs             | Document Intelligence `layout`       |
| Invoice, receipt, ID, or other prebuilt fields               | Document Intelligence prebuilt model |
| Fixed or variable custom document forms                      | Document Intelligence custom model   |
| Multimodal fields across documents, images, audio, and video | Content Understanding analyzer       |
| Extract, classify, or generate custom fields                 | Content Understanding field schema   |

**Confidence is not correctness:** route uncertain fields to review and retain source grounding such as page, polygon, timestamp, or document reference.

---

## Retrieval Practice — Lab 8

Pause here and complete [Lab 8](../lab/lab%208/lab.md), then check its solution.

---

## Azure AI Search and Knowledge Mining

**_[EXAM]_**

**Knowledge-mining pipeline:**

```text
Data source → indexer → skillset → index → query or knowledge store
```

**Exam decisions:**

- Full-text/BM25: exact lexical matching
- Semantic ranking: language-aware reranking
- Vector search: semantic similarity using embeddings
- Hybrid search: combine lexical and vector evidence
- Knowledge store: persist enriched projections for analytics or export

**A production index also needs:**

- A document key and stable source metadata
- Searchable, filterable, sortable, and vector fields as needed
- Chunking and overlap appropriate to the content
- Indexer failure monitoring and incremental refresh strategy
- Relevance evaluation with representative queries

---

## Translation Beyond Text

**_[EXAM]_**

| Scenario             | Service or workflow                                                                 |
| -------------------- | ----------------------------------------------------------------------------------- |
| Text translation     | Azure Translator `translate()`                                                      |
| Script conversion    | Translator `transliterate()`                                                        |
| Speech translation   | Speech `TranslationRecognizer`                                                      |
| Document translation | Translator document translation workflow with source and target storage             |
| Multilingual RAG     | Detect language, retrieve language-appropriate sources, translate only where needed |

**Design choice:** translating before retrieval may improve cross-language search, while translating after retrieval may preserve the original source for citations. Test both with the target dataset.

**MSLearn status:** text, transliteration, and speech translation are directly covered; document translation is less developed in the scraped course.

---

## Cross-Topic Exam Controls

Some exam scenarios combine topics. For low-latency voice agents, streaming audio, server-side VAD, and `silence_duration_ms` reduce turn latency; `input_audio_buffer.speech_started` signals barge-in. In a workflow, `Not(IsBlank(Local.Var1))` tests that a scoped variable has a value.

---

## Retrieval Practice — Lab 9

Pause here and complete [Lab 9](../lab/lab%209/lab.md) before continuing.

---

## Key Takeaways

1. **Output determines service:** caption, alt-text, detection, extraction, and video analysis are different tasks
2. **Ground visual answers:** preserve regions, pages, timestamps, confidence, and citations
3. **Accessibility is a quality requirement:** validate generated alt-text in context
4. **Visual safety needs layers:** filters, prompt shields, policy rules, disclosure, and review
5. **Choose extraction deliberately:** Document Intelligence for document structure; Content Understanding for multimodal analyzers
6. **Search operations matter:** monitor indexing, refreshes, failures, and relevance, not just query syntax
7. **Translation scope matters:** text, speech, scripts, documents, and multilingual retrieval have different workflows
8. **MSLearn relationship:** most core services are directly covered; the exam adds specific policy, accessibility, region-level, and operational expectations

---

<!-- _class: lead -->

# Appendix

Relationship to the Microsoft Learn path

---

<!-- _class: fit-20 -->

## Coverage Map

| Exam objective                                  | MSLearn status                                                                                                        |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Multimodal prompts and visual grounding         | **Direct** — dedicated vision lesson                                                                                  |
| Image and video generation/editing              | **Direct** — dedicated lessons                                                                                        |
| Accessibility descriptions and alt-text         | **Indirect** — accessibility is mentioned, but not taught as a visual-output workflow                                 |
| Video segments and object/region detection      | **Partial** — Content Understanding is covered; detailed vision detection patterns are lighter                        |
| Visual policy controls and watermarking         | **Exam gap** — not developed as a dedicated objective                                                                 |
| Document Intelligence and Content Understanding | **Direct** — multiple detailed lessons                                                                                |
| Search indexing, enrichment, and RAG            | **Direct** — dedicated AI Search lesson                                                                               |
| Document translation                            | **Partial** — text, speech translation, and transliteration are covered; document translation is not developed deeply |

**Interpretation:** this topic adds exam vocabulary and decision patterns around areas that the official lessons either mention briefly or treat through a different service.
