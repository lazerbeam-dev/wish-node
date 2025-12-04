#!/usr/bin/env python3
"""
scripts/fix_single_wish_task_ids.py

Usage:
  # Dry-run for a single wish (no commit)
  python scripts/fix_single_wish_task_ids.py a386d1b3-91e5-48ee-939f-a8990a803773 --dry

  # Apply changes for that wish
  python scripts/fix_single_wish_task_ids.py a386d1b3-91e5-48ee-939f-a8990a803773

  # Dry-run for ALL wishes
  python scripts/fix_single_wish_task_ids.py --all --dry

  # Apply for ALL wishes
  python scripts/fix_single_wish_task_ids.py --all
"""
import os
import sys
import argparse
import json
from uuid import uuid4
from pprint import pprint

# plug project root (one up from scripts/) onto sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

# import models from project
try:
    from models import Wish
except Exception as e:
    print("ERROR: cannot import models from project root:", PROJECT_ROOT)
    print("Exception:", e)
    raise

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")

def load_phases(raw):
    """Return list-of-phases from raw DB field (handles list/dict/string)."""
    if raw is None:
        return []
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, list) else [parsed]
        except Exception:
            # fallback: return single phase text
            return [{"title": raw, "tasks": []}]
    if isinstance(raw, dict):
        return [raw]
    return []

def ensure_ids_on_phases(phases):
    """
    Return normalized phases (new list). Add phase['id'] and task['id'], and
    ensure task['completed'] and task['completed_at'] exist.
    """
    out = []
    changed = False
    for p in phases or []:
        p_copy = dict(p) if isinstance(p, dict) else {"title": str(p), "tasks": []}

        if not p_copy.get("id"):
            p_copy["id"] = str(uuid4())
            changed = True

        raw_tasks = p_copy.get("tasks") or []
        # if tasks is a string (rare), attempt parse or split
        if isinstance(raw_tasks, str):
            try:
                raw_tasks = json.loads(raw_tasks)
            except Exception:
                raw_tasks = [ln.strip() for ln in raw_tasks.splitlines() if ln.strip()]

        normalized_tasks = []
        for t in raw_tasks:
            if t is None:
                t = {}
            if not isinstance(t, dict):
                t = {"title": str(t)}
            task_changed = False
            if not t.get("id"):
                t["id"] = str(uuid4())
                task_changed = True
            if "completed" not in t:
                t["completed"] = False
                task_changed = True
            if "completed_at" not in t:
                t["completed_at"] = None
                task_changed = True
            normalized_tasks.append(t)
            if task_changed:
                changed = True

        p_copy["tasks"] = normalized_tasks
        out.append(p_copy)
    return out, changed

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wish_id", nargs="?", help="Wish id to fix (omit with --all)")
    ap.add_argument("--all", action="store_true", help="Process all wishes")
    ap.add_argument("--dry", action="store_true", help="Dry run: show changes but do not commit")
    args = ap.parse_args()

    if not args.all and not args.wish_id:
        ap.error("either provide a wish_id or use --all")

    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    try:
        if args.all:
            wishes = db.query(Wish).all()
        else:
            w = db.query(Wish).filter(Wish.id == args.wish_id).first()
            if not w:
                print("Wish not found:", args.wish_id)
                return
            wishes = [w]

        total_updated = 0
        for w in wishes:
            print("\n=== Wish:", w.id, "| title:", getattr(w, "title", None))
            raw_phases = getattr(w, "phases", None)
            print("Raw phases type:", type(raw_phases).__name__)
            print("Raw phases (preview):")
            try:
                print(json.dumps(raw_phases, indent=2, ensure_ascii=False)[:2000])
            except Exception:
                pprint(raw_phases)

            parsed = load_phases(raw_phases)
            normalized, changed = ensure_ids_on_phases(parsed)

            if not changed:
                print("  -> No changes required for this wish.")
                continue

            print("  -> Changes detected. Preview of normalized phases (first 2000 chars):")
            try:
                print(json.dumps(normalized, indent=2, ensure_ascii=False)[:2000])
            except Exception:
                pprint(normalized)

            if not args.dry:
                print("  Committing changes to DB...")
                # persist using same mechanism as app (update field)
                db.query(Wish).filter(Wish.id == w.id).update({Wish.phases: normalized})
                total_updated += 1
            else:
                print("  Dry-run: not committing.")

        if not args.dry and total_updated > 0:
            db.commit()
            print(f"\nCommitted changes for {total_updated} wishes.")
        elif args.dry:
            print("\nDry-run complete. No DB changes were made.")
        else:
            print("\nNo wishes required updating.")

    finally:
        db.close()

if __name__ == "__main__":
    main()
