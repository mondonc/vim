#!/usr/bin/env python3
"""
rag.py — RAG sur une codebase avec Ollama + numpy

Dépendances : numpy (via rag/requirements.txt)
Modèle d'embedding : mxbai-embed-large (configurable via RAG_EMBED_MODEL)
Backend Ollama    : 192.168.122.1:11434 (configurable via OLLAMA_HOST)

Stockage : ~/.cache/vim-rag/<hash-projet>/
  - embeddings.npy : matrice (n_chunks, dim) des embeddings normalisés L2
  - chunks.json    : liste ordonnée des chunks (path, text, type, name, lines)
  - files.json     : map fichier -> { hash, chunk_start, chunk_end }
  - meta.json      : métadonnées (chemin projet, modèle, version)

Usage :
  rag.py index <path>              Indexer ou mettre à jour un projet
  rag.py query "<question>"        Interroger le RAG (JSON sur stdout)
  rag.py list                      Lister les projets indexés
  rag.py status <path>             État de l'index d'un projet
  rag.py clean <path>              Supprimer l'index d'un projet
"""

import argparse
import ast
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Iterator

import numpy as np

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://192.168.122.1:11434")


def _default_embed_model() -> str:
    """Résout le modèle d'embedding dans cet ordre :

    1. Variable d'environnement RAG_EMBED_MODEL (utile pour override ponctuel)
    2. Fichier ~/.vim/.rag-embed-model (écrit par ./install.sh rag)
    3. Valeur par défaut codée en dur
    """
    env = os.environ.get("RAG_EMBED_MODEL")
    if env:
        return env.strip()
    config_file = Path.home() / ".vim" / ".rag-embed-model"
    if config_file.exists():
        try:
            value = config_file.read_text(encoding="utf-8").strip()
            if value:
                return value
        except OSError:
            pass
    return "mxbai-embed-large"


EMBED_MODEL = _default_embed_model()
CACHE_DIR = Path(os.environ.get("RAG_CACHE_DIR", Path.home() / ".cache" / "vim-rag"))

VERSION = 1  # bump si on change le format de stockage

# Dossiers à ignorer complètement
SKIP_DIRS = {
    ".git", ".hg", ".svn",
    "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache",
    ".tox", ".nox",
    "venv", ".venv", "env", ".env",
    "node_modules", "bower_components",
    "dist", "build", "target",
    ".idea", ".vscode",
    "htmlcov", ".coverage",
    "migrations",  # Django : utile pour debug mais bruyant pour le RAG
    ".next", ".nuxt",
    "bundle",  # vim-plug / Vundle
}

# Extensions à indexer
INDEX_EXTENSIONS = {
    ".py", ".pyi", ".pyx",
    ".js", ".mjs", ".ts", ".jsx", ".tsx", ".vue",
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".yaml", ".yml", ".toml", ".json", ".ini", ".cfg",
    ".md", ".rst", ".txt",
    ".sh", ".bash", ".zsh",
    ".vim", ".lua",
    ".sql",
    ".c", ".h", ".cpp", ".hpp", ".cc",
    ".go", ".rs", ".rb", ".java",
    ".tf", ".nix",
}

# Fichiers spéciaux à indexer sans extension
INDEX_FILENAMES = {
    "Dockerfile", "dockerfile", "Makefile", "makefile",
    "Vagrantfile", ".gitignore", ".dockerignore",
    "pyproject.toml", "setup.py", "setup.cfg",
    "requirements.txt", "Pipfile", "poetry.lock",
}

MAX_FILE_SIZE = 500_000        # 500 KB par fichier
CHUNK_CHARS = 1000             # taille cible d'un chunk non-Python (~250 tokens)
CHUNK_OVERLAP = 150            # overlap entre chunks non-Python
MAX_CHUNK_CHARS = 1800         # hard cap (~450 tokens) : au-delà on découpe
EMBED_BATCH_SIZE = 16          # nb de textes par requête /api/embed
EMBED_PARALLEL = 4             # nb de requêtes parallèles
HTTP_TIMEOUT = 300             # secondes (indexation initiale peut être lente)
NUM_THREAD = int(os.environ.get("RAG_NUM_THREAD", "12"))  # cœurs CPU côté Ollama


