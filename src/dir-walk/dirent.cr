require "file"

module Dir::Walk
  enum SortMode : UInt32
    SortNone       = 0
    SortLexical    = 1
    SortFilesFirst = 2
    SortDirsFirst  = 3

    def to_s(io : IO) : Nil
      io << string_repr
    end

    def to_s : String
      string_repr
    end

    private def string_repr : String
      case self
      when SortNone       then "None"
      when SortLexical    then "Lexical"
      when SortFilesFirst then "FilesFirst"
      when SortDirsFirst  then "DirsFirst"
      else                     "SortMode(#{value})"
      end
    end
  end

  def self.default_num_workers : Int32
    num_cpu = System.cpu_count
    return 4 if num_cpu < 4
    {% if flag?(:darwin) %}
      case num_cpu
      when .<= 8  then 4
      when .<= 10 then 6
      else             10
      end
    {% else %}
      num_cpu > 32 ? 32 : num_cpu
    {% end %}
  end

  def self.default_to_slash : Bool
    {% if flag?(:win32) %}
      ENV.has_key?("MSYSTEM")
    {% else %}
      false
    {% end %}
  end

  class Config
    property follow : Bool
    property to_slash : Bool
    property num_workers : Int32
    property sort : SortMode
    property max_depth : Int32
    property ignore : Bool
    property ignore_opts : Ignore::IgnoreOptions
    property overrides : Ignore::Override?

    def initialize(
      @follow : Bool = false,
      to_slash : Bool? = nil,
      num_workers : Int32? = nil,
      @sort : SortMode = SortMode::SortNone,
      @max_depth : Int32 = 0,
      @ignore : Bool = false,
      @ignore_opts : Ignore::IgnoreOptions = Ignore::IgnoreOptions.new,
      @overrides : Ignore::Override? = nil,
    )
      @to_slash = to_slash.nil? ? Dir::Walk.default_to_slash : to_slash
      @num_workers = num_workers.nil? ? Dir::Walk.default_num_workers : num_workers
    end

    def copy : Config
      Config.new(follow: @follow, to_slash: @to_slash, num_workers: @num_workers,
        sort: @sort, max_depth: @max_depth, ignore: @ignore, ignore_opts: @ignore_opts,
        overrides: @overrides)
    end
  end

  class Error < Exception; end

  class ErrSkipDir < Error; end

  class ErrSkipFiles < Error; end

  class ErrTraverseLink < Error; end

  struct DirEntry
    getter parent : String
    getter name : String
    getter entry_type : File::Type
    getter depth : Int32

    @info : File::Info?
    @stat : File::Info?
    @info_loaded : Bool
    @stat_loaded : Bool

    def initialize(@parent, @name, @entry_type, @depth)
      @info = nil; @stat = nil; @info_loaded = false; @stat_loaded = false
    end

    def dir?
      @entry_type.directory?
    end

    def file?
      @entry_type.file?
    end

    def symlink?
      @entry_type.symlink?
    end

    def type
      @entry_type
    end

    def info : File::Info
      unless @info_loaded
        @info = File.info(path, follow_symlinks: false)
        @info_loaded = true
      end
      @info.not_nil!
    end

    def stat : File::Info
      if symlink?
        unless @stat_loaded
          @stat = File.info(path, follow_symlinks: true)
          @stat_loaded = true
        end
        @stat.not_nil!
      else
        info
      end
    rescue File::NotFoundError
      info
    end

    def path : String
      if @parent.ends_with?('/') || @parent.ends_with?('\\')
        @parent + @name
      else
        {@parent, @name}.join(File::SEPARATOR)
      end
    end
  end
end
