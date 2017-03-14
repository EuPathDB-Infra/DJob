#!@perl@

## parses varscan output to generate a gff file that can be loaded with InsertSNPs plugin

use strict;
use Getopt::Long;

my $file; 
my $strain;
my $output = 'snps.gff';
my $percentCutoff = 34;
my $pvalueCutoff = .01;
my $depthCutoffMult = 5;
my $minDepth = 3;
my $indelsFile = 'result.varscan.indels';

&GetOptions("file|f=s" => \$file, 
            "percentCutoff|pc=i"=> \$percentCutoff,
            "pvalueCutoff|pvc=s"=> \$pvalueCutoff,
            "depthCutoff|dc=i"=> \$depthCutoffMult,
            "minDepth|md=i"=> \$minDepth,
            "output|o=s"=> \$output,
            "strain|s=s"=> \$strain,
            "indelsFile|if=s"=> \$indelsFile,
            );

if (! -e $file || !$strain){
print <<endOfUsage;
parseVarscanToGFF.pl usage:

  parseVarscanToGFF.pl --file|f <varscan file> --strain <strain for snps> --percentCutoff|pc <frequency percent cutoff [34]> --pvalueCutoff|pvc <pvalue cutoff [0.01]> --depthCutoff|dc <multiplier times median for depth cutoff [3] NOTE: absolute cutoff set to 50 if median * multiplier < 50> --minDepth|md <minimum coverage before call SNP [3]>--output|o <outputFile [snps.gff]> --indelsFile|if <varscan output from pileup2indels [result.varscan.indels]>
endOfUsage
}

open(O,">$output");

my %iupac = ('A' => ['A'],
             'C' => ['C'],
             'G' => ['G'],
             'T' => ['T'],
             'R' => ['A','G'],
             'Y' => ['C','T'],
             'M' => ['A','C'],
             'K' => ['G','T'],
             'S' => ['C','G'],
             'W' => ['A','T'],
             'B' => ['C','G','T'],
             'D' => ['A','G','T'],
             'H' => ['A','C','T'],
             'V' => ['A','C','G'],
             'N' => ['A','C','G','T']
            );

##very first parse the indels file so can disregard calling snps inside deletions ... artifact of how varscan treats deletions
my %dels;
if(-e "$indelsFile"){
  print STDERR "Parsing indels file .. ";
  open(F,"$indelsFile") || die "unable to open indels file '$indelsFile'\n";
  my $ctIndels = 0;
  my $ctIndBases = 0;
  while(<F>){
    next if /^Chrom\s+Position/;
    my @t = split("\t",$_);
    chop $t[6];
    if($t[5] / ($t[4] + $t[5]) > 0.5 && $t[6] > 20){
      my $len = length($1);
      if($t[3] =~ /\*\/-(\w+)/){  #3this one is a deletion
        my $len = length($1);
        $ctIndels++;
        for(my $a = $t[1]+1;$a < $t[1]+1 + $len;$a++){
          $ctIndBases++;
          $dels{$t[0]}->{$a} = 1;
        }
      }
    }
  }
  close F;
  print STDERR "$ctIndels indels ($ctIndBases bases) identified\n";
}else{
  print STDERR "  NOTE: generating SNPs without regard to indels as indels file ($indelsFile) not found\n";
}

##first determine the depthCutoff
open(F, "$file") || die "unable to open file $file\n";
my @covArr;
while(<F>){
  next if /^Chrom\s+Position/;
  chomp;
  my @tmp = split("\t",$_);
  ##don't want to include positons where reference is N
  next if $tmp[2] =~ /N/i;
  push(@covArr,$tmp[4] + $tmp[5]);

}
close F;

##determine median..
my @sorted = sort{$a <=> $b}@covArr;
my $median = $sorted[int(scalar(@sorted) / 2)];
my $depthCutoff = int($median * $depthCutoffMult);
##should we make some minimum here .. perhaps 50?
$depthCutoff = 50 if $depthCutoff < 50;
print STDERR "Maximum depth cutoff for considering SNPs = $depthCutoff\n";
##what is the distribution of coverage?
print STDERR "Depth coverage distribution by percentile\n";
my $numSlices = 100;
my $s = 100 / $numSlices;
my $mult = int(scalar(@sorted) / $numSlices);
for(my$a=0;$a<$numSlices;$a++){
  print STDERR ($s*$a),": $sorted[$a*$mult]\n";
}
print STDERR "last: $sorted[-1]\n";

