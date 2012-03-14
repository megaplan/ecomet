-ifndef(smoke_stat).
-define(smoke_stat, true).

-record(stat, {
          sum         = 0.0 :: number(),
          sum_sq      = 0.0 :: number(),
          count_ok    = 0   :: non_neg_integer(),
          count_error = 0   :: non_neg_integer(),
          count       = 0   :: non_neg_integer()
         }).

-endif.
