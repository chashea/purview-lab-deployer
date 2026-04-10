#!/bin/bash
# Post-tool-use hook: auto-lint .psm1 files after edits
set -e
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType')

# Only run after successful edit/create operations
if [ "$RESULT_TYPE" != "success" ]; then
  exit 0
fi
if [ "$TOOL_NAME" != "edit" ] && [ "$TOOL_NAME" != "create" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.toolArgs' | jq -r '.path // empty')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only lint PowerShell module files
if echo "$FILE_PATH" | grep -qE '\.psm1$|\.ps1$'; then
  if command -v pwsh &>/dev/null; then
    pwsh -NoProfile -Command "
      if (Get-Module -ListAvailable PSScriptAnalyzer) {
        \$results = Invoke-ScriptAnalyzer -Path '$FILE_PATH' -Severity Warning -ExcludeRule PSAvoidUsingWriteHost,PSUseSingularNouns
        if (\$results) {
          Write-Host '⚠ PSScriptAnalyzer found issues in $FILE_PATH:' -ForegroundColor Yellow
          \$results | ForEach-Object { Write-Host \"  Line \$(\$_.Line): \$(\$_.Message)\" -ForegroundColor Yellow }
        }
      }
    " 2>/dev/null || true
  fi
fi
