#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# Config
# ----------------------------------------
RMD_FILE="baseline_tabulations.Rmd"
FREEZE_DATE="${1:-}"                          # arg 1: freeze date (e.g. 20251231), optional
RUN_DATE="${2:-$(date +%F)}"                  # arg 2: run date, defaults to today

# Standard report filename
OUTFILE="baseline_tabulations${RUN_DATE}.html"

# Freeze report filename (only used if FREEZE_DATE is provided)
if [[ -n "$FREEZE_DATE" ]]; then
  OUTFILE_FREEZE="baseline_tabulations${RUN_DATE}_freeze_date_${FREEZE_DATE}.html"
fi

LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/baseline_tabulations_${RUN_DATE}.log"

trap 'echo "[FAILED] baseline_tabulations run failed (see ${LOG})"' ERR

FOLDER_ID="1ag27R24lZm-t-IYSc4VI_mWzxB2bLhQp"
GDRIVE_BIN="/usr/local/bin/gdrive"
GDRIVE_CONFIG="/home/ec2-user/.gdrive"
SERVICE_JSON="gdrive_client.json"

# ----------------------------------------
# Helper: upload a file to Google Drive
# ----------------------------------------
upload_to_gdrive() {
  local file="$1"
  echo "[*] Uploading ${file} to Google Drive folder ${FOLDER_ID}" | tee -a "$LOG"
  local upload_id
  upload_id="$("$GDRIVE_BIN" --config "$GDRIVE_CONFIG" --service-account "$SERVICE_JSON" \
    upload --parent "$FOLDER_ID" "$file" 2>>"$LOG" | awk '/Uploaded/ {print $2}')"

  if [[ -n "${upload_id:-}" ]] && "$GDRIVE_BIN" --config "$GDRIVE_CONFIG" --service-account "$SERVICE_JSON" \
    info "$upload_id" >>"$LOG" 2>&1
  then
    echo "[$(date -Is)] Verified on Drive (id=${upload_id}); removing local file ${file}" | tee -a "$LOG"
    rm -f "$file"
  else
    echo "[$(date -Is)] ERROR: Could not verify upload of ${file} on Drive; keeping local copy" | tee -a "$LOG"
    exit 1
  fi
}

# ----------------------------------------
# Render standard report (no freeze date)
# ----------------------------------------
echo "[*] Rendering standard report: ${OUTFILE}"
Rscript -e "options(repos=c(CRAN='https://cloud.r-project.org')); \
  rmarkdown::render('${RMD_FILE}', output_format='html_document', output_file='${OUTFILE}')" \
  >>"$LOG" 2>&1
echo "[OK] Render complete: ${OUTFILE}"

upload_to_gdrive "$OUTFILE"

# ----------------------------------------
# Render freeze report (only if FREEZE_DATE supplied)
# ----------------------------------------
if [[ -n "$FREEZE_DATE" ]]; then
  echo "[*] Rendering freeze report: ${OUTFILE_FREEZE}"
  Rscript -e "options(repos=c(CRAN='https://cloud.r-project.org')); \
    rmarkdown::render('${RMD_FILE}', output_format='html_document', output_file='${OUTFILE_FREEZE}', \
    params=list(), \
    knit_root_dir=getwd())" \
    --args "${FREEZE_DATE}" \
    >>"$LOG" 2>&1
  echo "[OK] Render complete: ${OUTFILE_FREEZE}"

  upload_to_gdrive "$OUTFILE_FREEZE"
fi

echo "[$(date -Is)] All done." | tee -a "$LOG"
