-ifndef(smoke_child).
-define(smoke_child, true).

-record(chi, {
          pid   :: pid(),
          id    :: reference(),
          start :: tuple(),
          status:: ok | error,
          dur   :: non_neg_integer(), % received from req process, microseconds
          mon   :: reference()
                   }).

-endif.
