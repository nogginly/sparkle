# Spike: inline `yield` blocks in Sparkle, using receiver types read back
# from a type-checking round, with no ponyc fork. Usage:
#   crystal run spike/yield/inline.cr -- FILE.spk
# A method whose body calls `yield(...)` is a yielder. Each call to a yielder
# with a block is replaced by a copy of the yielder's body, with `yield(e)`
# replaced by the block's body after binding its parameter to `e`. Rounds
# repeat until no call to a yielder remains.
require "../../src/sparkle/driver"

lib LibPonyc
  fun ast_id(ast : Ast) : LibC::Int
  fun ast_line(ast : Ast) : LibC::SizeT
  fun ast_pos(ast : Ast) : LibC::SizeT
  fun ast_type(ast : Ast) : Ast
  fun ast_print_type(type : Ast, strtab : Strtab) : LibC::Char*
end

class Sparkle::Ponyc::Session
  # As `check`, and also the printed type of the receiver of each call
  # whose method name sits at one of `positions`.
  def receiver_types(positions : Set({Int32, Int32}), & : Tree -> Nil) : Hash({Int32, Int32}, String)
    @round += 1
    path = LibPonyc.stringtab(LibPonyc.spk_opt_strtab(@opt), "spk_round_#{@round}")
    LibPonyc.module_add_magic_src(path, "", @opt)
    LibPonyc.spk_errors_reset(@opt)
    package = LibPonyc.spk_module_load_parsed(@program, path, @opt)
    yield Tree.new(@opt, LibPonyc.ast_child(package))
    LibPonyc.spk_opt_set_limit(@opt, LibPonyc.spk_pass_expr)
    LibPonyc.spk_program_passes(@program, @opt)
    Ponyc.errors(@opt).each { |e| STDERR.puts "error #{e}" } if ENV["SPIKE_DEBUG"]?
    types = {} of {Int32, Int32} => String
    collect_types(package, positions, types)
    LibPonyc.ast_remove(package)
    types
  end

  private def collect_types(ast : LibPonyc::Ast, positions, types) : Nil
    child = LibPonyc.ast_child(ast)
    until child.null?
      at = {LibPonyc.ast_line(child).to_i32, LibPonyc.ast_pos(child).to_i32}
      # After the expression pass a call is (call (funref receiver name) ...).
      if LibPonyc.ast_id(child) == Tk::CALL.value && positions.includes?(at) && !types.has_key?(at)
        recv = LibPonyc.ast_child(LibPonyc.ast_child(child))
        type = LibPonyc.ast_type(recv)
        types[at] = String.new(LibPonyc.ast_print_type(type, LibPonyc.spk_opt_strtab(@opt))) unless type.null?
      end
      collect_types(child, positions, types)
      child = LibPonyc.ast_sibling(child)
    end
  end
end

