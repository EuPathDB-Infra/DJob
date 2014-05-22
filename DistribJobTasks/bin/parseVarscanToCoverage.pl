#!/usr/bin/perl

use strict;
use Getopt::Long;
use lib "$ENV{GUS_HOME}/lib/perl";

my $file; 
my $out;
my $percentCutoff = 60;

&GetOptions("file|f=s" => \$file, 
            "percentCutoff|pc=i"=> \$percentCutoff,
            "outputFile|o=s"=> \$out,
            );

if (! -e $file || !$out){
die &getUsage();
}

if($file =~ /\.gz$/) {
  open(F, "zcat $file|") || die "unable to open file $file for reading: $!";
}
else {
  open(F, "$file") || die "unable to open file $file for reading: $!";
}

open(O,">$out") or die "Cannot open file for writing: $!";


my ($spanStart, $prevSeq, $prevLoc);
while(<F>){
  next if /^Chrom\s+Position/;
  chomp;

  my @a = split(/\t/, $_);

  chop $a[6]; # chop off the % sign
  my $varPercent = 100 - $a[6];
  my $hasCoverage = $a[2] eq $a[3] && $varPercent >= $percentCutoff;

  my $isSameSequence = $prevSeq ? $prevSeq eq $a[0]  : 1;

  # start span 
  if(!$spanStart && $hasCoverage) {
    $spanStart = $a[1];
  }
  # end span
  elsif($spanStart && (!$isSameSequence || !$hasCoverage)) {
    print O "$a[0]\t$spanStart\t$prevLoc\n";
    $spanStart = undef;
  }
  else { }

  $prevSeq = $a[0];
  $prevLoc = $a[1];
}

if($spanStart) {
  print O "$prevSeq\t$spanStart\t$prevLoc\n";
}

close F;
close O;

sub getUsage {
return <<endOfUsage;
parseVarscanToCoverage.pl usage:

  parseVarscanToCoverage.pl --file|f <varscan file> --percentCutoff|pc <frequency percent cutoff [60]> --outputFile|o <output File for coverage> 
endOfUsage
}
