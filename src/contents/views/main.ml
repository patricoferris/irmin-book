open Lwt.Syntax


module Raw = struct
  (* $MDX part-begin=raw-types *)
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
  (* $MDX part-end *)

  (* $MDX part-begin=raw-helpers *)
  let default_name = "Default Name"
  let v1 age = { age }
  let v2 ?(name = default_name) age = { age; name }
  let v1_to_v2 : v1 -> v2 = fun { age } -> v2 age
  let v2_to_v1 : v2 -> v1 = fun { age; _ } -> { age }
  let to_v2 = function V1 v -> v1_to_v2 v | V2 v -> v
  let to_v1 = function V1 v -> v | (V2 _) as v -> v2_to_v1 (to_v2 v)
  let merge_v1 = Irmin.Merge.(default v1_t)
  let merge_v2 = Irmin.Merge.(default v2_t)
  (* $MDX part-end *)

  (* $MDX part-begin=raw-merge *)
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
  (* $MDX part-end *)
end

(* $MDX part-begin=view *)
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
(* $MDX part-end *)

module C2 = struct
  type t = Raw.v2 view

  let of_raw raw =
    let payload = Raw.to_v2 raw in
    { payload; raw }

  let to_raw t = t.raw
  let t = Irmin.Type.map Raw.t of_raw to_raw

  let v ~name age : t =
    let v = Raw.v2 ~name age in
    { payload = v; raw = V2 v }

  let merge = Irmin.Merge.(option @@ like t Raw.merge to_raw of_raw)
end

(* $MDX part-begin=stores *)
module S1 = Irmin_fs_unix.KV.Make (C1)
module S2 = Irmin_fs_unix.KV.Make (C2)
(* $MDX part-end *)
let info1 = S1.Info.none
let info2 = S2.Info.none

(* $MDX part-begin=main *)
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
(* $MDX part-end *)

let () = Lwt_main.run @@ main ()