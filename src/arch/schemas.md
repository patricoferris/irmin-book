# Schemas

Every Irmin store has a schema. This specifies the concrete implementations of the various kinds of customisable aspects of the store. For example what type are the keys, the branches and the contents.

In Irmin everything gets specified upfront using functor application. Whereas with something like `Hashtbl` its type will be inferred but its use.

Most stores take a `Schema` module to provide the concrete implementation of the various customisable parts of the Irmin store. This can be a little verbose, but most of the time the defaults are just fine.

```ocaml
module Schema : Irmin.Schema.S = struct
  open Irmin
  module Hash = Hash.BLAKE2B
  module Info = Info.Default
  module Branch = Branch.String
  module Path = Path.String_list
  module Metadata = Metadata.None
  module Contents = struct
    type t = int[@@deriving irmin]
    let merge = Irmin.Merge.(option @@ default t) 
  end
end
module S = Irmin_mem.Make (Schema)
(* A fake clock and info function for our commits *)
let clock = let time = ref 0L in fun () -> time := Int64.add !time 1L; !time
let info () = S.Info.v (clock ())
```

Here we've defined a schema to use Blake2B hash functions, default commit information, branches are strings, keys (or paths) are string lists, no extra metadata and finally the content of the store is integers.

However, we'll quickly run into problems as soon as we try to use the store.

```ocaml
# let config = Irmin_mem.config () in
  let* repo = S.Repo.v config in
  let* main = S.main repo in
  let* () = S.set_exn ~info main [ "hello" ] 1 in
  S.get main [ "hello" ];;
Line 4, characters 34-45:
Error: This expression has type 'a list
       but an expression was expected of type S.path
```

This is because in our definition of the schema we _hid_ the implementation details by adding `: Irmin.Schema.S`. So either we canleave that part out or we must provide a module type to expose the information (or at the very least the bits we need).

```ocaml
module type String_list_int_schema = Irmin.Schema.S 
   with type Hash.t = Irmin.Schema.default_hash
    and type Branch.t = string
    and type Info.t = Irmin.Info.default
    and type Metadata.t = unit
    and type Path.step = string
    and type Path.t = string list
    and type Contents.t = int
```

And then use that to define the store.

```ocaml
module Schema2 : String_list_int_schema = struct
  open Irmin
  module Hash = Hash.BLAKE2B
  module Info = Info.Default
  module Branch = Branch.String
  module Path = Path.String_list
  module Metadata = Metadata.None
  module Contents = struct
    type t = int[@@deriving irmin]
    let merge = Irmin.Merge.(option @@ default t) 
  end
end
module S = Irmin_mem.Make (Schema2)
let info () = S.Info.v (clock ())
```

And now the compiler knows what the types are (they haven't been abstracted away).

```ocaml
# let config = Irmin_mem.config () in
  let* repo = S.Repo.v config in
  let* main = S.main repo in
  let* () = S.set_exn ~info main [ "hello" ] 1 in
  S.get main [ "hello" ];;
- : int = 1
```
