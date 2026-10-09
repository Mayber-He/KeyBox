from sqlalchemy import Boolean, Column, ForeignKey, Integer, MetaData, String, Table, Text

metadata = MetaData()
accounts = Table('accounts', metadata,
    Column('id', String, primary_key=True), Column('username', String, unique=True, nullable=False),
    Column('password_hash', String, nullable=False), Column('created_at', Integer, nullable=False))
devices = Table('devices', metadata,
    Column('id', String, primary_key=True), Column('account_id', ForeignKey('accounts.id'), nullable=False),
    Column('name', String, nullable=False), Column('created_at', Integer, nullable=False),
    Column('last_seen', Integer, nullable=False), Column('revoked', Boolean, nullable=False))
tokens = Table('tokens', metadata,
    Column('hash', String, primary_key=True), Column('device_id', ForeignKey('devices.id'), nullable=False),
    Column('kind', String, nullable=False), Column('expires_at', Integer, nullable=False),
    Column('used', Boolean, nullable=False))
login_attempts = Table('login_attempts', metadata,
    Column('key', String, primary_key=True), Column('started_at', Integer, nullable=False),
    Column('failures', Integer, nullable=False))
vault_metadata = Table('vault_metadata', metadata,
    Column('account_id', ForeignKey('accounts.id'), primary_key=True),
    Column('version', Integer, nullable=False), Column('payload', Text, nullable=False))
items = Table('items', metadata,
    Column('account_id', ForeignKey('accounts.id'), primary_key=True), Column('id', String, primary_key=True),
    Column('version', Integer, nullable=False), Column('deleted', Boolean, nullable=False),
    Column('payload', Text), Column('updated_at', Integer, nullable=False))
operations = Table('operations', metadata,
    Column('account_id', ForeignKey('accounts.id'), primary_key=True), Column('id', String, primary_key=True),
    Column('request_hash', String, nullable=False), Column('response', Text, nullable=False))

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    from alembic import op
    metadata.create_all(op.get_bind())


def downgrade():
    from alembic import op
    metadata.drop_all(op.get_bind())
