from fastapi import FastAPI, HTTPException, Depends, Response, Body
from sqlalchemy.orm import Session
from uuid import uuid4
from datetime import datetime, timedelta, timezone
from models import Base, User, Wish, Item, WishStatus, Tier
from schemas import WishCreate, ItemOut
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv          
from openai import OpenAI  
from typing import Optional
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
import json
import traceback
from uuid import uuid4
from typing import Any, Dict
import items
class PlanRequest(BaseModel):
    # human text describing the wish (required)
    wish: str
    # optional owner id (client may already have an anon id); if omitted, a new anon owner id is returned
    owner_id: Optional[str] = None
    # optional client-supplied wish id to support idempotency / optimistic UI
    wish_id: Optional[str] = None
    # optional title override for the wish (fallback: first 80 chars of `wish`)
    title: Optional[str] = None

class TaskEdit(BaseModel):
    title: Optional[str] = None
    repeat: Optional[bool] = None
    # allow updating other small metadata if you want later:
    # completed: Optional[bool] = None
    # completed_at: Optional[str] = None

class TaskCreate(BaseModel):
    title: str
    repeat: Optional[bool] = False

class CompleteTaskBody(BaseModel):
    mark_incomplete: Optional[bool] = False
import ai
import os
import schemas

# Load .env immediately
load_dotenv()                           

# OpenAI client
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")        
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL")  
MODEL = "gpt-4o-mini"    
client = OpenAI(                                   
    api_key=OPENAI_API_KEY,
    base_url=OPENAI_BASE_URL
)

origins = [
    "http://localhost:3000",   # common web dev port
    "http://localhost:8000",
    "http://127.0.0.1:5500",
    "http://localhost:8080",
    "http://localhost",        # optional
    "*"                        # for quick dev, allow all origins (not recommended for prod)
]

# Database
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine)
Base.metadata.create_all(bind=engine)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,        # use ['*'] for quick dev; restrict in prod
    allow_credentials=True,
    allow_methods=["*"],          # allow OPTIONS, POST, GET, etc.
    allow_headers=["*"],          # allow Content-Type, Authorization, etc.
)

FREE_ACTIVE_WISH_LIMIT = 3

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def active_wish_count(db: Session, user_id: str):
    return db.query(Wish).filter(
        Wish.owner_id == user_id,
        Wish.status == WishStatus.in_progress,
        Wish.deleted == False
    ).count()

@app.post("/api/anon")
def create_anon(response: Response, db: Session = Depends(get_db)):
    anon_id = str(uuid4())
    user = User(id=anon_id, tier=Tier.anon)
    db.add(user)
    db.commit()
    # optional cookie for convenience in browser clients
    response.set_cookie("wishnode_anon_id", anon_id, httponly=True, max_age=60*60*24*365)
    return {"anon_user_id": anon_id}

@app.post("/api/users/claim")
def claim_user(anon_user_id: str, email: str, password_plain: str, db: Session = Depends(get_db)):
    """
    Convert an anonymous user (tier == Tier.anon) into a real user.
    - Finds the anon user by id + tier.
    - Creates a new permanent user row with a new id (tier=free).
    - Moves wishes from anon_user_id -> new_id.
    - Deletes the anonymous user row.
    - If the User model has 'email' and 'password_hash' columns, fill them;
      otherwise skip them to remain compatible with lightweight schemas.
    """
    # find anon user by tier
    anon = db.query(User).filter(User.id == anon_user_id, User.tier == Tier.anon).first()
    if not anon:
        raise HTTPException(status_code=404, detail="Anonymous user not found")

    # create new user id
    new_id = str(uuid4())
    new_user_kwargs = {"id": new_id, "tier": Tier.free, "created_at": datetime.now(timezone.utc)}


    # include email if the model defines such a column/attribute
    if hasattr(User, "email"):
        new_user_kwargs["email"] = email

    user = User(**new_user_kwargs)

    # set password_hash only if hashing util exists and model has the column
    if hasattr(User, "password_hash"):
        if "hash_password" in globals() and callable(globals().get("hash_password")):
            user.password_hash = hash_password(password_plain)
        else:
            # If no hashing util, do not set plaintext password — leave blank or handle appropriately.
            # We avoid storing passwords in plaintext; prefer to fail loudly in prod.
            # For tests/dev we just skip setting it.
            pass

    db.add(user)

    # move wishes from anon to new user id
    db.query(Wish).filter(Wish.owner_id == anon_user_id).update({Wish.owner_id: new_id})

    # remove the anon row to avoid duplicate accounts; if you prefer marking converted,
    # you could set anon.tier = Tier.free instead of deleting.
    try:
        db.delete(anon)
    except Exception:
        # If deletion is problematic for your schema (FKs), fallback to marking converted:
        if hasattr(anon, "tier"):
            anon.tier = Tier.free

    db.commit()
    return {"ok": True, "user_id": new_id}


