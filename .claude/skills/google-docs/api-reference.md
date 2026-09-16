# Google Docs API Reference

## Official Documentation

Use these references when troubleshooting API errors or looking up syntax:

- [Documents Resource Overview](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents) - Document structure and fields
- [documents.create](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/create) - Create new documents
- [documents.get](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/get) - Retrieve document content
- [documents.batchUpdate](https://developers.google.com/workspace/docs/api/reference/rest/v1/documents/batchUpdate) - Insert, update, delete content

## API Endpoints Used by Scripts

Base URL: `https://docs.googleapis.com/v1`

| Script | Endpoint | Method |
|--------|----------|--------|
| `create_doc.sh` | `/documents` | POST |
| `read_doc.sh` | `/documents/{documentId}` | GET |
| `doc_info.sh` | `/documents/{documentId}` | GET |
| `append_doc.sh` | `/documents/{documentId}:batchUpdate` | POST |
| `replace_doc.sh` | `/documents/{documentId}:batchUpdate` | POST |
| `create_from_markdown.sh` | Uses Drive API multipart upload | POST |

## Batch Update Requests

### Insert Text

```json
{"insertText": {"location": {"index": 1}, "text": "Hello World\n"}}
```

### Insert Heading

```json
[
  {"insertText": {"location": {"index": 1}, "text": "Heading\n"}},
  {"updateParagraphStyle": {
    "range": {"startIndex": 1, "endIndex": 9},
    "paragraphStyle": {"namedStyleType": "HEADING_1"},
    "fields": "namedStyleType"
  }}
]
```

### Format Text

```json
{"updateTextStyle": {
  "range": {"startIndex": 1, "endIndex": 10},
  "textStyle": {"bold": true, "italic": true},
  "fields": "bold,italic"
}}
```

### Insert Link

```json
[
  {"insertText": {"location": {"index": 1}, "text": "Click here"}},
  {"updateTextStyle": {
    "range": {"startIndex": 1, "endIndex": 11},
    "textStyle": {"link": {"url": "https://example.com"}},
    "fields": "link"
  }}
]
```

### Insert Table

```json
{"insertTable": {"rows": 3, "columns": 2, "location": {"index": 1}}}
```

### Delete Content

```json
{"deleteContentRange": {"range": {"startIndex": 1, "endIndex": 50}}}
```

## Creating Docs from Markdown

The `create_from_markdown.sh` script uses the Drive API multipart upload with MIME type conversion:

```bash
POST https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart
Content-Type: multipart/related; boundary=...

--boundary
Content-Type: application/json

{"name": "Title", "mimeType": "application/vnd.google-apps.document"}
--boundary
Content-Type: text/markdown

# Markdown content here
--boundary--
```

Google Drive automatically converts the markdown to native Google Docs formatting.
