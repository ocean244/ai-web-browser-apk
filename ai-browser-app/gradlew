#!/usr/bin/env sh
set -eu
APP_HOME=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
JAR="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"
if [ ! -f "$JAR" ]; then
  URL=$(sed -n 's/^distributionUrl=//p' "$APP_HOME/gradle/wrapper/gradle-wrapper.properties" | sed 's/\\//g')
  TMP_ZIP=$(mktemp)
  TMP_DIR=$(mktemp -d)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$TMP_ZIP"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP_ZIP" "$URL"
  else
    echo "Missing curl/wget" >&2
    exit 1
  fi
  unzip -oq "$TMP_ZIP" -d "$TMP_DIR"
  DIST_JAR=$(find "$TMP_DIR" -name "gradle-launcher-*.jar" | head -n 1)
  if [ -z "$DIST_JAR" ]; then
    echo "gradle-launcher jar not found" >&2
    exit 1
  fi
  cp "$DIST_JAR" "$JAR"
  rm -rf "$TMP_ZIP" "$TMP_DIR"
fi
exec java ${ORG_GRADLE_JVMARGS:-"-Xmx4g"} -cp "$JAR" org.gradle.wrapper.GradleWrapperMain "$@"