# ---------------------------------------------------------------------------
# Utils
# ---------------------------------------------------------------------------

def log(msg: str, *, file=sys.stderr):
    """Logs vers stderr pour ne pas polluer la sortie JSON."""
    print(msg, file=file, flush=True)


def project_hash(path: Path) -> str:
    return hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]


def project_cache(path: Path) -> Path:
    return CACHE_DIR / project_hash(path)


def file_hash(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def should_index(path: Path) -> bool:
    if path.suffix.lower() in INDEX_EXTENSIONS:
        return True
    if path.name in INDEX_FILENAMES:
        return True
    return False


def walk_project(root: Path) -> Iterator[Path]:
    """Parcourt le projet en ignorant SKIP_DIRS et les fichiers cachés (sauf dotfiles utiles)."""
    for dirpath, dirnames, filenames in os.walk(root):
        # Filtre in-place pour que os.walk n'entre pas dans ces dossiers
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS and not (d.startswith(".") and d not in {".github"})
        ]
        for fname in filenames:
            fpath = Path(dirpath) / fname
            if not should_index(fpath):
                continue
            try:
                if fpath.stat().st_size > MAX_FILE_SIZE:
                    continue
                if fpath.stat().st_size == 0:
                    continue
            except OSError:
                continue
            yield fpath


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------

def chunk_python(source: str, rel_path: str) -> list[dict]:
    """Chunk un fichier Python par définitions top-level (classes + fonctions).

    Si le parse échoue (fichier syntaxiquement cassé, Python 2, etc.), fallback
    sur un chunking texte.
    """
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError):
        return chunk_text(source, rel_path)

    lines = source.splitlines(keepends=True)
    chunks: list[dict] = []

    # Collecter les plages (start, end, kind, name) des défs top-level
    ranges: list[tuple[int, int, str, str]] = []
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            start = node.lineno - 1  # 0-indexed
            end = getattr(node, "end_lineno", None)
            if end is None:
                continue
            ranges.append((start, end, type(node).__name__, node.name))

    if not ranges:
        return chunk_text(source, rel_path)

    # Chunk "module" : tout ce qui précède la première déf (imports, constantes)
    first_start = ranges[0][0]
    if first_start > 0:
        head = "".join(lines[:first_start])
        if head.strip():
            chunks.append({
                "text": head,
                "path": rel_path,
                "type": "module",
                "name": "<module>",
                "start_line": 1,
                "end_line": first_start,
            })

    # Un chunk par déf top-level
    for start, end, kind, name in ranges:
        text = "".join(lines[start:end])
        if not text.strip():
            continue
        # Si une classe est énorme, on la subdivise par méthodes
        if kind == "ClassDef" and len(text) > CHUNK_CHARS * 3:
            chunks.extend(_split_large_class(source, start, end, name, rel_path))
        else:
            chunks.append({
                "text": text,
                "path": rel_path,
                "type": kind,
                "name": name,
                "start_line": start + 1,
                "end_line": end,
            })

    return chunks


def _split_large_class(source: str, cls_start: int, cls_end: int,
                        cls_name: str, rel_path: str) -> list[dict]:
    """Subdivise une classe volumineuse en chunks par méthode."""
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError):
        # Fallback : renvoie la classe en un seul bloc texte
        lines = source.splitlines(keepends=True)
        return [{
            "text": "".join(lines[cls_start:cls_end]),
            "path": rel_path,
            "type": "ClassDef",
            "name": cls_name,
            "start_line": cls_start + 1,
            "end_line": cls_end,
        }]

    lines = source.splitlines(keepends=True)
    chunks: list[dict] = []

    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == cls_name:
            # Header de la classe (signature + docstring)
            first_method_line = None
            for child in node.body:
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    first_method_line = child.lineno - 1
                    break
            header_end = first_method_line if first_method_line else (cls_end)
            header = "".join(lines[cls_start:header_end])
            if header.strip():
                chunks.append({
                    "text": header,
                    "path": rel_path,
                    "type": "ClassDef",
                    "name": f"{cls_name} (header)",
                    "start_line": cls_start + 1,
                    "end_line": header_end,
                })

            # Une entrée par méthode (avec préfixe de contexte)
            for child in node.body:
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    m_start = child.lineno - 1
                    m_end = getattr(child, "end_lineno", None)
                    if m_end is None:
                        continue
                    text = "".join(lines[m_start:m_end])
                    if not text.strip():
                        continue
                    chunks.append({
                        "text": f"# class {cls_name}:\n{text}",
                        "path": rel_path,
                        "type": "method",
                        "name": f"{cls_name}.{child.name}",
                        "start_line": m_start + 1,
                        "end_line": m_end,
                    })
            break  # on a traité notre classe

    return chunks


