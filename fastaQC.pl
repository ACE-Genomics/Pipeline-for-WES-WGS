#!/usr/bin/perl 
#
# Copyleft 2026 O. Sotolongo <asqwerty@gmail.com>  
#
# This script is intended for make QC to Fasta
use strict; 
use warnings; 
use File::Find::Rule;
use File::Basename;
use Cwd;
use FindBin;
use lib "$FindBin::Bin";
use wxsInit; 
use slurmExec;
use Data::Dump qw(dump);
############################################# 
# See: 
#   - For WES pipeline: http://detritus.fundacioace.com/wiki/doku.php?id=genetica:wes 
#   - For execution into SLURM: https://github.com/ACE-Genomics/Pipeline-for-WES-WGS/blob/main/slurmExec.md 
############################################# 
#
# Data Paths 
# 
my %dpaths = data_paths();
my $ref_fa = $dpaths{ref_dir}.'/'.$dpaths{ref_name}.'.fasta'; 
my $tmp_shit = $ENV{TMPDIR}; 
# 
#
# Executable Paths 
#
#
my %epaths = exec_paths();
# 
#
# 
# Get CLI inputs 
#
#
my $cfile; 
my $debug = 0; 
my $test = 0;
my $mode = 'wes';
my $init;
while (@ARGV and $ARGV[0] =~ /^-/) {
	$_ = shift;         
	last if /^--$/;         
	if (/^-c/) { $cfile = shift; chomp($cfile);}         
	if (/^-i/) { $init = shift; chomp($init);}         
	if (/^-g/) { $debug = 1;}         
	if (/^-t/) { $test = 1;}
	if (/^-m/) { $mode = shift; chomp($mode);}
} 
die "Should supply init data file\n" unless $init;
my %wesconf = init_conf($init);
my $workdir = getcwd;
$wesconf{outdir} = $workdir.'/output' unless $wesconf{outdir};
mkdir $wesconf{outdir} unless -d $wesconf{outdir}; 
my $slurmdir = $wesconf{outdir}.'/slurm'; 
mkdir $slurmdir unless -d $slurmdir;
# Do you want to process just a subset? Read the supplied list of subjects 
my @plist; 
if ($cfile and -f $cfile) {         
	open my $handle, "<$cfile";         
	chomp (@plist = <$handle>);         
	close $handle; 
}
my %ptask = ('cpus-per-task' => 8, time => ($mode  eq 'wgs')?'72:0:0':'24:0:0', 'mem-per-cpu' => '4G', debug => $test);
die "No such directory mate\n" unless -d $wesconf{src_dir};
my @content = find(file => 'name' => "*$wesconf{search_pattern}*", in => $wesconf{src_dir});
@content = grep {!/.*$wesconf{cleaner}.*/} @content if exists($wesconf{cleaner}) and $wesconf{cleaner};
my %pollos = map {/.*\/(\w+?)$wesconf{search_pattern}.*$/; $1 => $_} @content;
#dump %pollos; exit;
my @jobs;
foreach my $pollo (sort keys %pollos){
	my $go = 0;
	if ($cfile) {
		if (grep {/$pollo/} @plist) {$go = 1;}
	}else{
		$go = 1;
	}
	if (-f $pollos{$pollo} and $go){
		my $qdir = "$wesconf{outdir}/$pollo/qc";
		my $rdir = "$wesconf{outdir}/$pollo/results";
		my $tdir = "$wesconf{outdir}/$pollo/tmp";
		(my $another = $pollos{$pollo}) =~ s/$wesconf{search_pattern}/$wesconf{alt_pattern}/;
		# FASTQC	
		$ptask{'job-name'} = $pollo.'_fastQc';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_fastQc.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_fastQc.out';
		$ptask{command} = "mkdir -p $qdir\n";
		$ptask{command}.= "$epaths{fastqc} -o $qdir $pollos{$pollo} $another\n";
		my $jid = slurmexec(\%ptask);
		push @jobs, $jid;
	}
} 
unless ($test) {
	my %wtask = ('cpus-per-task' => 1, 'mail-type' => 'END','job-name' => 'end_qc', filename => $slurmdir.'/end.sh', output => $slurmdir.'/end.out', dependency => 'afterok:'.join(',afterok:',@jobs));
	slurmexec(\%wtask);
}
