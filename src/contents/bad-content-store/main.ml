open Lwt.Syntax

(* $MDX part-begin=contents *)
module C1 = struct
  type t = { name : string } [@@deriving irmin]

  let merge = Irmin.Merge.(option @@ default t)
end

module C2 = struct
  type t = { name : string; age : int }[@@deriving irmin]

  let merge = Irmin.Merge.(option @@ default t)
end
(* $MDX part-end *)

(* $MDX part-begin=stores *)
module S1 = Irmin_fs_unix.KV.Make (C1)
module S2 = Irmin_fs_unix.KV.Make (C2)
(* $MDX part-end *)

let info () = S1.Info.v 0L

(* $MDX part-begin=main *)
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
(* $MDX part-end *)

let () = Lwt_main.run @@ main ()