# Google Drive API Reference

## Official Documentation

Use these references when troubleshooting API errors or looking up syntax:

- [Drive API v3 Overview](https://developers.google.com/workspace/drive/api/reference/rest/v3) - API structure and available resources
- [Drives Resource](https://developers.google.com/workspace/drive/api/reference/rest/v3/drives) - Shared drive operations
- [files.create](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/create) - Create files and folders
- [files.get](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/get) - Get file metadata
- [files.list](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/list) - Search and list files
- [files.download](https://developers.google.com/workspace/drive/api/reference/rest/v3/files/download) - Download file content

## API Endpoints Used by Scripts

Base URL: `https://www.googleapis.com/drive/v3`

| Script | Endpoint | Method |
|--------|----------|--------|
| `search_files.sh` | `/files` | GET |
| `list_folder.sh` | `/files` | GET |
| `file_info.sh` | `/files/{fileId}` | GET |
| `download_file.sh` | `/files/{fileId}?alt=media` | GET |
| `download_file.sh` (export) | `/files/{fileId}/export` | GET |
| `copy_file.sh` | `/files/{fileId}/copy` | POST |

## Common Query Parameters

### files.list / search

```bash
GET /files?q={query}&pageSize={n}&orderBy={field}&fields={fieldMask}
```

**Query syntax examples:**
- `name contains 'report'` - Files with "report" in name
- `mimeType = 'application/vnd.google-apps.document'` - Google Docs only
- `'FOLDER_ID' in parents` - Files in specific folder
- `trashed = false` - Exclude trashed files
- `fullText contains 'budget'` - Full-text content search

### files.get

```bash
GET /files/{fileId}?fields={fieldMask}
```

**Common fields:** `id,name,mimeType,createdTime,modifiedTime,size,webViewLink,parents`

## MIME Types

| Type | MIME Type |
|------|-----------|
| Google Doc | `application/vnd.google-apps.document` |
| Google Sheet | `application/vnd.google-apps.spreadsheet` |
| Google Slides | `application/vnd.google-apps.presentation` |
| Folder | `application/vnd.google-apps.folder` |
| PDF | `application/pdf` |

## Exporting Google Workspace Files

Google Workspace files (Docs, Sheets, Slides) cannot be downloaded directly. Use the export endpoint:

```bash
GET /files/{fileId}/export?mimeType={exportMimeType}
```

**Export formats:**

| Source | Export MIME Type | Extension |
|--------|------------------|-----------|
| Docs | `text/plain` | .txt |
| Docs | `application/pdf` | .pdf |
| Docs | `application/vnd.openxmlformats-officedocument.wordprocessingml.document` | .docx |
| Sheets | `text/csv` | .csv |
| Sheets | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` | .xlsx |
| Slides | `application/pdf` | .pdf |
| Slides | `application/vnd.openxmlformats-officedocument.presentationml.presentation` | .pptx |

## Copying Files

```bash
POST /files/{fileId}/copy
Content-Type: application/json

{
  "name": "Copy Name",
  "parents": ["DESTINATION_FOLDER_ID"]
}
```
