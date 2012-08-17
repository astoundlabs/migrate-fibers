exports.up = (db) ->
  db.query "create table foo(id serial primary key)"

exports.down = (db) ->
  db.query "create fooz"