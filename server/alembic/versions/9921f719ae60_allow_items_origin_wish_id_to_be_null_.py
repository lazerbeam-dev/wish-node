"""allow items.origin_wish_id to be null on wish delete

Revision ID: 9921f719ae60
Revises: 5142827a66bc
Create Date: 2025-12-19 23:51:42.761250

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9921f719ae60'
down_revision: Union[str, Sequence[str], None] = '5142827a66bc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


from alembic import op
import sqlalchemy as sa

def upgrade():
	# 1. Drop existing FK
	op.drop_constraint(
		"items_origin_wish_id_fkey",
		"items",
		type_="foreignkey",
	)

	# 2. Make column nullable
	op.alter_column(
		"items",
		"origin_wish_id",
		existing_type=sa.Integer(),
		nullable=True,
	)

	# 3. Recreate FK with ON DELETE SET NULL
	op.create_foreign_key(
		"items_origin_wish_id_fkey",
		"items",
		"wishes",
		["origin_wish_id"],
		["id"],
		ondelete="SET NULL",
	)

def downgrade():
	# reverse if needed
	op.drop_constraint(
		"items_origin_wish_id_fkey",
		"items",
		type_="foreignkey",
	)

	op.alter_column(
		"items",
		"origin_wish_id",
		existing_type=sa.Integer(),
		nullable=False,
	)

	op.create_foreign_key(
		"items_origin_wish_id_fkey",
		"items",
		"wishes",
		["origin_wish_id"],
		["id"],
	)
