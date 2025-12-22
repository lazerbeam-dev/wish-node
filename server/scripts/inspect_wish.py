#!/usr/bin/env python3
"""
scripts/inspect_wish.py

Usage:
    python scripts/inspect_wish.py <wish_id>

Prints a full, human-readable dump of the Wish row and the phases/tasks structure.
"""

import os
import sys
import json
import argparse
from pprint import pprint

# Ensure project root (one level up from scripts/) is on sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

# Now import project models
try:
    from models import Wish  # type: ignore
except Exception as e:
    print("ERROR: failed to import models. Checked project root:", PROJECT_ROOT)
    print("Exception:", e)
    raise

# SQLAlchemy imports
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# DB URL from env or fallback
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")

def pretty_print_sqlalchemy_row(row):
    """Print column -> value for a SQLAlchemy mapped object."""
    try:
        cols = list(row.__table__.c)
    except Exception:
        # fallback: try __dict__
        print("Raw object __dict__:")
        pprint(row.__dict__)
        return

    out = {}
    for c in cols:
        name = c.name
        try:
            out[name] = getattr(row, name)
        except Exception as e:
            out[name] = f"<error reading attribute: {e}>"
    pprint(out, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Inspect a Wish row and its phases/tasks")
    parser.add_argument("wish_id", nargs="?", help="Wish id to inspect (UUID or string).")
    args = parser.parse_args()

    wish_id = args.wish_id
    if not wish_id:
        wish_id = input("Enter wish id: ").strip()
        if not wish_id:
            print("No wish id provided. Exiting.")
            return

    #print("Using DATABASE_URL =", DATABASE_URL)
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    try:
        w = db.query(Wish).filter(Wish.id == wish_id).first()
        if not w:
            print(f"Wish not found for id: {wish_id}")
            return

        print("\n=== Full Wish row (column -> value) ===")
        pretty_print_sqlalchemy_row(w)

        # Show repr too
        try:
            print("\n=== repr(w) ===")
            print(repr(w))
        except Exception:
            pass

        # Raw phases value (could be list, dict, or JSON string)
        raw_phases = getattr(w, "phases", None)
        print("\n=== Raw `phases` field (type: {}) ===".format(type(raw_phases).__name__))
        # print raw via pprint/truncated JSON
        try:
            pprint(raw_phases)
        except Exception:
            print(str(raw_phases))

        # Try to parse if it's a JSON string
        parsed = None
        if isinstance(raw_phases, str):
            print("\nNote: phases stored as string — attempting json.loads()")
            try:
                parsed = json.loads(raw_phases)
                print("JSON parse succeeded. Parsed structure:")
                print(json.dumps(parsed, indent=2, ensure_ascii=False)[:20000])
            except Exception as e:
                print("JSON parse failed:", e)
                # fallback: print raw string
                print(raw_phases[:2000])
        elif isinstance(raw_phases, (list, dict)):
            parsed = raw_phases
            print("\n=== Parsed phases ===")
            print(json.dumps(parsed, indent=2, ensure_ascii=False)[:20000])
        else:
            print("\nphases is neither string nor list/dict; its repr:")
            print(repr(raw_phases))

        # If parsed, iterate and print full details per phase and per task
        if parsed:
            print("\n\n=== Detailed phases/tasks dump ===")
            # Ensure it's a list (if dict, wrap)
            if isinstance(parsed, dict):
                parsed = [parsed]
            if not isinstance(parsed, list):
                print("Parsed phases is not a list; full repr:")
                pprint(parsed)
            else:
                for i, p in enumerate(parsed):
                    print(f"\n--- Phase {i} ---")
                    if not isinstance(p, dict):
                        print("Phase is not dict:", repr(p))
                        continue
                    # pretty-print phase fields
                    for k, v in p.items():
                        if k != "tasks":
                            print(f"{k}: {v!r}")
                    tasks = p.get("tasks", [])
                    print(f"tasks: ({len(tasks)} entries)")
                    for j, t in enumerate(tasks):
                        print(f"  - task[{j}]:")
                        if isinstance(t, dict):
                            for kk, vv in t.items():
                                print(f"      {kk}: {vv!r}")
                        else:
                            print(f"      (non-dict task) {repr(t)}")

    finally:
        db.close()


if __name__ == "__main__":
    main()
