module Dir::Walk::Ignore
  class Override
    getter gitignore : Gitignore

    def initialize(@gitignore : Gitignore = Gitignore.empty)
    end

    def self.empty : self
      new
    end

    def empty? : Bool
      @gitignore.empty?
    end

    # In override context, non-! patterns become include (whitelist) rules
    # after inverting the gitignore result. ! patterns become exclude rules.
    def num_whitelists : Int32
      @gitignore.globs.count { |g| !g.is_whitelist }
    end

    def num_ignores : Int32
      @gitignore.globs.count(&.is_whitelist)
    end

    def matched(path : String, is_dir : Bool) : Match
      return Match.none if empty?

      mat = @gitignore.matched(path, is_dir).invert

      if mat.none? && num_whitelists > 0 && !is_dir
        return Match.ignore
      end

      mat
    end
  end

  class OverrideBuilder
    getter builder : GitignoreBuilder

    def initialize(root : String | Path)
      @builder = GitignoreBuilder.new(root)
      @builder.allow_unclosed_class = false
    end

    def add(glob : String) : self
      @builder.add_line(nil, glob)
      self
    end

    def build : Override
      Override.new(@builder.build)
    end
  end
end
