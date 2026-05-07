# <img src="https://raw.githubusercontent.com/databio/markmeld/master/docs/img/markmeld_logo_long.svg?sanitize=true" alt="markmeld logo" height="70">

Markmeld is a markdown melder. It merges YAML and Markdown content using Jinja2 templates and pipes the result through a command (typically `pandoc`) to produce polished output such as PDF or HTML. It is useful for resumes, biosketches, manuscripts, proposals, books, and similar publication-ready documents.

Full documentation: [markmeld.databio.org](https://markmeld.databio.org).

## Installation

```bash
pip install markmeld
```

This installs the `mm` command-line executable. To produce PDFs you will also need [pandoc](https://pandoc.org/) and a LaTeX distribution available on your `PATH`.

## How it works

Markmeld is driven by three kinds of files:

1. **Configuration file** (`_markmeld.yaml`) — declares one or more *targets*, each describing how to build a document.
2. **Data files** — YAML for structured data, Markdown for prose.
3. **Jinja2 template** — defines how data is merged into the rendered output.

When you run `mm <target>`, markmeld loads the data files, renders them through the Jinja2 template, and pipes the result to the command specified by the target (defaulting to `pandoc`).

## Quick start

From the repo, build the demo:

```bash
cd demo
mm default
```

To inspect what gets produced without running pandoc:

```bash
mm default -p > rendered.md
```

To scaffold a new config file in the current directory:

```bash
mm -i
```

## Writing a config file

A minimal `_markmeld.yaml`:

```yaml
targets:
  target1:
    output_file: "{today}_demo_output.pdf"
    latex_template: pandoc_default.tex
    jinja_template: jinja_template.jinja
    command: |
      pandoc --template "{latex_template}" --output "{output_file}"
    data:
      yaml_files:
        - some_data.yaml
      md_files:
        some_text_data: some_text.md
```

- `jinja_template` — the Jinja2 template used to assemble the output.
- `data.yaml_files` / `data.md_files` — files merged into the template context. Markdown files are exposed under the keys you assign (e.g. `some_text_data`).
- `command` — the shell command receiving the rendered template on `stdin`. If omitted, the default pandoc command is used.
- `output_file` — destination path. `{today}` and other placeholders are substituted at build time.

## CLI usage

| Command | Description |
|---|---|
| `mm` | List available targets. |
| `mm -l` | List targets with their descriptions. |
| `mm <target>` | Build the target. |
| `mm <target> -p` | Print the rendered template instead of piping it to the command. |
| `mm <target> -d` | Dump the merged data object as JSON (useful for debugging Jinja templates). |
| `mm <target> -e` | Explain the target — show its resolved configuration. |
| `mm <target> -t` | Show the Jinja template that will be used. |
| `mm <target> -v key=value …` | Pass extra variables into the template. |
| `mm -c <config>` | Use a config other than `_markmeld.yaml`. |
| `mm -i [path]` | Initialize a new config file (default `_markmeld.yaml`). |

## Target types

- **Default** — renders the template and pipes it to `command`.
- **Raw** (`type: raw`) — runs `command` directly without piping anything to `stdin`.
- **Meta** (`type: meta`) — runs no command of its own; useful for grouping prebuilds.
- **Abstract** (`abstract: true`) — cannot be built directly, but can be inherited by other targets to share configuration.

Example meta target that builds two others:

```yaml
targets:
  all:
    type: meta
    prebuild:
      - target2
      - target3
```

## Rendering a Google Doc — `render.sh`

`render.sh` is a single wrapper that renders the **"4. Research Strategy"** Google Doc to PDF using markmeld. It handles the full pipeline: pulling the Doc + figure SVGs from Google Drive, sanitizing Google's markdown export, converting SVGs to PNGs, and running `mm`.

```
./render.sh                       # render from local cache (gdoc_build/)
./render.sh --fetch               # pull latest Doc + figure SVGs from Drive first
./render.sh --doc  <fileId>       # override the Doc id
./render.sh --figs <folderId>     # override the fig/ folder id
./render.sh --help
```

Output: `./4_Research_Strategy.pdf`

### What it does

1. **(optional) `--fetch`** — uses the Google Drive API to export the Doc as Markdown into `gdoc_build/research_strategy.md` and download every SVG from the figure folder into `gdoc_build/fig_svg/`.
2. **Sanitize** — unescapes Google's markdown export, drops the inline base64 image refs (`![][imageN]` and their `[imageN]: data:...` definitions), and replaces the `barrier-pipeline.csv` "image" with a placeholder note.
3. **Convert SVGs** — runs `rsvg-convert` only on SVGs newer than their corresponding PNG, so re-runs are fast.
4. **Render** — `mm research_strategy` from `gdoc_build/`.

### Prerequisites

The local-only path needs `mm`, `pandoc`, `tectonic` (or another pandoc PDF engine), `rsvg-convert`, and `python3` on `PATH`. On macOS:

```bash
pip install markmeld
brew install pandoc tectonic librsvg
```

### One-time setup for `--fetch`

```bash
pip install google-api-python-client google-auth-oauthlib google-auth-httplib2
```

Then create a **Desktop-app** OAuth client at [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials → Create OAuth client ID → Application type: *Desktop app* → Download JSON. Save the file to:

```bash
mkdir -p ~/.config/markmeld-grant
mv ~/Downloads/client_secret_*.json ~/.config/markmeld-grant/credentials.json
```

The first `--fetch` opens a browser tab for consent; the resulting token is cached at `~/.config/markmeld-grant/token.json` and reused thereafter.

### Build artifacts

The wrapper expects this layout (created on first run):

```
gdoc_build/
├── _markmeld.yaml             # markmeld target config
├── nih_template.tex           # custom LaTeX template (NIH-style headings, single column)
├── figattrs.lua               # pandoc Lua filter for {fullwidth=…} / {wrap=…} attrs
├── template.jinja             # Jinja wrapper
├── research_strategy.md       # raw Doc export (overwritten by --fetch)
├── research_strategy_clean.md # sanitized markdown (regenerated each run)
├── fig_svg/                   # SVG sources (overwritten by --fetch)
└── fig/                       # PNGs derived from fig_svg/
```

## Testing

Run the test suite:

```bash
pytest
```

Or build the bundled demos:

```bash
cd demo && mm default
cd demo_book && mm default
cd demo_collab && mm default
```

## Further reading

The `docs/` directory and [markmeld.databio.org](https://markmeld.databio.org) cover advanced topics:

- Imports and inheritance between configs (`docs/imports.md`, `docs/inheriting.md`)
- Mail-merge style multi-output targets (`docs/mail_merge.md`, `docs/multi_output_targets.md`)
- Recursive rendering (`docs/recursive_rendering.md`)
- Remote templates (`docs/remote_templates.md`)
- Side targets and target factories (`docs/side_targets.md`, `docs/target_factories.md`)
- Full configuration specification (`docs/config_specification.md`)
