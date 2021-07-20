open Cpr_lib
open Models

let tasks0 =
  let fpaths_and_legends ~alpha task =
    let open Fpath in
    List.map
      (fun is ->
        let a =
          Printf.sprintf
            "%s:%s:α=%.2f:%s:k=%d:%s:%s.dot"
            (tag_network task.network)
            (tag_scenario task.scenario)
            alpha
            (protocol_family task.protocol)
            (pow_per_block task.protocol)
            (tag_incentive_scheme is)
            (tag_strategy task.strategy)
        in
        ( v a
        , [ "Network", describe_network task.network
          ; "Scenario", describe_scenario task.scenario
          ; "Attacker Compute (α)", string_of_float alpha
          ; "Protocol", describe_protocol task.protocol
          ; "PoW per Block (k)", string_of_int (pow_per_block task.protocol)
          ; "Incentive Scheme", describe_incentive_scheme is
          ; "Attack Strategy", describe_strategy task.strategy
          ] ))
      task.incentive_schemes
  and label_node = function
    | None -> "genesis"
    | Some 0 -> "a"
    | Some _ -> "d"
  in
  List.concat_map
    (fun alpha ->
      List.concat_map
        (fun (protocol, incentive_schemes, strategies, activations) ->
          List.map
            (fun strategy ->
              let t =
                { network = TwoAgentsZero { alpha }
                ; incentive_schemes
                ; protocol
                ; scenario = FirstSelfish
                ; strategy
                ; activations
                ; activation_delay = 1.
                }
              in
              t, fpaths_and_legends ~alpha t, label_node)
            strategies)
        [ Nakamoto, [ Constant ], [ Honest ], 10
        ; B_k { k = 16 }, [ Constant ], [ Honest; SelfishSimple ], 200
        ; B_k { k = 8 }, [ Constant ], [ Honest; SelfishSimple ], 100
        ; B_k { k = 4 }, [ Constant ], [ Honest; SelfishSimple ], 50
        ; B_k { k = 1 }, [ Constant ], [ Honest; SelfishSimple ], 20
        ; ( B_k_lessleadership { k = 16 }
          , [ Constant ]
          , [ Honest; SelfishSimple; SelfishAdvanced ]
          , 200 )
        ; ( B_k_lessleadership { k = 8 }
          , [ Constant ]
          , [ Honest; SelfishSimple; SelfishAdvanced ]
          , 100 )
        ; ( B_k_lessleadership { k = 4 }
          , [ Constant ]
          , [ Honest; SelfishSimple; SelfishAdvanced ]
          , 50 )
        ; ( B_k_lessleadership { k = 1 }
          , [ Constant ]
          , [ Honest; SelfishSimple; SelfishAdvanced ]
          , 20 )
        ; George { k = 16 }, [ Constant ], [ Honest ], 48
        ; George { k = 8 }, [ Constant ], [ Honest ], 24
        ; George { k = 4 }, [ Constant ], [ Honest ], 12
        ])
    [ 0.25; 0.33; 0.5 ]
;;

let tasks1 =
  let fpaths_and_legends ~activation_delay task =
    let open Fpath in
    List.map
      (fun is ->
        let a =
          Printf.sprintf
            "%s:%s:d=%.2g:%s:k=%d:%s.dot"
            (tag_network task.network)
            (tag_scenario task.scenario)
            activation_delay
            (protocol_family task.protocol)
            (pow_per_block task.protocol)
            (tag_incentive_scheme is)
        in
        ( v a
        , [ "Network", describe_network task.network
          ; "Scenario", describe_scenario task.scenario
          ; "Activation Delay", string_of_float activation_delay
          ; "Protocol", describe_protocol task.protocol
          ; "PoW per Block (k)", string_of_int (pow_per_block task.protocol)
          ; "Incentive Scheme", describe_incentive_scheme is
          ] ))
      task.incentive_schemes
  and label_node = function
    | Some n -> "n:" ^ string_of_int n
    | None -> "genesis"
  in
  List.concat_map
    (fun activation_delay ->
      List.map
        (fun (protocol, incentive_schemes, activations) ->
          let t =
            { network = CliqueUniform10
            ; incentive_schemes
            ; protocol
            ; scenario = AllHonest
            ; strategy = Honest
            ; activations
            ; activation_delay
            }
          in
          t, fpaths_and_legends ~activation_delay t, label_node)
        [ Nakamoto, [ Constant ], 10
        ; B_k { k = 16 }, [ Constant ], 200
        ; B_k { k = 8 }, [ Constant ], 100
        ; B_k { k = 4 }, [ Constant ], 50
        ; B_k_lessleadership { k = 16 }, [ Constant ], 200
        ; B_k_lessleadership { k = 8 }, [ Constant ], 100
        ; B_k_lessleadership { k = 4 }, [ Constant ], 50
        ; George { k = 16 }, [ Constant; Punish; Discount; Hybrid ], 100
        ; George { k = 8 }, [ Constant; Punish; Discount; Hybrid ], 50
        ; George { k = 4 }, [ Constant; Punish; Discount; Hybrid ], 30
        ])
    [ 1.; 2.; 4. ]
;;

let print_dag oc (sim, confirmed, rewards, legend, label_node) =
  let open Simulator in
  let node_attr n =
    let open Simulator in
    let d = Dag.data n in
    [ ( "label"
      , Printf.sprintf
          "%s | t:%.1f | r:%.2g"
          (label_node d.appended_by)
          d.appended_at
          rewards.(Dag.id n) )
    ; ("color", if confirmed.(Dag.id n) then "black" else "red")
    ]
  in
  Dag.dot oc ~legend sim.global.view ~node_attr (Dag.roots sim.dag) |> Result.ok
;;

let run (task, fpaths_and_legends, label_node) =
  let (S s) = setup task in
  (* simulate *)
  let open Simulator in
  init ?deviations:s.deviations s.params s.protocol
  |> loop s.params
  |> fun sim ->
  let head =
    Array.to_seq sim.nodes
    |> Seq.map (fun (SNode x) -> x.preferred x.state)
    |> Dag.common_ancestor' sim.global.view
    |> Option.get
  in
  let confirmed = Array.make (Dag.size sim.dag) false
  and rewards = Array.make (Dag.size sim.dag) 0. in
  List.iter2
    (fun (path, legend) rw ->
      let () =
        Seq.iter
          (fun n ->
            confirmed.(Dag.id n) <- true;
            rw
              ~view:sim.global
              ~assign:(fun x n -> rewards.(Dag.id n) <- rewards.(Dag.id n) +. x)
              n)
          (Dag.iterate_ancestors sim.global.view [ head ])
      in
      let path =
        let open Fpath in
        v "." / "fig" / "chains" // path
      in
      let open Bos.OS in
      let d = Dir.create ~path:true (Fpath.parent path) in
      Result.bind d (fun _ ->
          File.with_oc path print_dag (sim, confirmed, rewards, legend, label_node))
      |> Result.join
      |> Rresult.R.failwith_error_msg)
    fpaths_and_legends
    s.reward_functions
;;

let () =
  Random.self_init ();
  List.iter run (tasks0 @ tasks1)
;;
