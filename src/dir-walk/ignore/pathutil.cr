module Dir::Walk::Ignore
  module PathUtil
    extend self

    def file_name?(path : Path) : Bool
      path.parent == Path.new("")
    end

    def file_name?(path : String) : Bool
      !path.includes?(File::SEPARATOR)
    end

    def file_name(path : Path) : String?
      name = path.basename.to_s
      name.empty? ? nil : name
    end

    def file_name(path : String) : String?
      return nil if path.ends_with?(File::SEPARATOR) || path.ends_with?("/")
      idx = path.rindex(File::SEPARATOR)
      if idx
        name = path[(idx + 1)..]
      else
        idx = path.rindex('/')
        name = idx ? path[(idx + 1)..] : path
      end
      name.empty? ? nil : name
    end

    def strip_prefix(prefix : String | Path, path : Path) : Path?
      strip_prefix(prefix.to_s, path.to_s).try { |s| Path.new(s) }
    end

    def strip_prefix(prefix : String, path : String) : String?
      prefix = prefix.rstrip(File::SEPARATOR).rstrip('/')
      return path if prefix.empty?
      p_len = prefix.size
      return nil unless path.starts_with?(prefix)
      return nil unless path.size == p_len || path[p_len] == '/' || path[p_len] == File::SEPARATOR
      rest = path[(p_len)..]
      rest = rest.lstrip('/').lstrip(File::SEPARATOR)
      rest.empty? ? "." : rest
    end

    def hidden_entry?(path : Path) : Bool
      path.basename.to_s.starts_with?('.')
    end

    def hidden_entry?(path : String) : Bool
      fn = file_name(path)
      fn.nil? ? false : fn.starts_with?('.')
    end

    def hidden_entry_by_name?(name : String) : Bool
      name.starts_with?('.')
    end
  end
end
