#!/usr/bin/env bash
# render.sh — render the "4. Research Strategy" Google Doc to PDF.
#
# Pipeline:
#   1. (optional) Fetch latest Doc + figure SVGs from Google Drive
#   2. Sanitize the Google-Docs markdown export (unescape, drop inline base64 imgs)
#   3. Convert any new/changed SVGs in gdoc_build/fig_svg/ to PNGs in gdoc_build/fig/
#   4. Run `mm research_strategy` (markmeld → pandoc → tectonic)
#
# Output: ./4_Research_Strategy.pdf
#
# Quick usage:
#   ./render.sh                   render from local cache (gdoc_build/)
#   ./render.sh --fetch           pull latest Doc + figures from Drive first
#   ./render.sh --doc  <fileId>   override the Doc id
#   ./render.sh --figs <folderId> override the fig/ folder id
#   ./render.sh --help
#
# --fetch requires (one-time):
#   pip install google-api-python-client google-auth-oauthlib google-auth-httplib2
#   Place a Desktop-app OAuth client JSON at ~/.config/markmeld-grant/credentials.json
#     (Google Cloud Console → APIs & Services → Credentials → Create OAuth client ID
#      → Application type: Desktop app → Download JSON)

set -euo pipefail

# --- Defaults (can be overridden via flags or env) ---
DOC_ID="${DOC_ID:-1uhb5nS3eWsJkqj_jxTJpvFXIhGxKLRKesTIljKyPO8c}"        # 4. Research Strategy
FIG_FOLDER_ID="${FIG_FOLDER_ID:-1I78DtX1sN-1bf-vxRiF9fmVjNdp7xfEF}"     # current fig/ folder
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD="$ROOT/gdoc_build"
FETCH=0

usage() {
  sed -n '/^# render.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--fetch)  FETCH=1; shift ;;
    --doc)       DOC_ID="$2"; shift 2 ;;
    --figs)      FIG_FOLDER_ID="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# --- Sanity checks ---
for cmd in mm pandoc tectonic rsvg-convert python3; do
  command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd" >&2; exit 1; }
done
mkdir -p "$BUILD/fig" "$BUILD/fig_svg"

# 1. Optional: refresh Doc + figures from Drive (uses Python + Drive API).
if [[ $FETCH -eq 1 ]]; then
  echo "→ Fetching from Drive..."
  python3 - "$DOC_ID" "$FIG_FOLDER_ID" "$BUILD" <<'PYEOF'
import io, sys, pathlib
try:
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseDownload
except ImportError:
    sys.exit("Missing Python deps. Run:\n"
             "  pip install google-api-python-client google-auth-oauthlib google-auth-httplib2")

doc_id, fig_folder_id, out_dir = sys.argv[1:4]
cfg = pathlib.Path.home() / ".config/markmeld-grant"
cfg.mkdir(parents=True, exist_ok=True)
creds_file, token_file = cfg / "credentials.json", cfg / "token.json"

if not creds_file.exists():
    sys.exit(
        f"\nOAuth credentials not found.\n"
        f"  Save a Desktop-app OAuth client JSON to:\n    {creds_file}\n"
        f"  (Google Cloud Console → APIs & Services → Credentials → OAuth client ID → Desktop)"
    )

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]
creds = Credentials.from_authorized_user_file(str(token_file), SCOPES) if token_file.exists() else None
if not creds or not creds.valid:
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    else:
        creds = InstalledAppFlow.from_client_secrets_file(str(creds_file), SCOPES).run_local_server(port=0)
    token_file.write_text(creds.to_json())

svc = build("drive", "v3", credentials=creds, cache_discovery=False)

def download(req):
    buf = io.BytesIO()
    dl = MediaIoBaseDownload(buf, req)
    done = False
    while not done:
        _, done = dl.next_chunk()
    return buf.getvalue()

# Export the Doc as markdown
print(f"  exporting Doc {doc_id} → markdown")
md_bytes = download(svc.files().export_media(fileId=doc_id, mimeType="text/markdown"))
md_path = pathlib.Path(out_dir) / "research_strategy.md"
md_path.write_bytes(md_bytes)
print(f"    {md_path} ({len(md_bytes):,} bytes)")

# Download every SVG in the fig folder
q = f"'{fig_folder_id}' in parents and mimeType='image/svg+xml' and trashed=false"
files = svc.files().list(q=q, pageSize=100, fields="files(id,name)").execute().get("files", [])
fig_dir = pathlib.Path(out_dir) / "fig_svg"
for f in files:
    data = download(svc.files().get_media(fileId=f["id"]))
    (fig_dir / f["name"]).write_bytes(data)
    print(f"  fetched {f['name']:<32} ({len(data):,} bytes)")
print(f"  {len(files)} SVGs in {fig_dir}/")
PYEOF
fi

# 2. Sanitize the markdown export.
echo "→ Sanitizing markdown..."
python3 - "$BUILD" <<'PYEOF'
import re, sys, pathlib
build = pathlib.Path(sys.argv[1])
src, dst = build / "research_strategy.md", build / "research_strategy_clean.md"
if not src.exists():
    sys.exit(f"Missing {src}. Run with --fetch, or save the Drive export there.")
text = src.read_text()
SENTINEL = "\x01"
text = text.replace(r"\\", SENTINEL)
for ch in ["!","[","]","(",")","*","_","#",">","<"]:
    text = text.replace("\\" + ch, ch)
text = text.replace(SENTINEL, "\\")
# Drop inline base64 image refs (Doc-inserted reference images we don't want)
text = re.sub(r"^!\[\]\[image\d+\]\s*$\n?", "", text, flags=re.MULTILINE)
text = re.sub(r"^\[image\d+\]:\s*<?data:image/[^>\s]+>?\s*$\n?", "", text, flags=re.MULTILINE)
# Replace the Table 1 CSV "image" with a note (pandoc can't render CSV as image)
text = re.sub(
    r"!\[[^\]]*Table 1[^\]]*\]\(fig/barrier-pipeline\.csv\)(\{[^}]*\})?",
    "*[Table 1 — RSVP barrier pipeline (table source not yet inlined)]*",
    text,
)
dst.write_text(text)
print(f"  {dst.name} ({len(text):,} chars)")
PYEOF

# 3. Convert any new/changed SVGs to PNGs.
echo "→ Converting SVGs..."
shopt -s nullglob
converted=0
for svg in "$BUILD/fig_svg/"*.svg; do
  name=$(basename "$svg" .svg)
  png="$BUILD/fig/${name}.png"
  if [[ ! -f "$png" || "$svg" -nt "$png" ]]; then
    rsvg-convert -d 200 -p 200 "$svg" -o "$png"
    echo "  ${name}.svg → fig/${name}.png"
    ((converted++))
  fi
done
[[ $converted -eq 0 ]] && echo "  (all up to date)"

# 4. Render via markmeld.
echo "→ Rendering..."
( cd "$BUILD" && mm research_strategy ) >/dev/null

PDF="$ROOT/4_Research_Strategy.pdf"
if [[ -f "$PDF" ]]; then
  pages=$(mdls -name kMDItemNumberOfPages "$PDF" 2>/dev/null | awk -F'= ' '{print $2}')
  size=$(stat -f%z "$PDF")
  echo "✓ $PDF (${pages:-?} pages, $((size/1024)) KB)"
else
  echo "✗ Render failed; PDF not produced." >&2
  exit 1
fi
