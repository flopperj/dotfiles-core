# Drive Query Syntax

For advanced searches using `--query`, use [Drive search query syntax](https://developers.google.com/drive/api/guides/search-files).

## Examples

```bash
# Files modified after a date
scripts/search_files.sh --query "modifiedTime > '2026-02-20'"

# Files shared with specific user
scripts/search_files.sh --query "'user@example.com' in readers"

# Files in a specific folder
scripts/search_files.sh --query "'FOLDER_ID' in parents"

# Files with specific text content
scripts/search_files.sh --query "fullText contains 'quarterly report'"

# Starred files
scripts/search_files.sh --query "starred = true"

# Trashed files
scripts/search_files.sh --query "trashed = true"
```

## Common Query Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `name contains` | Filename contains text | `name contains 'budget'` |
| `fullText contains` | Content contains text | `fullText contains 'Q1'` |
| `mimeType =` | Specific file type | `mimeType = 'application/pdf'` |
| `modifiedTime >` | Modified after date | `modifiedTime > '2026-01-01'` |
| `createdTime <` | Created before date | `createdTime < '2026-01-01'` |
| `'email' in readers` | Shared with user | `'user@example.com' in readers` |
| `'id' in parents` | In specific folder | `'FOLDER_ID' in parents` |

## Combining Queries

Use `and` / `or` to combine conditions:

```bash
scripts/search_files.sh --query "name contains 'report' and modifiedTime > '2026-02-01'"
scripts/search_files.sh --query "mimeType = 'application/pdf' or mimeType = 'image/png'"
```
