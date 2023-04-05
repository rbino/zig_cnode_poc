# Zig Erlang C Node PoC

Using Zig to implement an Erlang [C Node](https://www.erlang.org/doc/man/ei_connect.html).

## Prerequisites

- `zig master` (this was created with the `0.11.0-dev.2371+a31450375` build), you can just do `asdf
  install` in the root folder if you use `asdf` with the [`zig`
  plugin](https://github.com/asdf-community/asdf-zig).

## How to use

From the root directory

```bash
$ zig build run
```

This starts the Zig node.

From another terminal, run a `iex` shell with:

```bash
$ iex --sname foo
```

Now you can connect to the Zig node with (replacing `yourhostname` with the hostname of the machine
you're executing this example on):

```elixir
iex> Node.connect(:"zig@yourhostname")
```

And send a message with:

```elixir
iex> send(:global.whereis_name(:ziggy), {self(), :hello})
```

The Zig node expects message in the format `{pid(), atom()}`. If you send `:ping` as atom, the Zig
node will reply to the pid contained in the message with the `:pong` atom.

```elixir
iex> send(:global.whereis_name(:ziggy), {self(), :ping})
iex> flush()
:pong
:ok
```
