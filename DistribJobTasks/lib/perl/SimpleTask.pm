package DJob::DistribJobTasks::SimpleTask;

use DJob::DistribJob::Task;
use CBIL::Util::Utils;

@ISA = (DJob::DistribJob::Task);

use strict;

# [name, default (or null if reqd), comment]
my @properties = 
(
 ["cmd",    "",     "fully specified command to execute"],
 ["debug",  "false", ""],
 );

sub new {
    my $self = &DJob::DistribJob::Task::new(@_, \@properties);
    my $debug = $self->getProperty("debug");
    $self->{'debug'} = 1 if $debug =~ /true/i;
    return $self;
}

# called once
sub initServer {
    my ($self, $inputDir) = @_;
    # do nothing
}

sub initNode {
    my ($self, $node, $inputDir) = @_;
    my $nodeDir = $node->getDir();
    print "DEBUG: SimpleTask::initNode(node=$node, nodeDir=$nodeDir, inputDir=$inputDir)\n"
	if $self->{'debug'};

    my $cmd = "cp -r $inputDir/* $nodeDir";
    print "DEBUG: SimpleTask::initNode: running command $cmd...\n" if $self->{'debug'};
    $node->runCmd("$cmd");
    print "DEBUG: done\n" if $self->{'debug'};
}

sub getInputSetSize {
    my ($self, $inputDir) = @_;

    return 1;
}

sub initSubTask {
    my ($self, $start, $end, $node, $inputDir, $subTaskDir, $nodeSlotDir) = @_;
    print "DEBUG: SimpleTask::initSubTask(start=$start, end=$end, node=$node, "
	. "inputDir=$inputDir, subTaskDir=$subTaskDir, nodeSlotDir=$nodeSlotDir)\n"
	if $self->{'debug'};

    my $cmd = "cp -r $subTaskDir/* $nodeSlotDir";
    print "DEBUG: SimpleTask::initSubTask: running command $cmd...\n" if $self->{'debug'};
    $node->runCmd("$cmd");
    print "DEBUG: done\n" if $self->{'debug'};
}

sub makeSubTaskCommand { 
    my ($self, $node, $inputDir, $nodeExecDir) = @_;

    my $cmd = $self->getProperty("cmd");
    my $nodeDir = $node->getDir();

    print "DEBUG: SimpleTask::runSubTask: command from prop is $cmd...\n" if $self->{'debug'};
    $cmd =~ s/\$nodeDir/$nodeDir/g; #substitute nodeDir
    $cmd =~ s/\\s/ /g; #substiture space
    print "DEBUG: SimpleTask::runSubTask: running subTask w\/ command $cmd...\n" if $self->{'debug'};
    return $cmd;
}

sub integrateSubTaskResults {
    my ($self, $subTaskNum, $node, $nodeExecDir, $mainResultDir) = @_;

    my $cmd = "cp -r $nodeExecDir/* $mainResultDir";
    print "DEBUG: SimpleTask::integrateSubTaskResults: running command $cmd...\n" if $self->{'debug'};
    $node->runCmd("$cmd");
    $cmd = "mv $mainResultDir/subtask.output $mainResultDir/task.out";
    &runCmd($cmd) if -f "$mainResultDir/subtask.output";
    print "DEBUG: done\n" if $self->{'debug'};
}
1;