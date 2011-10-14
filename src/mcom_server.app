{application, mcom_server, [
	{description, "megaplan websocket server"},
	{id, "mpln_ws_serv"},
	{vsn, "1.0"},
	{modules, [
		mcom_conn_server,
		mcom_conn_sup,
		mcom_server_app,
		mcom_server,
		mcom_server_sup,
		y_cfg
	]},
	{registered, []},
	{env, []},
	{mod, {mcom_server_app,[]}},
	{applications, [kernel, stdlib]}
]}.

