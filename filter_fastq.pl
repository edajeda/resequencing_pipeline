#!/usr/bin/perl
# (c) 2010 Magnus Bjursell

# standard module usage
use strict;
use Getopt::Long;
use Pod::Usage;
use Cwd 'abs_path';
use FindBin;

# custom module usage
use lib $FindBin::Bin;
use mySharedFunctions qw(:basic);

my $dataHR = {};
my $infoHR = {};

$infoHR->{'configHR'} = readConfigFile();
$infoHR->{'optHR'}    = {};

my $debug  = 0;


# Read input and setup global variables
GetOptions ($infoHR->{'optHR'}, 'fq1=s', 'fq2=s', 'fqS=s', 'outdir=s', 'prefix=s',  'suffix=s','help', 'verbose') or pod2usage(2);
pod2usage(1) if $infoHR->{'optHR'}{'h'} or $infoHR->{'optHR'}{'help'};

unless ( -f $infoHR->{'optHR'}{'fq1'} or -f $infoHR->{'optHR'}{'fq2'} or -f $infoHR->{'optHR'}{'fqS'} ) { pod2usage("Error: At lease one sequence data file must be submitted.") }
if ( -f $infoHR->{'optHR'}{'fq1'} xor -f $infoHR->{'optHR'}{'fq2'} ) { pod2usage("Error: Both fq1 and fq2 must be present and match for paired end data.") }
if ( -f $infoHR->{'optHR'}{'fqS'} ) { pod2usage("Error: Single end read processing not implremented yet.") }

unless ( -d $infoHR->{'optHR'}{'outdir'} ) { pod2usage("Error: An existing output directory must be provided.") }
unless ( $infoHR->{'optHR'}{'prefix'} ) { pod2usage("Error: Please provide a prefix name.") }
$infoHR->{'optHR'}{'suffix'} = "filtered" unless $infoHR->{'optHR'}{'suffix'};


### ============= check options ===============###

my $minTrmRdLen = 40;
my $maxNoN      = 4;
my $maxNoQ10low = 5;
my $maxNoQ20low = 10;


### =========== main program start ============###

