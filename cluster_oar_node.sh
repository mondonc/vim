#!/bin/bash
# =============================================================================
# cluster_oar_node.sh — Tourne SUR le nœud OAR (soumis par cluster_oar.lua)
#
# Modèles fixes (adaptés à 2x RTX A5000, 48 GB total) :
#   Chat  : qwen2.5-coder:32b   (~19 GB Q4_K_M)
#   Embed : mxbai-embed-large   (670 MB)
#
# NE PAS MODIFIER les noms de modèles ici sans les mettre à jour
# dans cluster_oar.lua (constantes CHAT_MODEL / EMBED_MODEL).
# =============================================================================
set -euo pipefail

CHAT_MODEL="qwen2.5-coder:32b"
EMBED_MODEL="mxbai-embed-large"

OLLAMA_BIN="$HOME/bin/ollama"
OLLAMA_LIB="$HOME/lib/ollama"         # libs CUDA bundled avec le tgz ollama
SCRATCH="$HOME/scratch/$(whoami)/ollama"
LOG="$SCRATCH/logs/ollama.log"

mkdir -p "$HOME/bin" "$HOME/lib" "$SCRATCH/models" "$SCRATCH/logs"

export OLLAMA_MODELS="$SCRATCH/models"
export PATH="$PATH:$HOME/bin"
# Librairies CUDA/ROCm bundled extraites depuis le tgz ollama
export LD_LIBRARY_PATH="$OLLAMA_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# --- Infos nœud --------------------------------------------------------------
echo "[$(date -Iseconds)] =========================================="
echo "[$(date -Iseconds)] Nœud      : $(hostname -f)"
echo "[$(date -Iseconds)] OAR Job   : ${OAR_JOB_ID:-?}"
echo "[$(date -Iseconds)] OLLAMA_MODELS : $OLLAMA_MODELS"

# --- GPU ---------------------------------------------------------------------
echo "[$(date -Iseconds)] GPUs disponibles :"
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null \
    | awk '{printf "              [%s]\n", $0}' \
    || echo "              (nvidia-smi indisponible)"

# --- Installer ollama si absent ----------------------------------------------
if [ ! -x "$OLLAMA_BIN" ]; then
    echo "[$(date -Iseconds)] Téléchargement d'ollama (tgz officiel)…"

    # Détection de l'architecture (amd64 sur les nœuds Abaca, arm64 sinon)
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)  OLLAMA_ARCH="amd64" ;;
        aarch64) OLLAMA_ARCH="arm64" ;;
        *)
            echo "[$(date -Iseconds)] ERREUR : architecture non supportée : $ARCH"
            exit 1
            ;;
    esac

    #   $HOME/bin/ollama        ← binaire
    #   $HOME/lib/ollama/       ← libs CUDA/ROCm bundled
    curl -fsSL "https://ollama.com/download/ollama-linux-${OLLAMA_ARCH}.tar.zst" | tar -x --zstd -C "$HOME"

    chmod +x "$OLLAMA_BIN"
    echo "[$(date -Iseconds)] ✓ Ollama installé : $("$OLLAMA_BIN" --version 2>/dev/null || echo '(version inconnue)')"
fi

# --- Lancer ollama serve (utilise automatiquement tous les GPUs) -------------
echo "[$(date -Iseconds)] Démarrage de ollama serve…"
OLLAMA_HOST="0.0.0.0:11434" \
OLLAMA_MODELS="$OLLAMA_MODELS" \
    "$OLLAMA_BIN" serve > "$LOG" 2>&1 &
OLLAMA_PID=$!
echo "[$(date -Iseconds)] PID ollama : $OLLAMA_PID"

# Attendre que le serveur réponde (max 60s)
echo "[$(date -Iseconds)] Attente du démarrage…"
for i in $(seq 1 30); do
    if curl -sf --max-time 2 http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "[$(date -Iseconds)] ✓ Serveur ollama prêt"
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        echo "[$(date -Iseconds)] ERREUR : ollama ne répond pas après 60s"
        tail -20 "$LOG"
        exit 1
    fi
done

# --- Puller les modèles (skip si déjà en cache) ------------------------------
pull_model() {
    local model="$1"
    local base="${model%%:*}"

    if "$OLLAMA_BIN" list 2>/dev/null | awk 'NR>1{print $1}' | grep -q "^${base}"; then
        echo "[$(date -Iseconds)] ✓ $model déjà en cache — skip"
        return
    fi

    echo "[$(date -Iseconds)] Pull : $model …"
    "$OLLAMA_BIN" pull "$model"
    echo "[$(date -Iseconds)] ✓ $model prêt"
}

pull_model "$EMBED_MODEL"
pull_model "$CHAT_MODEL"

# --- Résumé ------------------------------------------------------------------
MODELS_LOADED=$("$OLLAMA_BIN" list 2>/dev/null \
    | awk 'NR>1{print $1}' | paste -sd ',' || echo "?")

echo ""
echo "[$(date -Iseconds)] =========================================="
echo "[$(date -Iseconds)] ✓ Ollama prêt — modèles : $MODELS_LOADED"
echo "[$(date -Iseconds)]   Tunnel depuis votre machine :"
echo "[$(date -Iseconds)]   ssh -N -L 11434:$(hostname -f):11434 \\"
echo "[$(date -Iseconds)]       -J login@access.grid5000.fr login@f$(hostname -d | cut -d. -f1).grid5000.fr"
echo "[$(date -Iseconds)] =========================================="

# Rester actif jusqu'au kill OAR (fin de walltime)
wait $OLLAMA_PID
