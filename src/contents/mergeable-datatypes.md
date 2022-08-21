# Mergeable Datatypes

One of Irmin's major selling points is having _mergeable datatypes_ (MDT). These are values that have a three-way merge function. If you are familiar with the `git` version control system then the idea should be familiar. 

Whenever you want to store some new value `x` in an Irmin store `S` at key `k`, there are two other _versions_ of `x` to consider. 

 1. The current version of `x` in store `S` at key `k` let's call it `x'`.
 2. The shared **lowest-common ancestor** (LCA) of `x` and `x'` in store `S` at key `k` let's call it `lca`.

A merge function takes these three values and either produces some "merged" value or we have a merge conflict and we return an error. A merge function for values of type `'a` are of type `'a Irmin.Merge.f`.

```ocaml
# #show_type Irmin.Merge.f;;
type nonrec 'a f =
    old:'a Irmin.Merge.promise ->
    'a -> 'a -> ('a, Irmin.Merge.conflict) result Lwt.t
```

Let's take a look at a few examples.

## Mergeable Counters

The classic MDT is a counter, an integer value that can be incremented and decremented.

```ocaml
module Counter = struct
  type t = int [@@deriving irmin]
  let incr t = t + 1
  let decr t = t - 1
end
```

By using `ppx_irmin` we derive a runtime representation of the type `t`. This creates a _value_ in the module called `t`. We're not quite ready to use our new module to instantiate a new, in-memory key-value Irmin store though.

```ocaml
# module Store = Irmin_mem.KV.Make (Counter);;
Line 1, characters 16-43:
Error: Modules do not match:
       sig
         type t = int
         val t : t Repr__Type.t
         val incr : t -> t
         val decr : t -> t
       end
     is not included in Irmin__.Contents.S
     The value `merge' is required but not provided
     File "src/irmin/contents_intf.ml", line 25, characters 2-30:
       Expected declaration
```

We need to provide a merge function! What properties should it have? The main one is probably that simultaneous increments and/or decrements should not be lost in the new merged value.

For example if Alice has a copy of the counter and increments it five times and Bob has a copy and decrements it twice, the final merged counter should be the lowest common ancestor plus five minus two.

```ocaml
module Counter = struct
  type t = int [@@deriving irmin]
  let incr t = t + 1
  let decr t = t - 1

  let merge ~old t1 t2 =
    let open Irmin.Merge.Infix in
    old () >>=* fun old ->
    let old = match old with None -> 0 | Some v -> v in
    let diff1 = t1 - old in
    let diff2 = t2 - old in
    Fmt.pr "LCA: %i, Diff1: %i, Diff2: %i%!" old diff1 diff2;
    Irmin.Merge.ok (old + diff1 + diff2)

  let merge = Irmin.Merge.(option (v t merge))
end
module Store = Irmin_mem.KV.Make (Counter)
let info () = Store.Info.v (Unix.gettimeofday () |> Int64.of_float);;
```

Note that the merge function here contains a print statement that you might actually debug log (with `Logs.debug`) to show the two diffs whenever the merge function is called. This is so we can see what is happening later on.

From here we can recreate the scenario between Alice and Bob. We'll use different branches to represent multiple stores.

```ocaml
let alice_action s = 
  let* v = Store.get s [ "counter" ] in
  let c = 
    Counter.incr v 
    |> Counter.incr
    |> Counter.incr
    |> Counter.incr
    |> Counter.incr
  in
  Store.set_exn ~info s [ "counter" ] c

let bob_action s = 
  let* v = Store.get s [ "counter" ] in
  let c = 
    Counter.decr v 
    |> Counter.decr
  in
  Store.set_exn ~info s [ "counter" ] c
```

Now for the main function which initialises the main store and applies both Alice's and Bob's actions and tries to merge them into the store.

```ocaml
# let config = Irmin_mem.config () in
  (* Initialise a new empty store and add counter with value 10 *)
  let* repo = Store.Repo.v config in
  let* main = Store.main repo in
  let* () = Store.set_exn ~info main [ "counter" ] 10 in

  (* Create two new branches as clones of the [main] branch *)
  let* alice_branch = Store.clone ~src:main ~dst:"alice" in
  let* bob_branch = Store.clone ~src:main ~dst:"bob" in

  (* Apply the actions *)
  let* () = alice_action alice_branch in
  let* () = bob_action bob_branch in

  (* Merge the results *)
  let* () = 
    let+ merge = Store.merge_into ~into:main ~info alice_branch in
    Result.get_ok merge
  in
  let* () = 
    let+ merge = Store.merge_into ~into:main ~info bob_branch  in
    Result.get_ok merge
  in
  Store.get main [ "counter" ];;
LCA: 10, Diff1: -2, Diff2: 5
- : int = 13
```

The merge function was only needed once. When `alice_action` is applied, it is a simple "fast-forward" merge because there is no three-way merge required. However, when `bob_action` is applied there is now the LCA (the initial `10` value), Bob's new value (`8`) and Alice's value that has been merged (`15`).

## Standard Mergeable Containers

It is quite common to use a basic set of mergeable datatypes to construct new custom MDTs by first converting your type to that datatype and performing the merge.
