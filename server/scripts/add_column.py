from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./dev.db")
# For sqlite, need uri=False
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})

with engine.connect() as conn:
    # Inspect existing columns on items table
    res = conn.execute(text("PRAGMA table_info(items);")).mappings().all()
    cols = [r["name"] for r in res]

    # 1) Add emoji column
    if "emoji" in cols:
        print("Column 'emoji' already exists.")
    else:
        try:
            conn.execute(
                text(
                    "ALTER TABLE items ADD COLUMN emoji TEXT NOT NULL DEFAULT '🍕';"
                )
            )
            print("Added 'emoji' column.")
        except OperationalError as e:
            print("Failed to add emoji column:", e)

    # 2) Add emoji_accent column
    if "emoji_accent" in cols:
        print("Column 'emoji_accent' already exists.")
    else:
        try:
            conn.execute(
                text(
                    "ALTER TABLE items ADD COLUMN emoji_accent TEXT NOT NULL DEFAULT '✨';"
                )
            )
            print("Added 'emoji_accent' column.")
        except OperationalError as e:
            print("Failed to add emoji_accent column:", e)