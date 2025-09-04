#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# CUBRID JDBC - Prepare Maven Central bundle from prebuilt artifacts (no build)
#   - Use JAR/POM in the working directory (default: ./bundle)
#   - Use release.pom in the working directory
#   - When making placeholders, include README.md in the working directory
#
# Usage:
#   ./jdbc-bundle.sh -f <GPG_FINGERPRINT> -s <SIGN_PASSPHRASE> [-v <VERSION>] [--make-empty-docs]
#     If -v is omitted: try VERSION-DIST → infer from file name (cubrid-jdbc-<ver>*.jar)
#
# Output:
#   ./cubrid-jdbc-<version>-release.zip   # created in repo root by default
# -----------------------------------------------------------------------------

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/bundle}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR}"

GROUP_ID="org.cubrid"
ARTIFACT_ID="cubrid-jdbc"

GPG_FINGERPRINT="${GPG_FINGERPRINT:-}"
SIGN_PASSPHRASE="${SIGN_PASSPHRASE:-}"
VERSION="${VERSION:-}"
MAKE_EMPTY_DOCS=false

PINENTRY_OPTS=()

log()  { printf '[%s] %s\n' "$1" "$2"; }
info() { log INFO "$*"; }
warn() { log WARN "$*"; }
err()  { log ERROR "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $0 -f <fingerprint> -s <sign_passphrase> [-v <version>] [--make-empty-docs] [-h]

Options:
  -f, --fingerprint     GPG key fingerprint  (env: GPG_FINGERPRINT)
  -s, --sign            GPG signing passphrase (env: SIGN_PASSPHRASE)
  -v, --version         Version (fallback: VERSION-DIST or infer from JAR names)
      --make-empty-docs Create placeholder sources/javadoc JARs if missing (requires README.md in ./bundle)
  -h, --help            Show help

Env overrides:
  WORK_DIR   Working directory with jars/pom/README.md  (default: ./bundle)
  OUT_DIR    Output directory for the final zip         (default: repo root)
EOF
}

parse_cli() {
  local argv=()
  while (($#)); do
    case "$1" in
      --fingerprint)        argv+=(-f "$2"); shift 2 ;;
      --fingerprint=*)      argv+=(-f "${1#*=}"); shift ;;
      --sign)               argv+=(-s "$2"); shift 2 ;;
      --sign=*)             argv+=(-s "${1#*=}"); shift ;;
      --version)            argv+=(-v "$2"); shift 2 ;;
      --version=*)          argv+=(-v "${1#*=}"); shift ;;
      --make-empty-docs)    argv+=(--make-empty-docs); shift ;;
      -f|-s|-v)             argv+=("$1" "$2"); shift 2 ;;
      -h|--help)            argv+=(-h); shift ;;
      *)                    argv+=("$1"); shift ;;
    esac
  done

  if ((${#argv[@]})); then set -- "${argv[@]}"; else set --; fi

  while (($#)); do
    case "$1" in
      -f) GPG_FINGERPRINT="$2"; shift 2 ;;
      -s) SIGN_PASSPHRASE="$2"; shift 2 ;;
      -v) VERSION="$2"; shift 2 ;;
      --make-empty-docs) MAKE_EMPTY_DOCS=true; shift ;;
      -h) usage; exit 0 ;;
      *) usage; exit 1 ;;
    esac
  done
}

check_prereqs() {
  [[ -n "$GPG_FINGERPRINT" ]] || { err "GPG fingerprint missing."; exit 1; }
  [[ -n "$SIGN_PASSPHRASE" ]] || { err "GPG passphrase missing."; exit 1; }
  gpg --batch --list-secret-keys "$GPG_FINGERPRINT" &>/dev/null \
    || { err "GPG secret key not found: $GPG_FINGERPRINT"; exit 1; }

  for c in zip md5sum sha1sum sha256sum sha512sum awk sed; do
    have "$c" || { err "Missing command: $c"; exit 1; }
  done
  $MAKE_EMPTY_DOCS && have jar || true
}

