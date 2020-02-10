(* Copyright (C) 2015-2016 Bloomberg Finance L.P.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * In addition to the permissions granted to you by the LGPL, you may combine
 * or link a "work that uses the Library" with a publicly distributed version
 * of this file to produce a combined library or application, then distribute
 * that combined work under the terms of your choosing, with no requirement
 * to comply with the obligations normally placed on you by section 4 of the
 * LGPL version 3 (or the corresponding section of a later version of the LGPL
 * should you choose to use a later version).
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA. *)

(** *)
module Js = Jsoo_common.Js

(*
 Error:
     *  {
     *    row: 12,
     *    column: 2, //can be undefined
     *    text: "Missing argument",
     *    type: "error" // or "warning" or "info"
     *  }
*)
let () =  
  Bs_conditional_initial.setup_env ();
  Clflags.binary_annotations := false

let error_of_exn e =   
  match Location.error_of_exn e with 
  | Some (`Ok e) -> Some e 
  | Some `Already_displayed
  | None -> None

type react_ppx_version = V2 | V3

let implementation ~use_super_errors ?(react_ppx_version=V3) prefix impl str  : Js.Unsafe.obj =
  let modulename = "Test" in
  (* let env = !Toploop.toplevel_env in *)
  (* Compmisc.init_path false; *)
  (* let modulename = module_of_filename ppf sourcefile outputprefix in *)
  (* Env.set_unit_name modulename; *)
  Lam_compile_env.reset () ;
  let env = Compmisc.initial_env() in (* Question ?? *)
  (* let finalenv = ref Env.empty in *)
  let types_signature = ref [] in
  if use_super_errors then begin
    Misc.Color.setup (Some Always);
    Lazy.force Super_main.setup ;
  end;


  try
    let ast = impl 
      (Lexing.from_string
        (if prefix then "[@@@bs.config{no_export}]\n#1 \"repl.ml\"\n"  ^ str else str )) in 
    let ast = match react_ppx_version with
    | V2 -> Reactjs_jsx_ppx_v2.rewrite_implementation ast
    | V3 -> Reactjs_jsx_ppx_v3.rewrite_implementation ast in 
    let ast = Bs_builtin_ppx.rewrite_implementation ast in 
    let typed_tree = 
      let (a,b,_,signature) = Typemod.type_implementation_more modulename modulename modulename env ast in
      (* finalenv := c ; *)
      types_signature := signature;
      (a,b) in      
  typed_tree
  |>  Translmod.transl_implementation modulename
  |> (* Printlambda.lambda ppf *) (fun 
    {Lambda.code = lam}
    ->
      let buffer = Buffer.create 1000 in
      let () = Js_dump_program.pp_deps_program
                          ~output_prefix:"" (* does not matter here *)
                          NodeJS
                          (Lam_compile_main.compile ""
                              lam)
                          (Ext_pp.from_buffer buffer) in
      let v = Buffer.contents buffer in
      Js.Unsafe.(obj [| "js_code", inject @@ Js.string v |]) )
      (* Format.fprintf output_ppf {| { "js_code" : %S }|} v ) *)
  with
  | e ->
      begin match error_of_exn  e with
      | Some error ->
          Location.report_error Format.err_formatter  error;
          Jsoo_common.mk_js_error error.loc error.msg
      | None ->
        Js.Unsafe.(obj [|
        "js_error_msg" , inject @@ Js.string (Printexc.to_string e)
        |])

      end


let compile impl ~use_super_errors ?react_ppx_version =
    implementation ~use_super_errors ?react_ppx_version false impl

(** TODO: add `[@@bs.config{no_export}]\n# 1 "repl.ml"`*)
let shake_compile impl ~use_super_errors ?react_ppx_version =
   implementation ~use_super_errors ?react_ppx_version true impl



(* let load_module cmi_path cmi_content cmj_name cmj_content =
  Js.create_file cmi_path cmi_content;
  Js_cmj_datasets.data_sets :=
    Map_string.add !Js_cmj_datasets.data_sets
      cmj_name (lazy (Js_cmj_format.from_string cmj_content))
       *)


let export (field : string) v =
  Js.Unsafe.set (Js.Unsafe.global) field v
;;

(* To add a directory to the load path *)

let dir_directory d =
  Config.load_path := d :: !Config.load_path


let () =
  dir_directory "/static/cmis"

let make_compiler name impl =
  export name
    (Js.Unsafe.(obj
                  [|"compile",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code ->
                         (compile impl ~use_super_errors:false (Js.to_string code)));
                    "shake_compile",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code ->
                         (shake_compile impl ~use_super_errors:false (Js.to_string code)));
                    "compile_super_errors",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code ->
                         (compile impl ~use_super_errors:true (Js.to_string code)));
                    "compile_super_errors_ppx_v2",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code ->
                         (compile impl ~use_super_errors:true ~react_ppx_version:V2 (Js.to_string code)));
                    "compile_super_errors_ppx_v3",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code ->
                         (compile impl ~use_super_errors:true ~react_ppx_version:V3 (Js.to_string code)));
                    "shake_compile_super_errors",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ code -> (shake_compile impl ~use_super_errors:true (Js.to_string code)));
                    "version", Js.Unsafe.inject (Js.string (Bs_version.version));
                    (* "load_module",
                    inject @@
                    Js.wrap_meth_callback
                      (fun _ cmi_path cmi_content cmj_name cmj_content ->
                        let cmj_bytestring = Js.to_bytestring cmj_content in
                        (* HACK: force string tag to ASCII (9) to avoid
                         * UTF-8 encoding *)
                        Js.Unsafe.set cmj_bytestring "t" 9;
                        load_module cmi_path cmi_content (Js.to_string cmj_name) cmj_bytestring); *)
                  |]))
let () = make_compiler "ocaml" Parse.implementation

(* local variables: *)
(* compile-command: "ocamlbuild -use-ocamlfind -pkg compiler-libs -no-hygiene driver.cmo" *)
(* end: *)
