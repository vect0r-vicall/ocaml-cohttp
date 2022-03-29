(** Portable Lwt implementation of HTTP client and server, without depending on
    a particular I/O implementation. The various [Make] functors must be
    instantiated by an implementation that provides a concrete IO monad. *)

(** The IO module is specialized for the [Lwt] monad. *)
module type IO = sig
  include Cohttp.S.IO with type 'a t = 'a Lwt.t

  type error

  val catch : (unit -> 'a t) -> ('a, error) result t
  (** [catch f] is [f () >|= Result.ok], unless [f] fails with an IO error, in
      which case it returns the error. *)

  val pp_error : Format.formatter -> error -> unit
end

(** The [Net] module type defines how to connect to a remote node and close the
    resulting channels to clean up. *)
module type Net = sig
  module IO : IO

  type endp
  type ctx [@@deriving sexp_of]


  val default_ctx : ctx
  val resolve : ctx:ctx -> Uri.t -> endp IO.t
  val connect_uri : ctx:ctx -> Uri.t -> (IO.conn * IO.ic * IO.oc) IO.t
  val connect_endp : ctx:ctx -> endp -> (IO.conn * IO.ic * IO.oc) IO.t
  val close_in : IO.ic -> unit
  val close_out : IO.oc -> unit
  val close : IO.ic -> IO.oc -> unit
end

module type Sleep = sig
  type 'a promise
  val sleep_ns : int64 -> unit promise
end

module type Connection = sig
  module Net : Net

  exception Retry
  type t

<<<<<<< HEAD
=======
  (** [create ?finalise ?persistent ?ctx endp] connects to [endp]. The
      connection handle may be used immediately, although the connection
      may not yet be established.
      @param finalise called when the connection is closed, but before
      still waiting requests are failed.
      @param persistent if [false], a [Connection: close] header is sent and
      the connection closed as soon as possible. If [true], it is
      assumed the remote end does support pipelining and multiple
      requests may be sent even before receiving any reply. By default
      we wait for the first response to decide whether connection
      keep-alive and pipelining is suppored.
      Chunked encoding can only be used when pipelining is supported.
      Therefore better avoid using chunked encoding on the very
      first request.
      @param ctx See [Net.ctx]
      @param endp The remote address, port and protocol to connect to.
  *)
>>>>>>> df56028 (Move selection of encoding from Client to Connection)
  val create :
    ?finalise:(t -> unit Net.IO.t) ->
    ?persistent:bool ->
    ?ctx:Net.ctx ->
    Net.endp ->
    t

  val connect :
    ?finalise:(t -> unit Net.IO.t) ->
    ?persistent:bool ->
    ?ctx:Net.ctx ->
    Net.endp ->
    t Net.IO.t

  val shutdown : t -> unit
  val close : t -> unit
  val is_closed : t -> bool
  val notify : t -> unit Net.IO.t
  val length : t -> int

  val request : t ->
    ?body:Body.t -> Cohttp.Request.t -> (Cohttp.Response.t * Body.t) Net.IO.t
end

module type Connection_cache = sig
  module IO : IO

  type t

  val request : t ->
    ?body:Body.t -> Cohttp.Request.t -> (Cohttp.Response.t * Body.t) IO.t
end

(** The [Client] module implements non-pipelined single HTTP client calls. Each
    call will open a separate {!Net} connection. For best results, the {!Body}
    that is returned should be consumed in order to close the file descriptor in
    a timely fashion. It will still be finalized by a GC hook if it is not used
    up, but this can take some additional time to happen. *)
