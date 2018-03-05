open XMLOutput

module type Type = sig
    (** Module defining an interval datatype, see {!val:itvize}. *)
    module Interval : sig
        type t
    end

    (** Name of the domain. *)
    val name : string

    (** Type of an abstract value. *)
    type t =
        | Top
        | Bot
        | Name of string

    (** Top abstract value *)
    val top: t

    (** Bottom abstract value *)
    val bottom: t

    (** Tests if the given abstract value is bottom. *)
    val is_bottom: t -> bool

    (** Computes the effect of a guard on an abstract value. *)
    val assume: string -> Cabs.expression -> t -> t

    (** Computes the effect of a list of parallel assignments on an abstract value. *)
    val assign : string -> (Domain.variable * Cabs.expression) list -> t -> t

    (** Computes the meet of two abstract values. *)
    val meet : string -> t -> t -> t

    (** Computes the join of two abstract values. *)
    val join: string -> t -> t -> t

    (** Eliminates the given list of variables from the given abstract value.*)
    val project: string -> Domain.variable list -> t -> t

    (** Minimizes the representation of the given abstract value. *)
    val minimize : string -> t -> t

    (** Computes the widening of two abstract values. *)
    val widen: string -> t -> t -> t

    (** [leq a1 a2] tests if [a1] is included into [a2]. *)
    val leq: t -> t -> bool

    val print : t -> unit

    (** Computes an interval of the values that the given expression can reach in the given abstract value. *)
    val itvize : t ->  Cabs.expression -> Interval.t

    (** Returns true if the given name is associated to an abstract value. *)
    val is_bound : string -> bool
end

module Lift (D : Domain.Type) : Type = struct

    (** Map indexed by strings. *)
    module MapS = Map.Make(struct type t = string let compare = Pervasives.compare end)

	(* Map associating abstract values to their name. *)
	let mapVal : D.t MapS.t ref = ref MapS.empty

	(**
		Returns the abstract value currently associated to the given name.
		@raise Invalid_argument if the name has got no association in the map.
	*)
    let get : string -> D.t
        = fun s ->
        try
            MapS.find s !mapVal
        with Not_found -> Pervasives.invalid_arg (Printf.sprintf "Run_Domain.get %s : %s" D.name s)

    let is_bound : string -> bool
        = fun s ->
        MapS.mem s !mapVal

	(** Associates a name and an abstract value in map !{!val:mapVal}. *)
	let set : D.t -> string -> unit
		= fun state name ->
		mapVal := MapS.add name state !mapVal

    (* DOMAIN TYPES *)

    let name = D.name ^ ":dirty"

    type t =
        | Top
    	| Bot
    	| Name of string

    let top = Top
    let bottom = Bot

    let state_to_string : t -> string
    	= function
    	| Top -> "top"
    	| Bot -> "bot"
    	| Name name -> name

    let value : t -> D.t
		= function
		| Top -> D.top
		| Bot -> D.bottom
		| Name s -> get s

    let lift : (D.t -> D.t -> D.t) -> string -> t -> t -> t
        = fun operator output_name p1 p2 ->
        set (operator (value p1) (value p2)) output_name;
        Name output_name

    (* OPERATORS *)
    let print : t -> unit
        = function
    	| Top -> print_string "top"
    	| Bot -> print_string "bot"
    	| Name name -> begin
            print_endline (name ^ ":");
            D.print (get name)
        end

    let meet = lift D.meet
    let join = lift D.join
    let widen = lift D.widen

	let assume : string -> Cabs.expression -> t -> t
        = fun output_name cond p2 ->
		set (D.assume cond (value p2)) output_name;
        Name output_name

	let assign : string -> (Domain.variable * Cabs.expression) list -> t -> t
        = fun output_name assigns p ->
		set (D.assign assigns (value p)) output_name;
        Name output_name

	let project : string -> Domain.variable list -> t -> t
        = fun output_name vars p ->
		set (D.project vars (value p)) output_name;
        Name output_name

	let minimize : string -> t -> t
        = fun output_name p ->
		set (D.minimize (value p)) output_name;
        Name output_name

    let is_bottom : t -> bool
        = fun p ->
        D.is_bottom (value p)

    let leq : t -> t -> bool
        = fun p1 p2 ->
        D.leq (value p1) (value p2)

    module Interval = D.Interval


    let itvize : t ->  Cabs.expression -> Interval.t
        = fun p expr ->
        D.itvize (value p) expr
end
