#!/usr/bin/perl 
#
# Copyleft 2024 O. Sotolongo <osotolongo@fundacioace.org>  
#
# This script is intended for extract the metrics from the gVCF files and the intermediate BAM files
# TYhis is intended to run after the Parabricks execution and is useless in other context
use strict; 
use warnings; 
use SLURMACE; 
use File::Find::Rule;
use File::Basename;
use Cwd;
use FindBin; 
use lib "$FindBin::Bin";
use wxsInit; 
use Data::Dump qw(dump);
############################################# 
# See: 
#   - For WES pipeline: http://detritus.fundacioace.com/wiki/doku.php?id=genetica:wes 
#   - For execution into SLURM: https://github.com/asqwerty666/acenip/blob/main/doc/SLURMACE.md 
############################################# 
#
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
my $init;
my $mode = 'wgs'; # Default mode here is WGS cause is what is intended for
my $debug = 0; 
my $test = 0; 
while (@ARGV and $ARGV[0] =~ /^-/) {
	$_ = shift;         
	last if /^--$/;         
	if (/^-c/) { $cfile = shift; chomp($cfile);}         
	if (/^-i/) { $init = shift; chomp($init);}
	if (/^-m/) { $mode = shift; chomp($mode);}
	if (/^-g/) { $debug = 1;}         
	if (/^-t/) { $test = 1;}         
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
my %ptask = (cpus => 8, time => '72:0:0', mem_per_cpu => '4G', debug => $test);

die "No such directory mate\n" unless -d $wesconf{src_dir};
my @pollos;
my $ipath = $wesconf{src_dir}.'/';
my @idirs = glob( $ipath.'*' );
foreach my $idir (@idirs) {
	my @gvcfs = find(file => 'name' => qr/.*\.g\.vcf\.gz$/, in => "$idir");
	if ( -d $idir and $gvcfs[0] and -f $gvcfs[0]) {
		my ($pollo) = $idir =~ /$ipath\/*(.*)$/;
		push @pollos, $pollo;
	}
}
my @jobs;
foreach my $pollo (@pollos){
	my $go = 0;
	my @mjobs;
	if ($cfile) {
		if (grep {/$pollo/} @plist) {$go = 1;}
	}else{
		$go = 1;
	}
	if (-d "$wesconf{src_dir}/$pollo" and $go){
		my $rdir = "$wesconf{src_dir}/$pollo/";
		my $tdir = "$wesconf{outdir}/$pollo/tmp";
		if(exists($ptask{'dependency'})){ delete($ptask{'dependency'}) };
		# VerifyBamID (freemix)
		$ptask{job_name} = $pollo.'_verifyBamID';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_verifyBamID.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_verifyBamID.out';
		$ptask{command} = "$epaths{freemix} --BamFile $rdir/$pollo"."_rmdup.bam --Reference $ref_fa --Output $rdir/$pollo".".vbid2\n";
		my $job = send2slurm(\%ptask); push @jobs, $job;
		# AnalyzeCovariates, depende de BaseRecalibrator
		my $unions = ($mode eq 'wgs')?'':$wesconf{panel_dir}.'/'.$wesconf{unions};
		$ptask{job_name} = $pollo.'_analyzeCovariates';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_analyzeCovariates.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_analyzeCovariates.out';
		$ptask{command} = "$epaths{gatk} AnalyzeCovariates -bqsr $rdir/$pollo"."_recal_data.table --plots $rdir/$pollo"."_AnalyzeCovariates.pdf\n";
		$job = send2slurm(\%ptask); push @jobs, $job;
		# Sort to coordinate
		$ptask{job_name} = $pollo.'_coordinateSortSam';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_coordinateSortSam.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_coordinateSortSam.out';
		$ptask{command} = "$epaths{gatk} SortSam -I $rdir/$pollo"."_recal.bam -O $tdir/$pollo"."_recal_sorted.bam -R $ref_fa --SORT_ORDER coordinate --CREATE_INDEX true --TMP_DIR $tdir\n";
		my $jid = send2slurm(\%ptask);
		my @mjobs; my $mjob; 
		unless ($mode eq 'wgs'){
			# CollectWGSMetrics, depende de ApplyBQSR
			$ptask{cpus} = 4;
			$ptask{job_name} = $pollo.'_collectRawMetrics';
			$ptask{filename} = $slurmdir.'/'.$pollo.'_collectRawMetrics.sh';
			$ptask{output} = $slurmdir.'/'.$pollo.'_collectRawMetrics.out';
			$ptask{command} = "$epaths{gatk}  DepthOfCoverage -I $tdir/$pollo"."_recal_sorted.bam -O $rdir/$pollo"."_raw_wes_metrics.txt -R $ref_fa".(($mode eq 'wgs')?' ':" -L $unions ")."--summary-coverage-threshold 10 --summary-coverage-threshold 15 --summary-coverage-threshold 20 --summary-coverage-threshold 30 --summary-coverage-threshold 40 --summary-coverage-threshold 50 --summary-coverage-threshold 60 --summary-coverage-threshold 70 --summary-coverage-threshold 80 --summary-coverage-threshold 90 --summary-coverage-threshold 100 --omit-depth-output-at-each-base true --omit-interval-statistics true --omit-locus-table true\n";
			$ptask{dependency} = "afterok:$jid";
			$mjob = send2slurm(\%ptask); push @mjobs, $mjob;
			$ptask{job_name} = $pollo.'_collectWgsMetrics';
			$ptask{filename} = $slurmdir.'/'.$pollo.'_collectWgsMetrics.sh';
			$ptask{output} = $slurmdir.'/'.$pollo.'_collectWgsMetrics.out';
			$ptask{command} = "$epaths{gatk}  DepthOfCoverage -I $tdir/$pollo"."_recal_sorted.bam -O $rdir/$pollo"."_wes_metrics.txt -R $ref_fa".(($mode eq 'wgs')?' ':" -L $unions ")."--summary-coverage-threshold 10 --summary-coverage-threshold 15 --summary-coverage-threshold 20 --summary-coverage-threshold 30 --summary-coverage-threshold 40 --summary-coverage-threshold 50 --summary-coverage-threshold 60 --summary-coverage-threshold 70 --summary-coverage-threshold 80 --summary-coverage-threshold 90 --summary-coverage-threshold 100 --omit-depth-output-at-each-base true --omit-interval-statistics true --omit-locus-table true --min-base-quality 20 -RF MappingQualityReadFilter --minimum-mapping-quality 20\n";
			$ptask{dependency} = "afterok:$jid";
			$mjob = send2slurm(\%ptask); push @mjobs, $mjob; 
			$ptask{job_name} = $pollo.'_collectPaddedMetrics';
			$ptask{filename} = $slurmdir.'/'.$pollo.'_collectPaddedMetrics.sh';
			$ptask{output} = $slurmdir.'/'.$pollo.'_collectPaddedMetrics.out';
			$ptask{command} = "$epaths{gatk}  DepthOfCoverage -I $tdir/$pollo"."_recal_sorted.bam -O $rdir/$pollo"."_padded_wes_metrics.txt -R $ref_fa".(($mode eq 'wgs')?' ':" -L $unions ")."--summary-coverage-threshold 10 --summary-coverage-threshold 15 --summary-coverage-threshold 20 --summary-coverage-threshold 30 --summary-coverage-threshold 40 --summary-coverage-threshold 50 --summary-coverage-threshold 60 --summary-coverage-threshold 70 --summary-coverage-threshold 80 --summary-coverage-threshold 90 --summary-coverage-threshold 100 --omit-depth-output-at-each-base true --omit-interval-statistics true --omit-locus-table true -ip 100 --min-base-quality 20 -RF MappingQualityReadFilter --minimum-mapping-quality 20\n";
			$ptask{dependency} = "afterok:$jid";
			$mjob = send2slurm(\%ptask); push @mjobs, $mjob;
		}else{
			 $ptask{cpus} = 4;
			 $ptask{job_name} = $pollo.'_collectWgsMetrics';
			 $ptask{filename} = $slurmdir.'/'.$pollo.'_collectWgsMetrics.sh';
			 $ptask{output} = $slurmdir.'/'.$pollo.'_collectWgsMetrics.out';
			 $ptask{command} = "$epaths{gatk} CollectWgsMetrics -I $tdir/$pollo"."_recal_sorted.bam -O $rdir/$pollo"."_wgs_metrics.txt -R $ref_fa\n";
			 $ptask{dependency} = "afterok:$jid";
			 $mjob = send2slurm(\%ptask); push @mjobs, $mjob;
			 $ptask{job_name} = $pollo.'_collectRawMetrics';
			 $ptask{filename} = $slurmdir.'/'.$pollo.'_collectRawMetrics.sh';
			 $ptask{output} = $slurmdir.'/'.$pollo.'_collectRawMetrics.out';
			 $ptask{command} = "$epaths{gatk} CollectRawWgsMetrics -I $tdir/$pollo"."_recal_sorted.bam -O $rdir/$pollo"."_raw_wgs_metrics.txt -R $ref_fa\n";
			 $ptask{dependency} = "afterok:$jid";
			 $mjob = send2slurm(\%ptask); push @mjobs, $mjob;
		}
		# VariantEval
		if(exists($ptask{'dependency'})){ delete($ptask{'dependency'}) };
		$ptask{cpus} = 8;
		$ptask{job_name} = $pollo.'_variantEval';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_variantEval.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_variantEval.out';
		my @gvcfs = find(file => 'name' => qr/.*\.g\.vcf\.gz$/, in => "$rdir");
		$ptask{command}.= "$epaths{gatk} VariantEval -R $ref_fa".(($mode eq 'wgs')?' ':" -L $unions ")."-D $dpaths{ref_dir}/$dpaths{hcsnps} -O $rdir/$pollo"."_eval.gatkreport --eval $gvcfs[0]\n";
		$job = send2slurm(\%ptask); push @jobs, $job;
		# cleanShit
		$ptask{job_name} = $pollo.'_closeSubject';
		$ptask{filename} = $slurmdir.'/'.$pollo.'_closeSubject.sh';
		$ptask{output} = $slurmdir.'/'.$pollo.'_closeSubject.out';
		$ptask{dependency} = 'afterok:'.join(',afterok:', @mjobs);
		$ptask{command} = $debug?":\n":"rm -rf $tdir\n";
		$job = send2slurm(\%ptask); push @jobs, $job;
	}
}
unless ($test) {
	my %wtask = (cpus => 1, job_name => 'end_metrics', filename => $slurmdir.'/end.sh', output => $slurmdir.'/end.out', dependency => 'afterok:'.join(',afterok:',@jobs));
	send2slurm(\%wtask);
}
