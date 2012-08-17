exports.up = (db) ->
  db.query "create table bar(id serial primary key)"

exports.down = (db) ->
  db.query "drop table bar"