{application, mcom_server, [
	{description, "megaplan comet server"},
	{id, "mpln_ws_serv"},
	{vsn, "1.0"},
	{modules, [
		mcom_conf,
		mcom_conf_rabbit,
		mcom_conn_server,
		mcom_conn_sup,
		mcom_handler_ws,
		mcom_rb,
		mcom_server_app,
		mcom_server,
		mcom_server_sup
	]},
	{registered, []},
	{env, []},
	{mod, {mcom_server_app,[]}},
	{applications, [kernel, stdlib, ssl]} % ssl - for yaws
]}.

