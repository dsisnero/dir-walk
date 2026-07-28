module Dir::Walk::Ignore
  struct Glob
    getter from : String?
    getter original : String
    getter actual : String
    getter is_whitelist : Bool
    getter is_only_dir : Bool

    def initialize(@from : String? = nil, @original : String = "",
                   @actual : String = "", @is_whitelist : Bool = false,
                   @is_only_dir : Bool = false)
    end

    def has_doublestar_prefix? : Bool
      @actual.starts_with?("**/") || @actual == "**"
    end
  end

  class Gitignore
    getter root : String
    getter globs : Array(Glob)

    def initialize(@root : String = "", @globs : Array(Glob) = [] of Glob)
    end

    def self.empty : self
      new
    end

    def empty? : Bool
      @globs.empty?
    end

    def matched(path : String, is_dir : Bool) : Match
      return Match.none if empty?

      candidate = strip_root(path)
      candidate = candidate.starts_with?("./") ? candidate[2..] : candidate

      best = Match.none

      @globs.each do |glob|
        if glob.is_only_dir && !is_dir
          next
        end

        if matches_glob?(candidate, glob.actual)
          if glob.is_whitelist
            best = Match.whitelist
          else
            best = Match.ignore
          end
        end
      end

      best
    end

    private def strip_root(path : String) : String
      return path if @root.empty? || @root == "."
      return path if PathUtil.file_name?(path)
      prefix = @root.rstrip('/').rstrip('\\')
      if path.starts_with?(prefix)
        rest = path[prefix.size..]
        rest = rest.lstrip('/').lstrip('\\')
        return rest.empty? ? "." : rest
      end
      path
    end

    private def matches_glob?(candidate : String, pattern : String) : Bool
      File.match?(pattern, candidate)
    end
  end

  class GitignoreBuilder
    getter root : String
    getter globs : Array(Glob)
    property case_insensitive : Bool
    property allow_unclosed_class : Bool

    def initialize(root : String | Path)
      p_root = Path.new(root.to_s)
      @root = PathUtil.strip_prefix("./", p_root).try(&.to_s) || root.to_s
      @globs = [] of Glob
      @case_insensitive = false
      @allow_unclosed_class = true
    end

    def build : Gitignore
      Gitignore.new(@root, @globs)
    end

    def add_line(from : String? = nil, line : String = "") : self
      return self if line.starts_with?('#')

      line = trim_trailing_space(line)
      return self if line.empty?

      original = line
      is_whitelist = false
      is_only_dir = false

      if line.starts_with?("\\!") || line.starts_with?("\\#")
        line = line[1..]
      else
        if line.starts_with?("!")
          is_whitelist = true
          line = line[1..]
        end
      end

      if line.ends_with?('/')
        is_only_dir = true
        line = line.rchop('/')
        if line.ends_with?('\\')
          line = line.rchop('\\')
        end
      end

      is_absolute = false
      if line.starts_with?('/')
        is_absolute = true
        line = line[1..]
      end

      pattern = line

      unless is_absolute || pattern.includes?('/')
        pattern = "**/#{pattern}" unless pattern.starts_with?("**/") || pattern == "**"
      end

      if pattern.ends_with?("/**")
        pattern = "#{pattern}/*"
      end

      glob = Glob.new(
        from: from, original: original, actual: pattern,
        is_whitelist: is_whitelist, is_only_dir: is_only_dir
      )

      @globs << glob
      self
    end

    def add(from : String? = nil, line : String = "") : self
      add_line(from, line)
    end

    private def trim_trailing_space(line : String) : String
      return line if line.ends_with?("\\ ")
      line.rstrip
    end
  end
end
