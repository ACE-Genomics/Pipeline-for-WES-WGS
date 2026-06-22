# slurmExec

This module contains a function to send the jobs to SLURM 
from the Perl scripts and another for wait the scripts
to finish its execution

- slurmexec

    The function takes a HASH as input where all the information 
    relative to the job should be stored. No data is mandatory 
    inside the input HASH, since the minimal values are automagicaly
    asigned by default as a constructor (no really, but anyway).

    Take into account that this subroutine only pass the parameters 
    to SLURM. So, the logic behind your actions should correspond
    to what you want to do in any case, exactly as if you were 
    writing sbatch scripts.

    All the hash keys, except for execution options, will be written 
    into the sbatch script that will be send to the queue. You can write, 
    by example

            my %task = (job-name => "whatever", 
            '-c' => 4, 
            partition => 'default',
            command => "hostname");
            slurmexec(\%task);
            

    and the result should be a script with

            #!/bin/bash
            #SBATCH --job-name=whatever
            #SBATCH -c 4
            #SBATCH --partition=default
            hostname

    The managed execution options for SLURM jobs are:

            - filename: File where the sbatch script will be stored
            - debug: Slurm script will be created but not send to the queue 
            - dependency: Full dependency string to be used at sbatch execution (--dependency), see more below
            - command: the full list of commands that should execute the sbatch script

    The function returns the jobid of the queued job, so it can be used to 
    build complex workflows.

            usage: my $job_id = slurmexec(\%job_properties);

    **Dependencies:** If dependencies are going to be used, you need to pass to
    the function the full string that SLURM expects. That is, you can pass something 
    like _singleton_ or _after:000000_ or even _afterok:000000,afterok:000001,afterok:000002_. 
    This last can be build, by example, storing every previous jobid into an ARRAY
    and passing then as,

            ...
                    my $jobid = slurmexec(\%previous);
                    push @jobids, $jobid;
            ...
            $task{'dependency'} = 'afterok:'.join(',afterok:',@jobids);
            ...
            slurmexec(\%task);

    Of course, if dependencies are not going to be used, the 
    **dependency** option could be safely ignored. But notice that, if you are 
    reusing a HASH then this key should be deleted from it. 

- wait4jobs

    This function uses slurm to ask if given jobs are running. User should supply an array with all the
    jobs that function should wait for. Once all the jobs have finished, the control is returned to main 
    program

            usage: wait4jobs(@jobs_list) 
