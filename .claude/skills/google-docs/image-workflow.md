# Image Workflow for Google Docs

## Standard Workflow (Mermaid Diagrams)

1. Generate PNG using mermaid-diagrams skill
2. Upload to Drive using google-drive skill
3. Share publicly with `share_file.sh --anyone`
4. Insert using `webContentLink` from share output

```bash
# 1. Generate PNG
mmdc -i diagram.mmd -o diagram.png -t default -b white -e png -s 4

# 2. Upload to Drive
FILE_ID=$(~/.claude/skills/google-drive/scripts/upload_file.sh diagram.png | grep "File ID:" | cut -d' ' -f3)

# 3. Share publicly
URL=$(~/.claude/skills/google-drive/scripts/share_file.sh $FILE_ID --anyone | grep "webContentLink:" | cut -d' ' -f2)

# 4. Insert into doc
scripts/insert_image.sh DOC_ID "$URL" --width 500
```

See [Insert inline images](https://developers.google.com/workspace/docs/api/how-tos/images).

## Corporate Workspace Limitation

**Problem:** Corporate Google Workspace policies may restrict public sharing (`--anyone`), causing `share_file.sh` to fail with error 403: "The user does not have sufficient permissions for this file."

The Google Docs API requires publicly accessible URLs for image insertion. When public sharing is blocked, use these workarounds:

### Workaround 1: Link Instead of Embed

Include Drive view links in the document. Users click to view diagrams.

```bash
# Upload and get file ID
FILE_ID=$(~/.claude/skills/google-drive/scripts/upload_file.sh diagram.png | grep "File ID:" | cut -d' ' -f3)

# Include link in markdown
# [View Diagram](https://drive.google.com/file/d/FILE_ID/view)
```

### Workaround 2: Manual Insertion

After creating the doc, manually insert images via **Insert > Image > Drive** in Google Docs UI.

### Workaround 3: External Hosting

Host images on a publicly accessible server (GitHub, S3, etc.) that doesn't have sharing restrictions.

```bash
# Example: Use GitHub raw URL
scripts/insert_image.sh DOC_ID "https://raw.githubusercontent.com/user/repo/main/diagram.png" --width 500
```
