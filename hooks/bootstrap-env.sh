#!/usr/bin/env bash
# bootstrap-env.sh — SessionStart hook: 環境情報を収集してキャッシュ + additionalContext に注入
# macOS (darwin) 前提。stdin から SessionStart hook の JSON を受け取る。
# Linux で使う場合は stat -f / md5 を GNU coreutils 版に置き換える必要あり。
set +e

JQ=$(command -v jq || echo "/opt/homebrew/bin/jq")
CACHE_DIR="$HOME/.claude/cache/bootstrap"
FORCE=false
MAX_AGE=86400  # 24 hours

# --force 引数チェック
for arg in "$@"; do
  [[ "$arg" == "--force" ]] && FORCE=true
done

# stdin から JSON を読み取り、cwd を抽出
INPUT=$(cat)
CWD=$(echo "$INPUT" | "$JQ" -r '.cwd // empty')
[[ -z "$CWD" ]] && exit 0

# cwd の md5 ハッシュをキーにする (macOS)
HASH=$(echo -n "$CWD" | md5)
CACHE_FILE="${CACHE_DIR}/${HASH}.md"
mkdir -p "$CACHE_DIR"

# additionalContext として stdout に JSON を吐く
emit_context() {
  local content="$1"
  [[ -z "$content" ]] && return 0
  "$JQ" -n --arg ctx "$content" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
}

# キャッシュ有効性チェック: トリガーファイルの mtime が CACHE_MTIME より新しければ無効
cache_valid() {
  local cache_mtime=$1
  local triggers=(
    "$CWD/package-lock.json"
    "$CWD/composer.lock"
    "$CWD/Pipfile.lock"
    "$CWD/yarn.lock"
    "$CWD/pnpm-lock.yaml"
    "$CWD/Gemfile.lock"
    "$CWD/go.sum"
    "$CWD/Cargo.lock"
    "$CWD/Dockerfile"
    "$CWD/docker-compose.yml"
    "$CWD/docker-compose.yaml"
    "$CWD/compose.yml"
    "$CWD/compose.yaml"
    "$CWD/.env.example"
  )
  for f in "${triggers[@]}"; do
    if [[ -f "$f" ]]; then
      local mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
      (( mt > cache_mtime )) && return 1
    fi
  done
  # Dockerfile.* (Dockerfile.dev, Dockerfile.prod 等)
  for f in "$CWD"/Dockerfile.*; do
    if [[ -f "$f" ]]; then
      local mt=$(stat -f %m "$f" 2>/dev/null || echo 0)
      (( mt > cache_mtime )) && return 1
    fi
  done
  return 0
}

# --- キャッシュヒット判定 ---
if [[ "$FORCE" == "false" && -f "$CACHE_FILE" ]]; then
  CACHE_MTIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$(( NOW - CACHE_MTIME ))
  if (( AGE < MAX_AGE )) && cache_valid "$CACHE_MTIME"; then
    emit_context "$(cat "$CACHE_FILE")"
    exit 0
  fi
fi

# --- プロジェクト名の取得 ---
PROJECT_NAME=$(basename "$CWD")
GENERATED=$(date "+%Y-%m-%d %H:%M:%S")

# --- 1. Languages ---
LANGS=""
HAS_DOCKER_ENV=false
COMPOSE_IMAGES=""
DOCKERFILE_IMAGES=""

for dockerfile in "$CWD"/Dockerfile "$CWD"/Dockerfile.*; do
  if [[ -f "$dockerfile" ]]; then
    HAS_DOCKER_ENV=true
    while IFS= read -r line; do
      image=$(echo "$line" | sed -E 's/^FROM[[:space:]]+//I; s/[[:space:]]+AS[[:space:]]+.*//I' | tr -d '[:space:]')
      [[ -z "$image" ]] && continue
      DOCKERFILE_IMAGES="${DOCKERFILE_IMAGES}${image}"$'\n'
      img_base="${image##*/}"
      name="${img_base%%:*}"
      if [[ "$img_base" == *:* ]]; then
        version="${img_base#*:}"
      else
        version=""
      fi
      [[ -n "$version" && "$version" != "latest" ]] && LANGS="${LANGS}"$'\n'"- ${name}: ${version} (Dockerfile)"
    done < <(grep -iE '^FROM ' "$dockerfile" 2>/dev/null)
  fi
done

COMPOSE_FILE=""
[[ -f "$CWD/docker-compose.yml" ]] && COMPOSE_FILE="$CWD/docker-compose.yml"
[[ -f "$CWD/compose.yml" ]] && COMPOSE_FILE="$CWD/compose.yml"
[[ -f "$CWD/docker-compose.yaml" ]] && COMPOSE_FILE="$CWD/docker-compose.yaml"
[[ -f "$CWD/compose.yaml" ]] && COMPOSE_FILE="$CWD/compose.yaml"

