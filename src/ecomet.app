{application, ecomet, [
    {description, "ecomet server"},
    {id, "ecomet"},
    {vsn, "1.5.2"},
    {modules, [
        ecomet_conf,
        ecomet_conf_rabbit,
        ecomet_conn_server,
        ecomet_conn_server_sio,
        ecomet_conn_server_sjs,
        ecomet_conn_sup,
        ecomet_data,
        ecomet_data_msg,
        ecomet_rb,
        ecomet_server_app,
        ecomet_server,
        ecomet_server_sup,
        ecomet_socketio_handler,
        ecomet_sockjs_handler,
        ecomet_stat,
        ecomet_test
    ]},
    {registered, [ecomet_server_sup, ecomet_conn_sup, ecomet_server]},
    {env, []},
    {mod, {ecomet_server_app,[]}},
    % ssl - for yaws, eworkman - for logs, ejobman - for ejobman_stat
    {applications, [kernel, stdlib, ssl, rabbit, ejobman, eworkman, socketio, sockjs]}
]}.

