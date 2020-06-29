# you can change cmd.sh depending on what type of queue you are using.
# If you have no queueing system and want to run on a local machine, you
# can change all instances 'queue.pl' to run.pl (but be careful and run
# commands one by one: most recipes will exhaust the memory on your
# machine).  queue.pl works with GridEngine (qsub).  slurm.pl works
# with slurm.  Different queues are configured differently, with different
# queue names and different ways of specifying things like memory;
# to account for these differences you can create and edit the file
# conf/queue.conf to match your queue's configuration.  Search for
# conf/queue.conf in http://kaldi-asr.org/doc/queue.html for more information,
# or search for the string 'default_config' in utils/queue.pl or utils/slurm.pl.

export train_cmd="queue.pl --mem 8G --nodes_rack 4"
export decode_cmd="queue.pl --mem 8G --nodes_rack 4"
export train_cmd_intel="queue.pl --mem 8G --nodes_rack 4"
export train_cmd_all_intel="queue.pl --mem 8G --remove_nodes_rack 7"
export train_cmd_r5="queue.pl --mem 16G --nodes_rack 5 --gpu_queue 1"
export train_cmd_r7="queue.pl --mem 16G --nodes_rack 7 --gpu_queue 1"
export train_cmd_r6="queue.pl --mem 16G --nodes_rack 6 --gpu_queue 1"
export train_cmd_r8="queue.pl --mem 16G --nodes_rack 8 --gpu_queue 1"
export train_cmd_tesla="queue.pl --mem 16G --nodes_tesla 1 --gpu_queue 1"
export gpu_cmd="queue.pl --mem 8G --gpu 1"




