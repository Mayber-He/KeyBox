from alembic import context

config = context.config
context.configure(connection=config.attributes['connection'], target_metadata=None)
with context.begin_transaction():
    context.run_migrations()