{
  local $| = 1;
  print STDERR "Starting analysis...\n";

  processInParameters($infoHR);
  $infoHR->{'optHR'}{'outdir_results'} = createDirs("$infoHR->{'optHR'}{'outdir'}/results");

  my $inFhHR = {}; my $outFhHR = {};
  {
    $inFhHR->{'1'}  = myOpen($infoHR->{'optHR'}{'fq1'});
    my $outFn = "$infoHR->{'optHR'}{'outdir'}/" . join(".", $infoHR->{'optHR'}{'prefix'}, "1", $infoHR->{'optHR'}{'suffix'}, "fastq");
    $outFhHR->{'1'} = myOpenRW($outFn);
    printf STDERR ("Input dir 1: %s\n   - Output name: %s; Direction: %s;\n\n", $infoHR->{'optHR'}{'fq1'}, $outFn, "1");
  }

  {
    $inFhHR->{'2'}  = myOpen($infoHR->{'optHR'}{'fq2'});
    my $outFn = "$infoHR->{'optHR'}{'outdir'}/" . join(".", $infoHR->{'optHR'}{'prefix'}, "2", $infoHR->{'optHR'}{'suffix'}, "fastq");
    $outFhHR->{'2'} = myOpenRW($outFn);
    printf STDERR ("Input dir 2: %s\n   - Output name: %s; Direction: %s;\n\n", $infoHR->{'optHR'}{'fq2'}, $outFn, "2");
  }

  {
    my $outFn = "$infoHR->{'optHR'}{'outdir'}/" . join(".", $infoHR->{'optHR'}{'prefix'}, "S", $infoHR->{'optHR'}{'suffix'}, "fastq");
    $outFhHR->{'S'} = myOpenRW($outFn);
    printf STDERR ("Single end output:\n   - Output name: %s; Direction: %s;\n\n", $outFn, "S");
  }

  while ( not eof($inFhHR->{'1'}) and not eof($inFhHR->{'2'}) ) {
    my $readsHR = {};

    print STDERR "." if $. % 100000 <= 3;
    $readsHR->{'1'} = readOneSeqEntery($inFhHR->{'1'});
    $readsHR->{'2'} = readOneSeqEntery($inFhHR->{'2'});

#next if $. < 100000;
#last if $. > 400000;

    die "Error: Fastq file read pairs not matching\n" unless $readsHR->{'1'}{'nameNoDir'} eq $readsHR->{'2'}{'nameNoDir'};
    die "Error: Cannot read fastq sequence ($readsHR->{'1'}{'name'}), file $infoHR->{'optHR'}{'fq1'} probably corrupted\n" unless $readsHR->{'1'}{'name'} and $readsHR->{'1'}{'seq'} and $readsHR->{'1'}{'qual'};
    die "Error: Cannot read fastq sequence ($readsHR->{'2'}{'name'}), file $infoHR->{'optHR'}{'fq2'} probably corrupted\n" unless $readsHR->{'2'}{'name'} and $readsHR->{'2'}{'seq'} and $readsHR->{'2'}{'qual'};

    analyseOneSequence($readsHR->{'1'}, $infoHR);
    analyseOneSequence($readsHR->{'2'}, $infoHR);

    if ( $readsHR->{'1'}{'pass'} and $readsHR->{'2'}{'pass'} ) {
      my $seqDir = 1; my $outDir = 1;
      printf {$outFhHR->{$outDir}} ("%s\n%s\n+\n%s\n", @{$readsHR->{$seqDir}}{'name', 'seq', 'qual'});
      $infoHR->{'no_reads'}{'passedDir'}{$outDir}++; $infoHR->{'no_reads'}{'passedDir'}{'total'}++;
      $infoHR->{'no_bases'}{'passedDir'}{$outDir} += $readsHR->{$seqDir}{'len'}; $infoHR->{'no_bases'}{'passedDir'}{'total'} += $readsHR->{$seqDir}{'len'};

      my $seqDir = 2; my $outDir = 2;
      printf {$outFhHR->{$outDir}} ("%s\n%s\n+\n%s\n", @{$readsHR->{$seqDir}}{'name', 'seq', 'qual'});
      $infoHR->{'no_reads'}{'passedDir'}{$outDir}++; $infoHR->{'no_reads'}{'passedDir'}{'total'}++;
      $infoHR->{'no_bases'}{'passedDir'}{$outDir} += $readsHR->{$seqDir}{'len'}; $infoHR->{'no_bases'}{'passedDir'}{'total'} += $readsHR->{$seqDir}{'len'};

    } elsif ( $readsHR->{'1'}{'pass'} ) {
      my $seqDir = 1; my $outDir = "S";
      printf {$outFhHR->{$outDir}} ("%s\n%s\n+\n%s\n", @{$readsHR->{$seqDir}}{'name', 'seq', 'qual'});
      $infoHR->{'no_reads'}{'passedDir'}{$outDir}++; $infoHR->{'no_reads'}{'passedDir'}{'total'}++;
      $infoHR->{'no_bases'}{'passedDir'}{$outDir} += $readsHR->{$seqDir}{'len'}; $infoHR->{'no_bases'}{'passedDir'}{'total'} += $readsHR->{$seqDir}{'len'};

    } elsif ( $readsHR->{'2'}{'pass'} ) {
      my $seqDir = 2; my $outDir = "S";
      printf {$outFhHR->{$outDir}} ("%s\n%s\n+\n%s\n", @{$readsHR->{$seqDir}}{'name', 'seq', 'qual'});
      $infoHR->{'no_reads'}{'passedDir'}{$outDir}++; $infoHR->{'no_reads'}{'passedDir'}{'total'}++;
      $infoHR->{'no_bases'}{'passedDir'}{$outDir} += $readsHR->{$seqDir}{'len'}; $infoHR->{'no_bases'}{'passedDir'}{'total'} += $readsHR->{$seqDir}{'len'};

    }
    undef($readsHR);
  }

  foreach my $fh ( keys %{$outFhHR} ) { close($outFhHR->{$fh}); }
  foreach my $fh ( keys %{$inFhHR} )  { close($inFhHR->{$fh}); }
  print STDERR "\nAll done\n\n";
}


