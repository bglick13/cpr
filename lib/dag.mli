(* mutable dag *)

type 'a t
type 'a node

(* maintenance *)
val roots : 'a list -> 'a t * 'a node list
val append : 'a t -> 'a node list -> 'a -> 'a node

(* partial visibility of nodes ; views cannot be edited *)
type ('a, 'b) view

val global_view : 'a t -> ('a, 'a) view
val local_view : ('a -> bool) -> ('a -> 'b) -> 'a t -> ('a, 'b) view

(** Raised by functions that operate on view and node when the node is not
  * visible in view. *)
exception Invalid_node_argument

(* data access *)

(** Raises {Invalid_node_argument}. *)
val data : ('a, 'b) view -> 'a node -> 'b

(* local navigation *)

(** Raises {Invalid_node_argument}. *)
val parents : ('a, 'b) view -> 'a node -> 'a node list

(** Raises {Invalid_node_argument}. *)
val children : ('a, 'b) view -> 'a node -> 'a node list
