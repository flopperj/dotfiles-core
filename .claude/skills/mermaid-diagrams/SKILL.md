---
name: mermaid-diagrams
description: Generate PNG images from Mermaid syntax using mermaid-cli (mmdc). Supports flowcharts, sequence diagrams, ER diagrams, class diagrams, and more. Can update markdown files to replace mermaid code blocks with image links for Google Docs compatibility. Use when the user wants to convert mermaid to PNG, generate diagram images, export diagrams for docs, or says "mermaid to PNG", "diagram image", or "export diagram".
user-invocable: true
---

# Mermaid Diagrams

Generate PNG diagrams from Mermaid syntax using `mmdc`.

## Prerequisites

**Check if `mmdc` is installed:**

```bash
if ! command -v mmdc &> /dev/null; then
  echo "mermaid-cli (mmdc) not found."
fi
```

**Install options (if not found):**

Option 1 — Global install (recommended for frequent use):

```bash
npm install -g @mermaid-js/mermaid-cli
```

Option 2 — Use via npx (no global install required):

```bash
npx -p @mermaid-js/mermaid-cli mmdc -i input.mmd -o output.png
```

For more information, see the [mermaid-cli GitHub repo](https://github.com/mermaid-js/mermaid-cli).

## Chrome Configuration

PNG generation requires Chrome/Puppeteer. If you encounter errors about Chrome not being found, set the `PUPPETEER_EXECUTABLE_PATH` environment variable to use your system Chrome:

```bash
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

Or prefix individual commands:

```bash
PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" mmdc -i diagram.mmd -o diagram.png -e png
```

## Quick Commands

### Generate PNG from .mmd file (light mode default)

```bash
mmdc -i diagram.mmd -o diagram.png -t default -b white -e png -s 4
```

### Generate from stdin

```bash
cat << 'EOF' | mmdc --input - -o output.png -t default -b white -e png -s 4
graph TD
    A[Start] --> B[End]
EOF
```

### Update markdown with diagram images

```bash
mmdc -i template.md -o output.md -t default -b white -e png -s 4
```

This extracts mermaid code blocks from markdown, generates numbered image files, and replaces blocks with `![diagram](./output-N.png)` references.

### Custom image output directory

```bash
mmdc -i template.md -o docs/README.md -a docs/images/ -t default -b white -e png -s 4
```

## Default Configuration

- **Theme**: `default` (light colors)
- **Background**: `white`
- **Scale**: `4` (4x resolution for crisp images)

For dark mode (only when requested): `-t dark -b transparent`

## Additional Resources

- For CLI options and troubleshooting, see [reference.md](reference.md)
- For diagram type examples, see [examples.md](examples.md)
