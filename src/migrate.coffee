yaml = require 'js-yaml'
fs = require 'fs'
pgfibers = require 'pg-fibers'
Future = require 'fibers/future'
fs = require 'fs'
_ = require 'underscore'
path = require 'path'
cwd = process.cwd

class Migration
  
  constructor: (file) ->
    dir = path.dirname(file)
    @filename = path.basename(file)
    @path = path.join(path.relative(__dirname, dir), @filename)
    
  up: (db) =>
    require(@path).up(db)
    db.query("insert into migrations(filename) values($1)", [@filename])
    
  down: (db) =>    
    require(@path).down(db)
    db.query("delete from migrations where filename = $1", [@filename])

module.exports = class Migrate

  constructor: (@options) ->
    
    @dbconfig = require(@options.config || path.join(process.cwd(), 'config/database.yml'))
    
    @env = @options.env || process.env.NODE_ENV || 'development'
    
    @db = pgfibers.connect(@dbconfig[@env])
    
    @path = path.join(cwd(), @options.migrations || './migrations')
    
    @init()

  query: (query, args) =>
    @db.query(query, args || null).rows

  init: =>
    sql = """
    CREATE TABLE IF NOT EXISTS migrations (
      id serial primary key,
      filename varchar,
      run_at timestamp default NOW()
    );
    """
    @query(sql)
    
  sort: (migrations) =>
    migrations.sort (x, y) -> x.filename.localeCompare(y.filename)
    
  available: =>    
    @_available ||= @sort(new Migration(path.join(@path, f)) for f in (fs.readdirSync(@path)))
    
  finished: =>
    @_finished = @sort(new Migration(path.join(@path, r.filename)) for r in @query("select filename from migrations"))   
    
  unfinished: =>
    @_unfinished ||= _.difference(@available(), @finished())

  transaction: (cb) =>
    @query 'BEGIN'
    try
      cb()
      @query 'COMMIT'
    catch e
      @query 'ROLLBACK'
      throw e
    
  up: (steps = null) =>
    targets = @available()
    targets = targets.slice(0, steps) if steps
    
    @transaction =>
      for m in targets
        m.up(@db)
            
  down: (steps) =>
    @transaction =>
      for m in @finished().reverse().slice(0, steps || 1)
        m.down(@db)