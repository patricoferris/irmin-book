# JSON at Rest

As has been mentioned many times, Irmin is fundamentally a key-value store. Thanks to its portability and flexibility both in storage backend and data format, Irmin is not the only means by which to interact with the data.

### Storing JSON values

We can instantiate a simple in-memory Irmin store that stores JSON objects.

```ocaml
module Store = Irmin_mem.KV.Make (Irmin.Contents.Json)
let info () = Store.Info.v (Unix.gettimeofday () |> Int64.of_float)
```

The type of JSON objects is identical to that of the [Ezjsonm](https://github.com/mirage/ezjsonm) library. The objects are *association lists* (lists of pairs where the first pair is a string, like a dictionary in other programming languages).

```ocaml
# #show Irmin.Contents.Json.t;;
val t : Store.contents Repr.ty
type nonrec t = (string * Irmin.Contents.json) list
```

This is very convenient, and we can quickly get and set values directly in the store using JSON-like OCaml values. The fact that the Ezjsonm representation of JSON values and the Irmin representation are the same is no coincidence, however, there is no strict dependency between the two so they could change in the future.

```ocaml
# let set_json_string_exn s k v =
  match Ezjsonm.value_from_string v with
  | `O assoc -> Store.set_exn ~info s k assoc
  | _ -> Lwt.fail (Failure "Expected a JSON object as a string");;
val set_json_string_exn : Store.t -> Store.path -> string -> unit Lwt.t =
  <fun>
```

From here we can now add JSON objects directly into the store.

```ocaml
# let config = Irmin_mem.config () in
  let* repo = Store.Repo.v config in
  let* main = Store.main repo in
  let* () = set_json_string_exn main [ "a" ] {|{ "hello": "world" }|} in
  let+ s = Store.get main [ "a" ] in
  print_endline @@ Ezjsonm.value_to_string (`O s);;
{"hello":"world"}
- : unit = ()
```

### Custom Types Stored as JSON

One problem with using `Irmin.Contents.Json.t` is that we've lost the richness of the OCaml type system to a certain extent. This means it isn't obvious what are store is actually storing. Is it random JSON objects or a serialisation of a more rich OCaml value? If it is the latter, it probably isn't the interface we want.

For example, consider the following simple message datatype.

```ocaml
module type Message = sig
  type t = string [@@deriving irmin]

  include Irmin.Contents.S with type t := t
end

module Message : Message = struct
  type t = string [@@deriving irmin]

  let merge ~old:_ a b =
    match String.compare a b with
    | 0 ->
        if Irmin.Type.(unstage (equal t)) a b then
            Irmin.Merge.ok a
        else
            let msg = "Conflicting entries have the same timestamp but different values" in
            Irmin.Merge.conflict "%s" msg
    | 1 -> Irmin.Merge.ok a
    | _ -> Irmin.Merge.ok b
    
  let merge = Irmin.Merge.(option (v t merge))
end
```

By default if we create a store with this content type, the data will be stored using the string representation defined in [repr](https://github.com/mirage/repr). For the most part this is actually quite JSON-like.

```ocaml
# Irmin.Type.to_string Message.t "Hello World";;
- : string = "Hello World"
```

But there is an actual JSON-backend to the representation.

```ocaml
# Irmin.Type.to_json_string Message.t "Hello World";;
- : string = "\"Hello World\""
```

In fact for the most part the encoding does use JSON to format the OCaml values. The difference are usually very subtle, for example OCaml strings are just bytes whereas for JSON they must be UTF-8. So we can get very different formats (or as above where the JSON string requires the inverted-commas).

```ocaml
let _no_output_because_utf8 = Irmin.Type.to_string Message.t "\xc3\x28"
```

Whereas we must convert to a UTF-8 string that we can serialise and deserialise.

```ocaml
# Irmin.Type.to_json_string Message.t "\xc3\x28";;
- : string = "{\"base64\":\"wyg=\"}"
```

Fortunately, we can override the runtime representation of the type Irmin uses to store the values and keep the richness of the actual type when programming with the Irmin interface, but be serialising the data into JSON values. This is particularly useful, for example, with the `Git.FS` backend to read and write JSON values in Git stores.

```ocaml
module Message_json : Message = struct
  type t = string [@@deriving irmin]

  let merge ~old:_ a b =
    match String.compare a b with
    | 0 ->
        if Irmin.Type.(unstage (equal t)) a b then
            Irmin.Merge.ok a
        else
            let msg = "Conflicting entries have the same timestamp but different values" in
            Irmin.Merge.conflict "%s" msg
    | 1 -> Irmin.Merge.ok a
    | _ -> Irmin.Merge.ok b

  let t = Irmin.(Type.like ~pp:(Type.pp_json t) ~of_string:(Type.of_json_string t) t)
    
  let merge = Irmin.Merge.(option (v t merge))
end
```


