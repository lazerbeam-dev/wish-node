# server/alembic/env.py
import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

# make project root importable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

config = context.config

# read DB URL from env (fallback to sqlite)
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://wishnode:pass@localhost:5432/wishnode")
config.set_main_option("sqlalchemy.url", DATABASE_URL)

fileConfig(config.config_file_name)

# Import your app's SQLAlchemy Base here.
# If your models.py is in this folder, the import below is correct.
# If your Base is in a package (e.g., `app.models`), change the import accordingly.
try:
    from models import Base
except Exception as e:
    raise RuntimeError("Could not import Base from models.py. Edit alembic/env.py import. Original error: " + str(e))

target_metadata = Base.metadata

def run_migrations_offline():
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True, compare_type=False,
	compare_server_default=False,)
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online():
    connectable = engine_from_config(config.get_section(config.config_ini_section), prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, compare_type=False, compare_server_default=False)
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
