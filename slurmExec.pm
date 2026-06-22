#!/usr/bin/perl

# Copyright 2026 O. Sotolongo <asqwerty@gmail.com>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use warnings;
package slurmExec;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(slurmexec wait4jobs);
our @EXPORT_OK = qw(slurmexec wait4jobs);
our %EXPORT_TAGS =(all => qw(slurmexec wait4jobs), usual => qw(slurmexec wait4jobs));
our $VERSION = 1.0;

sub default_task{
	# default values for any task
	my %task;
	$task{'mem-per-cpu'} = '4G';
	$task{'cpus-per-task'} = 1;
	$task{'time'} = '2:0:0';
	my $label = sprintf("%03d", rand(1000));
	$task{'filename'} = 'slurm_'.$label.'.sh';
	$task{'output'} = 'slurm_'.$label.'.out';
	$task{'job-name'} = 'myjob';
	$task{'mailtype'} = 'FAIL,TIME_LIMIT,STAGE_OUT';
	return %task;
}

=head1 slurmExec

This module contains a function to send the jobs to SLURM 
from the Perl scripts and another for wait the scripts
to finish its execution

=over

=item slurmexec

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

B<Dependencies:> If dependencies are going to be used, you need to pass to
the function the full string that SLURM expects. That is, you can pass something 
like I<singleton> or I<after:000000> or even I<afterok:000000,afterok:000001,afterok:000002>. 
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
B<dependency> option could be safely ignored. But notice that, if you are 
reusing a HASH then this key should be deleted from it. 


=cut

sub slurmexec{
	my %task = %{$_[0]};
	my %dtask = default_task;
	foreach my $p (keys %task){
		$task{$p} = $dtask{$p} unless $task{$p};
	}
	my $scriptfile = $task{filename};
	delete $task{filename};
	my $command;
	if (exists($task{command}) and $task{command}){
		$command = $task{command};
		delete $task{command};
	}
	my $debug = $task{debug};
	delete $task{debug};
	my $order;
	if(exists($task{dependency}) && $task{dependency}){
		$order = 'sbatch --parsable --dependency='.$task{'dependency'}.' '.$scriptfile;
	}else{
		$order = 'sbatch --parsable '.$scriptfile;
	}
	delete $task{dependency};
	open ESS, ">$scriptfile" or die 'Could not create slurm script\n';
	print ESS '#!/bin/bash'."\n";
	foreach my $prop (sort keys %task) {
		if ($prop =~ /^-.*/){
			if ($prop =~ /^--.*/){
				print ESS "#SBATCH $prop=$task{$prop} \n";
			}else{
				print ESS "#SBATCH $prop $task{$prop} \n";
			}
		}else{
			print ESS "#SBATCH --$prop=$task{$prop}\n";
		}
	}
	print ESS "$command\n" if $command;
	close ESS;
	unless ($debug) {
		my $code = qx/$order/;
		chomp $code;
		return $code;
	}
	return 0;
}


=item wait4jobs

This function uses slurm to ask if given jobs are running. User should supply an array with all the
jobs that function should wait for. Once all the jobs have finished, the control is returned to main 
program

	usage: wait4jobs(@jobs_list) 

=cut

sub wait4jobs{
	my $jlist = join ',',@_;
	my $status;
	do {
		sleep 60;
		$status = qx/squeue -j $jlist | grep -v JOBID/;
		print "." if $status;
	} while($status);
	print "\n";
}

=back
