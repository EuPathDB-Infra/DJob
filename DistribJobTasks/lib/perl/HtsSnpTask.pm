package DJob::DistribJobTasks::HtsSnpTask;

use DJob::DistribJob::Task;
use CBIL::Bio::FastaFileSequential;
use File::Basename;
use Cwd;
use CBIL::Util::Utils;

@ISA = (DJob::DistribJob::Task);

use strict;

# [name, default (or null if reqd), comment]
my @properties = 
(
	["fastaFile", "", "full path of fastaFile for genome"],
	["mateA", "none", "full path to file of reads"],
	["mateB", "none", "full path to file of paired ends reads"],
	["sraSampleIdQueryList", "none", "Comma delimited list of identifiers that can be used to retrieve SRS samples"],
	["outputPrefix", "result", "prefix of output files"],
	["bwaIndex", "", "full path of the bwa indices .. likely same as fasta file"],
	["varscan", "/genomics/eupath/eupath-tmp/software/VarScan/2.2.10/VarScan.jar", "full path to the varscan jar file"],
	["gatk", "/genomics/eupath/eupath-tmp/software/gatk/1.5.31/GenomeAnalysisTK.jar", "full path to the GATK jar file"],
	["strain", "", "strain to be put into the GFF file"],
	["consPercentCutoff", "60", "minimum allele percent for calling consensus base"],
	["snpPercentCutoff", "20", "minimum allele percent for calling SNPs"],
	["editDistance", "0.04", "mismatch in bwa"],
	["snpsOnly", "false", "if true then doesn't compute consensus or indels"]
);

sub new {
    my $self = &DJob::DistribJob::Task::new(@_, \@properties);
    return $self;
}

# called once 
sub initServer {
  my ($self, $inputDir) = @_;
  ##need to download fastq from sra if sample ids passed in.
  my $sidlist = $self->getProperty('sraSampleIdQueryList');
  if($sidlist && $sidlist ne 'none'){ ##have a value and other than default
    my $mateA = $self->getProperty('mateA');
    if(-e "$mateA"){
      print "reads file $mateA already present so not retrieving from SRA\n";
    }else{  ##need to retrieve here
      my $mateB;
      if(!$mateA || $mateA eq 'none'){
        $mateA = "reads_1.fastq";
        $self->setProperty('mateA',"$inputDir/$mateA");
        $mateB = "reads_2.fastq";
        $self->setProperty('mateB',"$inputDir/$mateB");
      }
      if(-e "$inputDir/$mateA"){
        print "Already retrieved fastq file from SRA from $sidlist\n";
        return 1;
      }
      $self->{nodeForInit}->runCmd("getFastqFromSra.pl --workingDir $inputDir --readsOne $mateA --readsTwo $mateB --sampleIdList '$sidlist'");
    }
  } 
}

sub initNode {
    my ($self, $node, $inputDir) = @_;
}

sub getInputSetSize {
    my ($self, $inputDir) = @_;
    return 1;
}

sub initSubTask {
    my ($self, $start, $end, $node, $inputDir, $serverSubTaskDir, $nodeExecDir,$subTask) = @_;
}

sub makeSubTaskCommand { 
    my ($self, $node, $inputDir, $nodeExecDir) = @_;

    my $fastaFile = $self->getProperty ("fastaFile");
    my $mateA = $self->getProperty ("mateA");
    my $mateB = $self->getProperty ("mateB");
    my $outputPrefix = $self->getProperty ("outputPrefix");
    my $bwaIndex = $self->getProperty ("bwaIndex");
    my $gatk = $self->getProperty ("gatk");
    my $varscan = $self->getProperty ("varscan");
    my $strain = $self->getProperty ("strain");
    my $consPercentCutoff = $self->getProperty ("consPercentCutoff");
    my $snpPercentCutoff = $self->getProperty ("snpPercentCutoff");
    my $editDistance = $self->getProperty ("editDistance");
    my $snpsOnly = $self->getProperty ("snpsOnly");
    my $wDir = "$node->{masterDir}/mainresult";
    
    
    my $cmd .= "runHTS_SNPs.pl --fastaFile $fastaFile --mateA $mateA".(-e "$mateB" ? " --mateB $mateB" : "");
    $cmd .= " --outputPrefix $outputPrefix --bwaIndex $bwaIndex --varscan $varscan";
    $cmd .= " --strain $strain --consPercentCutoff $consPercentCutoff --snpPercentCutoff $snpPercentCutoff";
    $cmd .= " --editDistance $editDistance".($snpsOnly eq 'false' ? "" : " --snpsOnly");
    $cmd .= " --workingDir $wDir";
      
#    print "Returning command: $cmd\n";
#    exit(0);  ##for testing
    return $cmd;
}

##cleanup materDir here and remove extra files that don't want to transfer back to compute node
sub integrateSubTaskResults {
    my ($self, $subTaskNum, $node, $nodeExecDir, $mainResultDir) = @_;
}

sub cleanUpServer {
  my($self, $inputDir, $mainResultDir, $node) = @_;
}

1;