def chunk_text(source: str, rel_path: str) -> list[dict]:
    """Chunk arbitraire par tranches de ~CHUNK_CHARS avec overlap."""
    chunks: list[dict] = []
    if not source.strip():
        return chunks

    # Si le fichier est petit, un seul chunk
    if len(source) <= CHUNK_CHARS:
        chunks.append({
            "text": source,
            "path": rel_path,
            "type": "text",
            "name": "<file>",
            "start_line": 1,
            "end_line": source.count("\n") + 1,
        })
        return chunks

    pos = 0
    idx = 0
    total_len = len(source)
    while pos < total_len:
        end = min(pos + CHUNK_CHARS, total_len)
        # Tenter de couper à un newline pour ne pas casser le milieu d'une ligne
        if end < total_len:
            newline = source.rfind("\n", pos + CHUNK_CHARS // 2, end)
            if newline != -1:
                end = newline + 1
        piece = source[pos:end]
        if piece.strip():
            start_line = source[:pos].count("\n") + 1
            end_line = source[:end].count("\n") + 1
            chunks.append({
                "text": piece,
                "path": rel_path,
                "type": "text",
                "name": f"chunk_{idx}",
                "start_line": start_line,
                "end_line": end_line,
            })
        idx += 1
        if end >= total_len:
            break
        pos = max(end - CHUNK_OVERLAP, pos + 1)

    return chunks


def _split_oversized(chunk: dict) -> list[dict]:
    """Découpe un chunk trop long en sous-chunks <= MAX_CHUNK_CHARS.

    Utilisé comme garde-fou final : si une fonction Python ou un morceau
    de texte dépasse la fenêtre de contexte du modèle d'embedding, on le
    tranche en morceaux raisonnables (en privilégiant les coupures sur
    des lignes vides / newlines).
    """
    text = chunk["text"]
    if len(text) <= MAX_CHUNK_CHARS:
        return [chunk]

    parts: list[dict] = []
    pos = 0
    idx = 0
    total = len(text)
    base_start = chunk["start_line"]

    while pos < total:
        end = min(pos + MAX_CHUNK_CHARS, total)
        # Chercher une bonne coupure (ligne vide, sinon newline) dans le
        # dernier quart du morceau, pour ne pas couper en plein milieu
        if end < total:
            boundary = text.rfind("\n\n", pos + MAX_CHUNK_CHARS // 2, end)
            if boundary == -1:
                boundary = text.rfind("\n", pos + MAX_CHUNK_CHARS // 2, end)
            if boundary != -1:
                end = boundary + 1

        piece = text[pos:end]
        if piece.strip():
            # Estimer la plage de lignes du sous-chunk dans le fichier d'origine
            lines_before = text[:pos].count("\n")
            lines_in = piece.count("\n")
            parts.append({
                "text": piece,
                "path": chunk["path"],
                "type": chunk["type"],
                "name": f"{chunk['name']} [part {idx + 1}]",
                "start_line": base_start + lines_before,
                "end_line": base_start + lines_before + lines_in,
            })
        idx += 1
        if end >= total:
            break
        # Petit overlap pour garder du contexte entre sous-chunks
        pos = max(end - CHUNK_OVERLAP, pos + 1)

    return parts


def chunk_file(path: Path, rel_path: str) -> list[dict]:
    try:
        source = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        log(f"  ⚠ lecture échouée {rel_path}: {e}")
        return []

    if path.suffix.lower() in {".py", ".pyi"}:
        raw_chunks = chunk_python(source, rel_path)
    else:
        raw_chunks = chunk_text(source, rel_path)

    # Garde-fou : aucun chunk ne doit dépasser MAX_CHUNK_CHARS
    final: list[dict] = []
    for c in raw_chunks:
        final.extend(_split_oversized(c))
    return final


# ---------------------------------------------------------------------------
# Ollama embeddings
# ---------------------------------------------------------------------------

def _ollama_post(endpoint: str, payload: dict) -> dict:
    """POST JSON sur Ollama, lève une exception claire si erreur."""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_HOST}{endpoint}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"Ollama HTTP {e.code} sur {endpoint}: {body[:500]}"
        ) from e
    except urllib.error.URLError as e:
        raise RuntimeError(
            f"Ollama injoignable sur {OLLAMA_HOST} : {e.reason}"
        ) from e


def embed_batch(texts: list[str]) -> np.ndarray:
    """Embed un batch via /api/embed. Retourne un array (n, dim) en float32."""
    if not texts:
        return np.empty((0, 0), dtype=np.float32)
    resp = _ollama_post("/api/embed", {
        "model": EMBED_MODEL,
        "input": texts,
        "options": {"num_thread": NUM_THREAD},
    })
    embeddings = resp.get("embeddings")
    if not embeddings or len(embeddings) != len(texts):
        raise RuntimeError(
            f"Ollama a renvoyé {len(embeddings or [])} embeddings "
            f"pour {len(texts)} textes"
        )
    return np.asarray(embeddings, dtype=np.float32)


def _embed_batch_with_fallback(texts: list[str]) -> tuple[np.ndarray, list[int]]:
    """Embed un batch ; si le batch échoue en 400 (ex: un chunk trop long),
    retry chunk par chunk pour garder les bons et skipper le(s) fautif(s).

    Retourne (matrix, local_indices_kept) : matrix est de taille
    (len(local_indices_kept), dim), et local_indices_kept donne les positions
    au sein du batch d'origine qui ont été embeddées avec succès.
    """
    try:
        matrix = embed_batch(texts)
        return matrix, list(range(len(texts)))
    except RuntimeError as e:
        # Si ce n'est pas une erreur "contexte dépassé", on repropage
        msg = str(e).lower()
        if "exceeds the context length" not in msg and "http 400" not in msg:
            raise
        # Retry un par un
        log(f"  ⚠ batch trop long, fallback 1-par-1 sur {len(texts)} chunks")
        kept_rows: list[np.ndarray] = []
        kept_idx: list[int] = []
        for i, t in enumerate(texts):
            try:
                row = embed_batch([t])
                kept_rows.append(row)
                kept_idx.append(i)
            except RuntimeError as e2:
                preview = t[:80].replace("\n", " ")
                log(f"  ⚠ chunk skippé ({len(t)} chars): {preview!r}... — {e2}")
        if not kept_rows:
            return np.empty((0, 0), dtype=np.float32), []
        return np.vstack(kept_rows), kept_idx


def embed_all(texts: list[str], *, progress_label: str = "") -> tuple[np.ndarray, list[int]]:
    """Embed une liste de textes en parallèle, par batchs.

    Retourne (embeddings, kept_indices) où kept_indices est la liste des
    indices globaux (dans `texts`) qui ont été embeddés avec succès, dans
    l'ordre de `embeddings`.
    """
    if not texts:
        return np.empty((0, 0), dtype=np.float32), []

    n = len(texts)
    batches: list[tuple[int, list[str]]] = []
    for i in range(0, n, EMBED_BATCH_SIZE):
        batches.append((i, texts[i:i + EMBED_BATCH_SIZE]))

    # Par batch : liste de (offset, matrix, local_kept_indices)
    results: list[tuple[int, np.ndarray, list[int]]] = []
    done_count = 0
    t0 = time.time()

    with ThreadPoolExecutor(max_workers=EMBED_PARALLEL) as pool:
        future_to_offset = {
            pool.submit(_embed_batch_with_fallback, batch_texts): offset
            for offset, batch_texts in batches
        }
        for fut in as_completed(future_to_offset):
            offset = future_to_offset[fut]
            matrix, kept = fut.result()  # propage les vraies erreurs
            results.append((offset, matrix, kept))
            done_count += matrix.shape[0]
            if progress_label:
                pct = int(100 * done_count / n)
                log(f"  {progress_label}: {pct}% ({done_count}/{n})")

    # Trier par offset, construire matrice finale + indices globaux
    results.sort(key=lambda x: x[0])
    kept_global: list[int] = []
    matrices: list[np.ndarray] = []
    for offset, matrix, kept in results:
        if matrix.size == 0:
            continue
        matrices.append(matrix)
        for local_i in kept:
            kept_global.append(offset + local_i)

    if matrices:
        full = np.vstack(matrices)
    else:
        full = np.empty((0, 0), dtype=np.float32)

    elapsed = time.time() - t0
    skipped = n - len(kept_global)
    if skipped > 0:
        log(f"  {len(kept_global)} embeddings gardés / {skipped} skippés "
            f"en {elapsed:.1f}s")
    else:
        log(f"  {n} embeddings en {elapsed:.1f}s ({n/max(elapsed, 0.01):.1f}/s)")
    return full, kept_global


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

def save_index(cache: Path, embeddings: np.ndarray, chunks: list[dict],
               files: dict, meta: dict) -> None:
    cache.mkdir(parents=True, exist_ok=True)
    np.save(cache / "embeddings.npy", embeddings)
    (cache / "chunks.json").write_text(json.dumps(chunks, ensure_ascii=False))
    (cache / "files.json").write_text(json.dumps(files, ensure_ascii=False))
    (cache / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False))


