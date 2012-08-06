(*
 * Copyright (c) 2012 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open Printf
open Code

type request = { 
  ic: IO.ic;
  headers: (string * string) list;
  meth: meth;
  uri: Uri.t;
  get: (string * string) list;
  post: (string * string) list;
  version: version;
  bodylen: int64;
  encoding: Transfer.encoding;
}

let meth r = r.meth
let uri r = r.uri
let version r = r.version

let path r = Uri.path r.uri

(* TODO repeated headers handled correctly *)
let header ~name r =
  try [ List.assoc name r.headers ]
  with Not_found -> []

let content_length headers = 
  try Int64.of_string (List.assoc "content-length" headers)
  with Not_found -> 0L

let content_type headers =
  try List.assoc "content-type" headers
  with Not_found -> ""

let params_get r = r.get
let params_post r = r.post
let param p r =
  try Some (List.assoc p r.post) with
  Not_found ->
    (try Some (List.assoc p r.get) with
    Not_found -> None)

(* Parse the transfer-encoding and content-length headers to
 * determine how to decode a body *)
let transfer_encoding headers =
  let enc =
    try Some (List.assoc "transfer-encoding" headers) 
    with Not_found -> None
  in
  match enc with
  |Some enc -> Transfer.Chunked
  |None -> begin
     try
       let len = Int64.of_string (List.assoc "content-length" headers) in
       Transfer.Fixed len
     with Not_found ->
       Transfer.Unknown
  end

open IO.M

let parse ic =
  Parser.parse_request_fst_line ic >>=
  function
  |None -> return None
  |Some (meth, uri, version) ->
    Parser.parse_headers ic >>= fun headers ->
    let ctype = content_type headers in
    let bodylen = content_length headers in
    let get = Uri.query uri in
    (match meth, ctype with
      |`POST, "application/x-www-form-urlencoded" -> 
        (* If the form is query-encoded, then extract those parameters also *)
        IO.read (Int64.to_int bodylen) ic >>= fun query ->
        let post = Uri.query_of_encoded query in
        let encoding = Transfer.Fixed 0L in
        return (post, encoding)
      |`POST, _ ->
        let post = [] in
        let encoding = transfer_encoding headers in
        return (post, encoding)
      | _ -> return ([], (Transfer.Fixed 0L)) 
    ) >>= fun (post, encoding) ->
    return (Some { ic; headers; meth; uri; version; bodylen; post; get; encoding })