@app.get("/api/wishes")
def list_active_wishes(user_id: str, db: Session = Depends(get_db)):
    wishes = db.query(Wish).filter(Wish.owner_id == user_id, Wish.status == WishStatus.in_progress).all()
    return {"wishes": [ {"id":w.id, "title":w.title, "phases": w.phases, "created_at": w.created_at} for w in wishes ]}

@app.get("/api/wishes/{wish_id}")
def get_wish(wish_id: str, db: Session = Depends(get_db)):
    w = db.query(Wish).filter(Wish.id == wish_id).first()
    if not w:
        raise HTTPException(status_code=404, detail="Wish not found")
    return {"wish": {"id": w.id, "title": w.title, "phases": w.phases, "status": w.status}}

def _persist_wish_phases(db: Session, wish: Wish, phases):
    """
    Persist the phases JSON for a wish using a direct update to avoid
    problems with mutable-in-place JSON objects and session state.
    After updating, commit and return the reloaded Wish object.
    """
    # Use SQLAlchemy update for reliability across DB backends
    try:
        db.query(Wish).filter(Wish.id == wish.id).update({Wish.phases: phases})
        db.commit()
    except Exception:
        # fallback: assign and commit (keeps previous behaviour if update fails)
        wish.phases = phases
        db.add(wish)
        db.commit()
    # return the freshly loaded Wish
    return db.query(Wish).filter(Wish.id == wish.id).first()

@app.post("/api/wishes/{wish_id}/tasks/{task_id}/complete")
def complete_task(
    wish_id: str,
    task_id: str,
    body: CompleteTaskBody = Body(None),
    db: Session = Depends(get_db),
):
    """
    Mark a task complete or incomplete.
    - If body.mark_incomplete == True => set completed=false, clear completed_at.
      We intentionally DO NOT decrement repeated_amount on un-complete (keeps history).
    - If marking complete => set completed=true, set completed_at to now (UTC ISO),
      and if task.repeat == True increment repeated_amount (creating it if missing).
    Returns same shape as before (ok/toast or created_item_id).
    """
    wish = db.query(Wish).filter(Wish.id == wish_id).first()
    if not wish:
        raise HTTPException(status_code=404, detail="Wish not found")

    phases = wish.phases or []
    updated = False

    mark_incomplete = bool(body.mark_incomplete) if body is not None else False
    phase_title = ""
    task_title = ""
    for p in phases:
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                if mark_incomplete:
                    # Mark task as incomplete (do not touch repeated_amount)
                    t["completed"] = False
                    t.pop("completed_at", None)
                else:
                    # Mark complete and set completed_at on the task
                    t["completed"] = True
                    # use timezone aware ISO
                    t["completed_at"] = datetime.now(timezone.utc).isoformat()
                    # If this is a repeating task, increment repeated_amount
                    if t.get("repeat") == True:
                        t["repeated_amount"] = int(t.get("repeated_amount", 0)) + 1
                updated = True
                phase_title = p.get("title", "")
                task_title = t.get("title", "")
                break
        if updated:
            break

    if not updated:
        raise HTTPException(status_code=404, detail="Task not found")

    # Persist phases using your helper (returns reloaded wish)
    wish = _persist_wish_phases(db, wish, phases)

    # Evaluate whether ALL tasks across all phases are completed
    def _task_done(t):
        # robust check for boolean-like values
        val = t.get("completed", False)
        if isinstance(val, bool):
            return val
        if isinstance(val, (int, float)):
            return bool(val)
        if isinstance(val, str):
            return val.lower() in ("true", "1", "yes", "y")
        return False

    all_done = True
    for p in (wish.phases or []):
        tasks = p.get("tasks") or []
        if not isinstance(tasks, list):
            all_done = False
            break
        for t in tasks:
            if not _task_done(t):
                all_done = False
                break
        if not all_done:
            break

    # Update wish status + completed_at based on all_done
    if all_done:
        wish.status = WishStatus.completed
        # store as timezone-aware datetime object (DB DateTime column)
        wish.completed_at = datetime.now(timezone.utc)
    else:
        # clear completed_at when incomplete and set status back to in_progress
        wish.status = WishStatus.in_progress
        wish.completed_at = None

    db.add(wish)
    db.commit()
    db.refresh(wish)

    if not mark_incomplete:
        # generate item (unchanged behavior)
        wish_items = db.query(Item).filter(Item.origin_wish_id == wish_id).all()
        item = items.create_item_from_ai(db, wish.owner_id, wish.id, phase_title, task_title, wish_items, wish.title, client)
        return {"ok": True, "toast": "Nice — one more rune etched.", "item": item}
    else:
        return {"ok": True, "toast": "Nice — one more rune etched."}


