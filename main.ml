module Message_json = struct
  type name = string [@@deriving irmin]
  type t = name list [@@deriving irmin]

  let merge ~old:_ a b =
    match List.compare String.compare a b with
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

let v = 
  let msg = [ "\xc3\x28" ] in
  Fmt.str "%s" Irmin.Type.(to_string Message_json.t msg),
  Fmt.str "%a" Fmt.(list string) (List.map Irmin.Type.(to_string Message_json.name_t) msg)