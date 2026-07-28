require "file"
require "./dirent"
require "./raw_dirent"

module Dir::Walk
  alias WalkFunc = (String, DirEntry?, Exception?) ->
  alias WorkItem = {DirEntry, String, Bool, Ignore::Matcher?}

  # Parallelism is opt-in. Resize the default execution context at startup:
  #   Fiber::ExecutionContext.default.resize(System.cpu_count)
  # Without this, fibers run concurrently (one at a time) but the channel-based
  # dispatch still works correctly — workers just don't run in parallel.

  def self.walk(conf : Config?, root : String, &walk_fn : WalkFunc) : Nil
    fi = File.info(root)
    c = conf.try(&.copy) || Config.new
    if c.to_slash
      root = root.gsub('\\', '/')
    end
    nw = c.num_workers > 0 ? c.num_workers : default_num_workers
    w = Walker.new(follow: c.follow, to_slash: c.to_slash, sort: c.sort, max_depth: c.max_depth)
    if w.follow
      w.add_dir_info(fi)
    end
    root = clean_root(root)
    entry = w.make_root_entry(root, fi)
    root_ig = if c.ignore
                empty_ig = Ignore::Matcher.new(dir: root, opts: c.ignore_opts, overrides: c.overrides)
                empty_ig.add_child(root)
              end
    if nw <= 1
      sequential_walk(w, root, entry, walk_fn, root_ig)
    else
      parallel_walk(w, root, entry, walk_fn, nw, root_ig)
    end
  end

  private def self.sequential_walk(w : Walker, root : String, entry : DirEntry,
                                   walk_fn : WalkFunc, root_ig : Ignore::Matcher?) : Nil
    w.call_walk_fn(root, entry, walk_fn)
    return if w.max_depth > 0 && entry.depth >= w.max_depth
    todo = Deque(WorkItem).new
    ig = root_ig
    enq = ->(de : DirEntry, p : String, cd : Bool) {
      child_ig = ig.try(&.add_child(p))
      todo << {de, p, cd, child_ig}
    }
    begin
      w.read_dir(root, entry.depth + 1, enq, walk_fn, ig)
    rescue ex : File::Error
      w.call_walk_fn(root, entry, walk_fn, ex) rescue return
    end
    while item = todo.shift?
      de, dp, cd, ig = item
      unless cd
        begin
          w.call_walk_fn(dp, de, walk_fn)
        rescue ex : ErrSkipDir
          next
        end
      end
      next if w.max_depth > 0 && de.depth >= w.max_depth
      begin
        w.read_dir(dp, de.depth + 1, enq, walk_fn, ig)
      rescue ex : File::Error
        w.call_walk_fn(dp, de, walk_fn, ex) rescue nil
      end
    end
  end

  private def self.spawn_worker(w : Walker, walk_fn : WalkFunc,
                                workc : Channel(WorkItem),
                                enqueuec : Channel(WorkItem),
                                resc : Channel(Exception?),
                                donec : Channel(Nil))
    spawn(name: "dir-walk-worker") do
      loop do
        select
        when donec.receive?
          break
        when item = workc.receive?
          break if item.nil?
          de, dp, cd, ig = item
          err = w.walk_dir(de, dp, cd, walk_fn, enqueuec, ig)
          select
          when donec.receive?
            break
          when resc.send(err)
          end
        end
      end
    end
  end

  private def self.parallel_walk(w : Walker, root : String, entry : DirEntry,
                                 walk_fn : WalkFunc, num_workers : Int32,
                                 root_ig : Ignore::Matcher?) : Nil
    workc = Channel(WorkItem).new(num_workers)
    enqueuec = Channel(WorkItem).new(num_workers)
    resc = Channel(Exception?).new(num_workers)
    donec = Channel(Nil).new

    num_workers.times do
      spawn_worker(w, walk_fn, workc, enqueuec, resc, donec)
    end

    todo = Deque(WorkItem).new
    todo << {entry, root, false, root_ig}
    out = 0

    loop do
      if todo.empty?
        select
        when it = enqueuec.receive?
          todo << it if it
        when err = resc.receive?
          out -= 1
          if err
            donec.close
            raise err
          end
          if out == 0 && todo.empty?
            select
            when it = enqueuec.receive?
              todo << it if it
            else
              break
            end
          end
        end
      else
        item = todo.last
        select
        when workc.send(item)
          todo.pop
          out += 1
        when it = enqueuec.receive?
          todo << it if it
        when err = resc.receive?
          out -= 1
          if err
            donec.close
            raise err
          end
          if out == 0 && todo.empty?
            select
            when it = enqueuec.receive?
              todo << it if it
            else
              break
            end
          end
        end
      end
    end

    workc.close
  end

  private class Walker
    getter follow : Bool; getter max_depth : Int32
    @sort : SortMode; @dir_infos : Array(File::Info)

    def initialize(@follow : Bool, @to_slash : Bool, @sort : SortMode, @max_depth : Int32)
      @dir_infos = [] of File::Info
    end

    def add_dir_info(fi)
      @dir_infos << fi
    end

    def should_skip_dir?(fi)
      @dir_infos.any? { |i| fi.same_file?(i) }
    end

    def should_traverse?(path, de)
      ts = de.stat; return false unless ts.directory?; return false if should_skip_dir?(ts)
      loop do
        parent = File.dirname(path); return true if parent == path; return false if File.info(parent).same_file?(ts); path = parent
      end
    rescue File::NotFoundError
      false
    end

    def join_paths(dir, base)
      if File::SEPARATOR == '/'
        dir.ends_with?('/') ? dir + base : dir + '/' + base
      else
        @to_slash ? (dir.ends_with?('/') ? dir + base : dir + '/' + base) : (dir.ends_with?(File::SEPARATOR) ? dir + base : dir + File::SEPARATOR + base)
      end
    end

    def make_root_entry(root, fi)
      DirEntry.new(parent: File.dirname(root), name: File.basename(root), entry_type: fi.type, depth: 0)
    end

    def call_walk_fn(path, entry, walk_fn, err = nil)
      walk_fn.call(path, entry, err)
    end

    def walk_dir(de, dir_path, callback_done, walk_fn, enqueuec, ig : Ignore::Matcher?)
      unless callback_done
        begin
          call_walk_fn(dir_path, de, walk_fn)
        rescue ex : ErrSkipDir
          return nil
        rescue ex : Exception
          return ex
        end
      end
      return nil if @max_depth > 0 && de.depth >= @max_depth
      begin
        enq = ->(d : DirEntry, p : String, c : Bool) {
          child_ig = ig.try(&.add_child(p))
          enqueuec.send({d, p, c, child_ig})
        }
        read_dir(dir_path, de.depth + 1, enq, walk_fn, ig)
      rescue ex : File::Error
        call_walk_fn(dir_path, de, walk_fn, ex) rescue return ex; nil
      rescue ex : Exception
        ex
      end
    end

    def on_dir_ent(dir_name, base_name, de, enqueue, walk_fn, ig : Ignore::Matcher?)
      joined = join_paths(dir_name, base_name)
      if ig
        m = ig.matched(joined, de.dir?)
        if m.ignore?
          return
        end
      end
      if de.dir?
        enqueue.call(de, joined, false); return
      end
      begin
        walk_fn.call(joined, de, nil)
      rescue ex : ErrTraverseLink
        if de.symlink?
          @follow ? nil : (enqueue.call(de, joined, true); return)
        end
      rescue ex : ErrSkipFiles
        raise ex
      rescue ex : ErrSkipDir
        walk_fn.call(joined, de, ex) rescue return; return
      end
      if de.symlink? && @follow && should_traverse?(joined, de)
        enqueue.call(de, joined, true)
      end
    end

    def read_dir(dir_path, depth, enqueue, walk_fn, ig : Ignore::Matcher?)
      entries = @sort.sort_none? ? nil : [] of DirEntry; skip_files = false
      Dir::Walk.raw_read_dir(dir_path) do |name, d_type|
        type = d_type.unknown? ? detect_type_via_lstat(dir_path, name) : d_type
        next if skip_files && type.file?
        de = DirEntry.new(parent: dir_path, name: name, entry_type: type, depth: depth)
        if entries
          entries << de
        else
          begin
            on_dir_ent(dir_path, name, de, enqueue, walk_fn, ig)
          rescue ex : ErrSkipFiles
            skip_files = true
          end
        end
      end
      return if entries.nil?; sort_entries(entries)
      entries.each { |de| next if skip_files && de.file?; begin
        on_dir_ent(dir_path, de.name, de, enqueue, walk_fn, ig)
      rescue ex : ErrSkipFiles
        skip_files = true
      end }
    end

    private def detect_type_via_lstat(d, n)
      File.info?(join_paths(d, n), follow_symlinks: false).try(&.type) || File::Type::Unknown rescue File::Type::Unknown
    end

    private def sort_entries(e)
      return if e.size <= 1
      case @sort
      when SortMode::SortLexical    then e.sort_by!(&.name)
      when SortMode::SortFilesFirst then e.sort! { |a, b| compare_files_first(a, b) }
      when SortMode::SortDirsFirst  then e.sort! { |a, b| compare_dirs_first(a, b) }
      end
    end

    private def compare_files_first(a, b)
      ra, rb = a.file?, b.file?; if ra && !rb
        -1
      elsif !ra && rb
        1
      elsif !ra && !rb
        da, db = a.dir?, b.dir?; !da && db ? -1 : da && !db ? 1 : a.name <=> b.name
      else
        a.name <=> b.name
      end
    end

    private def compare_dirs_first(a, b)
      da, db = a.dir?, b.dir?; if da && !db
        -1
      elsif !da && db
        1
      elsif !da && !db
        ra, rb = a.file?, b.file?; ra && !rb ? -1 : !ra && rb ? 1 : a.name <=> b.name
      else
        a.name <=> b.name
      end
    end
  end

  private def self.clean_root(root)
    {% if flag?(:win32) %}; return root; {% end %}; sep = File::SEPARATOR; i = root.size - 1; while i >= 0
      return root[..i] unless root[i] == sep; i -= 1
    end; root.empty? ? root : root[0..0]
  end
end
