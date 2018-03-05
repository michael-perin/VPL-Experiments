(**
	This module provides a functor that takes an abstract domain and allows to run traces with it.
	Each operator has a dedicated timer.
*)

open XMLOutput

(**
	Folder that contains polyhedron files.
	The [load] operator will look for files in this folder.
 *)
let folder : string ref = ref ""

let variables : Domain.variable list ref = ref []

let add_variable : Domain.variable -> unit
	= fun var ->
	variables := !variables @ [var]

let (list_to_string : ('a -> string) -> 'a list -> string -> string)
	= fun to_string l sep->
	Printf.sprintf "[%s]" (String.concat sep (List.map to_string l))

let rec expression_to_string : Cabs.expression -> string
	= Cabs.(function
	| NOTHING -> "skip"
	| UNARY (MINUS, e) -> Printf.sprintf "-(%s)" (expression_to_string e)
	| UNARY (PLUS, e) -> Printf.sprintf "+(%s)" (expression_to_string e)
	| UNARY (NOT, e) -> Printf.sprintf "!(%s)" (expression_to_string e)
	| UNARY (POSINCR, e) -> Printf.sprintf "%s++" (expression_to_string e)
	| UNARY (POSDECR, e) -> Printf.sprintf "%s--" (expression_to_string e)
	| BINARY (ADD, e1, e2) -> Printf.sprintf "%s + %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (SUB, e1, e2) -> Printf.sprintf "%s - %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (MUL, e1, e2) -> Printf.sprintf "%s * %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (DIV, e1, e2) -> Printf.sprintf "%s / %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (AND, e1, e2) -> Printf.sprintf "%s && %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (OR, e1, e2) -> Printf.sprintf "%s || %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (BAND, e1, e2) -> Printf.sprintf "%s & %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (BOR, e1, e2) -> Printf.sprintf "%s | %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (EQ, e1, e2) -> Printf.sprintf "%s == %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (LE, e1, e2) -> Printf.sprintf "%s <= %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (LT, e1, e2) -> Printf.sprintf "%s < %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (GE, e1, e2) -> Printf.sprintf "%s >= %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (GT, e1, e2) -> Printf.sprintf "%s > %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (NE, e1, e2) -> Printf.sprintf "%s != %s" (expression_to_string e1) (expression_to_string e2)
	| BINARY (ASSIGN, e1, e2) -> Printf.sprintf "%s = %s" (expression_to_string e1) (expression_to_string e2)
	| CALL (f, args) -> Printf.sprintf "%s (%s)"
		(expression_to_string f)
		(list_to_string expression_to_string args ", ")
	| COMMA es -> list_to_string expression_to_string es ", "
	| CONSTANT (CONST_INT i) -> i
	| CONSTANT (CONST_FLOAT f) -> f
	| VARIABLE var -> var
	| _ -> Pervasives.invalid_arg "expression_to_string"
	)

(**
	This functor takes an abstract domain and provides a function [run] for running the domain on a trace.
*)
module Lift (D : DirtyDomain.Type) = struct

	let load : string -> Cabs.expression
		= let rec(substring : string -> int -> string)
			= fun s i ->
			(String.sub s i ((String.length s) - i))
		in
		let is_the_poly : string -> string -> bool
			= fun id s ->
			try
				let ri = String.rindex s '_' in
				let id_s = substring s (ri+1) in
				String.equal id id_s
			with Not_found | Invalid_argument _ -> false
		in
		(* Replaces variable names in the condition by that of [variables] in the right order. *)
		let rec replace_variables : Cabs.expression -> Cabs.expression
			= Cabs.(function
			| CONSTANT _ as c-> c
			| VARIABLE v -> let id = IOBuild.get_var_id v in
				if id < List.length !variables
				then VARIABLE (List.nth !variables id)
				else VARIABLE v
			| UNARY (op, e) -> UNARY (op, replace_variables e)
			| BINARY (op, e1, e2) -> BINARY (op, replace_variables e1, replace_variables e2)
			| _ -> Pervasives.invalid_arg "replace_variables"
			)
		in
		fun file_name ->
		Printf.sprintf "Loading file %s from folder %s"
			file_name !folder
			|> print_endline ;
		let ri = String.rindex file_name '.' in
		let id = substring file_name (ri+1) in
		let name = String.sub file_name 0 ri in
		let file = Printf.sprintf "%s/%s.vpl" !folder name in
		let in_ch = Pervasives.open_in file in
		let poly = ref []
		and register = ref false in
		(* Skip polyhedron name *)
		try
			while true do
				let s = Pervasives.input_line in_ch in
				if is_the_poly id s
				then begin
					poly := [file_name];
					register := true;
				end
				else if !register
					then if String.length s > 0 && String.get s 0 = 'P'
						then Pervasives.raise End_of_file
						else if not(String.equal s "")
							then poly := s :: !poly
			done;
			Pervasives.failwith "Trace_reader.load"
		with End_of_file -> begin
			let s = List.rev !poly
				|> String.concat "\n" in
			Printf.sprintf "Parsing matrix %s" s
				|> print_endline ;
			let cond = FCParser.one_matrix FCLexer.token (Lexing.from_string (s ^ "\n"))
				|> IOBuild.to_cond
				|> replace_variables
			in
			Printf.sprintf "Loaded file %s, obtained %s"
				file (expression_to_string cond)
				|> print_endline;
			cond
		end

		module Value = struct
			type t =
				| Int of int option
				| Float of float option

			let to_string : t -> string
				= function
				| Int (Some i) -> Printf.sprintf "int %i" i
				| Int None -> "int"
				| Float (Some f) -> Printf.sprintf "float %f" f
				| Float None -> "float"

			let op : (int -> int -> int) -> (float -> float -> float) -> t -> t -> t =
			fun int_op float_op v1 v2 ->
			match v1,v2 with
			| Int (Some i1), Int (Some i2) -> Int (Some (int_op i1 i2))
			| Float (Some f1), Float (Some f2) -> Float (Some (float_op f1 f2))
			| Int (Some i1), Float (Some f2) -> Float (Some (float_op (float_of_int i1) f2))
			| Float (Some f1), Int (Some i2) -> Float (Some (float_op f1 (float_of_int i2)))
			| _-> Pervasives.failwith "Value.op: unexpected None value"

			let add = op (+) (+.)

			let sub = op (-) (-.)

			let mul = op ( * ) ( *. )

			let div = op (/) (/.)

			let opp x = op (fun i j -> -1 * i) (fun u v -> -1. *. u) x (Int (Some 0))

			let bop : (int -> int -> 'bool) -> (float -> float -> 'bool) -> t -> t -> bool
				= fun int_op float_op v1 v2 ->
				match v1,v2 with
				| Int (Some i1), Int (Some i2) -> int_op i1 i2
				| Float (Some f1), Float (Some f2) -> float_op f1 f2
				| Int (Some i1), Float (Some f2) -> float_op (float_of_int i1) f2
				| Float (Some f1), Int (Some i2) -> float_op f1 (float_of_int i2)
				| _-> Pervasives.failwith "Value.bop: unexpected None value"

			let le = bop (<=) (<=)
			let lt = bop (<) (<)
			let ge = bop (>=) (>=)
			let gt = bop (>) (>)
			let eq = bop (=) (=)
			let neq = bop (<>) (<>)
		end

        module MapS = Map.Make(struct type t = string let compare = Pervasives.compare end)

		type mem = Value.t MapS.t

        let rec is_state : Cabs.expression -> bool
			= Cabs.(function
			| CALL (VARIABLE fun_name, [])
				when String.equal fun_name "bot" || String.equal fun_name "top" -> true
			| CALL (VARIABLE fun_name, [s1;s2]) when is_state s1 && is_state s2 -> begin
				match fun_name with
				| "meet" | "widen" | "join" -> true
				| _ -> false
				end
			| CALL (VARIABLE "guard", [s1;e]) when is_state s1 -> true
			| VARIABLE name -> D.is_bound name
			| e -> false
			)

		let rec parse_state : Cabs.expression -> D.t
			= Cabs.(D.(function
			| CALL (VARIABLE fun_name, []) when String.equal fun_name "top" -> top
			| CALL (VARIABLE fun_name, []) when String.equal fun_name "bot" -> bottom
			| CALL(VARIABLE "load", [CONSTANT (CONST_STRING file_name)]) ->
				let cond = load file_name in
                assume "VPL_RESERVED" cond D.top
			| CALL(VARIABLE "project", args)
				when List.length args > 0 && is_state (List.hd args)
				&& List.for_all (function VARIABLE _ -> true | _ -> false) (List.tl args) ->
				let vars = List.map
					(function VARIABLE var -> var | _ -> invalid_arg "from_body")
					(List.tl args)
				in
				project "VPL_RESERVED" vars (parse_state (List.hd args))
			| CALL (VARIABLE fun_name, [s1;s2]) when is_state s1 && is_state s2 -> begin
				match fun_name with
				| "meet" -> meet "VPL_RESERVED" (parse_state s1) (parse_state s2)
				| "widen" -> widen "VPL_RESERVED" (parse_state s1) (parse_state s2)
				| "join" -> join "VPL_RESERVED" (parse_state s1) (parse_state s2)
				| _ -> Pervasives.invalid_arg "parse_state"
				end
			| CALL (VARIABLE "guard", [s1;e]) when is_state s1 ->
				assume "VPL_RESERVED" e (parse_state s1)
			| VARIABLE name -> Name name
			| _ -> Pervasives.invalid_arg "parse_state"
			))

        let parse_assign : Cabs.expression -> (Domain.variable * Cabs.expression)
			= Cabs.(function
			| BINARY (ASSIGN, (VARIABLE var), e) -> (var, e)
			| _ -> Pervasives.failwith "Unexpected assignment"
			)

		let is_computation : Cabs.expression -> bool
			= Cabs.(function
			| BINARY (ASSIGN, VARIABLE var, e) -> true
			| UNARY (POSINCR, VARIABLE var) -> true
			| UNARY (POSDECR, VARIABLE var) -> true
			| _ -> false
			)

		let parse_computation : Cabs.expression -> Domain.variable * Cabs.expression
			= Cabs.(function
			| BINARY (ASSIGN, VARIABLE var, e) -> (var, e)
			| UNARY (POSINCR, VARIABLE var) -> (var, BINARY (ADD, VARIABLE var, CONSTANT (CONST_INT "1")))
			| UNARY (POSDECR, VARIABLE var) -> (var, BINARY (SUB, VARIABLE var, CONSTANT (CONST_INT "1")))
			| _ -> Pervasives.invalid_arg "parse_computation"
			)

		let rec eval_aexpr : mem -> Cabs.expression -> Value.t
			= fun mem -> Cabs.(function
			| CONSTANT (CONST_INT c) -> Value.Int (Some (int_of_string c))
			| CONSTANT (CONST_FLOAT c) -> Value.Float (Some (float_of_string c))
			| VARIABLE name -> begin
				try
					match MapS.find name mem with
					| Value.Int (Some i) -> Value.Float (Some (float_of_int i))
					| Value.Float (Some f) -> Value.Float (Some f)
					| Value.Int None | Value.Float None -> Pervasives.failwith ("Variable " ^ name ^ " is used but not initialized")
				with Not_found ->
					Pervasives.failwith ("Variable " ^ name ^ " is not declared")
				end
			| UNARY (PLUS, e) -> eval_aexpr mem e
			| UNARY (MINUS, e) -> Value.opp (eval_aexpr mem e)
			| UNARY (POSINCR, e) -> Value.add (eval_aexpr mem e) (Value.Int (Some 1))
			| UNARY (POSDECR, e) -> Value.sub (eval_aexpr mem e) (Value.Int (Some 1))
			| BINARY (ADD, e1, e2)-> Value.add (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (SUB, e1, e2)-> Value.sub (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (MUL, e1, e2)-> Value.mul (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (DIV, e1, e2)-> Value.div (eval_aexpr mem e1) (eval_aexpr mem e2)
			| NOTHING -> Value.Int None
			(*| CALL(e, arguments) -> *)
			| e -> begin
				Cprint.print_expression e 5;
				Value.Int (Some 0)
				end
			)

		let rec eval_bexpr : mem -> Cabs.expression -> bool
			= fun mem -> Cabs.(function
			| UNARY (NOT, e) -> not (eval_bexpr mem e)
			| UNARY (_, _) -> Pervasives.failwith "eval_bexpr: Unexpected unary expression"
			| BINARY (AND, e1, e2) -> (eval_bexpr mem e1) && (eval_bexpr mem e2)
			| BINARY (BAND, e1, e2) -> (eval_bexpr mem e1) & (eval_bexpr mem e2)
			| BINARY (OR, e1, e2) -> (eval_bexpr mem e1) || (eval_bexpr mem e2)
			| BINARY (BOR, e1, e2) -> (eval_bexpr mem e1) or (eval_bexpr mem e2)
			| BINARY (LE, e1, e2) -> Value.le (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (LT, e1, e2) -> Value.lt (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (GE, e1, e2) -> Value.ge (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (GT, e1, e2) -> Value.gt (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (EQ, e1, e2) -> Value.eq (eval_aexpr mem e1) (eval_aexpr mem e2)
			| BINARY (NE, e1, e2) -> Value.neq (eval_aexpr mem e1) (eval_aexpr mem e2)
			| CALL (VARIABLE "includes", [e1 ; e2]) when is_state e1 && is_state e2 ->
				D.leq (parse_state e2) (parse_state e1)
			| _ -> Pervasives.failwith "Unexpected boolean expression"
			)

		let update_mem : mem -> Domain.variable -> Cabs.expression -> mem
			= fun mem var e ->
			MapS.add var (eval_aexpr mem e) mem

        let top_expr : Cabs.expression = Cabs.(BINARY (LE, CONSTANT (CONST_INT "0"), CONSTANT (CONST_INT "1")))

        (** Initializes the memory with the type of variables *)
		let init_variables : mem -> Cabs.definition list -> mem
			= fun mem defs ->
			List.fold_left
				(fun mem -> function
					| Cabs.DECDEF(Cabs.INT (_,_), _, names) ->
						List.fold_left
							(fun mem (name,_,_,e) ->
							match eval_aexpr mem e with
							| Value.Int i -> MapS.add name (Value.Int i) mem
							| Value.Float _ -> Pervasives.failwith ("Variable " ^ name ^ " is declared as int but is given a float value")
							)
							mem names
					| Cabs.DECDEF(Cabs.FLOAT _, _, names) ->
						List.fold_left
							(fun mem (name,_,_,e) ->
							match eval_aexpr mem e with
							| Value.Int (Some i) -> MapS.add name (Value.Float (Some (float_of_int i))) mem
							| Value.Int None -> MapS.add name (Value.Float None) mem
							| Value.Float f -> MapS.add name (Value.Float f) mem
							)
							mem names
					| Cabs.DECDEF(Cabs.NAMED_TYPE "abs_value", _, names) -> begin
							List.iter (fun (name, _, _, _) -> let _ = D.assume name top_expr D.top in ()) names;
							mem
						end
					| Cabs.DECDEF(Cabs.NAMED_TYPE "var", _, names) -> begin
							List.iter (fun (name, _, _, _) -> add_variable name) names;
							mem
						end
					| _ -> mem
				)
				mem defs

        let rec run : mem -> Cabs.body -> mem
			= fun mem (defs, stmt) ->
			let mem = init_variables mem defs in
			Cabs.(match stmt with
			| NOP -> mem
			| COMPUTATION (BINARY (ASSIGN, (VARIABLE res_name), CALL(VARIABLE fun_name, [st1; st2])))
				when is_state st1 && is_state st2 -> begin
				match fun_name with
				| "meet" -> begin
                    let _ = D.meet res_name (parse_state st1) (parse_state st2) in mem
                end
				| "join" -> let _ = D.join res_name (parse_state st1) (parse_state st2) in mem
				| "widen" -> let _ = D.widen res_name (parse_state st1) (parse_state st2) in mem
				| _ -> Pervasives.failwith "Unexpected function call with two abstract states"
				end
			| COMPUTATION (BINARY (ASSIGN, (VARIABLE res_name), CALL(VARIABLE "load", [CONSTANT (CONST_STRING file_name)]))) ->
				let cond = load file_name in
                let _ = D.assume res_name cond D.top in
                mem
			| COMPUTATION (BINARY (ASSIGN, (VARIABLE res_name), CALL(VARIABLE "project", args)))
				when List.length args > 0 && is_state (List.hd args)
				&& List.for_all (function VARIABLE _ -> true | _ -> false) (List.tl args) ->
				let vars = List.map
					(function VARIABLE var -> var | _ -> invalid_arg "from_body")
					(List.tl args)
				in
                let _ = D.project res_name vars (parse_state (List.hd args)) in
                mem
			| COMPUTATION (BINARY (ASSIGN, (VARIABLE res_name), CALL(VARIABLE fun_name, [st; e])))
				when is_state st && not (is_state e) -> begin
				match fun_name with
				| "guard" -> let _ = D.assume res_name e (parse_state st) in mem
				| "assign" -> let _ = D.assign res_name [parse_assign e] (parse_state st) in mem
				| _ -> Pervasives.failwith "Unexpected function call with one abstract state"
				end
			| COMPUTATION e when is_computation e ->
				let (var, assign) = parse_computation e in
                update_mem mem var assign
			| IF (e, s1, s2) ->
                if eval_bexpr mem e
                then run mem ([],s1)
		        else run mem ([],s2)
			| WHILE (e, s) ->
                if eval_bexpr mem e
    			then begin
    				let mem' = run mem ([],s) in
    				run mem' ([], WHILE (e, s))
    			end
    			else mem
            | BLOCK body -> run mem body
			| SEQUENCE (s1,s2) ->
                let mem' = run mem ([],s1) in
    			run mem' ([],s2)
			| _ -> begin
				Cprint.print_statement stmt;
				Pervasives.failwith "Unexpected statement"
				end
			)

end
