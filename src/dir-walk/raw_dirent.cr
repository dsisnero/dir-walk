{% unless flag?(:win32) %}
  require "c/dirent"
{% end %}

# POSIX/BSD d_type values (standardized across Linux, macOS, BSD)
module Dir::Walk
  private DT_UNKNOWN =  0_u8
  private DT_FIFO    =  1_u8
  private DT_CHR     =  2_u8
  private DT_DIR     =  4_u8
  private DT_BLK     =  6_u8
  private DT_REG     =  8_u8
  private DT_LNK     = 10_u8
  private DT_SOCK    = 12_u8
  private DT_WHT     = 14_u8

  private def self.dt_to_type(d_type : UInt8) : File::Type
    case d_type
    when DT_DIR  then File::Type::Directory
    when DT_REG  then File::Type::File
    when DT_LNK  then File::Type::Symlink
    when DT_BLK  then File::Type::BlockDevice
    when DT_CHR  then File::Type::CharacterDevice
    when DT_FIFO then File::Type::Pipe
    when DT_SOCK then File::Type::Socket
    else              File::Type::Unknown
    end
  end

  # Reads directory entries using raw LibC.readdir for maximum speed.
  # Yields (name : String, entry_type : File::Type) for each entry.
  # Skips "." and ".." and zero-inode entries (deleted files on macOS).
  def self.raw_read_dir(dir_path : String, & : String, File::Type ->) : Nil
    {% if flag?(:win32) %}
      # Windows has no POSIX dirent API. Let the walker resolve each entry's
      # type with its existing lstat fallback.
      Dir.each_child(dir_path) do |name|
        yield name, File::Type::Unknown
      end
    {% else %}
    dir = LibC.opendir(dir_path.check_no_null_byte)
    unless dir
      raise File::Error.from_errno("Error opening directory", file: dir_path)
    end

    begin
      Errno.value = Errno::NONE
      while entry = LibC.readdir(dir)
        ent = entry.value

        # Skip entries with zero inode (deleted but not yet removed on macOS/BSD)
        {% if flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) || flag?(:netbsd) %}
          next if ent.d_ino == 0
        {% end %}

        name_ptr = ent.d_name.to_unsafe

        # Fast path: skip "." and ".." without string allocation
        if name_ptr[0] == '.'.ord
          if name_ptr[1] == 0_u8
            next # "."
          elsif name_ptr[1] == '.'.ord && name_ptr[2] == 0_u8
            next # ".."
          end
        end

        name = String.new(name_ptr)
        d_type = ent.d_type
        type = dt_to_type(d_type)

        yield name, type

        Errno.value = Errno::NONE
      end

      if Errno.value != Errno::NONE
        raise File::Error.from_errno("Error reading directory entries", file: dir_path)
      end
    ensure
      LibC.closedir(dir)
    end
    {% end %}
  end
end
