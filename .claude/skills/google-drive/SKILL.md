---
name: google-drive
description: Search, list, download, upload, and copy files from Google Drive. Set sharing permissions. Supports Google Docs, Sheets, Slides, PDFs, images, and folders. Use when the user mentions Google Drive, asks to find a file, needs to download a document for context, wants to upload images, set sharing, list folder contents, asks to create a document from a template, or references a drive.google.com URL.
user-invocable: true
---

# Google Drive

## Prerequisites

**Default project:** `rsg-api-auth-dev` (Google Docs and Drive APIs enabled)

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive" \
  --client-id-file=/workspace/google-cloud-sdk/intuit_client_secrets.json \
  --set-quota-project=rsg-api-auth-dev
```

## Scripts

Scripts location: `scripts/` subdirectory of this skill (resolves via `~/.claude/skills/google-drive/scripts/` or `~/.cursor/skills/google-drive/scripts/`)

File IDs are extracted automatically from URLs:
- Docs: `docs.google.com/document/d/FILE_ID/edit`
- Sheets: `docs.google.com/spreadsheets/d/FILE_ID/edit`
- Drive: `drive.google.com/file/d/FILE_ID/view`

## Operations

| Operation | Command |
|-----------|---------|
| Search | `scripts/search_files.sh --name "report" --type doc` |
| Download | `scripts/download_file.sh FILE_ID [--stdout] [--format md]` |
| Upload | `scripts/upload_file.sh image.png [--folder FOLDER_ID]` |
| Share | `scripts/share_file.sh FILE_ID --anyone` |
| Copy | `scripts/copy_file.sh FILE_ID --name "New Name"` |
| Info | `scripts/file_info.sh FILE_ID` |
| List folder | `scripts/list_folder.sh [FOLDER_ID] [--tree]` |

**Search types:** `doc`, `sheet`, `slide`, `pdf`, `image`, `folder`, `all`

**Export formats:**
- Docs: `text`, `md`, `pdf`, `docx`, `html`
- Sheets: `csv`, `xlsx`, `pdf`
- Slides: `pdf`, `pptx`

## Share Files

```bash
scripts/share_file.sh FILE_ID --anyone                    # Anyone with link
scripts/share_file.sh FILE_ID --email user@example.com   # Specific user
scripts/share_file.sh FILE_ID --domain example.com       # Domain-wide
```

**Note:** Corporate policies may block `--anyone`. See [workflows.md](workflows.md) for workarounds.

## Additional Resources

- Common workflows and examples: [workflows.md](workflows.md)
- Advanced query syntax: [query-syntax.md](query-syntax.md)
- API reference: [api-reference.md](api-reference.md)
- Google Cloud project setup: [google-cloud-setup.md](google-cloud-setup.md)
