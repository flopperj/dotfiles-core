---
name: google-docs
description: Create, read, append, replace content, and insert images in Google Docs. Converts Markdown to native Docs formatting including headings, lists, tables, links, and code blocks. Use when the user asks to create a Google Doc, read a doc, edit a doc, insert images, convert markdown to Google Docs, or references a docs.google.com URL.
user-invocable: true
---

# Google Docs

## Prerequisites

**Default project:** `rsg-api-auth-dev` (Google Docs and Drive APIs enabled)

```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive" \
  --client-id-file=/workspace/google-cloud-sdk/<your-org>_client_secrets.json \
  --set-quota-project=rsg-api-auth-dev
```

## Scripts

Scripts location: `scripts/` subdirectory of this skill (resolves via `~/.claude/skills/google-docs/scripts/` or `~/.cursor/skills/google-docs/scripts/`)

Document IDs are extracted automatically from URLs: `docs.google.com/document/d/DOC_ID/edit`

| Operation | Command |
|-----------|---------|
| Create (plain) | `scripts/create_doc.sh "Title" "Content"` |
| Create (markdown) | `scripts/create_doc.sh "Title" "# Heading" --markdown` |
| Create from file | `scripts/create_from_markdown.sh "Title" --file doc.md` |
| Read | `scripts/read_doc.sh DOC_ID` |
| Append | `scripts/append_doc.sh DOC_ID "Text"` |
| Replace | `scripts/replace_doc.sh DOC_ID "Content"` |
| Insert image | `scripts/insert_image.sh DOC_ID IMAGE_URL [--width W] [--index N]` |
| Info | `scripts/doc_info.sh DOC_ID` |

## Markdown Support

Use `--markdown` flag or `create_from_markdown.sh` for proper formatting:

```bash
scripts/create_from_markdown.sh "Report" --file report.md
echo "# Hello World" | scripts/create_from_markdown.sh "Test"
```

Supported: headings, lists, tables, links, bold/italic, code blocks, horizontal rules.

## Insert Images

Images must be publicly accessible URLs. For Drive images, share publicly first.

```bash
scripts/insert_image.sh DOC_ID "https://..." --width 500
```

**Note:** Corporate policies may block public sharing. See [image-workflow.md](image-workflow.md) for workarounds.

## Additional Resources

- Image embedding workflow: [image-workflow.md](image-workflow.md)
- API reference and batch requests: [api-reference.md](api-reference.md)
- Auth troubleshooting: [troubleshooting.md](troubleshooting.md)
- Google Cloud project setup: [google-cloud-setup.md](google-cloud-setup.md)
