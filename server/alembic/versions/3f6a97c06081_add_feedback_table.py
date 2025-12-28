from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "3f6a97c06081"
down_revision = "5142827a66bc"
branch_labels = None
depends_on = None

def upgrade():
	op.create_table(
		"feedback",
		sa.Column("id", sa.String(), primary_key=True),
		sa.Column("user_id", sa.String(), nullable=True),
		sa.Column("text", sa.Text(), nullable=False),
		sa.Column(
			"source",
			sa.String(length=32),
			nullable=True,
		),
		sa.Column("user_agent", sa.Text(), nullable=True),
		sa.Column("path", sa.Text(), nullable=True),
		sa.Column(
			"created_at",
			sa.DateTime(timezone=True),
			nullable=False,
			server_default=sa.text("now()"),
		),
	)


def downgrade():
	op.drop_table("feedback")