{ # Print information

  my $prtFH = myOpenRW("$infoHR->{'optHR'}{'outdir_results'}/" . join(".", $infoHR->{'optHR'}{'prefix'}, $infoHR->{'optHR'}{'suffix'}, 'summary', 'txt'));

  die "\nNo input reads\n\n" unless $infoHR->{'no_reads'}{'total'};

  print $prtFH "Settings\n";
  print $prtFH "Min trimmed read length\t$minTrmRdLen\n";
  print $prtFH "Max number of N\t$maxNoN\n";
  print $prtFH "Max number of < Q10 bases\t$maxNoQ10low\n";
  print $prtFH "Max number of < Q20 bases\t$maxNoQ20low\n";
  print $prtFH "\n";

  print $prtFH "Summary\n";
  print $prtFH "Total number of reads\t$infoHR->{'no_reads'}{'total'}\n";
  print $prtFH "\n";

  printf $prtFH ("Number of reads skipped because trimmed read length < %d bases\t%d\t%0.2f%%\n", $minTrmRdLen, $infoHR->{'no_reads'}{'too_short_trm_rd'}, 100 * $infoHR->{'no_reads'}{'too_short_trm_rd'} / $infoHR->{'no_reads'}{'total'});
  printf $prtFH ("Number of reads skipped because of > %d 'N'\t%d\t%0.2f%%\n", $maxNoN,  $infoHR->{'no_reads'}{'too_many_N'}, 100 * $infoHR->{'no_reads'}{'too_many_N'} / $infoHR->{'no_reads'}{'total'});
  printf $prtFH ("Number of reads skipped because of > %d bases under q10\t%d\t%0.2f%%\n", $maxNoQ10low, $infoHR->{'no_reads'}{'too_many_under10'}, 100 * $infoHR->{'no_reads'}{'too_many_under10'} / $infoHR->{'no_reads'}{'total'});
  printf $prtFH ("Number of reads skipped because of > %d bases under q20\t%d\t%0.2f%%\n", $maxNoQ20low, $infoHR->{'no_reads'}{'too_many_under20'}, 100 * $infoHR->{'no_reads'}{'too_many_under20'} / $infoHR->{'no_reads'}{'total'});
  print $prtFH "\n\n";

  die "\nNo passed reads\n\n" unless $infoHR->{'no_reads'}{'passedDir'}{'total'};

  print $prtFH "Number of reads and bases passed (S: single)\n";
  print $prtFH "Dir\tReads\t% of passed reads\t% of total reads\tBases\t% of passed bases\t% of total bases\n";
  foreach my $outDir ( sort { ( $a =~ /total/ ? "zzz" : $a ) cmp ( $b =~ /total/ ? "zzz" : $b ) } keys %{$infoHR->{'no_reads'}{'passedDir'}} ) {
    printf $prtFH ("%s\t%d\t%0.2f%%\t%0.2f%%\t%d\t%0.2f%%\t%0.2f%%\n", $outDir, $infoHR->{'no_reads'}{'passedDir'}{$outDir}, 100 * $infoHR->{'no_reads'}{'passedDir'}{$outDir} / $infoHR->{'no_reads'}{'passedDir'}{'total'},
                   100 * $infoHR->{'no_reads'}{'passedDir'}{$outDir} / $infoHR->{'no_reads'}{'total'}, $infoHR->{'no_bases'}{'passedDir'}{$outDir}, 100 * $infoHR->{'no_bases'}{'passedDir'}{$outDir} / $infoHR->{'no_bases'}{'passedDir'}{'total'},
                   100 * $infoHR->{'no_bases'}{'passedDir'}{$outDir} / $infoHR->{'no_bases'}{'total'});
  }
  print $prtFH "\n\n";

  print $prtFH "Read length histogram\n";
  for my $len ( 0 .. scalar(@{$infoHR->{'length_histogram'}}) - 1 ) {
    printf $prtFH ("\t%d\t%d\t%0.2f%%\n", $len, $infoHR->{'length_histogram'}[$len], 100 * $infoHR->{'length_histogram'}[$len] / $infoHR->{'no_reads'}{'passedDir'}{'total'}) if $infoHR->{'length_histogram'}[$len];
  }
  print $prtFH "\n\n";

  my $smooth = 4;
  foreach my $GCpct ( sort { $a <=> $b } keys %{$infoHR->{'gc_pct_histogram'}} ) { $infoHR->{'gc_pct_histogram_avg'}{$smooth * int( ($GCpct < 100 ? $GCpct : 99.99999) / $smooth)} += $infoHR->{'gc_pct_histogram'}{$GCpct}; }
  print $prtFH "Percent GC histogram\n";
  print $prtFH "Percent GC\tRead count\tPercent of all reads\n";
  foreach my $GCpct ( sort { $a <=> $b } keys %{$infoHR->{'gc_pct_histogram_avg'}} ) {
    printf $prtFH ("%0.2f\t%d\t%0.2f%%\n", $GCpct + ($smooth / 2), $infoHR->{'gc_pct_histogram_avg'}{$GCpct}, (100 * $infoHR->{'gc_pct_histogram_avg'}{$GCpct} / $infoHR->{'no_reads'}{'passedDir'}{'total'}) );
  }
  print $prtFH "\n\n";

  print $prtFH "Positionbased data\n";
  print $prtFH "\tposition\tavg quality\tno 'N'\tpct 'N'\tTotal bases\n";
  for my $pos ( 1 .. scalar(@{$infoHR->{'total_bases_positionbased'}}) - 1 ) {
    printf $prtFH ("\t%d\t%0.2f\t%d\t%0.2f%%\t%d\n", $pos, $infoHR->{'total_base_quality_positionbased'}[$pos] / $infoHR->{'total_bases_positionbased'}[$pos], $infoHR->{'no_N_positionbased'}[$pos],
                   100 * $infoHR->{'no_N_positionbased'}[$pos] / $infoHR->{'total_bases_positionbased'}[$pos], $infoHR->{'total_bases_positionbased'}[$pos]);
  }
  print $prtFH "\n\n";

  close($prtFH);
}

