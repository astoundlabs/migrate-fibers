yaml = require 'js-yaml'
fs = require 'fs'
pgfibers = require 'pg-fibers'
Future = require 'fibers/future'
fs = require 'fs'
_ = require 'underscore'
path = require 'path'
cwd = process.cwd
exec = require('child_process').exec

class Migration
  
  constructor: (file, @options = {}) ->
    dir = path.dirname(file)
    @filename = path.basename(file)
    @path = path.join(path.relative(__dirname, dir), @filename)
    
  up: (db) =>
    m = require(@path)
    if m.up?
      console.log "up #{@filename}" unless @options?.quiet
      require(@path).up(db)
      db.query("insert into migrations(filename) values($1)", [@filename])
    
  down: (db) =>       
    m = require(@path)
    if m.down?
      console.log "down #{@filename}" unless @options?.quiet
      m.down(db)
      db.query("delete from migrations where filename = $1", [@filename])

module.exports = class Migrate

  constructor: (@options) ->
    
    @dbconfig = require(@options.config || path.join(process.cwd(), 'config/database.yml'))
    
    @env = @options.env || process.env.NODE_ENV || 'development'    
    
    @path = path.join(cwd(), @options.migrations || './migrations')    

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
    @_available ||= @sort(new Migration(path.join(@path, f), {quiet: @options?.quiet}) for f in (fs.readdirSync(@path)))
    
  finished: =>
    @_finished = @sort(new Migration(path.join(@path, r.filename), {quiet: @options?.quiet}) for r in @query("select filename from migrations"))   
    
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
    @db = pgfibers.connect(@dbconfig[@env])
    @init()
    
    targets = @available()
    targets = targets.slice(0, steps) if steps
    
    @transaction =>
      for m in targets
        m.up(@db)
            
  down: (steps) =>
    @db = pgfibers.connect(@dbconfig[@env])
    @init()
    
    @transaction =>
      for m in @finished().reverse().slice(0, steps || 1)
        m.down(@db)

  create: (name, ext = 'coffee') =>
    unless fs.existsSync(@path)
      fs.mkdirSync(@path) 
    
    timestamp = Date.now()
    filename = "#{timestamp}-#{name}.#{ext}"
    fullpath = path.join(@path, filename)
    f = new Future
    exec "touch #{fullpath}", f.resolver()
    f.wait()    
    filename
    