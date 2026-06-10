#!/data/data/com.termux/files/usr/bin/bash

set -e

ROOT_DIR="$HOME/projects"
LOG_DIR="$ROOT_DIR/logs"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$LOG_DIR/master-build-$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

run_build() {
  NAME="$1"
  PROJECT_PATH="$2"
  BUILD_COMMAND="$3"

  log "STARTING: $NAME"

  if [ ! -d "$PROJECT_PATH" ]; then
    log "SKIPPED: $NAME (missing folder: $PROJECT_PATH)"
    return
  fi

  cd "$PROJECT_PATH"

  if eval "$BUILD_COMMAND" >> "$LOG_FILE" 2>&1; then
    log "SUCCESS: $NAME"
  else
    log
cat > ~/master-build.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

set -e

ROOT_DIR="$HOME/projects"
LOG_DIR="$ROOT_DIR/logs"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$LOG_DIR/master-build-$TIMESTAMP.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

run_build() {
  NAME="$1"
  PROJECT_PATH="$2"
  BUILD_COMMAND="$3"

  log "STARTING: $NAME"

  if [ ! -d "$PROJECT_PATH" ]; then
    log "SKIPPED: $NAME (missing folder: $PROJECT_PATH)"
    return
  fi

  cd "$PROJECT_PATH"

  if eval "$BUILD_COMMAND" >> "$LOG_FILE" 2>&1; then
    log "SUCCESS: $NAME"
  else
    log "FAILED: $NAME"
  fi

  cd "$ROOT_DIR"
}

log "=============================="
log "MASTER BUILD STARTED"
log "=============================="

run_build "Core API" \
  "$HOME/projects/core-api" \
  "git pull && npm install && npm run build"

run_build "Frontend App" \
  "$HOME/projects/frontend" \
  "git pull && npm install && npm run build"

run_build "Python Services" \
  "$HOME/projects/python-services" \
  "git pull && pip install -r requirements.txt"

log "=============================="
log "MASTER BUILD COMPLETE"
log "Saved: $LOG_FILE"
log "=============================="

