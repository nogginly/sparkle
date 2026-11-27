require "./tree"

module Sparkle::Ponyc
  # The in-memory packages one compile or type check builds: the root
  # package, and each package it requires, added to the program parsed only,
  # under a key that a `use` in another package names.
  class Packages
    getter root : Tree
    getter added = [] of LibPonyc::Ast

    def initialize(@opt : LibPonyc::PassOpt, @program : LibPonyc::Ast, @root : Tree, @prefix : String)
    end

    # Adds an empty package for `name` and returns the key a `use` names it
    # by, and the tree to build it in. The key has no `:`, which ponyc would
    # read as a scheme.
    def add(name : String) : {String, Tree}
      key = "#{@prefix}#{name}"
      path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(@opt), key)
      LibPonyc.module_add_magic_src(path, "", @opt)
      package = LibPonyc.spk_module_load_parsed(@program, path, @opt)
      raise "ponyc failed to load the package #{key}" if package.null?
      @added << package
      {key, Tree.new(@opt, LibPonyc.ast_child(package))}
    end
  end
end
