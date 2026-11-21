#!/usr/bin/env bash
#
# zip_flutter_project.sh
# Packages a Flutter project into ./project-context.zip (in the directory you
# run the script from) so it can be uploaded to Claude. Build output, caches
# and common secret files are excluded. Any existing project-context.zip is
# replaced. If CLAUDE.md exists in the current directory, it is added too.
#
# Usage:
#   ./zip_flutter_project.sh [project_dir] [options]
#
# project_dir defaults to the current directory.
#
# Options:
#   --with-platforms   Also include android/ ios/ web/ linux/ macos/ windows/
#                      (build folders and caches are still excluded)
#   --no-assets        Skip the assets/ and fonts/ folders
#   -h, --help         Show this help

set -euo pipefail

OUTPUT_NAME="project-context.zip"
START_DIR="$(pwd)"
OUTPUT="$START_DIR/$OUTPUT_NAME"

PROJECT_DIR="."
WITH_PLATFORMS=false
WITH_ASSETS=true

# ---- parse args -------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --with-platforms) WITH_PLATFORMS=true ;;
    --no-assets)      WITH_ASSETS=false ;;
    -h|--help)
      sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *)  PROJECT_DIR="$arg" ;;
  esac
done

# ---- sanity checks ----------------------------------------------------------
command -v zip >/dev/null 2>&1 || { echo "Error: 'zip' is not installed." >&2; exit 1; }

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
if [[ ! -f "$PROJECT_DIR/pubspec.yaml" ]]; then
  echo "Error: no pubspec.yaml in $PROJECT_DIR - is this a Flutter project root?" >&2
  exit 1
fi

# ---- find CLAUDE.md in the current directory (any common casing) ------------
CLAUDE_MD=""
for name in CLAUDE.md Claude.md claude.md; do
  if [[ -f "$START_DIR/$name" ]]; then
    CLAUDE_MD="$START_DIR/$name"
    break
  fi
done

# ---- replace any previous zip ----------------------------------------------
if [[ -f "$OUTPUT" ]]; then
  rm -f "$OUTPUT"
  echo "Replaced previous $OUTPUT_NAME"
fi

# ---- what to include --------------------------------------------------------
INCLUDE=(
  lib
  test
  integration_test
  pubspec.yaml
  pubspec.lock
  analysis_options.yaml
  l10n.yaml
  build.yaml
  .metadata
  README.md
)

$WITH_ASSETS && INCLUDE+=(assets fonts)
$WITH_PLATFORMS && INCLUDE+=(android ios web linux macos windows)

cd "$PROJECT_DIR"

EXISTING=()
for item in "${INCLUDE[@]}"; do
  [[ -e "$item" ]] && EXISTING+=("$item")
done

# CLAUDE.md inside the project dir is already covered below if it is the same file
if [[ -z "$CLAUDE_MD" ]]; then
  for name in CLAUDE.md Claude.md claude.md; do
    if [[ -f "$PROJECT_DIR/$name" ]]; then
      CLAUDE_MD="$PROJECT_DIR/$name"
      break
    fi
  done
fi

# ---- what to exclude (build output, caches, secrets) ------------------------
EXCLUDE=(
  "*/build/*"
  "*/.dart_tool/*"
  "*/.gradle/*"
  "*/Pods/*"
  "*/.idea/*"
  "*/DerivedData/*"
  "*.iml"
  "*.DS_Store"
  "*.class"
  "*.apk"
  "*.aab"
  "*.ipa"
  # secrets - do NOT share these
  "*.jks"
  "*.keystore"
  "*key.properties"
  "*local.properties"
  "*google-services.json"
  "*GoogleService-Info.plist"
  "*.env"
  "*.env.*"
)

# ---- zip --------------------------------------------------------------------
zip -r -q "$OUTPUT" "${EXISTING[@]}" -x "${EXCLUDE[@]}"

# add CLAUDE.md at the zip root (-j drops its directory path)
if [[ -n "$CLAUDE_MD" ]]; then
  zip -j -q "$OUTPUT" "$CLAUDE_MD"
  echo "Included: $(basename "$CLAUDE_MD")"
else
  echo "No CLAUDE.md found - skipped"
fi

echo "Created: $OUTPUT"
echo "Size:    $(du -h "$OUTPUT" | cut -f1)"
echo "Files:   $(unzip -Z1 "$OUTPUT" | grep -vc '/$')"
echo "Tip: run 'unzip -l $OUTPUT_NAME | less' to double-check before sharing."