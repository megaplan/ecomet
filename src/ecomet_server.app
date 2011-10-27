{application, ecomet_server, [
	{description, "ecomet server"},
	{id, "ecomet_srv"},
	{vsn, "1.0"},
	{modules, [

	]},
	{registered, []},
	{env, []},
	{mod, {ecomet_server_app,[]}},
	{applications, [kernel, stdlib, ssl]} % ssl - for yaws
]}.

