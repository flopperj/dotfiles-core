# Google Drive Workflows

## Add File Content to Context

```bash
scripts/search_files.sh --name "design doc"
scripts/download_file.sh FILE_ID --stdout
```

## Create Document from Template

```bash
scripts/search_files.sh --name "template" --type doc
scripts/copy_file.sh TEMPLATE_ID --name "New Project Brief"
```

## Export Spreadsheet Data

```bash
scripts/search_files.sh --type sheet --name "data"
scripts/download_file.sh FILE_ID --format csv --output data.csv
```

## Embed Image in Google Doc

Requires: mermaid-diagrams skill, google-docs skill

```bash
# 1. Generate PNG from mermaid
mmdc -i diagram.mmd -o diagram.png -t default -b white -e png -s 4

# 2. Upload to Drive
FILE_ID=$(scripts/upload_file.sh diagram.png | grep "File ID:" | cut -d' ' -f3)

# 3. Share publicly to get webContentLink
URL=$(scripts/share_file.sh $FILE_ID --anyone | grep "webContentLink:" | cut -d' ' -f2)

# 4. Insert into Google Doc
~/.claude/skills/google-docs/scripts/insert_image.sh DOC_ID "$URL" --width 500
```

## Corporate Workspace Limitation

**Problem:** If `--anyone` fails with error 403 ("The user does not have sufficient permissions for this file"), your organization's Google Workspace admin policy restricts public link sharing.

The Google Docs API requires publicly accessible URLs for image insertion. When public sharing is blocked:

### Workaround 1: Link Instead of Embed

Include a clickable link to the Drive file in your document:

```markdown
**Diagram: Architecture**
[View Diagram](https://drive.google.com/file/d/FILE_ID/view)
```

### Workaround 2: Manual Insertion

Create the doc first, then manually insert images via **Insert > Image > Drive** in Google Docs UI.

### Workaround 3: External Hosting

Upload images to a publicly accessible location (GitHub, S3, etc.) that doesn't have sharing restrictions.

### Alternative Sharing Options

If public sharing is blocked, you can still share with:

```bash
scripts/share_file.sh FILE_ID --email user@example.com      # Specific user
scripts/share_file.sh FILE_ID --group team@example.com     # Google Group
scripts/share_file.sh FILE_ID --domain example.com         # Domain-wide
```
