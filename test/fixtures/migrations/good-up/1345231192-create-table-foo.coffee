exports.up = (db) ->
  db.query """
    create table foo(
      id serial primary key,
      name text
    );
  """