if [[ -n "$COMPOSE_FILE" ]]; then
  HAS_DOCKER_ENV=true
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    COMPOSE_IMAGES="${COMPOSE_IMAGES}${image}"$'\n'
    img_base="${image##*/}"
    name="${img_base%%:*}"
    if [[ "$img_base" == *:* ]]; then
      version="${img_base#*:}"
    else
      version=""
    fi
    [[ -n "$version" && "$version" != "latest" ]] && LANGS="${LANGS}"$'\n'"- ${name}: ${version} (compose)"
  done < <(grep -E '^[[:space:]]+image:' "$COMPOSE_FILE" 2>/dev/null | sed -E 's/^[[:space:]]+image:[[:space:]]*//' | tr -d '"'"'" 2>/dev/null)
fi

# 非Docker環境: ホストの言語バージョンをフォールバック
if [[ "$HAS_DOCKER_ENV" == "false" ]]; then
  if command -v node &>/dev/null; then
    LANGS="${LANGS}"$'\n'"- node: $(node --version 2>/dev/null) (host)"
  fi
  if command -v php &>/dev/null; then
    LANGS="${LANGS}"$'\n'"- php: $(php --version 2>/dev/null | head -1 | awk '{print $2}') (host)"
  fi
  if command -v python3 &>/dev/null; then
    LANGS="${LANGS}"$'\n'"- python3: $(python3 --version 2>/dev/null | awk '{print $2}') (host)"
  fi
  if command -v go &>/dev/null; then
    LANGS="${LANGS}"$'\n'"- go: $(go version 2>/dev/null | awk '{print $3}' | sed 's/go//') (host)"
  fi
  if command -v ruby &>/dev/null; then
    LANGS="${LANGS}"$'\n'"- ruby: $(ruby --version 2>/dev/null | awk '{print $2}') (host)"
  fi
fi

LANGS_SECTION=""
if [[ -n "$LANGS" ]]; then
  LANGS_SECTION="## Languages
$(echo "$LANGS" | grep -v '^$' | sort -u)
"
fi

