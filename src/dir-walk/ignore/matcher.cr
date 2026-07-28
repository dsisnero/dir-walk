module Dir::Walk::Ignore
  record IgnoreOptions,
    hidden : Bool = true,
    ignore : Bool = true,
    parents : Bool = true,
    git_ignore : Bool = true,
    git_exclude : Bool = true,
    require_git : Bool = true

  class Matcher
    getter dir : String
    getter overrides : Override?
    getter types : Types?
    getter parent : Matcher?
    getter opts : IgnoreOptions

    @ignore_matcher : Gitignore
    @git_ignore_matcher : Gitignore
    @git_exclude_matcher : Gitignore

    def initialize(
      @dir : String = "",
      @overrides : Override? = nil,
      @types : Types? = nil,
      @parent : Matcher? = nil,
      @opts : IgnoreOptions = IgnoreOptions.new,
      @ignore_matcher : Gitignore = Gitignore.empty,
      @git_ignore_matcher : Gitignore = Gitignore.empty,
      @git_exclude_matcher : Gitignore = Gitignore.empty,
    )
    end

    def root? : Bool
      @parent.nil?
    end

    def empty? : Bool
      @ignore_matcher.empty? && @git_ignore_matcher.empty? &&
        @git_exclude_matcher.empty? &&
        (!@overrides || @overrides.empty?) &&
        (!@types || @types.empty?) &&
        !@opts.hidden
    end

    def add_child(dir_path : String, entry_names : Array(String)? = nil) : Matcher
      ig_matcher = if @opts.ignore && (entry_names.nil? || entry_names.includes?(".ignore"))
                     build_gitignore(dir_path, [".ignore"])
                   else
                     Gitignore.empty
                   end

      gi_matcher = if @opts.git_ignore && (entry_names.nil? || entry_names.includes?(".gitignore"))
                     build_gitignore(dir_path, [".gitignore"])
                   else
                     Gitignore.empty
                   end

      gi_exclude_matcher = if @opts.git_exclude && (entry_names.nil? || entry_names.includes?(".git"))
                             build_gitignore(File.join(dir_path, ".git"), ["info/exclude"])
                           else
                             Gitignore.empty
                           end

      Matcher.new(
        dir: dir_path,
        overrides: @overrides,
        types: @types,
        parent: self,
        opts: @opts,
        ignore_matcher: ig_matcher,
        git_ignore_matcher: gi_matcher,
        git_exclude_matcher: gi_exclude_matcher,
      )
    end

    def matched(path : String, is_dir : Bool) : Match
      ov = @overrides
      if ov && !ov.empty?
        m = ov.matched(path, is_dir)
        return m unless m.none?
      end

      result = matched_ignore(path, is_dir)
      return result if result.ignore?

      ts = @types
      if ts && !ts.empty? && !is_dir
        t = ts.matched(path)
        return t if t.ignore?
      end

      if @opts.hidden && PathUtil.hidden_entry?(path)
        return Match.ignore
      end

      result
    end

    def matched_ignore(path : String, is_dir : Bool) : Match
      m_ignore = Match.none
      m_gi = Match.none
      m_gi_exclude = Match.none

      parents.each do |ig|
        m_ignore = m_ignore.or(ig.ignore_matcher.matched(path, is_dir)) if m_ignore.none?
        m_gi = m_gi.or(ig.git_ignore_matcher.matched(path, is_dir)) if m_gi.none?
        m_gi_exclude = m_gi_exclude.or(ig.git_exclude_matcher.matched(path, is_dir)) if m_gi_exclude.none?
      end

      m_ignore.or(m_gi).or(m_gi_exclude)
    end

    protected getter ignore_matcher : Gitignore
    protected getter git_ignore_matcher : Gitignore
    protected getter git_exclude_matcher : Gitignore

    def parents : Iterator(Matcher)
      ParentsIterator.new(self)
    end

    private def build_gitignore(dir : String, names : Array(String)) : Gitignore
      builder = GitignoreBuilder.new(dir)
      names.each do |name|
        file_path = File.join(dir, name)
        next unless File.exists?(file_path)
        File.each_line(file_path) do |line|
          builder.add_line(dir, line)
        end
      rescue
      end
      builder.build
    end
  end

  struct ParentsIterator
    include Iterator(Matcher)
    @current : Matcher?

    def initialize(@current : Matcher?)
    end

    def next
      current = @current
      if current
        @current = current.parent
        current
      else
        stop
      end
    end
  end

  class MatcherBuilder
    getter dir : String
    property overrides : Override?
    property types : Types?
    property opts : IgnoreOptions

    def initialize(@dir : String = "")
      @overrides = nil
      @types = nil
      @opts = IgnoreOptions.new
    end

    def build : Matcher
      Matcher.new(
        dir: @dir,
        overrides: @overrides,
        types: @types,
        opts: @opts,
      )
    end

    def hidden(yes : Bool) : self
      @opts = IgnoreOptions.new(hidden: yes, ignore: @opts.ignore,
        parents: @opts.parents, git_ignore: @opts.git_ignore,
        git_exclude: @opts.git_exclude, require_git: @opts.require_git)
      self
    end

    def ignore(yes : Bool) : self
      @opts = IgnoreOptions.new(hidden: @opts.hidden, ignore: yes,
        parents: @opts.parents, git_ignore: @opts.git_ignore,
        git_exclude: @opts.git_exclude, require_git: @opts.require_git)
      self
    end

    def git_ignore(yes : Bool) : self
      @opts = IgnoreOptions.new(hidden: @opts.hidden, ignore: @opts.ignore,
        parents: @opts.parents, git_ignore: yes,
        git_exclude: @opts.git_exclude, require_git: @opts.require_git)
      self
    end
  end
end