exit;


# SUBS

sub readOneSeqEntery {
  my $inFH = shift;
  my $readHR = {};

# Read name
  do { $readHR->{'name'} = <$inFH>; chomp($readHR->{'name'}); } until ( $readHR->{'name'} =~ /^\@/ or eof($inFH) );
  return undef if length($readHR->{'name'}) == 0;
  ($readHR->{'nameNoDir'}) = ($readHR->{'name'} =~ /([^\/]+\/)/);
# Read seq
  $readHR->{'seq'}  = <$inFH>; chomp($readHR->{'seq'});
# Check second name
  my $line = <$inFH>; chomp($line);
  die "Fastq file error: expected '+'\n" unless $line =~ /^\+/;
# Read qual
  $readHR->{'qual'} = <$inFH>; chomp($readHR->{'qual'});
  return $readHR;
}

sub analyseOneSequence {
  my $readHR = shift;
  my $infoHR = shift;

  $infoHR->{'no_reads'}{'total'}++;
  $infoHR->{'no_bases'}{'total'} += length($readHR->{'seq'});

  if ( $readHR->{'qual'} =~ /(B+)$/ ) { my $noBs = length($1); $readHR->{'seq'} = substr($readHR->{'seq'}, 0, -1 * $noBs); $readHR->{'qual'} = substr($readHR->{'qual'}, 0, -1 * $noBs); }
  $readHR->{'len'} = length($readHR->{'seq'});
  $infoHR->{'no_reads'}{'too_short_trm_rd'}++, return undef() unless $readHR->{'len'} >= $minTrmRdLen;

  my $noN = $readHR->{'seq'} =~ tr/nN//; my $noQ10low = $readHR->{'qual'} =~ tr/\@A-I//; my $noQ20low = $readHR->{'qual'} =~ tr/\@A-S//;
  $infoHR->{'no_reads'}{'too_many_N'}++, return undef() if $noN > $maxNoN;
  $infoHR->{'no_reads'}{'too_many_under10'}++, return undef() if $noQ10low > $maxNoQ10low;
  $infoHR->{'no_reads'}{'too_many_under20'}++, return undef() if $noQ20low > $maxNoQ20low;

  warn "\nNumber of bases ($readHR->{'len'}) != number of quality values (" . length($readHR->{'qual'}) . ") for $readHR->{'name'}" unless $readHR->{'len'} == length($readHR->{'qual'});
  $infoHR->{'length_histogram'}[$readHR->{'len'}]++;
  $infoHR->{'gc_pct_histogram'}{round(100 * ( $readHR->{'seq'} =~ tr/[GCgc]// ) / $readHR->{'len'}, 1)}++;

  while ( $readHR->{'seq'} =~ /[Nn]/g ) { $infoHR->{'no_N_positionbased'}[pos($readHR->{'seq'})]++; }
  while ( $readHR->{'qual'} =~ /(.)/g ) { $infoHR->{'total_base_quality_positionbased'}[pos($readHR->{'qual'})] += ord($1) - 64; $infoHR->{'total_bases_positionbased'}[pos($readHR->{'qual'})]++; }

  $readHR->{'pass'} = 1;
  return 1;
}

sub processInParameters {
  my @okSuffix = qw(fastq fq); my $matchStr = join("|", @okSuffix);
  for my $p ( 'fq1', 'fq2', 'fqS', 'outdir' ) {
    next unless -e $infoHR->{'optHR'}{$p};
    $infoHR->{'optHR'}{$p} = abs_path($infoHR->{'optHR'}{$p});
    if ( $p =~ /^fq\w$/ ) {
      if ( $infoHR->{'optHR'}{$p} =~ /(([^\/]+)\.($matchStr))$/ ) {
        $infoHR->{'optHR'}{$p . "n"} = $1;
        $infoHR->{'optHR'}{$p . "b"} = $2;
      } else {
        pod2usage("Error: Input sequence files must be fastq and end with " . join(" or ", @okSuffix) . ".")
      }
    }
  }
}



#__END__


=head1 NAME

filter_fastq.pl - Filter fastq sequence files

=head1 SYNOPSIS

filter_fastq.pl [options]

  Options:
   --help            Brief help message
   --verbose         Write some additional output
   --outdir          Output directory [required]
   --prefix          Prefix [required]
   --suffix          Suffix (default: filtered)
   --fq1             PE fastq file, direction 1
   --fq2             PE fastq file, direction 2
   --fqS             SE fastq file

Output files will be named: prefix.dir.suffix.fastq. At least one fastq file is required. If paired end (PE) data is used, both fq1 and fq2 are required and must match internally.

=cut

#=head1 OPTIONS

#=over 8

#=item B<-help>

#Print a brief help message and exits.

#=back

#=head1 DESCRIPTION







