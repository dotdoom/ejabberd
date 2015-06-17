%%%----------------------------------------------------------------------
%%% File    : mod_auth_log.erl
%%%----------------------------------------------------------------------

-module(mod_auth_log).
-author('mail@example.org').

-behaviour(gen_mod).

%% API
-export([start/2, stop/1, auth_success_log/3, auth_failure_log/3]).

-include("ejabberd.hrl").
-include("jlib.hrl").

start(Host, _Opts) ->
	ejabberd_hooks:add(c2s_auth_success, Host, ?MODULE, auth_success_log, 100),
	ejabberd_hooks:add(c2s_auth_failure, Host, ?MODULE, auth_failure_log, 100),
	ok.

stop(Host) ->
	ejabberd_hooks:delete(c2s_auth_success, Host, ?MODULE, auth_success_log, 100),
	ejabberd_hooks:delete(c2s_auth_failure, Host, ?MODULE, auth_failure_log, 100),
	ok.

get_now_seconds() ->
	{MegaSeconds, Seconds, _MicroSeconds} = now(),
	(MegaSeconds * 1000000 + Seconds).

addlog(Timestamp, IP, JID, Source, Action) ->
	SUser = ejabberd_odbc:escape(JID#jid.user),
	LServer = JID#jid.server,
	SServer = ejabberd_odbc:escape(LServer),
	SSource = ejabberd_odbc:escape("Authentication source: " ++ Source),
	SAction = ejabberd_odbc:escape(Action),
	SIP = ejabberd_odbc:escape(jlib:ip_to_list(IP)),
	odbc_queries:add_security_log(LServer,
		SUser, SServer, SIP, SAction, SSource, Timestamp),
	{LServer, SUser}.

auth_success_log(IP, JID, Source) ->
	addlog(now(), IP, JID, Source, "auth_success"),
	ok.

auth_failure_log(IP, JID, Source) ->
	{Server, User} = addlog(now(), IP, JID, Source, "auth_failure"),
	FailureTime = case odbc_queries:get_failure_time(Server, User) of
					  {selected, _, [{FailureTimeValue}]} ->
					  	  case string:to_integer(FailureTimeValue) of
					  	  	  {FailureTimeValueInt, []} ->
					  	  	  	  FailureTimeValueInt;
					  	  	  _ ->
					  	  	  	  0
					  	  end;
					  _ ->
					  	  0
				  end,
	CurrentTime = get_now_seconds(),
	odbc_queries:set_failure_time(Server, User, CurrentTime),
	case (CurrentTime - FailureTime) < 4 of
		true ->
			timer:sleep(3000);
		_ ->
			ok
	end,
	ok.