# --- 2. Dependencies (top 10) ---
DEPS=""
if [[ -f "$CWD/package.json" ]]; then
  PKG_DEPS=$("$JQ" -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries | .[0:10] | .[] | "- " + .key + ": " + .value' "$CWD/package.json" 2>/dev/null)
  [[ -n "$PKG_DEPS" ]] && DEPS="${DEPS}${PKG_DEPS}"$'\n'
fi
if [[ -f "$CWD/composer.json" ]]; then
  COMP_DEPS=$("$JQ" -r '(.require // {}) | to_entries | .[0:10] | .[] | "- " + .key + ": " + .value' "$CWD/composer.json" 2>/dev/null)
  [[ -n "$COMP_DEPS" ]] && DEPS="${DEPS}${COMP_DEPS}"$'\n'
fi
DEPS_SECTION=""
if [[ -n "$DEPS" ]]; then
  DEPS_SECTION="## Dependencies (top 10)
${DEPS}"
fi

# --- 3. Docker Services ---
DOCKER_SECTION=""
if [[ -n "$COMPOSE_FILE" ]]; then
  if command -v yq &>/dev/null; then
    SERVICES=$(yq -r '.services | keys | .[]' "$COMPOSE_FILE" 2>/dev/null | paste -sd', ' -)
  else
    SERVICES=$(grep -E '^  [a-zA-Z_-]+:' "$COMPOSE_FILE" 2>/dev/null | sed 's/://;s/^ *//' | paste -sd', ' -)
  fi
  if [[ -n "$SERVICES" ]]; then
    DOCKER_SECTION="## Docker Services
- ${SERVICES}
"
  fi
fi

# --- 4. Directory Structure (depth 2) ---
DIR_TREE=$(cd "$CWD" && find . -maxdepth 2 -type d -not -path '*/\.*' -not -path '*/node_modules/*' -not -path '*/vendor/*' 2>/dev/null | sort | head -30)
DIR_SECTION=""
if [[ -n "$DIR_TREE" ]]; then
  DIR_SECTION="## Directory Structure (depth 2)
${DIR_TREE}
"
fi

# --- 5. Makefile Targets ---
MAKE_SECTION=""
if [[ -f "$CWD/Makefile" ]]; then
  TARGETS=$(grep -E '^[a-zA-Z_-]+:' "$CWD/Makefile" 2>/dev/null | sed 's/:.*//' | head -20 | paste -sd', ' -)
  if [[ -n "$TARGETS" ]]; then
    MAKE_SECTION="## Makefile Targets
- ${TARGETS}
"
  fi
fi

# --- 6. Environment Keys (.env.example) ---
ENV_SECTION=""
if [[ -f "$CWD/.env.example" ]]; then
  ENV_KEYS=$(grep -E '^[A-Z_]+=' "$CWD/.env.example" 2>/dev/null | cut -d= -f1 | head -30 | paste -sd', ' -)
  if [[ -n "$ENV_KEYS" ]]; then
    ENV_SECTION="## Environment Keys (.env.example)
- ${ENV_KEYS}
"
  fi
fi

# --- 7. Test Framework ---
TEST_FW=""
if [[ -f "$CWD/package.json" ]]; then
  if "$JQ" -e '.devDependencies.jest // .dependencies.jest' "$CWD/package.json" &>/dev/null; then
    TEST_FW="${TEST_FW}"$'\n'"- Jest"
  fi
  if "$JQ" -e '.devDependencies.vitest // .dependencies.vitest' "$CWD/package.json" &>/dev/null; then
    TEST_FW="${TEST_FW}"$'\n'"- Vitest"
  fi
fi
[[ -f "$CWD/phpunit.xml" || -f "$CWD/phpunit.xml.dist" ]] && TEST_FW="${TEST_FW}"$'\n'"- PHPUnit"
[[ -f "$CWD/pytest.ini" || -f "$CWD/pyproject.toml" ]] && TEST_FW="${TEST_FW}"$'\n'"- pytest"
TEST_SECTION=""
if [[ -n "$TEST_FW" ]]; then
  TEST_SECTION="## Test Framework
$(echo "$TEST_FW" | grep -v '^$')
"
fi

# --- 8. CI/CD ---
CI_SECTION=""
if [[ -d "$CWD/.github/workflows" ]]; then
  CI_FILES=$(ls "$CWD/.github/workflows/"*.yml 2>/dev/null | xargs -I{} basename {} | paste -sd', ' -)
  [[ -z "$CI_FILES" ]] && CI_FILES=$(ls "$CWD/.github/workflows/"*.yaml 2>/dev/null | xargs -I{} basename {} | paste -sd', ' -)
  if [[ -n "$CI_FILES" ]]; then
    CI_SECTION="## CI/CD
- GitHub Actions: ${CI_FILES}
"
  fi
fi

# --- 9. Summary (Claude が最初に読む結論セクション) ---
SUMMARY_DB=""
SUMMARY_FRAMEWORK=""
SUMMARY_LANG=""
SUMMARY_TEST=""

# DB: SQL/NoSQL DB のみ（Redis 等のキャッシュは除外）
parse_image() {
  # usage: parse_image "$img" → sets PARSED_NAME, PARSED_VERSION
  local img="$1"
  local base="${img##*/}"
  PARSED_NAME="${base%%:*}"
  if [[ "$base" == *:* ]]; then
    PARSED_VERSION="${base#*:}"
  else
    PARSED_VERSION=""
  fi
}

if [[ -n "$COMPOSE_IMAGES" ]]; then
  DB_ENTRIES=""
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    parse_image "$img"
    if echo "$PARSED_NAME" | grep -qiE '^(postgres|postgresql|mysql|mariadb|mongo|mongodb|oracle|mssql|cockroachdb|sqlserver)'; then
      entry="${PARSED_NAME}${PARSED_VERSION:+ ${PARSED_VERSION}}"
      if ! echo "$DB_ENTRIES" | grep -qxF "$entry"; then
        DB_ENTRIES="${DB_ENTRIES}${entry}"$'\n'
      fi
    fi
  done <<< "$COMPOSE_IMAGES"
  SUMMARY_DB=$(echo "$DB_ENTRIES" | grep -v '^$' | paste -sd', ' -)
fi

# Framework: composer.json / package.json から検出
if [[ -f "$CWD/composer.json" ]]; then
  "$JQ" -e '.require["laravel/framework"]' "$CWD/composer.json" &>/dev/null && SUMMARY_FRAMEWORK="Laravel"
  [[ -z "$SUMMARY_FRAMEWORK" ]] && "$JQ" -e '.require["symfony/framework-bundle"]' "$CWD/composer.json" &>/dev/null && SUMMARY_FRAMEWORK="Symfony"
fi
if [[ -f "$CWD/package.json" ]]; then
  fw_extra=""
  "$JQ" -e '.dependencies.next // .devDependencies.next' "$CWD/package.json" &>/dev/null && fw_extra="Next.js"
  [[ -z "$fw_extra" ]] && "$JQ" -e '.dependencies["@nestjs/core"] // .devDependencies["@nestjs/core"]' "$CWD/package.json" &>/dev/null && fw_extra="NestJS"
  [[ -z "$fw_extra" ]] && "$JQ" -e '.dependencies.nuxt // .devDependencies.nuxt' "$CWD/package.json" &>/dev/null && fw_extra="Nuxt"
  [[ -z "$fw_extra" ]] && "$JQ" -e '.dependencies.react // .devDependencies.react' "$CWD/package.json" &>/dev/null && fw_extra="React"
  if [[ -n "$fw_extra" ]]; then
    SUMMARY_FRAMEWORK="${SUMMARY_FRAMEWORK:+${SUMMARY_FRAMEWORK} + }${fw_extra}"
  fi
fi

# Primary Language: Dockerfile FROM を優先、なければ compose の言語系 image
PRIMARY_LANG_ENTRIES=""
collect_primary_lang() {
  local source_images="$1"
  [[ -z "$source_images" ]] && return 0
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    parse_image "$img"
    if echo "$PARSED_NAME" | grep -qiE '^(php|node|python|ruby|golang|openjdk|rust)'; then
      local entry="${PARSED_NAME}${PARSED_VERSION:+ ${PARSED_VERSION}}"
      if ! echo "$PRIMARY_LANG_ENTRIES" | grep -qxF "$entry"; then
        PRIMARY_LANG_ENTRIES="${PRIMARY_LANG_ENTRIES}${entry}"$'\n'
      fi
    fi
  done <<< "$source_images"
}

collect_primary_lang "$DOCKERFILE_IMAGES"
[[ -z "$PRIMARY_LANG_ENTRIES" ]] && collect_primary_lang "$COMPOSE_IMAGES"
SUMMARY_LANG=$(echo "$PRIMARY_LANG_ENTRIES" | grep -v '^$' | paste -sd', ' -)

# Test
SUMMARY_TEST=$(echo "$TEST_FW" | grep -v '^$' | sed 's/^- //' | paste -sd', ' -)

SUMMARY_SECTION=""
if [[ -n "$SUMMARY_DB" || -n "$SUMMARY_FRAMEWORK" || -n "$SUMMARY_LANG" || -n "$SUMMARY_TEST" ]]; then
  SUMMARY_SECTION="## Summary"
  [[ -n "$SUMMARY_DB" ]] && SUMMARY_SECTION="${SUMMARY_SECTION}
- **DB**: ${SUMMARY_DB}"
  [[ -n "$SUMMARY_LANG" ]] && SUMMARY_SECTION="${SUMMARY_SECTION}
- **Primary Language**: ${SUMMARY_LANG}"
  [[ -n "$SUMMARY_FRAMEWORK" ]] && SUMMARY_SECTION="${SUMMARY_SECTION}
- **Framework**: ${SUMMARY_FRAMEWORK}"
  [[ -n "$SUMMARY_TEST" ]] && SUMMARY_SECTION="${SUMMARY_SECTION}
- **Test**: ${SUMMARY_TEST}"
  SUMMARY_SECTION="${SUMMARY_SECTION}
"
fi

# --- 最終アセンブル (Summary を冒頭に配置) ---
OUTPUT="# Environment Bootstrap: ${PROJECT_NAME}
Generated: ${GENERATED}
"
[[ -n "$SUMMARY_SECTION" ]] && OUTPUT="${OUTPUT}
${SUMMARY_SECTION}"
[[ -n "$LANGS_SECTION" ]] && OUTPUT="${OUTPUT}
${LANGS_SECTION}"
[[ -n "$DEPS_SECTION" ]] && OUTPUT="${OUTPUT}
${DEPS_SECTION}"
[[ -n "$DOCKER_SECTION" ]] && OUTPUT="${OUTPUT}
${DOCKER_SECTION}"
[[ -n "$DIR_SECTION" ]] && OUTPUT="${OUTPUT}
${DIR_SECTION}"
[[ -n "$MAKE_SECTION" ]] && OUTPUT="${OUTPUT}
${MAKE_SECTION}"
[[ -n "$ENV_SECTION" ]] && OUTPUT="${OUTPUT}
${ENV_SECTION}"
[[ -n "$TEST_SECTION" ]] && OUTPUT="${OUTPUT}
${TEST_SECTION}"
[[ -n "$CI_SECTION" ]] && OUTPUT="${OUTPUT}
${CI_SECTION}"

# キャッシュに書き込み + additionalContext に注入
echo "$OUTPUT" > "$CACHE_FILE"
emit_context "$OUTPUT"