def load_index(cache: Path) -> tuple[np.ndarray, list[dict], dict, dict] | None:
    if not (cache / "embeddings.npy").exists():
        return None
    try:
        embeddings = np.load(cache / "embeddings.npy")
        chunks = json.loads((cache / "chunks.json").read_text())
        files = json.loads((cache / "files.json").read_text())
        meta = json.loads((cache / "meta.json").read_text())
    except (OSError, json.JSONDecodeError, ValueError) as e:
        log(f"  ⚠ index corrompu ({e}), réindexation complète nécessaire")
        return None
    return embeddings, chunks, files, meta


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_index(project_path: Path) -> int:
    project_path = project_path.resolve()
    if not project_path.is_dir():
        log(f"ERREUR : {project_path} n'est pas un dossier")
        return 1

    cache = project_cache(project_path)
    log(f"Projet : {project_path}")
    log(f"Cache  : {cache}")
    log(f"Modèle : {EMBED_MODEL} via {OLLAMA_HOST} (num_thread={NUM_THREAD})")

    # Charger l'index existant s'il y en a un
    existing = load_index(cache)
    old_files: dict = {}
    old_chunks: list[dict] = []
    old_embeddings: np.ndarray | None = None
    if existing is not None:
        old_embeddings, old_chunks, old_files, old_meta = existing
        if old_meta.get("embed_model") != EMBED_MODEL:
            log(f"  ⚠ modèle changé ({old_meta.get('embed_model')} -> {EMBED_MODEL}), "
                f"réindexation complète")
            old_files, old_chunks, old_embeddings = {}, [], None

    # Lister les fichiers actuels + hash
    log("→ Scan du projet...")
    current_files: dict = {}
    all_paths = list(walk_project(project_path))
    for fpath in all_paths:
        rel = str(fpath.relative_to(project_path))
        try:
            h = file_hash(fpath)
        except OSError:
            continue
        current_files[rel] = {"hash": h, "path": str(fpath)}
    log(f"  {len(current_files)} fichiers candidats")

    # Diff : nouveaux / modifiés / supprimés / inchangés
    new_or_changed = []
    unchanged = []
    for rel, info in current_files.items():
        if rel in old_files and old_files[rel].get("hash") == info["hash"]:
            unchanged.append(rel)
        else:
            new_or_changed.append(rel)
    removed = [rel for rel in old_files if rel not in current_files]

    log(f"  nouveaux/modifiés : {len(new_or_changed)}")
    log(f"  inchangés         : {len(unchanged)}")
    log(f"  supprimés         : {len(removed)}")

    # Garder les chunks des fichiers inchangés
    kept_chunks: list[dict] = []
    kept_embeddings_idx: list[int] = []
    if old_embeddings is not None:
        for rel in unchanged:
            info = old_files[rel]
            start = info["chunk_start"]
            end = info["chunk_end"]
            for i in range(start, end):
                kept_embeddings_idx.append(i)
                kept_chunks.append(old_chunks[i])

    # Chunk les nouveaux/modifiés
    log("→ Chunking des fichiers modifiés...")
    new_chunks: list[dict] = []
    file_chunk_ranges: dict = {}  # rel -> (start, end) dans new_chunks
    for rel in new_or_changed:
        fpath = Path(current_files[rel]["path"])
        before = len(new_chunks)
        new_chunks.extend(chunk_file(fpath, rel))
        after = len(new_chunks)
        if after > before:
            file_chunk_ranges[rel] = (before, after)
    log(f"  {len(new_chunks)} nouveaux chunks")

    # Embed les nouveaux chunks
    if new_chunks:
        log("→ Génération des embeddings...")
        new_embeddings, kept_indices = embed_all(
            [c["text"] for c in new_chunks],
            progress_label="embed",
        )
        # Filtrer new_chunks aux indices qui ont réussi
        if len(kept_indices) < len(new_chunks):
            new_chunks = [new_chunks[i] for i in kept_indices]
            # Recalculer les ranges par fichier à partir des chunks filtrés
            file_chunk_ranges = {}
            for i, c in enumerate(new_chunks):
                rel = c["path"]
                if rel in file_chunk_ranges:
                    file_chunk_ranges[rel] = (file_chunk_ranges[rel][0], i + 1)
                else:
                    file_chunk_ranges[rel] = (i, i + 1)
    else:
        dim = kept_embeddings_idx and old_embeddings.shape[1] or 0
        new_embeddings = np.empty((0, dim), dtype=np.float32)

    # Assembler l'index final
    if kept_embeddings_idx:
        kept_arr = old_embeddings[kept_embeddings_idx]
    else:
        kept_arr = np.empty((0, new_embeddings.shape[1] if new_embeddings.size else 0),
                            dtype=np.float32)

    final_embeddings = np.vstack([kept_arr, new_embeddings]) if new_embeddings.size or kept_arr.size else np.empty((0, 0), dtype=np.float32)
    final_chunks = kept_chunks + new_chunks

    # Reconstruire files.json avec les nouveaux ranges
    final_files: dict = {}
    # Les chunks "kept" sont en premier, dans l'ordre où on les a ajoutés
    idx = 0
    for rel in unchanged:
        info = old_files[rel]
        count = info["chunk_end"] - info["chunk_start"]
        final_files[rel] = {
            "hash": info["hash"],
            "chunk_start": idx,
            "chunk_end": idx + count,
        }
        idx += count
    # Puis les nouveaux
    for rel, (s, e) in file_chunk_ranges.items():
        count = e - s
        final_files[rel] = {
            "hash": current_files[rel]["hash"],
            "chunk_start": idx,
            "chunk_end": idx + count,
        }
        idx += count

    meta = {
        "version": VERSION,
        "project_path": str(project_path),
        "embed_model": EMBED_MODEL,
        "embed_dim": int(final_embeddings.shape[1]) if final_embeddings.size else 0,
        "n_chunks": len(final_chunks),
        "n_files": len(final_files),
        "indexed_at": int(time.time()),
    }

    save_index(cache, final_embeddings, final_chunks, final_files, meta)
    log(f"✓ Index : {len(final_chunks)} chunks depuis {len(final_files)} fichiers")
    return 0