open(F, "$file") || die "unable to open file $file\n";
my @tmpLines;
while(<F>){
  next if /^Chrom\s+Position/;
  chomp;
  my @tmp = split("\t",$_);
  ##don't want to include positons where reference is N
  next if $tmp[2] =~ /N/i;
  ##don't want to examine positions that are in indels
  next if $dels{$tmp[0]}->{$tmp[1]};
  my $line = \@tmp;
  if(scalar(@tmpLines) > 0 && $tmpLines[-1]->[1] == $line->[1] && $tmpLines[-1]->[0] eq $line->[0]){  ##same position
    push(@tmpLines,$line);
  }else{
    &process(\@tmpLines) if scalar(@tmpLines) > 0;
    undef @tmpLines;
    push(@tmpLines,$line);
  }
}
&process(\@tmpLines) if scalar(@tmpLines) > 0;

close F;
close O;

#process this one and print to O 
sub process {
  my($lines) = @_;
    
  my $cov =  &getCoverage($lines);
  return if $cov > $depthCutoff || $cov < $minDepth;  ## exceeds depthCutoff

  ##want to reprint with percent properly computed if multiple lines
#  if(scalar(@{$lines}) > 1){
#    foreach my $l (@{$lines}){
#      $l->[6] = int($l->[5] / $cov * 1000) / 10;
#      print join("\t",@{$l})."\n";
#    }
#    print "-------------------\n";
#  }
  ## now process ... 
  my $f = $lines->[0];  ##process the first one ....
  my @alleles = &getAlleles($lines,$cov);
  return unless scalar(@alleles) >= 1;
  my $id = "NGS_SNP.$f->[0].$f->[1]";
  print O "$f->[0]\tNGS_SNP\tSNP\t$f->[1]\t$f->[1]\t.\t+\t.\tID $id; Allele \"".join("\" \"",@alleles)."\";\n";
}

sub getAlleles {
  my($lines,$cov) = @_;
  my $minPvalue = &getMinPvalue($lines);
  my @alleles;
  ##make a reference entry if > $depthCutoff ... how can we determine p value .. don't really have one!
  ## could use the minimum pvalue ...
  ## NOTE:  only want to include a reference allele if there is another SNP at this location and the reference percentCoverage is > cutoff
  my $needRef = 1;
  foreach my $l (@{$lines}){
    if($l->[5] / $cov * 100 >= $percentCutoff && $l->[11] <= $pvalueCutoff){
      push(@alleles,"$strain:".&getAllele($l).":$cov:".(int($l->[5] / $cov * 1000) / 10).":$l->[10]:$l->[11]");
      if($needRef && $l->[4] / $cov * 100 >= $percentCutoff && $l->[11] <= $pvalueCutoff){
        push(@alleles,"$strain:$l->[2]:$cov:".(int($l->[4] / $cov * 1000) / 10).":$l->[9]:$minPvalue");
        $needRef = 0;
      }
    }
  }
  return @alleles;
}

##note that am summing coverage at each position for each base.
sub getCoverage {
  my($lines) = @_;
  my $cov = $lines->[0]->[4] + $lines->[0]->[5];
  for(my $a = 1;$a < scalar(@{$lines}); $a++){
    $cov += $lines->[$a]->[5];
  }
  return $cov;
}

sub printGFF {
  my($l,$cov,$type,$pvalue) = @_;
#  print STDERR "printGFF('line',$cov,$type,$pvalue)\n";
  my $allele = $type eq 'reference' ? $l->[2] : &getAllele($l);
  my $perc = $type eq 'reference' ? int($l->[4] / $cov * 1000) / 10 : int($l->[5] / $cov * 1000) / 10;
  my $id = "NGS_SNP.".$l->[0] .".".$l->[1];
  print O "$l->[0]\t$type\tSNP\t$l->[1]\t$l->[1]\t.\t.\t.\tID $id; Allele \"$strain:$allele:$cov:$perc:$pvalue:".($type eq 'reference' ? $l->[9] : $l->[10])."\"\n";
}

sub getAllele {
  my($l) = @_;
#  die "ERROR: consensus symbol '$l->[3]' has > 2 possibilities (".join(",",@{$iupac{$l->[3]}}).")" if scalar(@{$iupac{$l->[3]}}) > 2;
  foreach my $n (@{$iupac{$l->[3]}}){
    return $n if $n ne $l->[2];
  }
  return 'undefined';
}

sub getMinPvalue {
  my($lines) = @_;
  my $p = 1;
  foreach my $l (@{$lines}){
    $p = $l->[11] if $l->[11] < $p;
  }
  return $p;
}
