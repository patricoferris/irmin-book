# Runtime Types

One thing that will quickly become very apparent is the need to define an `'a Irmin.Type.t` for nearly every type. This is a so-called runtime type. It _represents_ the type `'a` at runtime as an OCaml value.

Internally it reuses the [mirage/repr](https://github.com/mirage/repr) library. Some runtime types come predefined, such as that for boolean values.

```ocaml
# Irmin.Type.bool;;
- : bool Repr.ty = <abstr>
```

This carries information with it about how to interact with actual `bool` values, for example how to serialise it in different ways.

```ocaml
# Irmin.Type.to_string Irmin.Type.bool true;;
- : string = "true"
# Irmin.Type.to_json_string Irmin.Type.bool true;;
- : string = "true"
```

## ppx_irmin

Because so many modules and functions expect a runtime type, Irmin provides a ppx that can in the majority of cases derive the runtime representation of your type for you.

```ocaml
# type t = { name : string }[@@deriving irmin];;
type t = { name : string; }
val t : t Repr.ty = <abstr>
```

You can see that this created a _value_ called `t` (not to be confused with the type itself). 

```ocaml
# Irmin.Type.to_string t { name = "Bob" };;
- : string = "{\"name\":\"Bob\"}"
```

You can also build up representations of more complex types using the built-in combinators.

```ocaml
# let t = Irmin.Type.(list (pair string (option int)));;
val t : (string * int option) list Repr.ty = <abstr>
```

## Uses

Irmin mainly uses the runtime types for serialisation purposes. For example if your Irmin store is using the file system backend (`Irmin.FS`) then Irmin needs to know how to turn your contents into a string and your key into a file path. Conversely, it will need to know how to turn file paths into your path type and file contents into your content type.

```ocaml
# let s = Irmin.Type.to_string t [ "key1", Some 1; "key2", None ];;
val s : string = "[[\"key1\",{\"some\":1}],[\"key2\",null]]"
# let v = Irmin.Type.of_string t s;;
val v : ((string * int option) list, [ `Msg of string ]) result =
  Ok [("key1", Some 1); ("key2", None)]
```

