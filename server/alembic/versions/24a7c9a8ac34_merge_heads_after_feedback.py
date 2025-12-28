"""merge heads after feedback

Revision ID: 24a7c9a8ac34
Revises: 9921f719ae60, 3f6a97c06081
Create Date: 2025-12-28 10:16:33.074205

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '24a7c9a8ac34'
down_revision: Union[str, Sequence[str], None] = ('9921f719ae60', '3f6a97c06081')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