def cmd_query(project_path: Path, query: str, k: int = 5) -> int:
    project_path = project_path.resolve()
    cache = project_cache(project_path)
    existing = load_index(cache)
    if existing is None:
        err = {
            "error": "not_indexed",
            "message": f"Aucun index pour {project_path}. Lance : rag.py index <path>",
        }
        print(json.dumps(err), flush=True)
        return 2

    embeddings, chunks, _files, meta = existing
    if len(chunks) == 0:
        print(json.dumps({"results": [], "query": query}), flush=True)
        return 0

    # Vérifier que le modèle d'embedding n'a pas changé
    if meta.get("embed_model") != EMBED_MODEL:
        err = {
            "error": "model_mismatch",
            "message": (
                f"Index créé avec {meta.get('embed_model')} mais RAG_EMBED_MODEL="
                f"{EMBED_MODEL}. Relance : rag.py index <path>"
            ),
        }
        print(json.dumps(err), flush=True)
        return 3

    # Embed la question
    q_emb = embed_batch([query])[0]
    # L2-normalize la requête (l'API est censée le faire mais on s'assure)
    norm = float(np.linalg.norm(q_emb))
    if norm > 0:
        q_emb = q_emb / norm

    # Similarité cosinus = produit scalaire (vecteurs normalisés)
    sims = embeddings @ q_emb
    top_k = min(k, len(chunks))
    top_idx = np.argpartition(-sims, top_k - 1)[:top_k]
    top_idx = top_idx[np.argsort(-sims[top_idx])]

    results = []
    for i in top_idx:
        c = chunks[int(i)]
        results.append({
            "score": float(sims[int(i)]),
            "path": c["path"],
            "type": c["type"],
            "name": c["name"],
            "start_line": c["start_line"],
            "end_line": c["end_line"],
            "text": c["text"],
        })

    print(json.dumps({
        "query": query,
        "project": str(project_path),
        "n_chunks_total": len(chunks),
        "results": results,
    }, ensure_ascii=False), flush=True)
    return 0


