-ifndef(smoke_req).
-define(smoke_req, true).

-record(req, {
          start           :: tuple(), % now
          parent          :: pid(),
          status          :: ok | error, % job result
          id              :: reference(),
          serv_tag        :: string(),
          ses_sn          :: non_neg_integer(),
          ses_base        :: string(),
          debug = []      :: [atom()],
          host            :: string(),
          url             :: string(),
          method          :: string(),
          params = []     :: list(),
          heartbeat_timeout :: non_neg_integer(),
          timeout         :: non_neg_integer()
                             }).

-endif.
