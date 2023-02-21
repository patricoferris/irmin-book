# Versioned Data

Currently [Irmin][] only supports *monomorphic* operations over stores, meaning there can
only be one return type from functions like `Store.get`. On the way to heterogeneity, a logical
first stop is being able to *version* content datatypes.

Versioning in this sense relates to the type and not the value. Irmin let's you version OCaml values,
but we want to have different versions of the type of that value whilst still preserving key
characteristics of the Irmin store.

## Changing the Content Type

Before we do that, let's first look at how it can go wrong. First let's define two types that are meant
to represent the same value but just one version is newer and has added new fields.

<!-- $MDX file=bad-content-store/main.ml,part=contents -->
```ocaml
module C1 = struct
  type t = { name : string } [@@deriving irmin]

  let merge = Irmin.Merge.(option @@ default t)
end

module C2 = struct
  type t = { name : string; age : int }[@@deriving irmin]

  let merge = Irmin.Merge.(option @@ default t)
end
```

The only difference between the two types is the extra `age : int` field in `C2.t`. We can instantiate two Irmin
key-value stores that use the filesystem.

<!-- $MDX file=bad-content-store/main.ml,part=stores -->
```ocaml
module S1 = Irmin_fs_unix.KV.Make (C1)
module S2 = Irmin_fs_unix.KV.Make (C2)
```

And now we can store a `C1.t` in the store and try and read it back using the `S2` interface.

<!-- $MDX file=bad-content-store/main.ml,part=main -->
```ocaml
let main () =
  let conf = Irmin_fs.config "./tmp" in
  let* repo = S1.Repo.v conf in
  let* main = S1.main repo in
  let* () = S1.set_exn ~info main [ "a" ] C1.{ name = "Alice" } in
  let* repo = S2.Repo.v conf in
  let* main = S2.main repo in
  let* v = S2.get main [ "a" ] in
  Fmt.pr "Name: %s" v.name;
  Lwt.return_unit
```

But this goes wrong if we try running it!

```sh
$ ./bad-content-store/main.exe
Fatal error: exception Irmin.Tree.find_all: encountered dangling hash 15942488a5c800c506817379631ace9263149cf42b0c8bc409a5a6e9698d6e5194ff6d178365e1642d9b5b29dee30ed18e5b4605c281a35db7d214428bfff510
[2]
```

## Using Views

