from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")
# For sqlite, need uri=False
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})

with engine.connect() as conn:
    # check if column exists
    res = conn.execute(text("PRAGMA table_info(wishes);")).mappings().all()
    cols = [r['name'] for r in res]
    if 'deleted' in cols:
        print("Column 'deleted' already exists.")
    else:
        try:
            conn.execute(text("ALTER TABLE wishes ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;"))
            print("Added 'deleted' column.")
        except OperationalError as e:
            print("Failed to ALTER TABLE:", e)
