-ifndef(ecomet_stat).
-define(ecomet_stat, true).

% types: web socket, rabbit
% key: time
% dir key: inc {own, other}, og

-record(stat, {
    wsock, % {day, hour, min} dictionaries
    rabbit
}).

-endif.