setup_pinentry() {
  local v major minor
  v=$(gpg --version | head -n1 | awk '{print $3}')
  major=${v%%.*}; minor=${v#*.}; minor=${minor%%.*}
  (( major > 2 || (major == 2 && minor >= 1) )) \
    && PINENTRY_OPTS=(--pinentry-mode loopback) || PINENTRY_OPTS=()
}

infer_version() {
  [[ -n "$VERSION" ]] && return 0
  if [[ -f "${WORK_DIR}/VERSION-DIST" ]]; then
    VERSION=$(< "${WORK_DIR}/VERSION-DIST")
    info "Version (VERSION-DIST): ${VERSION}"
    return 0
  fi

  shopt -s nullglob
  local f base rest
  local candidates=( "${WORK_DIR}/${ARTIFACT_ID}-"*.jar )
  for f in "${candidates[@]}"; do
    base="${f##*/}"
    [[ "$base" == *-sources.jar || "$base" == *-javadoc.jar ]] && continue
    rest="${base#${ARTIFACT_ID}-}"
    rest="${rest%.jar}"
    VERSION="$rest"
    info "Version (from jar name): ${VERSION}"
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  err "Cannot detect version. Provide -v or VERSION-DIST."
  exit 1
}

ensure_release_pom() {
  [[ -f "${WORK_DIR}/release.pom" ]] || { err "release.pom not found in WORK_DIR: $WORK_DIR"; exit 1; }
  cp "${WORK_DIR}/release.pom" "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom"
  sed -i.back \
    -e "1,/<version>/{s#<version>[^<]*</version>#<version>${VERSION}</version>#;}" \
    "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom"
  rm -f "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.back"
  info "POM ready: ${ARTIFACT_ID}-${VERSION}.pom"
}

ensure_docs_jars() {
  $MAKE_EMPTY_DOCS || return 0

  local src="${WORK_DIR}/${ARTIFACT_ID}-${VERSION}-sources.jar"
  local jdk="${WORK_DIR}/${ARTIFACT_ID}-${VERSION}-javadoc.jar"
  local readme="${WORK_DIR}/README.md"

  if [[ -f "$src" && -f "$jdk" ]]; then
    warn "Placeholders requested but sources/javadoc JARs already exist. Skip creation."
    return 0
  fi

  if [[ ! -f "$readme" ]]; then
    err "README.md not found in WORK_DIR ($WORK_DIR). Cannot create placeholder sources/javadoc JARs."
    exit 1
  fi

  info "Create placeholder sources/javadoc JARs with README.md (from ./bundle)."
  if [[ -f "$src" ]]; then
    warn "Skip sources placeholder: already exists ($(basename "$src"))."
  else
    jar cf "$src" -C "$WORK_DIR" README.md
  fi
  if [[ -f "$jdk" ]]; then
    warn "Skip javadoc placeholder: already exists ($(basename "$jdk"))."
  else
    jar cf "$jdk" -C "$WORK_DIR" README.md
  fi
}

sign_and_checksum() {
  info "Signing and generating checksums..."
  local gpg_opts=(--batch --yes --local-user "$GPG_FINGERPRINT" --passphrase "$SIGN_PASSPHRASE")
  ((${#PINENTRY_OPTS[@]})) && gpg_opts+=("${PINENTRY_OPTS[@]}")

  shopt -s nullglob
  local files=( "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.jar
                "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom" )
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { err "No artifacts found in WORK_DIR: $WORK_DIR"; exit 1; }

  for f in "${files[@]}"; do
    info "  - sign $(basename "$f")"
    gpg "${gpg_opts[@]}" --armor --detach-sign --output "${f}.asc" "$f"

    info "  - checksums $(basename "$f")"
    md5sum    "$f" | awk '{print $1}' > "${f}.md5"
    sha1sum   "$f" | awk '{print $1}' > "${f}.sha1"
    sha256sum "$f" | awk '{print $1}' > "${f}.sha256"
    sha512sum "$f" | awk '{print $1}' > "${f}.sha512"
  done
}

create_bundle() {
  local group_path; group_path=$(printf '%s' "$GROUP_ID" | tr '.' '/')
  local topdir="${group_path%%/*}"   # "org"
  local stage="${WORK_DIR}/stage/${group_path}/${ARTIFACT_ID}/${VERSION}"
  local zip="${OUT_DIR}/${ARTIFACT_ID}-${VERSION}-release.zip"

  rm -rf "${WORK_DIR}/stage"
  mkdir -p "$stage"

  shopt -s nullglob
  local jars=( "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.jar
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.asc
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.md5
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.sha1
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.sha256
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}"*.sha512 )
  local poms=( "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom"
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.asc"
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.md5"
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.sha1"
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.sha256"
               "${WORK_DIR}/${ARTIFACT_ID}-${VERSION}.pom.sha512" )
  shopt -u nullglob

  [[ ${#jars[@]} -gt 0 ]] || { err "No JAR files in WORK_DIR."; exit 1; }
  [[ ${#poms[@]} -gt 0 ]] || { err "No POM/signature files in WORK_DIR."; exit 1; }

  cp "${jars[@]}" "${stage}/"
  cp "${poms[@]}" "${stage}/"

  ( cd "${WORK_DIR}/stage" && [[ -d "$topdir" ]] && zip -qr "${zip}" "$topdir" ) \
    && log OK "Release ZIP ready: ${zip}" \
    || { err "ZIP creation failed: ${zip}"; exit 1; }
}

##### Main #####
parse_cli "$@"
check_prereqs
setup_pinentry
infer_version
ensure_release_pom
ensure_docs_jars
sign_and_checksum
create_bundle
