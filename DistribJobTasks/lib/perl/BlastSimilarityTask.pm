package DJob::DistribJobTasks::BlastSimilarityTask;

use DJob::DistribJob::Task;
use CBIL::Bio::FastaFile;
use File::Basename;
use Cwd;
use CBIL::Util::Utils;

@ISA = (DJob::DistribJob::Task);

use strict;

# [name, default (or null if reqd), comment]
my @properties = 
(
 ["blastBinDir",   "",   "eg, /genomics/share/pkg/bio/ncbi-blast/latest"],
 ["dbFilePath",      "",     "full path to database file"],
 ["inputFilePath",   "",     "full path to input file"],
 ["dbType",          "",     "p or n (not nec. if cdd run)"],
 ["pValCutoff",      "1e-5",  ""],
 ["lengthCutoff",    "10",    ""],
 ["percentCutoff",   "20",    ""],
 ["blastProgram",    "",     "rpsblast if cdd | any wu-blast"],
 ["regex",           "'(\\S+)'",     "regex for id on defline after the >"],
 ["blastParamsFile", "",    "file holding blast params -relative to inputdir"],
 );

sub new {
    my $self = &DJob::DistribJob::Task::new(@_, \@properties);
    return $self;
}

# called once 
sub initServer {
    my ($self, $inputDir) = @_;

    my $blastBin = $self->{props}->getProp("blastBinDir");
    my $dbFilePath = $self->{props}->getProp("dbFilePath");
    my $dbType = $self->{props}->getProp("dbType");
    my $blastProgram = $self->{props}->getProp("blastProgram");

    if (-e "$dbFilePath.gz") {
	&runCmd("gunzip $dbFilePath.gz");
    }

    die "blastBinDir $blastBin doesn't exist" unless -e $blastBin;

    # run if we don't have indexed files or they are older than seq file
    if ($blastProgram eq 'rpsblast') {  
	die "dbFilePath $dbFilePath doesn't exist" unless -e "$dbFilePath";
	my $cwd = &getcwd();
	chdir(dirname($dbFilePath));
	my @ls = `ls -rt $dbFilePath.mn $dbFilePath.rps`;
	map { chomp } @ls;
	if (scalar(@ls) != 2 || $ls[0] ne "$dbFilePath.mn") {
	    &runCmd("$blastBin/copymat -r T -P $dbFilePath");
	}

	my @ls = `ls -rt $dbFilePath $dbFilePath.p*`;
	map { chomp } @ls;
	if (scalar(@ls) != 6 || $ls[0] ne $dbFilePath) {
	    &runCmd("$blastBin/formatdb -o T -i $dbFilePath");
	}
	chdir $cwd;

    } else {
	die "dbFilePath $dbFilePath doesn't exist" unless -e $dbFilePath;
	my @ls = `ls -rt $dbFilePath $dbFilePath.x$dbType*`;
	map { chomp } @ls;
	if (scalar(@ls) != 4 || $ls[0] ne $dbFilePath) {
	    &runCmd("$blastBin/xdformat -$dbType $dbFilePath");
	}
    }
}

sub initNode {
    my ($self, $node, $inputDir) = @_;

    my $blastProgram = $self->{props}->getProp("blastProgram");
    my $dbFilePath = $self->{props}->getProp("dbFilePath");
    my $nodeDir = $node->getDir();

    $node->runCmd("cp $dbFilePath.* $nodeDir");
    if ($blastProgram eq 'rpsblast') {  
	$node->runCmd("cp $dbFilePath $nodeDir");
    }
}

sub getInputSetSize {
    my ($self, $inputDir) = @_;

    my $fastaFileName = $self->{props}->getProp("inputFilePath");

    if (-e "$fastaFileName.gz") {
	&runCmd("gunzip $fastaFileName.gz");
    }

    print "Creating index for $fastaFileName (may take a while)\n";
    $self->{fastaFile} = CBIL::Bio::FastaFile->new($fastaFileName);
    return $self->{fastaFile}->getCount();
}

sub initSubTask {
    my ($self, $start, $end, $node, $inputDir, $subTaskDir, $nodeSlotDir) = @_;

    my $blastParamsFile = $self->{props}->getProp("blastParamsFile");
    &runCmd("cp $inputDir/$blastParamsFile $subTaskDir");
    $self->{fastaFile}->writeSeqsToFile($start, $end, "$subTaskDir/seqsubset.fsa");

    $node->runCmd("cp -r $subTaskDir/* $nodeSlotDir");
}

sub runSubTask { 
    my ($self, $node, $inputDir, $subTaskDir, $nodeSlotDir) = @_;

    my $blastBin = $self->{props}->getProp("blastBinDir");
    my $lengthCutoff = $self->{props}->getProp("lengthCutoff");
    my $pValCutoff = $self->{props}->getProp("pValCutoff");
    my $percentCutoff = $self->{props}->getProp("percentCutoff");
    my $blastProgram = $blastBin . "/" . $self->{props}->getProp("blastProgram");
    my $regex = $self->{props}->getProp("regex");
    my $blastParamsFile = $self->{props}->getProp("blastParamsFile");
    my $dbFilePath = $self->{props}->getProp("dbFilePath");

    my $dbFile = $node->getDir() . "/" . basename($dbFilePath);

    my $cmd =  "blastSimilarity  --blastBinDir $blastBin --database $dbFile --seqFile $nodeSlotDir/seqsubset.fsa --lengthCutoff $lengthCutoff --pValCutoff $pValCutoff --percentCutoff $percentCutoff --blastProgram $blastProgram --regex $regex --blastParamsFile $nodeSlotDir/$blastParamsFile";

    $node->execSubTask("$nodeSlotDir/result", "$subTaskDir/result", $cmd);
}

sub integrateSubTaskResults {
    my ($self, $subTaskNum, $subTaskResultDir, $mainResultDir) = @_;

    &runCmd("cat $subTaskResultDir/blastSimilarity.out >> $mainResultDir/blastSimilarity.out");
    &runCmd("cat $subTaskResultDir/blastSimilarity.log >> $mainResultDir/blastSimilarity.log");
}
1;