# Mermaid CLI Reference

## Command Options

| Option | Description | Default |
|--------|-------------|---------|
| `-i, --input` | Input file (.mmd or .md) or `-` for stdin | Required |
| `-o, --output` | Output file (.png, .svg, .pdf) | input + ".svg" |
| `-t, --theme` | Theme: `default`, `forest`, `dark`, `neutral` | `default` |
| `-b, --backgroundColor` | Background color | `white` |
| `-w, --width` | Page width in pixels | 800 |
| `-H, --height` | Page height in pixels | 600 |
| `-s, --scale` | Scale factor for output | 1 |
| `-a, --artefacts` | Output directory for images (markdown mode) | output directory |
| `-c, --configFile` | JSON config file for mermaid | None |
| `-p, --puppeteerConfigFile` | JSON config for puppeteer | None |
| `-q, --quiet` | Suppress log output | false |

## Theme Comparison

| Theme | Best For |
|-------|----------|
| `default` | Light mode, general purpose (recommended) |
| `neutral` | Light mode, minimal styling |
| `forest` | Light mode, green accent colors |
| `dark` | Dark mode presentations |

## Troubleshooting

### Diagram not rendering

- Validate syntax at https://mermaid.live/
- Verify installation: `which mmdc`

### Text cut off

Increase dimensions:

```bash
mmdc -i diagram.mmd -o diagram.png -w 1200 -H 800
```

### Blurry output

Increase scale factor:

```bash
mmdc -i diagram.mmd -o diagram.png -s 2
```

### Linux sandbox issues

Create `puppeteer-config.json`:

```json
{
  "args": ["--no-sandbox"]
}
```

Use: `mmdc -i input.mmd -o output.png -p puppeteer-config.json`