@app.post("/api/wishes/{wish_id}/phases/{phase_id}/tasks")
def add_task(wish_id: str, phase_id: str, payload: TaskCreate, db: Session = Depends(get_db)):
    """
    Create a new task inside a specified phase.
    Body: { "title": str, "repeat": bool }
    Returns created task and the refreshed wish phases.
    """
    wish = db.query(Wish).filter(Wish.id == wish_id).first()
    if not wish:
        raise HTTPException(status_code=404, detail="Wish not found")

    phases = wish.phases or []
    target_phase = next((p for p in phases if p.get("id") == phase_id), None)
    if target_phase is None:
        raise HTTPException(status_code=404, detail="Phase not found")

    # Build normalized task dict (matching _normalize_task output)
    raw = {"title": payload.title, "repeat": bool(payload.repeat)}
    new_task = _normalize_task(raw)

    # Append and persist
    target_phase_tasks = target_phase.get("tasks", [])
    target_phase_tasks.append(new_task)
    target_phase["tasks"] = target_phase_tasks

    # persist phases and reload wish
    saved = _persist_wish_phases(db, wish, phases)

    return {
        "ok": True,
        "task": new_task,
        "wish": {"id": saved.id, "phases": saved.phases}
    }

@app.delete("/api/wishes/{wish_id}")
def delete_wish(wish_id: str, db: Session = Depends(get_db)):
    wish = db.query(Wish).filter(Wish.id == wish_id).first()
    if not wish:
        raise HTTPException(status_code=404, detail="Wish not found")
    db.delete(wish)
    db.commit()
    return {"ok": True}

@app.get("/api/vault")
def get_vault(user_id: str, db: Session = Depends(get_db)):
    items = db.query(Item).join(Wish, Item.origin_wish_id == Wish.id).filter(Wish.owner_id == user_id).all()
    return {"items": [ {"id":it.id, "origin_wish_id": it.origin_wish_id, "title": it.title, "emoji": it.emoji, "legendariness": it.legendariness, "emoji_accent": it.emoji_accent, "description": it.description, "created_at": it.created_at} for it in items ]}

@app.get("/api/users/{user_id}/should_nudge")
def should_nudge(user_id: str, db: Session = Depends(get_db)):
    # find last completed task timestamp across wishes
    latest = None
    wishes = db.query(Wish).filter(Wish.owner_id == user_id).all()
    for w in wishes:
        for p in w.phases or []:
            for t in p.get("tasks", []):
                ca = t.get("completed_at")
                if not ca:
                    continue
                # accept either ISO string or datetime object
                try:
                    if isinstance(ca, str):
                        dt = datetime.fromisoformat(ca)
                    elif isinstance(ca, datetime):
                        dt = ca
                    else:
                        # try to coerce to string then parse
                        dt = datetime.fromisoformat(str(ca))
                except Exception:
                    # ignore malformed timestamps
                    continue

                if latest is None or dt > latest:
                    latest = dt

    if latest is None:
        return {"should_nudge": True}
    if datetime.now(timezone.utc) - latest > timedelta(hours=48):
        return {"should_nudge": True}
    return {"should_nudge": False}

@app.get("/api/test_chatgpt")
def test_chatgpt():
    try:
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": "Say hello from the Wishnode server."}]
        )
        return {"reply": resp.choices[0].message.content}
    except Exception as e:
        return {"error": str(e)}
