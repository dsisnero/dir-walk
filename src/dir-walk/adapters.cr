require "file"
require "./dirent"

module Dir::Walk
  def self.ignore_permission_errors(walk_fn : WalkFunc) : WalkFunc
    ->(path : String, de : DirEntry?, err : Exception?) {
      return if err && err.is_a?(File::AccessDeniedError)
      walk_fn.call(path, de, err)
    }
  end

  def self.ignore_duplicate_dirs(walk_fn : WalkFunc) : WalkFunc
    filter = EntryFilter.new
    ->(path : String, de : DirEntry?, err : Exception?) {
      walk_fn.call(path, de, err)
      if de && dir_entry_directory?(path, de)
        if filter.entry(path, de)
          raise ErrSkipDir.new
        end
        raise ErrTraverseLink.new if de.symlink?
      end
    }
  end

  def self.ignore_duplicate_files(walk_fn : WalkFunc) : WalkFunc
    filter = EntryFilter.new
    ->(path : String, de : DirEntry?, err : Exception?) {
      if de
        if filter.entry(path, de)
          raise ErrSkipDir.new if dir_entry_directory?(path, de)
          return
        end
        walk_fn.call(path, de, err)
        raise ErrTraverseLink.new if de.symlink? && dir_entry_directory?(path, de)
      end
    }
  end

  private def self.dir_entry_directory?(path, de) : Bool
    de.dir? || (de.symlink? && File.info?(path, follow_symlinks: true).try(&.directory?))
  end

  def self.stat_dir_entry(path : String, de : DirEntry) : File::Info
    de.symlink? ? de.stat : de.info
  rescue File::NotFoundError
    de.info
  end

  def self.dir_entry_depth(de : DirEntry) : Int32
    de.depth
  end

  class EntryFilter
    @seen : Array(File::Info)

    def initialize
      @seen = [] of File::Info
    end

    def entry(path, de)
      fi = de.info
      return true if @seen.any?(&.same_file?(fi))
      @seen << fi; false
    rescue File::NotFoundError
      false
    end
  end
end
