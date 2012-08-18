Migrate = require '../lib/migrate'
child_process = require('child_process')
Future = require 'fibers/future'
yaml = require('js-yaml')
settings = require('../config/database.yml').test
pgfibers = require 'pg-fibers'
should = require 'should'
pg = require 'pg'
path = require 'path'
fs = require 'fs'


exec = (cmd) ->
  f = new Future
  child_process.exec cmd, (err, stdout, stderr) ->
    if err
      f.throw(err)
    else
      f.return([stdout, stderr])
  f.wait()

gettables = (db) ->
  (r.tablename for r in db.query("select tablename from pg_tables").rows)  

before ->
  try
    exec("PGPASSWORD=#{settings.password} dropdb -U #{settings.user} #{settings.database}")
  catch e
    #pass

  exec("PGPASSWORD=#{settings.password} createdb -U #{settings.user} -O #{settings.user} #{settings.database}")
  @db = pgfibers.connect(settings)


describe 'Migrate', ->

  beforeEach ->
    @db.query("drop table if exists foo")
    @db.query("drop table if exists bar")
    @db.query("drop table if exists migrations")
      
  describe 'up', ->
      
    describe 'that succeeds', ->

      beforeEach ->
        @migrate = new Migrate
          migrations: './test/fixtures/migrations/good-up'

      it 'should run unrun migrations', ->
        @migrate.up()
        @db.query("select count(*) from foo").rows[0].count.should.eql 1

      it 'should run migrations in alphabetical order', ->
        @migrate.up()
        run = @db.query("select id, filename from migrations").rows
        byFilename = run.sort((x, y) -> x.filename.localeCompare(y.filename.localeCompare))
        byId = run.sort((x,y) -> parseInt(x) - parseInt(y))
        byFilename.should.eql byId


      it 'should add migration to migration table', ->
        @migrate.up()
        @db.query("select count(*) from migrations").rows[0].count.should.eql 2        

      it 'if steps are specified, should only run specified number of migrations', ->
        @migrate.up(1)
        @db.query("select count(*) from migrations").rows[0].count.should.eql 1

    describe 'that fails', ->
      beforeEach ->
        @migrate = new Migrate
          migrations: './test/fixtures/migrations/bad-up'
        try          
          @migrate.up()
        catch e
          #pass

      it 'should rollback changes', ->
        tables = gettables(@db)
        tables.should.not.include('foo')

      it 'should not add migration to migration table', ->
        @db.query("select count(*) from migrations").rows[0].count.should.eql 0              

  describe 'down', ->
    
    describe 'that succeeds', ->
      beforeEach ->
        @migrate = new Migrate
          migrations: './test/fixtures/migrations/good-down'
              
      it 'should execute down on already executed migrations', ->
        @migrate.up(1)
        @migrate.down(1)
        tables = gettables(@db)
        tables.should.not.include 'foo'
      
      it 'should run migration in reverse alphabetical order', ->
        @migrate.up()
        @migrate.down(1)
        tables = gettables(@db)        
        tables.should.include 'foo'
        tables.should.not.include 'bar'
        
      it 'should only execute specified number of steps', ->
        @migrate.up()
        @migrate.down(1)
        tables = gettables(@db)
        tables.should.include 'foo'
        tables.should.not.include 'bar'
        
      it 'should remove migrations from migration table', ->
        @migrate.up()        
        @migrate.down(1)
        @db.query("select count(*) from migrations").rows[0].count.should.eql 1
      
    describe 'that fails', ->
      beforeEach ->
        @migrate = new Migrate
          migrations: './test/fixtures/migrations/bad-down'      
        @migrate.up()
        try
          @migrate.down(2)
        catch e
          # pass
                        
      it 'should rollback changes', ->          
        tables = gettables(@db)
        tables.should.include 'bar'        
        
      it 'should not remove migrations from table', ->
        @db.query("select count(*) from migrations").rows[0].count.should.eql 2

  describe 'constructor', ->
    it 'should connect to db based on environment', ->
      (=>
        @migrate = new Migrate
          migrations: './test/fixtures/migrations/good-down'
          env: 'development'
        @migrate.up()
      ).should.throw()
      
  describe 'create', ->
    beforeEach ->
      @migrate = new Migrate
        migrations: './test/tmp'
      @filename = @migrate.create('foo')

    afterEach ->
      fs.unlinkSync(path.join('./test/tmp', @filename))
      
    it 'should create filename with timestamp', ->
      parseInt(@filename.split('-')[0], 10).should.be.within(Date.now() - 100, Date.now() + 100)

    it 'should create a filename with name', ->
      @filename.replace('.coffee', '').split('-').should.include 'foo'

    it 'should create file in migration directory', ->
      fs.existsSync(path.join('./test/tmp', @filename))