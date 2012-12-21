(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Pervasiveext
open Client

let rpc xml =
    let open Xmlrpc_client in
    XMLRPC_protocol.rpc ~transport:(Unix "/var/xapi/xapi") ~http:(xmlrpc ~version:"1.0" "/") xml

let _ =
    let session_id = Client.Session.login_with_password ~rpc ~uname:"" ~pwd:"" ~version:"1.0" in
	finally
		(fun () -> Create_templates.create_all_templates rpc session_id)
		(fun () -> Client.Session.logout rpc session_id)
