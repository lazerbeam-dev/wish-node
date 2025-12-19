from sqlalchemy import create_engine, text
from dotenv import load_dotenv 
import os
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
	raise RuntimeError("DATABASE_URL must be set (Postgres only)")

engine = create_engine(
	DATABASE_URL,
	pool_pre_ping=True,
	future=True,
)

table_name = "items"
with engine.begin() as conn:
	conn.execute(text("""
		ALTER TABLE {table_name}
		ADD COLUMN IF NOT EXISTS core_id TEXT
	""".format(table_name= table_name)))

	# conn.execute(text("""
	# 	ALTER TABLE users
	# 	ADD COLUMN IF NOT EXISTS password_hash TEXT
	# """))

	# conn.execute(text("""
	# 	ALTER TABLE users
	# 	ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user'
	# """))

	print("{table_name} table updated successfully.".format(table_name =table_name))

    # 2) Add emoji_accent column
    # if "emoji_accent" in cols:
    #     print("Column 'emoji_accent' already exists.")
    # else:
    #     try:
    #         conn.execute(
    #             text(
    #                 "ALTER TABLE items ADD COLUMN emoji_accent TEXT NOT NULL DEFAULT '✨';"
    #             )
    #         )
    #         print("Added 'emoji_accent' column.")
    #     except OperationalError as e:
    #         print("Failed to add emoji_accent column:", e)