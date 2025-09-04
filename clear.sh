#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/bundle}"

rm ${BUNDLE_DIR}/cubrid-jdbc-*-*.jar.*
rm ${BUNDLE_DIR}/cubrid-jdbc-*.jar.*
rm ${BUNDLE_DIR}/cubrid-jdbc-*.pom*
rm -rf ${BUNDLE_DIR}/stage/
rm cubrid-jdbc-*-release.zip