The following is courtesy of [Thomas Gazagnaire](https://github.com/samoht).

### Raw views

One way to fix this problem is to abstract the content type behind a view on it. This view
let's us hide some details to the end user whilst giving us the power to do more complex manipulations
of the data we are storing. To begin with, the view contains information about the version of the data.

<!-- $MDX file=views/main.ml,part=raw-types -->
```ocaml
  type v1 = { age : int } [@@deriving irmin ~pre_hash]
  type v2 = { age : int; name : string } [@@deriving irmin ~pre_hash]

  type t = V1 of v1 | V2 of v2 [@@deriving irmin]

  (* change depending on what you want to index - here we just skip the
     version field. Can only hash the age (but that will merge values
     with the same hash, so it's not a great index here). *)
  let pre_hash = function
    | V1 v -> pre_hash_v1 v
    | V2 v -> pre_hash_v2 v

  let t = Irmin.Type.like ~pre_hash t
```

This code handles serialising the version information so we can re-use that later without polluting
the content-addressable storage with fields we might not have later. For example, a user might only
habe their `age` and not be aware of the `V1` version number, but they don't need to be aware of it
for us to do content-addressed lookups for the data.

However, we do need to manage smooth upgrades and downgrades from the versions but this is only verbose,
not complicated.

<!-- $MDX file=views/main.ml,part=raw-helpers -->
```ocaml
  let default_name = "Default Name"
  let v1 age = { age }
  let v2 ?(name = default_name) age = { age; name }
  let v1_to_v2 : v1 -> v2 = fun { age } -> v2 age
  let v2_to_v1 : v2 -> v1 = fun { age; _ } -> { age }
  let to_v2 = function V1 v -> v1_to_v2 v | V2 v -> v
  let to_v1 = function V1 v -> v | (V2 _) as v -> v2_to_v1 (to_v2 v)
  let merge_v1 = Irmin.Merge.(default v1_t)
  let merge_v2 = Irmin.Merge.(default v2_t)
```

Finally, we need to define a sufficient default merge function over versioned data.

<!-- $MDX file=views/main.ml,part=raw-merge -->
```ocaml
  let merge : t Irmin.Merge.t =
    let open Lwt_result.Infix in
    let promise x = Irmin.Merge.promise x in
    let upgrade x = V2 (to_v2 x) in
    let wrap_v1 v = V1 v in
    let wrap_v2 v = V2 v in
    let rec f ~old x y =
      old () >>= fun old ->
      match (old, x, y) with
      | Some (V1 old), V1 x, V1 y ->
          Irmin.Merge.f merge_v1 ~old:(promise old) x y >|= wrap_v1
      | Some (V2 old), V2 x, V2 y ->
          Irmin.Merge.f merge_v2 ~old:(promise old) x y >|= wrap_v2
      | _ ->
          let old =
            match old with
            | None -> fun () -> Lwt.return (Ok None)
            | Some old -> promise (upgrade old)
          in
          f ~old (upgrade x) (upgrade y)
    in
    Irmin.Merge.seq [ Irmin.Merge.default t; Irmin.Merge.v t f ]
```

### Higher-level Abstraction

With our raw views we can now provide a higher-level abstraction to use within our actual Irmin stores.

<!-- $MDX file=views/main.ml,part=view -->
```ocaml
type 'a view = { payload : 'a; raw : Raw.t }

let version v = match v.raw with V1 _ -> 1 | V2 _ -> 2

module C1 = struct
  type t = Raw.v1 view

  let of_raw raw =
    let payload = Raw.to_v1 raw in
    { payload; raw }

  let to_raw t = t.raw
  let t = Irmin.Type.map Raw.t of_raw to_raw

  let v age =
    let v = Raw.v1 age in
    { payload = v; raw = V1 v }

  let merge = Irmin.Merge.(option @@ like t Raw.merge to_raw of_raw)
end
```

To be concise only `V1` is shown here but as you can see it reuses all of the `Raw` values we defined
previously. We can always convert to and from an `Raw.t` and that is how the runtime value `t` is defined.
This means if we pull a `V2` out of the store but the serialised version is a `V1` we can still deserialise it.

We can use these `Content` modules for stores now.

<!-- $MDX file=views/main.ml,part=stores -->
```ocaml
module S1 = Irmin_fs_unix.KV.Make (C1)
module S2 = Irmin_fs_unix.KV.Make (C2)
```

And finally write a program where we interleave the stores, reading old and new values as we go!

<!-- $MDX file=views/main.ml,part=main -->
```ocaml
let main () =
  let config = Irmin_fs.config "./tmp2" in
  let* repo = S1.Repo.v config in
  let* main = S1.main repo in
  let* repo2 = S2.Repo.v config in
  let* main2 = S2.main repo2 in
  let c1 = C1.v 42 in
  let _h1 = S1.Contents.hash c1 in
  let* () = S1.set_exn ~info:info1 main [ "a" ] c1 in
  Fmt.pr "Storing S1 at a: { age = %i }\n%!" c1.payload.age;
  let* v1 = S1.get main [ "a" ] in
  Fmt.pr "S1 lookup a: %i (version = %d)\n%!" v1.payload.age (version v1);
  let* v2 = S2.get main2 [ "a" ] in
  Fmt.pr "S2 lookup a: %i (version = %d)\n%!" v2.payload.age (version v2);
  let c2 = C2.v 43 ~name:"Alice" in
  let* () = S2.set_exn ~info:info2 main2 [ "b" ] c2 in
  Fmt.pr "Storing S2 at b: { age = %i; name = %s }\n%!" c2.payload.age c2.payload.name;
  let* v = S2.get main2 [ "a" ] in
  Fmt.pr "S2 lookup a: %s %i (version = %d)\n%!" v.payload.name v.payload.age
    (version v);
  let* v = S1.get main [ "b" ] in
  Fmt.pr "S1 lookup b for age: %i\n%!" v.payload.age;
  Lwt.return_unit
```

Let's run the program!

```sh
$ ./views/main.exe
Storing S1 at a: { age = 42 }
S1 lookup a: 42 (version = 1)
S2 lookup a: 42 (version = 1)
Storing S2 at b: { age = 43; name = Alice }
S2 lookup a: Default Name 42 (version = 1)
S1 lookup b for age: 43
```

{{#include ../links.md}}