def cmd_list() -> int:
    if not CACHE_DIR.exists():
        print(json.dumps({"projects": []}, indent=2))
        return 0
    projects = []
    for d in sorted(CACHE_DIR.iterdir()):
        if not d.is_dir():
            continue
        meta_file = d / "meta.json"
        if not meta_file.exists():
            continue
        try:
            meta = json.loads(meta_file.read_text())
        except json.JSONDecodeError:
            continue
        projects.append({
            "cache": str(d),
            "project_path": meta.get("project_path"),
            "n_chunks": meta.get("n_chunks"),
            "n_files": meta.get("n_files"),
            "embed_model": meta.get("embed_model"),
            "indexed_at": meta.get("indexed_at"),
        })
    print(json.dumps({"projects": projects}, indent=2, ensure_ascii=False))
    return 0


def cmd_status(project_path: Path) -> int:
    project_path = project_path.resolve()
    cache = project_cache(project_path)
    existing = load_index(cache)
    if existing is None:
        print(json.dumps({"indexed": False, "project": str(project_path)}))
        return 0
    _, chunks, files, meta = existing
    print(json.dumps({
        "indexed": True,
        "project": str(project_path),
        "cache": str(cache),
        "n_chunks": len(chunks),
        "n_files": len(files),
        "meta": meta,
    }, indent=2, ensure_ascii=False))
    return 0