def _ensure_user_exists(db: Session, owner_id: str):
    user = db.query(User).filter(User.id == owner_id).first()
    if not user:
        user = User(id=owner_id, tier=Tier.anon)
        db.add(user)
        db.commit()
        db.refresh(user)
    return user

def _normalize_task(raw: Any) -> Dict:
    """
    Ensure a single task is a dict with 'title' (str), 'repeat' (bool),
    and stable 'id', 'completed', 'completed_at' fields.
    """
    if raw is None:
        raise ValueError("task is None")
    # simple string -> task
    if isinstance(raw, str):
        base = {"title": raw, "repeat": False}
    elif not isinstance(raw, dict):
        base = {"title": str(raw), "repeat": False}
    else:
        title = raw.get("title") or raw.get("text") or raw.get("name")
        if not title:
            raise ValueError("task missing title")
        repeat = bool(raw.get("repeat", False))
        # merge known fields but keep other keys intact
        base = {"title": str(title), "repeat": repeat}
        # carry over optional fields if present (text, hint, etc.)
        for optional in ("text", "hint", "notes", "habit_interval"):
            if optional in raw:
                base[optional] = raw[optional]

    # ensure stable id (use provided id if present, else generate new)
    base_id = None
    if isinstance(raw, dict):
        base_id = raw.get("id")
    if not base_id:
        base_id = str(uuid4())
    base["id"] = str(base_id)

     # completion metadata
    base["completed"] = bool(raw.get("completed", False)) if isinstance(raw, dict) else False
    base["completed_at"] = raw.get("completed_at") if isinstance(raw, dict) else None

    # ensure a repeated_amount field exists (server-side canonical field)
    # if caller provided something sensible, preserve it; otherwise default to 0
    try:
        base["repeated_amount"] = int(raw.get("repeated_amount", 0)) if isinstance(raw, dict) else 0
        if base["repeated_amount"] < 0:
            base["repeated_amount"] = 0
    except Exception:
        base["repeated_amount"] = 0

    return base

# before creating the Wish, ensure tasks have ids/completed metadata
def _ensure_task_ids_in_phases(phases):
    out = []
    for p in phases or []:
        p_copy = dict(p) if isinstance(p, dict) else {"title": str(p), "tasks": []}
        raw_tasks = p_copy.get("tasks") or []
        normalized_tasks = []
        for t in raw_tasks:
            # reuse the same _normalize_task helper to produce canonical tasks
            normalized_tasks.append(_normalize_task(t))
        p_copy["tasks"] = normalized_tasks
        # optionally preserve/assign phase id
        if not p_copy.get("id"):
            p_copy["id"] = str(uuid4())
        out.append(p_copy)
    return out

def _normalize_phase(raw: Any) -> Dict:
    """
    Ensure a phase is a dict with 'title' (str) and 'tasks' (list of normalized tasks).
    """
    if raw is None:
        raise ValueError("phase is None")
    if isinstance(raw, str):
        return {"title": raw, "tasks": []}
    if not isinstance(raw, dict):
        return {"title": str(raw), "tasks": []}
    title = raw.get("title") or raw.get("name")
    if not title:
        raise ValueError("phase missing title")
    raw_tasks = raw.get("tasks") or []
    if isinstance(raw_tasks, str):
        # try to parse JSON list if provided as a string
        try:
            parsed = json.loads(raw_tasks)
            raw_tasks = parsed
        except Exception:
            # fallback: split lines
            raw_tasks = [ln.strip() for ln in raw_tasks.splitlines() if ln.strip()]
    if not isinstance(raw_tasks, (list, tuple)):
        raise ValueError("phase.tasks must be a list")
    tasks = []
    for t in raw_tasks:
        tasks.append(_normalize_task(t))
    return {"title": str(title), "tasks": tasks}

