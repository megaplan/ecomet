{application, ecomet_server, [
	{description, "ecomet server"},
	{id, "ecomet_srv"},
	{vsn, "1.0"},
	{modules, [
		ecomet_conf,
		ecomet_conf_rabbit,
		ecomet_conn_server,
		ecomet_conn_sup,
		ecomet_handler_ws,
		ecomet_rb,
		ecomet_server_app,
		ecomet_server,
		ecomet_server_sup
	]},
	{registered, []},
	{env, []},
	{mod, {ecomet_server_app,[]}},
	{applications, [kernel, stdlib, ssl]} % ssl - for yaws
]}.

