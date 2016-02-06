require 'digest'
require 'base64'
require 'yaml'
require 'find'
require 'optparse'

class RSUtils

  attr_reader :path
  attr_accessor :client, :version, :current, :firstrun
  
  def initialize(path)
    @filehashfilepath = File.join(path,'.filehashes')
    @inserturifilepath = File.join(path,'.inserturi')
    @ourifilepath = File.join(path,'.uri')
    @path = path
    @current ={}
    @version = 0
    @firstrun = false
    directory_hash
  end
  
  def clear_current
    @current = {}
  end
  
  def directory_hash
    Find.find(@path) do |p|
      Find.prune if File.split(p)[1][0] == '.'
      unless File.directory? p
        unless (p.include? @inserturifilepath or p.include? @filehashfilepath) or p.include? @ourifilepath
          @current[(Digest::SHA256.new << File.read(p)).base64digest] = p
        end
      end
    end
  end

  def files_to_update
    last = YAML::load(File.read(@filehashfilepath)) unless @firstrun
    @version = last[0] if @version == 0 unless @firstrun
    if @firstrun
      @current.keys
    else
      @current.keys - last[1].keys
    end
  end
  
  def save_uris(uri,ouri)
    File.open(@inserturifilepath, 'w+') do |file|
      file.puts YAML::dump uri
    end
    File.open(@ourifilepath, 'w+') do |file|
      file.puts YAML::dump ouri
    end
  end 
   
  def serialize
    File.open(@filehashfilepath, 'w+') do |file|
      file.puts YAML::dump [@version, @current]
    end
    puts 'hashes stored in .filehashes'
  end
  
  def update
    if File.exist? @filehashfilepath
      updateables = files_to_update
      return updateables
    else
      puts "Perform full upload to initialize the directory for use"
      if @firstrun
        updateables = files_to_update
        return updateables
      else
        return []
      end
    end
  end
  
  def twopart_upload
    largerfiles = []
    @current.each_key do |u|
      if (File.size @current[u]) > 1048576
        largerfiles << u
      end
    end
    largerfiles
  end
  
  def format_file_list(updateable,uri)
    files = []
    unless updateable.size == 0
      updateable.each do |u|
        name = @current[u].sub @path, ''
        name.sub! '\\' '/' if File::SEPARATOR == '\\'
        name = name[1..-1] if name[0] == '/'
        file = {name: name, uploadfrom: 'disk', filename: @current[u]} unless @current[u] =~ /^CHK@/
        file = {name: @current[u].split('/')[-1], uploadfrom: 'redirect', targeturi: @current[u]} if @current[u] =~ /^CHK@/
        files.push file
      end
    end
    unless files.size == 0
      (@current.keys - updateable).each do |u|
        name = @current[u].sub @path, ''
        name.sub! '\\' '/' if File::SEPARATOR == '\\'
        name = name[1..-1] if name[0] == '/'
        ssk = uri.split '@'
        ssk = 'SSK@'+(ssk[1].split('/')[0...-1].join('/'))+"-#{@version}/"+name
        file = {name: name, uploadfrom: 'redirect', targeturi: ssk}
        file = {name: @current[u].split('/')[-1], uploadfrom: 'redirect', targeturi: @current[u]} if @current[u] =~ /^CHK@/
        files.push file
      end
    end
    files
  end

end

