(** Erlang ports, the Lwt way! *)

module Alberto_lwt : sig
  val read_term : Lwt_io.input_channel -> Alberto.t Lwt.t
  (** [read_term ic] fetches an Erlang [!term] from the port channel [ic]. *)

  val write_term : Lwt_io.output_channel -> Alberto.t -> unit Lwt.t
  (** [write_term oc term] serializes a given Erlang [!term] to the port
      channel [oc]. *)

  val interact : (Alberto.t -> Alberto.t) -> unit Lwt.t
  (** [interact f] main port loop, recieves Erlang terms from stdin,
      executes a given key function [f] and sends back the results. *)
end = struct
  open Lwt

  let rec read_term ic =
    Lwt_io.BE.read_int ic >>= fun len ->
    (* The current version of lwt doesn't use -safe-string. *)
    let buf = Bytes.create len in
    Lwt_io.read_into_exactly ic buf 0 len >>= fun _ ->
    return @@ Alberto.decode_exn (Bytes.to_string buf)

  and write_term oc term =
    let buf = Alberto.encode_exn term in
    Lwt_io.BE.write_int oc (String.length buf) >>= fun () ->
    Lwt_io.write oc buf >>= fun () -> Lwt_io.flush oc

  and interact f =
    let rec transform state = function
      | `Atom "stop" -> exit 0
      | `Atom "ping" -> state, `Atom "pong"
      | term ->
        let term = try f term with exn ->
          `Tuple [`Atom "error";
                  `Tuple [term; `String (Printexc.to_string exn)]]
        in (state, term)
    and loop state =
      read_term Lwt_io.stdin >>= fun term ->
      let (state, term) = transform state term in
      write_term Lwt_io.stdout term >>= fun () -> loop state
    in Lwt.catch (fun () -> loop 0) (fun exn ->
        match exn with
          | End_of_file -> exit 1
          | _ -> raise exn)
end


let () = Lwt_main.run (Alberto_lwt.interact (fun x -> x))
