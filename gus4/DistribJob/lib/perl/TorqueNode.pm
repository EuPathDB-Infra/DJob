package DJob::DistribJob::TorqueNode;

use DJob::DistribJob::Node ":states";
use Cwd;
use strict;

our @ISA = qw(DJob::DistribJob::Node);

sub queueNode {
  my $self = shift;
  if (!$self->getJobid()) {     ##need to run qsub 
    ##first create the script...
    my $runFile = $self->{fileName};
    if(!$runFile){
      $runFile = "nodeScript.$$";
    }elsif($runFile =~ /cancel/){
      $runFile =~ s/cancel/run/;
    }else{
      $runFile = "$runFile.run";
    }
    $self->{script} = $runFile;
    if(!-e "$runFile"){
      open(R,">$runFile") || die "unable to create script file '$runFile'\n";
      print R "#!/bin/sh\n\n$ENV{GUS_HOME}/bin/nodeSocketServer.pl $self->{serverHost} $self->{serverPort}\n";
      close R;
      system("chmod +x $runFile");
    }
    my $qsubcmd = "qsub -N DistribJob -V -j oe -l nodes=1:ppn=$self->{procsPerNode}".($self->{runTime} ? ",walltime=00:$self->{runTime}:00" : "").($self->{queue} ? " -q $self->{queue}" : "")." $runFile";
##    print STDERR "\n$qsubcmd\n\n";
    my $jid = `$qsubcmd`;
    chomp $jid;
    $self->{workingDir} = "/$self->{nodeWorkingDirsHome}/$jid";
    $self->setJobid($jid);
    if($self->{fileName}){
      open(C,">>$self->{fileName}");
      print C "$self->{jobid} ";
      close C;
    }
  }
 
  $self->setState($QUEUED);
}

sub getNodeAddress {
  my $self = shift;
  if (!defined $self->{nodeNum}) {
    my $getCmd = "qstat -n $self->{jobid}";
    my @stat = `$getCmd`;
    return undef if $?;         ##command failed
    if ($stat[-1] =~ /^\s*(\S+)/) {
      $self->{nodeNum} = $1;
    }
  }
  return $self->{nodeNum};
}

# remove this node's job from the queue
sub removeFromQueue {
  my $cmd = "qdel $self->{jobid} > /dev/null 2>&1";
  system($cmd) && print STDERR "Failed running command to delete job from queue.  '$cmd'";
}

sub getQueueState {
  my $self = shift;
  return 1 if $self->getState() == $FAILEDNODE || $self->getState() == $COMPLETE;  ##should not be in queue
  my $jobid = $self->getJobid();
  if(!$jobid){
    print STDERR "TorqueNode->getQueueState: unable to checkQueueStatus as can't retrieve JobID\n";
    return 0;
  }
  my $checkCmd = "qstat -n $jobid 2> /dev/null";
  my $res = `$checkCmd`;
  return $? >> 8 ? 0 : 1;  ##returns 0 if error running qstat with this jobid
}

sub deleteLogFilesAndTmpDir {
  my $self = shift;
  my $jobidfordel;
  if($self->{jobid} =~ /^(\d+)/){
    $jobidfordel = $1;
  }else{
    print "Unable to remove log files\n";
    return;
  }
  my $delFile = "DistribJob.o$jobidfordel";
#  print "Unlinking $delFile\n";
  unlink("delFile"); ## || print STDERR "Unable to unlink $delFile\n";
  my @outfiles = glob("DistribJob.*");
  if(scalar(@outfiles) == 0){
    ##remove the script file
    unlink("$self->{script}") || print STDERR "Unable to unlink $self->{script}\n";
  }
}

# static method
sub getQueueSubmitCommand {
  my ($class, $queue) = @_;

  return "qsub -V -cwd".$queue ? " -q $queue" : "";
}

# static method to extract Job Id from job submitted file text
# used to get job id for distribjob itself
sub getJobIdFromJobInfoString {
  my ($class, $jobInfoString) = @_;

  # Your job 1580354 ("script") has been submitted
  $jobInfoString =~ /Your job (\S+)/;
  return $1;
}

# static method to provide command to run to get status of a job
# used to get status of distribjob itself
sub getCheckStatusCmd {
  my ($class, $jobId) = @_;

  return "qstat -n $jobId";
}

# static method to provide command to run kill jobs
sub getKillJobCmd {
  my ($class, $jobIds) = @_;

  return "qdel $jobIds";
}

# static method to extract status from status file
# used to check status of distribjob itself
# return 1 if still running.
sub checkJobStatus {
  my ($class, $statusFileString, $jobId) = @_;

#5728531 0.50085 runLiniacJ i_wei        r     10/03/2014

  return $statusFileString =~ /$jobId\s+\S+\s+\S+\s+\S+\s+[r|h|w]/;
}

1;