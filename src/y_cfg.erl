-module(y_cfg).
-compile(export_all).

sconf() ->
    sconf("/var/www/01/www").

sconf(Docroot) ->
[
    {docroot, Docroot},
    {port, 8184},
    {listen, {0,0,0,0}},
    {ebin_dir, ["/var/www/01/ebin"]},
    %{appmods, [{"/", my_appmod}]},
    {servername, "localhost"},
    {ssl0, [
        % {certfile, "/var/www/01/conf/ssl/localhost-cert.pem"},
        % {keyfile, "/var/www/01/conf/ssl/localhost-key.pem"}
        {certfile, "/var/www/01/conf/ssl/192.168.9.138.crt"},
        {keyfile, "/var/www/01/conf/ssl/192.168.9.138.key"}
    ]},
    {flags, [
        {dir_listings, true}
    ]}
]
.

gconf() ->
    [
        %{yaws_dir, "/usr/lib/yaws"},
        {yaws_dir, "/home/user1/util/erlang/http/yaws-1.91"},
        {logdir, "/var/log/erpher/yaws"},
        {ebin_dir, ["/usr/lib/yaws/custom/ebin"]},
        {include_dir, ["/usr/lib/yaws/custom/include"]},
        {max_connections, nolimit},
        {trace, false},
        {copy_error_log, true},
        {log_wrap_size, 1000000},
        {log_resolve_hostname, false},
        {fail_on_bind_err, true},
        {auth_log, true},
        {id, eworkman_yaws},
        {pick_first_virthost_on_nomatch, true},
        {use_fdsrv, false},
        {subconfigdir, "/var/www/01/conf"}
    ]
.