def cmd_clean(project_path: Path) -> int:
    project_path = project_path.resolve()
    cache = project_cache(project_path)
    if cache.exists():
        shutil.rmtree(cache)
        log(f"✓ Index supprimé : {cache}")
    else:
        log(f"Aucun index pour {project_path}")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="RAG sur une codebase (Ollama + numpy)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_index = sub.add_parser("index", help="Indexer ou mettre à jour un projet")
    p_index.add_argument("path", type=Path)

    p_query = sub.add_parser("query", help="Interroger le RAG (sortie JSON)")
    p_query.add_argument("query")
    p_query.add_argument("--project", type=Path, default=Path.cwd())
    p_query.add_argument("-k", type=int, default=5, help="Nb de chunks (défaut 5)")

    p_list = sub.add_parser("list", help="Lister les projets indexés")

    p_status = sub.add_parser("status", help="État de l'index")
    p_status.add_argument("path", type=Path, nargs="?", default=Path.cwd())

    p_clean = sub.add_parser("clean", help="Supprimer l'index")
    p_clean.add_argument("path", type=Path)

    args = parser.parse_args()

    try:
        if args.cmd == "index":
            return cmd_index(args.path)
        if args.cmd == "query":
            return cmd_query(args.project, args.query, args.k)
        if args.cmd == "list":
            return cmd_list()
        if args.cmd == "status":
            return cmd_status(args.path)
        if args.cmd == "clean":
            return cmd_clean(args.path)
    except RuntimeError as e:
        # Erreurs "propres" (Ollama injoignable, etc.)
        if args.cmd == "query":
            print(json.dumps({"error": "runtime", "message": str(e)}), flush=True)
        else:
            log(f"ERREUR : {e}")
        return 10
    except KeyboardInterrupt:
        log("\n✗ Interrompu")
        return 130

    return 1


if __name__ == "__main__":
    sys.exit(main())
