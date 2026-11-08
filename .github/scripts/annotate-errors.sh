#!/usr/bin/env bash
# Превращает ошибки компилятора Swift и упавшие XCTest из лога в аннотации GitHub
# (видны на странице запуска без открытия логов). Использование: annotate-errors.sh <log>
set -u
log="${1:?log file}"
[ -f "$log" ] || { echo "::error::Лог $log не найден"; exit 0; }

# Формат: /path/File.swift:12:5: error: message   или   /path/File.swift:12: error: -[Tests test] : message
pattern='^/[^:]+:[0-9]+(:[0-9]+)?: (fatal )?error: '
count=$(grep -E "$pattern" "$log" | sort -u | wc -l | tr -d ' ')
echo "Найдено ошибок: $count"

grep -E "$pattern" "$log" | sort -u | head -50 | while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  message="${line#*error: }"
  relative="${file#"${GITHUB_WORKSPACE:-}"/}"
  short="$(basename "$file")"
  # Текст ошибки дублируем в заголовок, чтобы он был виден в сводке Annotations.
  echo "::error file=${relative},line=${lineno},title=${short}:${lineno}::${message}"
done

# Ошибки без пути (линковка, xcodegen, схема).
grep -E "^(error|xcodebuild: error|ld: |clang: error|❌)" "$log" | sort -u | head -10 | while IFS= read -r line; do
  echo "::error title=build::${line}"
done

# Полный список — в лог шага.
echo "----- все ошибки -----"
grep -E "$pattern|^error|xcodebuild: error|ld: " "$log" | sort -u | head -200 || true
exit 0
