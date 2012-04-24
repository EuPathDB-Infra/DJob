#!/usr/bin/perl

use strict;
use Getopt::Long;

my($fastaFile,$mateA,$mateB,$bwaIndex,$strain,$snpsOnly);
my $out = "result";
my $varscan = "/home/brunkb/software/varscan/VarScan.v2.2.10.jar";
my $gatk = "/home/brunkb/software/GATK/11-Apr-2012/GenomeAnalysisTK-1.5-25-gf46f7d0/GenomeAnalysisTK.jar";
my $consPercentCutoff = 60; ## use to generate consensus
my $snpPercentCutoff = 20; ## use for snps and indels
my $editDistance = 0.04;

&GetOptions("fastaFile|f=s" => \$fastaFile, 
            "mateA|ma=s"=> \$mateA,
            "mateB|mb=s" => \$mateB,
            "outputPrefix|o=s" => \$out,
            "bwaIndex|b=s" => \$bwaIndex,
            "varscan|v=s" => \$varscan,
            "gatk|g=s" => \$gatk,
            "strain|s=s" => \$strain,
            "consPercentCutoff|cpc=s" => \$consPercentCutoff,
            "snpPercentCutoff|spc=s" => \$snpPercentCutoff,
            "editDistance|ed=s" => \$editDistance,
            "snpsOnly!" => \$snpsOnly,
            );

die "varscan jar file not found\n".&getParams() unless -e "$varscan";
die "mateA file not found\n".&getParams() unless -e "$mateA";
die "mateB file not found\n".&getParams() if ($mateB && !-e "$mateB");
die "fasta file not found\n".&getParams() unless -e "$fastaFile";
die "bwa indices not found\n".&getParams() unless -e "$bwaIndex.amb";
die "you must provide a strain\n".&getParams() unless $strain;
##should add in usage

$snpPercentCutoff = $consPercentCutoff unless $snpPercentCutoff;


## indices ..  bwa index -p <prefix for indices> <fastafile>  ##optional -c flag if colorspace

## do we want to check to see if bwa indices are present and if not, create?

my $cmd = "(bwa aln -t 4 -n $editDistance $bwaIndex $mateA > $out.mate1.sai) >& $out.bwa_aln_mate1.log";
print STDERR &getDate().": $cmd\n\n";

system($cmd);

if(-e "$mateB"){
  $cmd = "(bwa aln -t 4 -n $editDistance $bwaIndex $mateB > $out.mate2.sai) >& $out.bwa_aln_mate2.log";
  print STDERR &getDate().": $cmd\n\n";
  system($cmd);

  $cmd = "(bwa sampe -r '\@RG\tID:EuP\tSM:$strain\tPL:Illumina' $bwaIndex $out.mate1.sai $out.mate2.sai $mateA $mateB > $out.sam) >& $out.bwa_sampe.log";
  print STDERR &getDate().": $cmd\n\n";
  system($cmd);
}else{
  print STDERR &getDate().": Aligning in single end mode only\n";
  
  $cmd = "(bwa samse -r '\@RG\tID:EuP\tSM:$strain\tPL:Illumina' $bwaIndex $out.mate1.sai $mateA > $out.sam) >& $out.bwa_samse.log";
  print STDERR &getDate().": $cmd\n\n";
  system($cmd);
}

$cmd = "samtools faidx $fastaFile" unless -e "$fastaFile.fai";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

$cmd = "(samtools view -t $fastaFile.fai -uS $out.sam | samtools sort - $out) >& $out.samtools_view.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

$cmd = "samtools index $out.bam";
print STDERR &getDate().": $cmd\n\n";
system($cmd);


$cmd = "java -Xmx2g -jar $gatk -I $out.bam -R $fastaFile -T RealignerTargetCreator -o forIndelRealigner.intervals >& realignerTargetCreator.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

my $outGatk = $out . "_gatk";
$cmd = "java -Xmx2g -jar $gatk -I $out.bam -R $fastaFile -T IndelRealigner -targetIntervals forIndelRealigner.intervals -o $outGatk.bam >& indelRealigner.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

## I wonder if would be good to sort again here?

$cmd = "(samtools pileup -f $fastaFile $outGatk.bam > $outGatk.pileup) &> $outGatk.pileup.err";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

my $pc = $consPercentCutoff / 100;
my $mpc = $snpPercentCutoff / 100;

$cmd = "(java -Xmx2g -jar $varscan pileup2snp $outGatk.pileup --p-value 0.01 --min-coverage 5 --min-var-freq $mpc > $outGatk.varscan.snps ) >& $outGatk.varscan_snps.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

$cmd = "parseVarscanToGFF.pl --f $outGatk.varscan.snps --strain $strain --pc $snpPercentCutoff --o $outGatk.SNPs.gff >& $outGatk.parseVarscan.err";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

exit(0) if $snpsOnly;

$cmd = "(java -Xmx2g -jar $varscan pileup2indel $outGatk.pileup --p-value 0.01 --min-coverage 5 --min-var-freq $mpc > $outGatk.varscan.indels ) >& $outGatk.varscan_indels.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);


$cmd = "(java -Xmx2g -jar $varscan pileup2cns $outGatk.pileup --p-value 0.01 --min-coverage 5 --min-var-freq $pc > $outGatk.varscan.cons ) >& $outGatk.varscan_cons.log";
print STDERR &getDate().": $cmd\n\n";
system($cmd);

sub getParams {
  return &getDate().": runBWA_HTS.pl ... parameter values:\n\tfastaFile=$fastaFile\n\tbwaIndex=$bwaIndex\n\tmateA=$mateA\n\tmateB=$mateB\n\toutputPrefix=$out\n\tstrain=$strain\n\tconsPercentCutoff=$consPercentCutoff\n\tsnpPercentCutoff=$snpPercentCutoff\n\teditDistance=$editDistance\n\tvarscan=$varscan\n\tgatk=$gatk\n\n";
}

sub getDate {
  my $date = `date`;
  chomp $date;
  return $date;
}
