exports.up = (db) ->
  db.query "insert into foo(name) values ('bar');"