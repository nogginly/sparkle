require "./parser"
require "./rules"
require "./lowerer"
require "./inliner"
require "./contracts"
require "./packages"
require "./diagnostics"
require "./ponyc/compiler"
require "./ponyc/session"

module Sparkle
  module Driver
    METHOD_WITHOUT_CALL = "can't reference a method without calling it"
    MAX_ROUNDS          = 50
    PONYC_RELATIVES     = [".tools/ponyc/bin/ponyc", "vendor/ponyc/build/release/ponyc"]
    INSTALLED_PONY_HOME = "lib/pony"
    INSTALLED_LIBRARY   = "share/sparkle/stdlib"

    # Formats a parse error as `file:line:col: message`, the source line and a caret.
    def self.format_error(path : String, source : String, err : ParseError) : String
      line = source.lines(chomp: true)[err.line - 1]? || ""
      "#{path}:#{err.line}:#{err.col}: #{err.message}\n#{line}\n#{Diagnostics.caret_padding(line, err.col)}^\n"
    end

    # The Pony installation whose standard library and runtime `build` uses:
    # the one holding `$SPARKLE_PONYC`, else `lib/pony` beside an installed
    # `bin/sparkle` (see `make install`), else the one holding the `ponyc`
    # found by `find_ponyc`.
    def self.find_pony_home(env_value : String? = ENV["SPARKLE_PONYC"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      if exe_path && (env_value.nil? || env_value.empty?)
        installed = File.join(File.dirname(File.dirname(File.expand_path(exe_path))), INSTALLED_PONY_HOME)
        return installed if File.directory?(File.join(installed, "packages", "builtin"))
      end
      find_ponyc(env_value, exe_path, cwd).try { |ponyc| File.dirname(File.dirname(ponyc)) }
    end

    # The Sparkle library's directory: `$SPARKLE_LIB`, else
    # `share/sparkle/stdlib` beside an installed `bin/sparkle`, else
    # `stdlib` searched upward from the executable and the working
    # directory. Nil when there is none.
    def self.find_library(env_value : String? = ENV["SPARKLE_LIB"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      return env_value if env_value && !env_value.empty?
      roots = [] of String
      if exe_path
        prefix = File.dirname(File.dirname(File.expand_path(exe_path)))
        installed = File.join(prefix, INSTALLED_LIBRARY)
        return installed if File.directory?(installed)
        roots << prefix
      end
      roots << File.expand_path(cwd)
      roots.each do |root|
        dir = root
        loop do
          candidate = File.join(dir, "stdlib")
          return candidate if File.directory?(candidate)
          parent = File.dirname(dir)
          break if parent == dir
          dir = parent
        end
      end
      nil
    end

    # Locates ponyc: `$SPARKLE_PONYC`, then `.tools/ponyc`, then the vendored
    # build, each searched upward from the executable and the working
    # directory, then `PATH`.
    def self.find_ponyc(env_value : String? = ENV["SPARKLE_PONYC"]?, exe_path : String? = Process.executable_path, cwd : String = Dir.current) : String?
      if env_value && !env_value.empty?
        return env_value
      end
      roots = [] of String
      if exe_path
        roots << File.dirname(File.dirname(File.expand_path(exe_path)))
      end
      roots << File.expand_path(cwd)
      PONYC_RELATIVES.each do |relative|
        roots.each do |root|
          dir = root
          loop do
            candidate = File.join(dir, relative)
            return candidate if File.file?(candidate) && File::Info.executable?(candidate)
            parent = File.dirname(dir)
            break if parent == dir
            dir = parent
          end
        end
      end
      Process.find_executable("ponyc")
    end

    # Everything `build` and `tree_text` need once the sources parse.
    # `files`, `sources` and `programs` hold every package's files; `units`
    # groups them into packages, the root last.
    private record Project, files : Array(String), package : String, sources : Array(String), programs : Array(Program), units : Array(PackageSet::Unit), home : String, primed : Hash(String, Set(String)), predicates : Rules::Predicates

    # Parses the Sparkle files at `path`, and the packages they require, and
    # finds ponyc; nil, with the reason on `err`, if either fails.
    private def self.load_project(path : String, err : IO, contracts : Bool = true) : Project?
      root, package = sources_for(path)
      if root.empty?
        err.puts "sparkle: no .spk files in #{path}"
        return
      end
      home = find_pony_home
      unless home
        err.puts "sparkle: ponyc not found (set SPARKLE_PONYC, run `make ponyc`, or put ponyc on PATH)"
        return
      end
      set = PackageSet.new(find_library, contracts, home)
      begin
        set.load(File.directory?(path) ? path : File.dirname(path), root)
      rescue e : PackageSet::Failure
        err.print format_error(e.file, e.source, e.error)
        return
      end
      files, sources, programs = set.files, set.sources, set.programs
      Project.new(files, package, sources, programs, set.units, home, Rules.primed_params(programs), Rules.enum_predicates(programs))
    end

    # Lowers each package into its own tree: the root into the root's, and
    # each package it requires into one `packages` adds, before the
    # packages that require it, so their `use`s can name its key. Yields
    # the index of each file before lowering it.
    private def self.lower_units(packages : Ponyc::Packages, units : Array(PackageSet::Unit), files : Array(String), sources : Array(String), programs : Array(Program), calls : Hash(String, Set({Int32, Int32})), primed : Hash(String, Set(String)), predicates : Rules::Predicates, stub : Inliner? = nil, & : Int32 -> Nil) : Nil
      keys = {} of String => String
      units.each_with_index do |unit, position|
        tree = if position == units.size - 1
                 packages.root
               else
                 key, added = packages.add(unit.name)
                 keys[unit.dir] = key
                 added
               end
        requires = unit.requires.transform_values { |dir| keys[dir] }
        implicit = unit.implicit.map { |dir| keys[dir] }
        unit.files.each do |i|
          yield i
          lowerer = Lowerer.new(tree, calls[files[i]]? || Set({Int32, Int32}).new, primed, predicates).packages(requires, implicit)
          stub.try { |inliner| lowerer.stub(inliner.names, inliner.plain, inliner.probes) }
          lowerer.lower(programs[i], files[i], sources[i])
        end
      end
    end

    private def self.lower_project(packages : Ponyc::Packages, project : Project, calls : Hash(String, Set({Int32, Int32})), & : Int32 -> Nil) : Nil
      lower_units(packages, project.units, project.files, project.sources, project.programs, calls, project.primed, project.predicates) { |i| yield i }
    end

    # The lowered tree of the package at `path`, as `build` compiles it,
    # printed as `ponyc --astmodule` prints one.
    def self.tree_text(path : String, err : IO) : {Int32, String?}
      project = load_project(path, err) || return {1, nil}
      current = 0
      begin
        calls = tree_calls(project) { |i| current = i }.calls
        text = Ponyc.tree_text(project.home) do |packages|
          lower_project(packages, project, calls) { |i| current = i }
        end
        {0, text}
      rescue e : ParseError
        err.print format_error(project.files[current], project.sources[current], e)
        {1, nil}
      end
    end

    # Type-checks the `.spk` file or package at `path` without generating
    # code, reporting errors as `build` does. Returns the exit code.
    def self.check(path : String, err : IO = STDERR) : Int32
      project = load_project(path, err) || return 1
      current = 0
      session = Ponyc::Session.new(project.home)
      begin
        rounds = tree_calls(session, project.units, project.files, project.sources, project.programs, project.primed, project.predicates) { |i| current = i }
        calls, inliner = rounds.calls, rounds.inliner
        return 1 unless posts_match?(project, rounds, err)
        ok, errors = session.verify do |packages|
          lower_project(packages, project, calls) { |i| current = i }
        end
        err.print Diagnostics.rewrite(errors, names: Rules.enum_names(project.programs), origins: inliner.origins, sources: project.files.zip(project.sources).to_h)
        ok ? 0 : 1
      rescue e : ParseError
        err.print format_error(project.files[current], project.sources[current], e)
        1
      ensure
        session.close
      end
    end

    private def self.build_tree(project : Project, out_dir : String?, err : IO, release : Bool) : {Int32, String?}
      current = 0
      begin
        rounds = tree_calls(project) { |i| current = i }
        calls, inliner = rounds.calls, rounds.inliner
        return {1, nil} unless posts_match?(project, rounds, err)
        out_dir ||= File.join(".sparkle", "bin")
        Dir.mkdir_p(out_dir)
        ok, errors = Ponyc.compile_tree(out_dir, project.package, project.home, release) do |packages|
          lower_project(packages, project, calls) { |i| current = i }
        end
        err.print Diagnostics.rewrite(errors, names: Rules.enum_names(project.programs), origins: inliner.origins, sources: project.files.zip(project.sources).to_h)
        {ok ? 0 : 1, File.join(out_dir, project.package)}
      rescue e : ParseError
        err.print format_error(project.files[current], project.sources[current], e)
        {1, nil}
      end
    end

    private def self.tree_calls(project : Project, & : Int32 -> Nil) : Rounds
      session = Ponyc::Session.new(project.home)
      begin
        tree_calls(session, project.units, project.files, project.sources, project.programs, project.primed, project.predicates) { |i| yield i }
      ensure
        session.close
      end
    end

    # The positions, per file, of the bare `x.name`s the type checker reports
    # as methods: lowers, type-checks and adds positions until none is new.
    # One `Ponyc::Session` serves every round, so the standard library is
    # loaded and checked once. Yields the index of each file before lowering it.
    def self.tree_calls(files : Array(String), sources : Array(String), programs : Array(Program), home : String, primed : Hash(String, Set(String)) = Rules.primed_params(programs), predicates : Rules::Predicates = Rules.enum_predicates(programs), & : Int32 -> Nil) : Hash(String, Set({Int32, Int32}))
      session = Ponyc::Session.new(home)
      begin
        unit = PackageSet::Unit.new(".", "main", (0...files.size).to_a, {} of String => String, [] of String)
        tree_calls(session, [unit], files, sources, programs, primed, predicates) { |i| yield i }.calls
      ensure
        session.close
      end
    end

    # The field-or-method loop, which also inlines `yield` (see `Inliner`):
    # while a call with a block to a yielding method's name is undecided,
    # each round lowers the program stubbed, reads those calls' receiver
    # types, and inlines the ones that reach a yielding method. Then the
    # yielding methods are dropped and the rounds go on, unstubbed, until no
    # new call is found. Programs are changed in place.
    private def self.tree_calls(session : Ponyc::Session, units : Array(PackageSet::Unit), files : Array(String), sources : Array(String), programs : Array(Program), primed : Hash(String, Set(String)), predicates : Rules::Predicates, & : Int32 -> Nil) : Rounds
      calls = Hash(String, Set({Int32, Int32})).new
      handled = Set({String, Int32, Int32}).new
      clean = false
      inliner = Inliner.new(files, programs)
      finished = !inliner.yielding?
      MAX_ROUNDS.times do
        sites = finished ? [] of Inliner::Site : inliner.sites
        receivers = sites.select(&.call.recv).map { |site| {site.file, site.call.name_line, site.call.name_col} }.to_set
        report = session.check(receivers) do |packages|
          lower_units(packages, units, files, sources, programs, calls, primed, predicates, finished ? nil : inliner) { |i| yield i }
        end
        found, types, handled = report.errors, report.types, report.handled
        inliner.probed(report.probes)
        clean = found.empty?
        grown = false
        found.each do |file, line, column, message|
          next unless message == METHOD_WITHOUT_CALL && files.includes?(file)
          grown = true if (calls[file] ||= Set({Int32, Int32}).new).add?({line, column})
        end
        decided = false
        sites.reverse_each do |site|
          yield files.index(site.file) || 0
          type = site.call.recv ? types[{site.file, site.call.name_line, site.call.name_col}]? : nil
          decided = true if inliner.decide(site, type)
        end
        if !sites.empty? && !decided && !grown
          inliner.give_up(sites)
          decided = true
        end
        grown = true if decided
        if sites.empty? && !finished
          inliner.finish
          finished = true
          grown = true
        end
        break unless grown
      end
      Rounds.new(calls, inliner, handled, clean)
    end

    # What the field-or-method loop found: the method calls among bare
    # names, the inliner, the calls of its last round that reach a message
    # handler, and whether that round had no errors.
    private record Rounds, calls : Hash(String, Set({Int32, Int32})), inliner : Inliner, handled : Set({String, Int32, Int32}), clean : Bool

    # Whether every call that reaches a message handler is written with
    # `<~`, and every `<~` reaches one; reports each that is not on `err`. Decided
    # only when the last round type-checked cleanly; ponyc's own errors
    # come first otherwise.
    private def self.posts_match?(project : Project, rounds : Rounds, err : IO) : Bool
      return true unless rounds.clean
      ok = true
      project.files.each_with_index do |file, i|
        each_call(project.programs[i]) do |e, name, post, bare|
          origin = rounds.inliner.origins[{file, e[0], e[1]}]?
          message = rounds.handled.includes?({file, e[0], e[1]})
          next if message == post
          ok = false
          text = if post
                   "`<~` posts a message, and `#{name}` is a method: call it with `.`"
                 else
                   "`#{name}` is a message: post it with `#{bare ? "self " : ""}<~`"
                 end
          at_file, line, col = origin ? {origin.file, origin.line, origin.col} : {file, e[0], e[1]}
          index = project.files.index(at_file) || i
          err.print format_error(at_file, project.sources[index], ParseError.new(text, line, col))
        end
      end
      ok
    end

    # Yields each call in `program`, a bare name included: the position of
    # its name, the name, whether it is written with `<~`, and whether it
    # has no receiver.
    private def self.each_call(program : Program, & : {Int32, Int32}, String, Bool, Bool -> Nil) : Nil
      program.items.each do |item|
        next unless item.is_a?(TypeDecl)
        exprs = item.methods.flat_map { |method| method.body || [] of Expr } + item.fields.compact_map(&.init)
        found = [] of Expr
        exprs.each do |stmt|
          Walk.find(stmt) do |e|
            found << e if e.is_a?(Call) || e.is_a?(Ident)
            false
          end
        end
        found.each do |e|
          case e
          when Call  then yield({e.name_line, e.name_col}, e.name, e.post, e.recv.nil?)
          when Ident then yield({e.line, e.col}, e.name, false, true)
          end
        end
      end
    end

    # The Sparkle files and package name for a build path.
    def self.sources_for(path : String) : {Array(String), String}
      if File.directory?(path)
        files = Dir.glob(File.join(path, "*.spk")).sort
        {files, File.basename(File.expand_path(path))}
      else
        {[path], File.basename(File.dirname(File.expand_path(path)))}
      end
    end

    # Compiles the `.spk` file or package at `path` with the linked-in Pony
    # compiler, against the standard library of the Pony installation found
    # by `find_pony_home`. It lowers to ponyc's AST. The code is unoptimised,
    # as with `crystal build`, unless `release` is set.
    # Every contract clause is checked, unless `release` is set and
    # `all_contracts` is not: then only `expects` is.
    # Returns the exit code and the binary's path, which lands in `out_dir`.
    def self.build(path : String, out_dir : String?, err : IO = STDERR, release : Bool = false, all_contracts : Bool = false) : {Int32, String?}
      project = load_project(path, err, contracts: all_contracts || !release) || return {1, nil}
      build_tree(project, out_dir, err, release)
    end
  end
end
