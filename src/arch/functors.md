# A Primer on Functors

Programming applications in Irmin requires a familiarity with OCaml's functors. Here are a few resources for learning more about them:

 - [The OCaml manual](https://v2.ocaml.org/releases/4.14/htmlman/moduleexamples.html#s%3Afunctors): The definitive guide to different aspects of the OCaml language.

What follows is an Irmin-specific introduction to functors.

## Generalisation

Functors, in a non-theoretical sense, can be thought of as functions over modules. A functor takes a module and produces another module. For example, we might produce a new module that hashes values provided they can be serialised to a string.

```ocaml
(* A module signature for modules who have a main type called [t]
   and that provide a function [serialise] to convert [t] to a [string]. *)
module type Serialisable = sig
    type t
    val serialise : t -> string
end
```

We will also need another module signature describing what a digestable type looks like.

```ocaml
module type Digestable = sig
    type t
    (** The values to digest *)

    type hash
    (** The type of digests produced *)

    val hash_to_string : hash -> string
    (** Convert digests to a string *)

    val digest : t -> hash
end
```

We could then provide a SHA256 hashing functor for serialisable types.

```ocaml
module SHA256 (S : Serialisable) : Digestable with type t = S.t and type hash = Digestif.SHA256.t = struct
    type t = S.t
    type hash = Digestif.SHA256.t
    let hash_to_string = Digestif.SHA256.to_raw_string
    let digest v = Digestif.SHA256.digest_string (S.serialise v)
end
```

We can then use our functor.

```ocaml
module Integer = struct
  type t = int
  let serialise = string_of_int
end

module Digest_int = SHA256(Integer)
```

And then use it.

```ocaml
# let d = Digest_int.digest 42;;
val d : Digest_int.hash = <abstr>
# Digest_int.hash_to_string d |> Base64.encode_exn;;
- : string = "c0dctApWjo2ooEXO0RATfhWfiQrE2og7axfcZRs6gEk="
```