module YieldSpike
  include Sparkle
  extend self

  record Site, call : Call, body : Array(Expr), index : Int32

  @@fresh = 0
  # Where the call being inlined is: every node copied from the yielder takes
  # it, because ponyc checks that a name is declared before it is used by
  # comparing source positions.
  @@at = {0, 0}
  # Pony fields are private to their type, so inlined code reads a field
  # through a generated accessor, private to the package: {type, field, cap}.
  @@accessors = Set({String, String, String?}).new
  @@owner = ""
  @@cap : String? = nil
  @@names = Set(String).new

  def yielders(program : Program) : Hash({String, String}, Method)
    found = {} of {String, String} => Method
    program.items.each do |item|
      next unless item.is_a?(TypeDecl)
      item.methods.each { |m| found[{item.name, m.name}] = m if (body = m.body) && yields?(body) }
    end
    found
  end

  def yields?(body : Array(Expr)) : Bool
    body.any? { |e| yields?(e) }
  end

  def yields?(e : Expr) : Bool
    case e
    when Call   then (e.recv.nil? && e.name == "yield") || e.args.any? { |a| yields?(a) } || (e.block.try { |b| yields?(b.body) } || false)
    when While  then yields?(e.body)
    when If     then yields?(e.then_) || (e.else_.try { |b| yields?(b) } || false)
    when Lambda then yields?(e.body)
    else             false
    end
  end

  # Statement-position calls with a block to a method that some type yields from.
  def sites(program : Program, names : Set(String)) : Array(Site)
    found = [] of Site
    program.items.each do |item|
      next unless item.is_a?(TypeDecl)
      item.methods.each { |m| m.body.try { |b| collect_sites(b, names, found) } }
    end
    found
  end

  def collect_sites(body : Array(Expr), names, found) : Nil
    body.each_with_index do |e, i|
      found << Site.new(e, body, i) if e.is_a?(Call) && e.block && names.includes?(e.name) && e.recv
      case e
      when While then collect_sites(e.body, names, found)
      when If    then collect_sites(e.then_, names, found); e.else_.try { |b| collect_sites(b, names, found) }
      when Call  then e.block.try { |b| collect_sites(b.body, names, found) }
      end
    end
  end

  # The statements that replace `call`, a call of `m` on a receiver of type `owner`.
  def inline(call : Call, m : Method, owner : String) : Array(Expr)
    @@owner = owner
    @@cap = m.cap
    @@fresh += 1
    @@at = {call.line, call.col}
    tag = "y#{@@fresh}_"
    recv = "#{tag}self"
    locals = m.params.map(&.name).to_set
    m.body.try { |b| assigned(b, locals) }
    block = call.block || raise "no block"
    out = [Assign.new(call.line, call.col, Ident.new(call.line, call.col, recv), call.recv || raise("no receiver"), nil)] of Expr
    m.params.each_with_index do |param, i|
      arg = call.args[i]? || param.default || raise "missing argument #{param.name}"
      out << Assign.new(call.line, call.col, Ident.new(call.line, call.col, tag + param.name), arg, param.type)
    end
    out.concat(stmts(m.body || [] of Expr, recv, tag, locals, block))
    out
  end

  def assigned(body : Array(Expr), into : Set(String)) : Nil
    body.each do |e|
      case e
      when Assign then (t = e.target).is_a?(Ident) && into << t.name
      when While  then assigned(e.body, into)
      when If     then assigned(e.then_, into); e.else_.try { |b| assigned(b, into) }
      when Call   then e.block.try { |b| b.params.each { |p| into << p.name }; assigned(b.body, into) }
      end
    end
  end

  def stmts(body : Array(Expr), recv, tag, locals, block : Lambda) : Array(Expr)
    body.flat_map do |e|
      if e.is_a?(Call) && e.recv.nil? && e.name == "yield"
        bind = block.params.map_with_index do |p, i|
          Assign.new(@@at[0], @@at[1], Ident.new(@@at[0], @@at[1], p.name), expr(e.args[i]? || raise("yield without a value"), recv, tag, locals, block), p.type).as(Expr)
        end
        bind + block.body
      else
        [expr(e, recv, tag, locals, block)]
      end
    end
  end

  def expr(e : Expr, recv, tag, locals, block) : Expr
    r = ->(x : Expr) { expr(x, recv, tag, locals, block) }
    case e
    when SelfRef then Ident.new(@@at[0], @@at[1], recv)
    when IVarRef
      @@accessors << {@@owner, e.name, @@cap}
      Call.new(@@at[0], @@at[1], Ident.new(@@at[0], @@at[1], recv), "_yf_#{e.name}", [] of Expr, [] of NamedArg, nil, true, @@at[0], @@at[1])
    when Ident     then locals.includes?(e.name) ? Ident.new(@@at[0], @@at[1], tag + e.name) : Call.new(@@at[0], @@at[1], Ident.new(@@at[0], @@at[1], recv), e.name, [] of Expr, [] of NamedArg, nil, true, @@at[0], @@at[1])
    when Assign    then Assign.new(@@at[0], @@at[1], r.call(e.target), r.call(e.value), e.type)
    when OpAssign  then OpAssign.new(@@at[0], @@at[1], r.call(e.target), e.op, r.call(e.value))
    when Binary    then Binary.new(@@at[0], @@at[1], e.op, r.call(e.left), r.call(e.right))
    when Unary     then Unary.new(@@at[0], @@at[1], e.op, r.call(e.operand))
    when Paren     then Paren.new(@@at[0], @@at[1], r.call(e.expr))
    when Index     then Index.new(@@at[0], @@at[1], r.call(e.recv), e.args.map(&r), e.bang)
    when FieldRead then FieldRead.new(@@at[0], @@at[1], r.call(e.recv), e.name)
    when While     then While.new(@@at[0], @@at[1], r.call(e.cond), stmts(e.body, recv, tag, locals, block), e.inverted)
    when If        then If.new(@@at[0], @@at[1], r.call(e.cond), stmts(e.then_, recv, tag, locals, block), e.else_.try { |b| stmts(b, recv, tag, locals, block) }, e.negate, e.is_elsif, e.modifier)
    when Call
      callee_block = e.block.try do |b|
        Lambda.new(@@at[0], @@at[1], b.params.map { |p| Param.new(@@at[0], @@at[1], tag + p.name, p.type, p.default) }, stmts(b.body, recv, tag, locals, block), b.brace)
      end
      target = e.recv.try { |x| r.call(x) } || Ident.new(@@at[0], @@at[1], recv)
      Call.new(@@at[0], @@at[1], target, e.name, e.args.map(&r), e.named, callee_block, e.parens, @@at[0], @@at[1])
    when Return, Next, Break then raise "#{e.class.name.split("::").last} in a yielding method is not handled by the spike"
    else                          e
    end
  end

  # Runs the block on `program` changed so that it resolves: each `yield(e)`
  # in a yielder is just `e`, and each call to a yielder drops its block.
  # The changes are undone afterwards.
  def stubbed(program : Program, table, found : Array(Site), &)
    saved_bodies = table.values.map { |m| {m, m.body} }
    saved_calls = found.map { |site| {site.call, site.call.block, site.call.parens} }
    table.values.each { |m| m.body = m.body.try { |b| unyield(b) } }
    found.each { |site| site.call.block = nil; site.call.parens = true }
    begin
      yield
    ensure
      saved_bodies.each { |m, body| m.body = body }
      saved_calls.each { |call, block, parens| call.block = block; call.parens = parens }
    end
  end

  def unyield(body : Array(Expr)) : Array(Expr)
    body.map { |e| unyield(e) }
  end

  def unyield(e : Expr) : Expr
    case e
    when Call
      return e.args[0]? || NilLit.new(e.line, e.col) if e.recv.nil? && e.name == "yield"
      return Call.new(e.line, e.col, e.recv, e.name, e.args, e.named, nil, true, e.name_line, e.name_col) if @@names.includes?(e.name)
      block = e.block.try { |b| Lambda.new(b.line, b.col, b.params, unyield(b.body), b.brace) }
      Call.new(e.line, e.col, e.recv, e.name, e.args, e.named, block, e.parens, e.name_line, e.name_col)
    when While then While.new(e.line, e.col, e.cond, unyield(e.body), e.inverted)
    when If    then If.new(e.line, e.col, e.cond, unyield(e.then_), e.else_.try { |b| unyield(b) }, e.negate, e.is_elsif, e.modifier)
    else            e
    end
  end

  # `def _yf_items : this->T = @items`, with the yielder's capability.
  def add_accessors(program : Program) : Nil
    @@accessors.each do |owner, field, cap|
      decl = program.items.find { |i| i.is_a?(TypeDecl) && i.name == owner }.as(TypeDecl)
      f = decl.fields.find { |x| x.name == field } || raise "no field #{field}"
      type = ArrowType.new(f.line, f.col, NamedType.new(f.line, f.col, "this"), f.type || raise("untyped field"))
      body = [IVarRef.new(f.line, f.col, field)] of Expr
      decl.methods << Method.new(f.line, f.col, "def", cap, false, "_yf_#{field}", [] of Param, type, body, f.line, f.col)
    end
  end

  def run(path : String) : Nil
    source = File.read(path)
    program = Parser.parse(source)
    home = Driver.find_pony_home || raise "no Pony"
    table = yielders(program)
    names = table.keys.map(&.[1]).to_set
    @@names = names
    rounds = 0
    loop do
      found = sites(program, names)
      break if found.empty?
      rounds += 1
      positions = found.map { |s| {s.call.name_line, s.call.name_col} }.to_set
      types = {} of {Int32, Int32} => String
      stubbed(program, table, found) do
        # ponyc's state is global: one session at a time.
        calls = Driver.tree_calls([path], [source], [program], home) { }
        session = Ponyc::Session.new(home)
        begin
          types = session.receiver_types(positions) do |tree|
            Lowerer.new(tree, calls[path]? || Set({Int32, Int32}).new, Rules.primed_params([program]), Rules.enum_predicates([program])).lower(program, path, source)
          end
        ensure
          session.close
        end
      end
      found.reverse_each do |site|
        type = types[{site.call.name_line, site.call.name_col}]? || raise "no receiver type for #{site.call.name} at #{site.call.name_line}:#{site.call.name_col}"
        owner = type.split(/[\[ ]/).first
        m = table[{owner, site.call.name}]? || raise "#{owner} has no yielding #{site.call.name}"
        STDERR.puts "round #{rounds}: #{site.call.name} at #{site.call.name_line}:#{site.call.name_col} on #{type}"
        site.body[site.index, 1] = inline(site.call, m, owner)
      end
    end
    program.items.each { |item| item.methods.reject! { |m| table.values.includes?(m) } if item.is_a?(TypeDecl) }
    add_accessors(program)
    out_dir = File.join(".sparkle", "spike")
    Dir.mkdir_p(out_dir)
    calls = Driver.tree_calls([path], [source], [program], home) { }
    ok, errors = Ponyc.compile_tree(out_dir, "yield_spike", home) do |tree|
      Lowerer.new(tree, calls[path]? || Set({Int32, Int32}).new, Rules.primed_params([program]), Rules.enum_predicates([program])).lower(program, path, source)
    end
    STDERR.print errors
    exit 1 unless ok
    STDERR.puts "inlined in #{rounds} rounds"
    Process.run(File.join(out_dir, "yield_spike"), output: STDOUT, error: STDERR)
  end
end

YieldSpike.run(ARGV[0])