@app.get("/api/users/{user_id}/wishes")
def list_user_wishes(user_id: str, db: Session = Depends(get_db)):
    """
    Return all wishes for a user with minimal fields for UI lists:
      [{ "id": "...", "title": "...", "status": "...", "deleted": False }, ...]
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    wishes = db.query(Wish).filter(Wish.owner_id == user_id).all()

    def _status_to_str(s):
        # Handle SQLAlchemy Enum-like objects or plain strings
        if s is None:
            return "unknown"
        if hasattr(s, "name"):
            return s.name
        if hasattr(s, "value"):
            return str(s.value)
        return str(s)

    return {
        "wishes": [
            {
                "id": w.id,
                "title": w.title,
                "status": _status_to_str(w.status),
                "deleted": bool(getattr(w, "deleted", False))
            }
            for w in wishes
        ]
    }

@app.post("/api/wishes/plan")
def api_get_plan(req: PlanRequest, db: Session = Depends(get_db)):
    """
    Generate a plan from human `req.wish` text, normalize it to the expected schema,
    and SAVE the resulting phases into a Wish row. Returns canonical saved wish + owner_id.
    Expected AI output shape:
      {
        "title": "string",
        "phases": [
          {
            "title": "string",
            "tasks": [{"title":"string", "repeat":false}]
          }
        ]
      }

    NOTE: owner_id is REQUIRED for predictability. The client must call /api/anon
    once and persist the anon id; plans cannot be created without that owner id.
    """
    try:
        # Enforce owner_id presence for predictability
        if not req.owner_id:
            raise HTTPException(
                status_code=400,
                detail="owner_id is required. Call /api/anon to obtain one and persist it on the client before requesting a plan."
            )

        # Fetch existing user; do NOT auto-create anon users here
        user = db.query(User).filter(User.id == req.owner_id).first()
        if not user:
            raise HTTPException(
                status_code=404,
                detail="owner_id not found. Call /api/anon to create an anonymous user first."
            )

        # 1) Call AI
        out = ai.get_plan_from_chatgpt(req.wish, client, model=MODEL)

        # Defensive JSON parsing if AI returns a JSON string
        if isinstance(out, str):
            try:
                out = json.loads(out)
            except Exception:
                # keep raw string -> below validation will handle heuristics
                pass

        if not isinstance(out, dict):
            # final attempt: if out is something else, raise helpful error
            raise RuntimeError("AI returned unexpected top-level type (expected dict)")

        # 2) Validate & normalize top level fields
        ai_title = out.get("title")

        raw_phases = out.get("phases")
        if raw_phases is None:
            # maybe the model placed steps/plan under other keys — try fallbacks
            for fallback in ("plan", "steps", "outline", "result"):
                if fallback in out:
                    candidate = out[fallback]

                    # If candidate is a dict that itself contains "phases" (the common "plan": {...} case),
                    # pull the inner phases list out. If candidate is already a list, use it directly.
                    if isinstance(candidate, dict) and "phases" in candidate and isinstance(candidate["phases"], (list, tuple)):
                        raw_phases = candidate["phases"]
                    elif isinstance(candidate, (list, tuple)):
                        raw_phases = candidate
                    else:
                        # otherwise fall back to the candidate itself (later normalization will try to coerce)
                        raw_phases = candidate
                    break

        # If phases is a JSON string, try parse
        if isinstance(raw_phases, str):
            try:
                raw_phases = json.loads(raw_phases)
            except Exception:
                # keep the string — normalization will attempt to split by lines
                pass

        if raw_phases is None:
            raise RuntimeError("AI returned no phases")

        # Now normalize: accept dict (wrap), list, or string forms
        normalized_phases = []
        if isinstance(raw_phases, dict):
            normalized_phases = [_normalize_phase(raw_phases)]
        elif isinstance(raw_phases, (list, tuple)):
            for p in raw_phases:
                normalized_phases.append(_normalize_phase(p))
        elif isinstance(raw_phases, str):
            # fallback: split lines into simple phase titles
            lines = [ln.strip() for ln in raw_phases.splitlines() if ln.strip()]
            if not lines:
                raise RuntimeError("AI returned phases as an unparseable string")
            for ln in lines:
                normalized_phases.append({"title": ln, "tasks": []})
        else:
            raise RuntimeError(f"AI returned phases in an unexpected format (type={type(raw_phases).__name__})")

        # 4) Enforce active-wish limit if creating new
        wish_obj = None
        if req.wish_id:
            wish_obj = db.query(Wish).filter(Wish.id == req.wish_id).first()

        creating_new = wish_obj is None
        if creating_new and user.tier != Tier.pro and active_wish_count(db, user.id) >= FREE_ACTIVE_WISH_LIMIT:
            raise HTTPException(status_code=403, detail="Free limit reached. Delete/complete an active wish to continue.")

        # 5) Create or update the Wish
        now = datetime.now(timezone.utc)
        if wish_obj:
            wish = _persist_wish_phases(db, wish_obj, normalized_phases)
            # prefer AI title > request title > truncated wish text
            if ai_title:
                wish.title = ai_title
            elif req.title:
                wish.title = req.title
            db.add(wish)
            db.commit()
            db.refresh(wish)
            saved = wish
            created = False
        else:
            wish_id = req.wish_id or str(uuid4())
            # pick title: AI title > req.title > truncated req.wish
            chosen_title = ai_title or req.title or (req.wish[:80] + ("..." if len(req.wish) > 80 else ""))
            normalized_phases = _ensure_task_ids_in_phases(normalized_phases)
            new = Wish(
                id=wish_id,
                owner_id=user.id,
                title=chosen_title,
                phases=normalized_phases,
                status=WishStatus.in_progress,
                created_at=now,
                deleted=False
            )
            db.add(new)
            db.commit()
            db.refresh(new)
            saved = new
            created = True

        # 6) Return canonical saved wish and owner id
        return {
            "ok": True,
            "created": created,
            "wish": {
                "id": saved.id,
                "owner_id": saved.owner_id,
                "title": saved.title,
                "phases": saved.phases,
                "status": saved.status,
                "created_at": saved.created_at,
            },
            "owner_id": user.id
        }

    except HTTPException:
        raise
    except FileNotFoundError as e:
        print("FileNotFoundError in /api/wishes/plan:", str(e))
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Server misconfiguration (missing file).")
    except Exception as e:
        # Log truncated raw AI output & stacktrace to aid debugging
        print("Unhandled exception in /api/wishes/plan:", str(e))
        try:
            print("Raw AI output (truncated):", json.dumps(out)[:2000])
        except Exception:
            try:
                print("Raw AI output (repr):", repr(out)[:2000])
            except Exception:
                pass
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Plan generation failed, check server logs for details.")

@app.get("/api/test_chatgpt_pipeline")
def test_chatgpt_pipeline():
    # A dummy wish for testing the full plan pipeline
    test_wish = "I want to get in shape and run a 5km race."

    try:
        out = ai.get_plan_from_chatgpt(test_wish, client, model=MODEL)
        return {
            "ok": True,
            "used_dummy_wish": test_wish,
            "result": out
        }
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

@app.delete("/api/wishes/{wish_id}/tasks/{task_id}")
def delete_task(wish_id: str, task_id: str, db: Session = Depends(get_db)):
    """
    Remove a single task from a wish's phases JSON.
    Returns 200 {"ok": True} on success or 404/5xx on failure.
    """
    wish = db.query(Wish).filter(Wish.id == wish_id).first()
    if not wish:
        raise HTTPException(status_code=404, detail="Wish not found")

    phases = wish.phases or []
    found = False

    # find & remove
    for p in phases:
        tasks = p.get("tasks", [])
        idx = next((i for i, t in enumerate(tasks) if t.get("id") == task_id), None)
        if idx is not None:
            # remove the task from this phase
            tasks.pop(idx)
            p["tasks"] = tasks
            found = True
            break

    if not found:
        raise HTTPException(status_code=404, detail="Task not found")

    # persist and return fresh wish
    saved = _persist_wish_phases(db, wish, phases)
    return {"ok": True, "wish": {"id": saved.id, "phases": saved.phases}}

@app.patch("/api/wishes/{wish_id}/tasks/{task_id}")
def edit_task(wish_id: str, task_id: str, payload: TaskEdit, db: Session = Depends(get_db)):
    """
    Update a task's editable fields (title, repeat, ...).
    Accepts JSON body with { "title": "...", "repeat": true/false }.
    Returns the updated wish phases for convenience.
    """
    wish = db.query(Wish).filter(Wish.id == wish_id).first()
    if not wish:
        raise HTTPException(status_code=404, detail="Wish not found")

    phases = wish.phases or []
    found = False

    for p in phases:
        for t in p.get("tasks", []):
            if t.get("id") == task_id:
                # apply edits
                if payload.title is not None:
                    t["title"] = str(payload.title)
                if payload.repeat is not None:
                    t["repeat"] = bool(payload.repeat)
                # optionally keep existing completed/completed_at untouched
                found = True
                break
        if found:
            break

    if not found:
        raise HTTPException(status_code=404, detail="Task not found")

    # persist and return fresh wish
    saved = _persist_wish_phases(db, wish, phases)
    return {"ok": True, "wish": {"id": saved.id, "phases": saved.phases}}

