# Contracts

A method states what it `expects` of its caller and what it `guarantees` in return; a type states what it `maintains`. Each clause is checked when the program runs.

```crystal
class Account
  maintains @balance >= 0

  @balance : Int64 = 0

  def ref deposit(amount : Int64)
    expects amount > 0
    guarantees @balance == old(@balance) + amount

    @balance += amount
  end

  def ref withdraw(amount : Int64) : Int64
    expects amount > 0, amount <= @balance
    guarantees result == amount

    @balance -= amount
    amount
  end

  def balance : Int64 = @balance
end

actor Main
  def self.new(env : Env)
    account = Account.new
    account.deposit(100)
    taken = account.withdraw(30)
    env.out <~ print("left #{account.balance}")
  end
end
```

```text
left 70
```

## Clauses

| Clause | Written | Checked | A failure means |
|---|---|---|---|
| `expects cond, …` | first lines of a `def` or `on` | on entry | the caller broke the contract |
| `guarantees cond, …` | after any `expects` | on each normal return | the method broke its promise |
| `maintains cond, …` | first lines of a `class`, `struct` or `actor` | after each constructor, public `ref` method and message handler | the type broke its own rule |

- The body starts at the first line that is not a clause. A one-line `def x = expr` takes none.
- Commas separate conditions; each is checked and reported on its own.
- In `guarantees`, `result` is the return value and `old(expr)` is `expr` before the body ran. `old` needs a `val` value, such as a number or `Bool`: write `old(@items.size)`, not `old(@items)`.
- `expects`, `guarantees` and `maintains` are reserved words.

## Failure

A failed clause prints where it is and exits with status 1. Withdrawing 500 from the account above prints, on standard error:

```text
main.spk:14:25: contract failed in Account.withdraw: expects amount <= @balance
```

It is not an error that `rescue` can catch: a broken contract is a bug, not a case to handle. Output not yet written by `env.out` may be lost.

## Read-only

A condition sees `self` and the arguments as `box`, so it cannot change them. Calling a `ref` method in one is a type error:

```text
main.spk:5:20: receiver type is not a subtype of target type
    expects @lines.push(line) == None
                   ^
```

An `iso` argument or result cannot be read in a clause: seen as `box`, it is a `tag`.

## Where each applies

| Method | `expects` | `guarantees` | `maintains` after it |
|---|---|---|---|
| `def` (`box`) | yes | yes | no: it cannot change `self` |
| `def ref`, public | yes | yes | yes |
| `def ref _helper` | yes | yes | no: a helper may leave the rule broken for its caller to restore |
| `def self.new` | its arguments only | yes, without `result` or `old` | yes |
| `on` | yes, when the message is processed | no: no caller sees its end | yes |
| `def name!` | yes | on normal return only | yes, if `ref` |

```crystal
actor Counter
  maintains @count <= 10

  @count : Int32 = 0

  on add(n : Int32)
    expects n > 0
    @count += n
  end
end
```

## Builds

| Command | Checks |
|---|---|
| `sparkle check`, `sparkle build`, `sparkle run` | every clause |
| `--release` | `expects` only |
| `--release --contracts=all` | every clause |

Clauses on a method that yields, an abstract method or a `tag` method are not supported yet. See [limits](limits.md).