module type Client = sig
  type ctx

  module Connection : Connection with type Net.ctx = ctx

  val set_cache :
    (?body:Body.t -> Cohttp.Request.t -> (Cohttp.Response.t * Body.t) Lwt.t) ->
    unit

  val call :
    ?ctx:ctx ->
    ?headers:Http.Header.t ->
    ?body:Body.t ->
    ?chunked:bool ->
    Http.Method.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t
  (** [call ?ctx ?headers ?body ?chunked meth uri] will resolve the [uri] to a
      concrete network endpoint using context [ctx]. It will then issue an HTTP
      request with method [meth], adding request headers from [headers] if
      present. If a [body] is specified then that will be included with the
      request, using chunked encoding if [chunked] is true. The default is to
      disable chunked encoding for HTTP request bodies for compatibility
      reasons.

      In most cases you should use the more specific helper calls in the
      interface rather than invoke this function directly. See {!head}, {!get}
      and {!post} for some examples.

      To avoid leaks, the body needs to be consumed, using the functions
      provided in the {!Body} module and, if not necessary, should be explicitly
      drained calling {!Body.drain_body}. Leaks are logged as debug messages by
      the client, these can be enabled activating the debug logging. For
      example, this can be done as follows in [cohttp-lwt-unix]

      {[
        Cohttp_lwt_unix.Debug.activate_debug ();
        Logs.set_level (Some Logs.Warning)
      ]}

      Depending on [ctx], the library is able to send a simple HTTP request or
      an encrypted one with a secured protocol (such as TLS). Depending on how
      conduit is configured, [ctx] might initiate a secured connection with TLS
      (using [ocaml-tls]) or SSL (using [ocaml-ssl]), on [*:443] or on the
      specified port by the user. If neitehr [ocaml-tls] or [ocaml-ssl] are
      installed on the system, [cohttp]/[conduit] tries the usual ([*:80]) or
      the specified port by the user in a non-secured way. *)

  val head :
    ?ctx:ctx -> ?headers:Http.Header.t -> Uri.t -> Http.Response.t Lwt.t

  val get :
    ?ctx:ctx ->
    ?headers:Http.Header.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val delete :
    ?ctx:ctx ->
    ?body:Body.t ->
    ?chunked:bool ->
    ?headers:Http.Header.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val post :
    ?ctx:ctx ->
    ?body:Body.t ->
    ?chunked:bool ->
    ?headers:Http.Header.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val put :
    ?ctx:ctx ->
    ?body:Body.t ->
    ?chunked:bool ->
    ?headers:Http.Header.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val patch :
    ?ctx:ctx ->
    ?body:Body.t ->
    ?chunked:bool ->
    ?headers:Http.Header.t ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val post_form :
    ?ctx:ctx ->
    ?headers:Http.Header.t ->
    params:(string * string list) list ->
    Uri.t ->
    (Http.Response.t * Body.t) Lwt.t

  val callv :
    ?ctx:ctx ->
    Uri.t ->
    (Http.Request.t * Body.t) Lwt_stream.t ->
    (Http.Response.t * Body.t) Lwt_stream.t Lwt.t
end

(** The [Server] module implements a pipelined HTTP/1.1 server. *)
module type Server = sig
  module IO : IO

  type conn = IO.conn * Cohttp.Connection.t [@@warning "-3"]

  type response_action =
    [ `Expert of Http.Response.t * (IO.ic -> IO.oc -> unit Lwt.t)
    | `Response of Http.Response.t * Body.t ]
  (** A request handler can respond in two ways:

      - Using [`Response], with a {!Response.t} and a {!Body.t}.
      - Using [`Expert], with a {!Response.t} and an IO function that is
        expected to write the response body. The IO function has access to the
        underlying {!IO.ic} and {!IO.oc}, which allows writing a response body
        more efficiently, stream a response or to switch protocols entirely
        (e.g. websockets). Processing of pipelined requests continue after the
        {!unit Lwt.t} is resolved. The connection can be closed by closing the
        {!IO.ic}. *)

  type t

  val make_response_action :
    ?conn_closed:(conn -> unit) ->
    callback:(conn -> Http.Request.t -> Body.t -> response_action Lwt.t) ->
    unit ->
    t

  val make_expert :
    ?conn_closed:(conn -> unit) ->
    callback:
      (conn ->
      Http.Request.t ->
      Body.t ->
      (Http.Response.t * (IO.ic -> IO.oc -> unit Lwt.t)) Lwt.t) ->
    unit ->
    t

  val make :
    ?conn_closed:(conn -> unit) ->
    callback:
      (conn -> Http.Request.t -> Body.t -> (Http.Response.t * Body.t) Lwt.t) ->
    unit ->
    t

  val resolve_local_file : docroot:string -> uri:Uri.t -> string
    [@@deprecated "Please use Cohttp.Path.resolve_local_file. "]
  (** Resolve a URI and a docroot into a concrete local filename. *)

  val respond :
    ?headers:Http.Header.t ->
    ?flush:bool ->
    status:Http.Status.t ->
    body:Body.t ->
    unit ->
    (Http.Response.t * Body.t) Lwt.t
  (** [respond ?headers ?flush ~status ~body] will respond to an HTTP request
      with the given [status] code and response [body]. If [flush] is true, then
      every response chunk will be flushed to the network rather than being
      buffered. [flush] is true by default. The transfer encoding will be
      detected from the [body] value and set to chunked encoding if it cannot be
      determined immediately. You can override the encoding by supplying an
      appropriate [Content-length] or [Transfer-encoding] in the [headers]
      parameter. *)

  val respond_string :
    ?flush:bool ->
    ?headers:Http.Header.t ->
    status:Http.Status.t ->
    body:string ->
    unit ->
    (Http.Response.t * Body.t) Lwt.t

  val respond_error :
    ?headers:Http.Header.t ->
    ?status:Http.Status.t ->
    body:string ->
    unit ->
    (Http.Response.t * Body.t) Lwt.t

  val respond_redirect :
    ?headers:Http.Header.t ->
    uri:Uri.t ->
    unit ->
    (Http.Response.t * Body.t) Lwt.t

  val respond_need_auth :
    ?headers:Http.Header.t ->
    auth:Cohttp.Auth.challenge ->
    unit ->
    (Http.Response.t * Body.t) Lwt.t

  val respond_not_found : ?uri:Uri.t -> unit -> (Http.Response.t * Body.t) Lwt.t
  val callback : t -> IO.conn -> IO.ic -> IO.oc -> unit Lwt.t
end
