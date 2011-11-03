#!/bin/sh
for t in `seq 1 10`
do
	(
	for a in `seq 1 82`
	do
		amqp-publish -e negacom -r ev2 -b "t$t=${a}, `date`"
		sleep 1
	done
	) &
	amqp-publish -e negacom -r ev2 -b "sp, `date`"
done
