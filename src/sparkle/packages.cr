require "./parser"
require "./contracts"

module Sparkle
  # The Sparkle packages of one build, parsed: the root package, every
  # package it requires and theirs, and the library's `prelude`, which every
  # other package requires without saying so. Packages come before the
  # packages that require them, so the root is last.
  class PackageSet
    # A package: its directory, the name its Pony key is made from, the
    # indexes of its files, each `require` path that names a Sparkle
    # package with that package's directory, and the directories it
    # requires without saying so.
    record Unit, dir : String, name : String, files : Array(Int32), requires : Hash(String, String), implicit : Array(String)

    # A failure to load, at a position in a file.
    class Failure < Exception
      getter file : String
      getter source : String
      getter error : ParseError

      def initialize(@file, @source, @error)
        super(@error.message)
      end
    end

    getter files = [] of String
    getter sources = [] of String
    getter programs = [] of Program
    getter units = [] of Unit

    @state = {} of String => Symbol
    @names = Set(String).new
    @prelude : String? = nil
    @in_prelude = false

    PONY_DECLARATION  = /^(?:class|actor|primitive|struct|interface|trait|type)(?: (?:val|ref|iso|box|tag|trn))? ([A-Z][A-Za-z0-9_]*)/m
    ALWAYS_REOPENABLE = %w[builtin collections]

    @pony_types = {} of String => Set(String)

    # `library` is the Sparkle library's directory, if any, and `pony_home`
    # the Pony installation whose packages' types a class may reopen. Every
    # contract clause is kept when `contracts` is set, otherwise only
    # `expects`.
    def initialize(@library : String?, @contracts : Bool = true, @pony_home : String? = nil)
    end

    # Loads the package in `dir`, made of `files`, and everything it
    # requires. Raises `Failure` at the first file that does not parse, or
    # at a `require` that names no package or closes a cycle.
    def load(dir : String, files : Array(String)) : self
      dir = File.expand_path(dir)
      if (library = @library) && (prelude = PackageSet.package_dir(File.join(library, "prelude"))) && prelude != dir
        @in_prelude = true
        visit(prelude, PackageSet.spk_files(prelude), [] of String)
        @in_prelude = false
        @prelude = prelude
      end
      visit(dir, files, [] of String)
      self
    end

    # The `.spk` files directly in `dir`, sorted.
    def self.spk_files(dir : String) : Array(String)
      Dir.glob(File.join(dir, "*.spk")).sort
    end

    # `dir`, expanded, if it holds `.spk` files.
    def self.package_dir(dir : String) : String?
      expanded = File.expand_path(dir)
      File.directory?(expanded) && !spk_files(expanded).empty? ? expanded : nil
    end

    private def visit(dir : String, files : Array(String), chain : Array(String)) : Nil
      @state[dir] = :loading
      indexes = [] of Int32
      requires = {} of String => String
      checked = false
      files.each do |file|
        index = parse(file)
        indexes << index
        program = @programs[index]
        pony = ALWAYS_REOPENABLE.dup
        program.items.each do |item|
          next unless item.is_a?(RequireDecl)
          target = resolve(item, dir, index)
          unless target
            pony << item.path
            next
          end
          requires[item.path] = target
          case @state[target]?
          when :loading then fail(index, item, "packages require each other: #{(chain + [dir, target]).map { |each| File.basename(each) }.join(" -> ")}")
          when nil      then visit(target, PackageSet.spk_files(target), chain + [dir])
          end
        end
        mark_reopenings(program, index, pony)
        checked = Contracts.apply(program, file, all: @contracts) || checked
      end
      Contracts.support(@programs[indexes.first]) if checked && !indexes.empty?
      implicit = (prelude = @prelude) && !@in_prelude ? [prelude] : [] of String
      @units << Unit.new(dir, unique_name(dir), indexes, requires, implicit)
      @state[dir] = :done
    end

    # Marks each class named after a type of the Pony `packages` as a
    # reopening, and checks that it and every module hold only methods.
    private def mark_reopenings(program : Program, index : Int32, packages : Array(String)) : Nil
      names = packages.reduce(Set(String).new) { |all, package| all.concat(pony_types(package)) }
      program.items.each do |item|
        next unless item.is_a?(TypeDecl)
        item.reopens = item.kind == "class" && names.includes?(item.name)
        next unless Rules.inline_only?(item)
        what = item.reopens ? "a reopened Pony type" : "a module"
        item.fields.first?.try { |field| fail(index, field, "#{what} cannot have fields") }
        item.methods.find(&.self_recv).try { |method| fail(index, method, "#{what} cannot have constructors") }
        item.maintains.first?.try { |clause| fail(index, clause, "#{what} cannot have `maintains`") }
      end
    end

    # The names of the types the Pony package `name` declares, read from
    # its sources.
    private def pony_types(name : String) : Set(String)
      @pony_types[name] ||= begin
        found = Set(String).new
        if home = @pony_home
          Dir.glob(File.join(home, "packages", name, "*.pony")).each do |file|
            File.read(file).scan(PONY_DECLARATION) { |match| found << match[1] }
          end
        end
        found
      end
    end

    private def parse(file : String) : Int32
      source = File.read(file)
      shown = PackageSet.shown(file)
      begin
        program = Parser.parse(source)
      rescue e : ParseError
        raise Failure.new(shown, source, e)
      end
      @files << shown
      @sources << source
      @programs << program
      @files.size - 1
    end

    # The directory of the Sparkle package `item` names, or nil when it
    # names a Pony package.
    private def resolve(item : RequireDecl, dir : String, index : Int32) : String?
      path = item.path
      if path.starts_with?("./") || path.starts_with?("../")
        return PackageSet.package_dir(File.join(dir, path)) || fail(index, item, "no Sparkle package at \"#{path}\": a directory of .spk files")
      end
      @library.try { |library| PackageSet.package_dir(File.join(library, path)) }
    end

    private def fail(index : Int32, at : Node, message : String) : NoReturn
      raise Failure.new(@files[index], @sources[index], ParseError.new(message, at.line, at.col))
    end

    private def unique_name(dir : String) : String
      base = File.basename(dir).downcase.gsub(/[^a-z0-9_]/, "_")
      name = base
      count = 1
      until @names.add?(name)
        count += 1
        name = "#{base}_#{count}"
      end
      name
    end

    # `file` relative to the working directory when it is inside it.
    def self.shown(file : String) : String
      return file unless Path[file].absolute?
      relative = Path[file].relative_to(Dir.current).to_s
      relative.starts_with?("..") ? file : relative
    end
  end
end
