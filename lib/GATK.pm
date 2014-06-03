package GATK;
use Moo;
use IO::File;
use IO::Dir;
extends 'Roll';

##-----------------------------------------------------------
##---------------------- ATTRIBUTES -------------------------
##-----------------------------------------------------------

has indels => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_indels',
);

has dbsnp => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_dbsnp',
);

has 'intervals' => (
    is      => 'rw',
    lazy    => 1,
    builder => '_build_intervals',
);

##-----------------------------------------------------------
##------------------------ METHODS --------------------------
##-----------------------------------------------------------

sub _build_intervals {
    my $tape = shift;
    my $itv  = $tape->commandline->{interval_list};

    $tape->intervals($itv);
}

##-----------------------------------------------------------

sub _build_indels {
    my $tape   = shift;
    my $knowns = $tape->options->{known_indels};

    $tape->ERROR('Issue building known indels from file') unless ($knowns);

    my $known_vcfs;
    foreach my $vcf ( @{$knowns} ) {
        chomp $vcf;
        next unless ( $vcf =~ /\.vcf$/ );
        $known_vcfs .= "--known $vcf ";
    }
    $tape->indels($known_vcfs);
}

##-----------------------------------------------------------

sub _build_dbsnp {
    my $tape   = shift;
    my $knowns = $tape->options->{known_dbsnp};

    $tape->ERROR('Issue building known dbsnp from file') unless ($knowns);

    my $known_vcfs = "--knownSites $knowns";
    $tape->dbsnp($known_vcfs);
}

##-----------------------------------------------------------

sub GATK_RealignerTargetCreator {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $dedup  = $tape->file_retrieve('Picard_MarkDuplicates');
    my $output = $tape->output . $opts->{ugp_id} . '_realign.intervals';
    $tape->file_store($output);

    my $input;
    foreach my $in ( @{$dedup} ) {
        $input .= " -I $in ";
    }

    my $cmd = sprintf(
        "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T RealignerTargetCreator "
          . "-R %s %s %s %s -o %s\n",
        $opts->{java_xmx}, $opts->{tmp}, $opts->{GATK}, $opts->{fasta}, $input,
        $tape->ddash, $tape->indels, $output );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_IndelRealigner {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $dedup  = $tape->file_retrieve('Picard_MarkDuplicates');
    my $target = $tape->file_retrieve('GATK_RealignerTargetCreator');
    ( my $known = $tape->indels ) =~ s/--known/-known/g;

    my @cmds;
    foreach my $dep ( @{$dedup} ) {
        ( my $output = $dep ) =~ s/\.bam/_realign.bam/;

        $tape->file_store($output);

        my $cmd = sprintf(
            "java -jar -Xmx%s -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
              . "%s -T IndelRealigner -R %s -I %s -targetIntervals %s %s -o %s\n",
            $opts->{java_xmx}, $opts->{java_thread}, $opts->{tmp},
            $opts->{GATK},     $opts->{fasta},       $dep,
            join( '', @$target ), $known, $output
        );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------

sub GATK_BaseRecalibrator {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $align = $tape->file_retrieve('GATK_IndelRealigner');

    my @cmds;
    foreach my $aln ( @{$align} ) {
        my $file = $tape->file_frags($aln);

        ( my $output = $file->{full} ) =~ s/\.bam/_recal_data.table/g;
        $tape->file_store($output);

        my $cmd =
          sprintf( "java -jar -Xmx%s -Djava.io.tmpdir=%s %s "
              . "-T BaseRecalibrator -R %s -I %s %s %s -o %s\n",
            $opts->{java_xmx}, $opts->{tmp}, $opts->{GATK}, $opts->{fasta},
            $aln, $tape->ddash, $tape->dbsnp, $output );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------

sub GATK_PrintReads {
    my $tape = shift;
    $tape->pull;

    my $opts  = $tape->options;
    my $table = $tape->file_retrieve('GATK_BaseRecalibrator');
    my $align = $tape->file_retrieve('GATK_IndelRealigner');

    my @cmds;
    foreach my $bam ( @{$align} ) {
        my $recal_t = shift @{$table};

        my $b_frag = $tape->file_frags($bam);
        my $r_frag = $tape->file_frags($recal_t);

        unless ( $b_frag->{parts}[0] eq $r_frag->{parts}[0] ) {
            $tape->ERROR(
                'bam file and recal table not a match review commands');
        }

        ( my $output = $bam ) =~ s/\.bam/_recal.bam/g;
        $tape->file_store($output);

        my $cmd =
          sprintf( "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T PrintReads "
              . "-R %s -I %s %s -BQSR %s -o %s\n",
            $opts->{java_xmx}, $opts->{tmp}, $opts->{GATK}, $opts->{fasta},
            $bam, $tape->ddash, $recal_t, $output );
        push @cmds, $cmd;
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------

sub GATK_HaplotypeCaller {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    # collect files and stack them.
    my $reads = $tape->file_retrieve('GATK_PrintReads');
    my @inputs = map { "$_" } @{$reads};

    if ( $tape->intervals ) {
        # create, print and store regions.
        my $inv_file = $tape->intervals;
        my $REGION = IO::File->new( $inv_file, 'r' )
          or $tape->ERROR('Interval file could not be found or opened');

        my %regions;
        foreach my $reg (<$REGION>) {
            chomp $reg;
            my @chrs = split /:/, $reg;
            push @{ $regions{ $chrs[0] } }, $reg;
        }

        foreach my $chr ( keys %regions ) {
            my $output_reg = $tape->output . "chr$chr" . "_region_file.list";
            $tape->file_store($output_reg);

            my $INTERNAL = IO::File->new( $output_reg, 'w' ) if $tape->execute;

            foreach my $list ( @{ $regions{$chr} } ) {
                print $INTERNAL "$list\n" if $tape->execute;
            }
        }
    }

    # foreach bam file run it across the individual region files and store the output.
    my @cmds;
    my $regions = $tape->file_retrieve('GATK_HaplotypeCaller')
      if $tape->intervals;

    foreach my $bam ( @{$reads} ) {
        my $file = $tape->file_frags($bam);

        # calls can be split up base on intervals given
        if ( $tape->intervals ) {
            foreach my $list ( @{$regions} ) {
                next unless ( $list =~ /\.list/ );

                my $name = $file->{parts}[0];
                ( my $output = $list ) =~ s/_file.list/_$name.raw.snps.indels.gvcf/;
                $tape->file_store($output);

                my $cmd = sprintf(
			"java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T HaplotypeCaller "
                      . "-R %s %s -I %s -L %s -o %s\n",
                    $opts->{java_xmx}, $opts->{tmp}, $opts->{GATK},
                    $opts->{fasta}, $tape->ddash, $bam, $list, $output );
                push @cmds, $cmd;
            }
        }
        else {
            ( my $updated = $file->{name} ) =~ s/\.bam/\.raw.snps.indels.gvcf/;
    	    my $output = $tape->output . $updated; 
            $tape->file_store($output);

            my $cmd = sprintf(
                "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T HaplotypeCaller "
                . "-R %s %s -I %s -o %s\n",
                $opts->{java_xmx}, $opts->{tmp}, $opts->{GATK}, $opts->{fasta},
                $tape->ddash, $bam, $output );
            push @cmds, $cmd;
        }
    }
    $tape->bundle( \@cmds );
}

##-----------------------------------------------------------

sub GATK_CombineGVCF {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $gvcf = $tape->file_retrieve('GATK_HaplotypeCaller');
    my @iso = grep { /\.gvcf$/ } @{$gvcf};

    if ( $opts->{backgrounds} ) {

        my $BK = IO::Dir->new( $opts->{backgrounds} )
          or $tape->ERROR('Could not find/open background directory');

        # push 'em on!
        # http://open.spotify.com/track/2RnWnqnMqBuFosND1hbGjk
        foreach my $back ( $BK->read ) {
            next unless ( $back =~ /mergeGvcf.vcf$/ );
            chomp $back;
            my $fullpath = $opts->{backgrounds} . "/$back";
            push @iso, $fullpath;
        }
        $BK->close;
    }
    my $variants = join( " --variant ", @iso );

    my $output = $tape->output . $opts->{ugp_id} . '_mergeGvcf.vcf';
    $tape->file_store($output);

    my $cmd = sprintf(
        "java -jar -Xmx%s %s -T CombineGVCFs -R %s " . "--variant %s -o %s\n",
        $opts->{java_xmx}, $opts->{GATK}, $opts->{fasta}, $variants, $output );

    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_GenotypeGVCF {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    # will need to step through to get only gvcf
    my $combined = $tape->file_retrieve('GATK_CombineGVCF');
    my @merged = grep { /_mergeGvcf.vcf$/ } @{$combined};

    my $output   = $tape->output . $opts->{ugp_id} . "_genotyped.vcf";
    $tape->file_store($output);

    my $cmd =
      sprintf( "java -jar -Xmx%s %s -T GenotypeGVCFs -R %s "
          . "%s --variant %s -o %s\n",
        $opts->{java_xmx}, $opts->{GATK}, $opts->{fasta}, $tape->ddash,
        shift @merged, $output );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_VariantRecalibrator_SNP {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $genotpd = $tape->file_retrieve('GATK_GenotypeGVCF');

    my $recalFile =
      '-recalFile ' . $tape->output . $opts->{ugp_id} . '_snp_recal';
    my $tranchFile =
      '-tranchesFile ' . $tape->output . $opts->{ugp_id} . '_snp_tranches';
    my $rscriptFile =
      '-rscriptFile ' . $tape->output . $opts->{ugp_id} . '_snp_plots.R';

    $tape->file_store($recalFile);
    $tape->file_store($tranchFile);

    my $resource = $opts->{resource_SNP};
    my $anno     = $opts->{use_annotation_SNP};

    my $cmd = sprintf(
        "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T VariantRecalibrator "
          . "-R %s %s -resource:%s -an %s -input %s %s %s %s -mode SNP\n",
        $opts->{java_xmx}, $opts->{tmp},
        $opts->{GATK},     $opts->{fasta},
        $tape->ddash, join( ' -resource:', @$resource ),
        join( ' -an ', @$anno ), @$genotpd,
        $recalFile, $tranchFile,
        $rscriptFile
    );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_VariantRecalibrator_INDEL {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $genotpd = $tape->file_retrieve('GATK_GenotypeGVCF');

    my $recalFile =
      '-recalFile ' . $tape->output . $opts->{ugp_id} . '_indel_recal';
    my $tranchFile =
      '-tranchesFile ' . $tape->output . $opts->{ugp_id} . '_indel_tranches';
    my $rscriptFile =
      '-rscriptFile ' . $tape->output . $opts->{ugp_id} . '_indel_plots.R';

    $tape->file_store($recalFile);
    $tape->file_store($tranchFile);

    my $resource = $opts->{resource_INDEL};
    my $anno     = $opts->{use_annotation_INDEL};

    my $cmd = sprintf(
        "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T VariantRecalibrator "
          . "-R %s %s -resource:%s -an %s -input %s %s %s %s -mode INDEL\n",
        $opts->{java_xmx}, $opts->{tmp},
        $opts->{GATK},     $opts->{fasta},
        $tape->ddash, join( ' -resource:', @$resource ),
        join( ' -an ', @$anno ), @$genotpd,
        $recalFile, $tranchFile,
        $rscriptFile
    );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_ApplyRecalibration_SNP {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $recal_files = $tape->file_retrieve('GATK_VariantRecalibrator_SNP');
    my $get         = $tape->file_retrieve('GATK_GenotypeGVCF');
    my $genotpd     = shift @{$get};

    # need to add a copy because it here.
    ( my $output = $genotpd ) =~ s/_genotyped.vcf$/_recal_SNP.vcf/g;
    $tape->file_store($output);

    my $cmd = sprintf(
        "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T ApplyRecalibration "
          . "-R %s %s -input %s %s %s -mode SNP -o %s\n",
        $opts->{java_xmx},     $opts->{tmp},          $opts->{GATK},
        $opts->{fasta},        $tape->ddash,          $genotpd,
        shift @{$recal_files}, shift @{$recal_files}, $output
    );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_ApplyRecalibration_INDEL {
    my $tape = shift;
    $tape->pull;

    my $opts = $tape->options;

    my $recal_files = $tape->file_retrieve('GATK_VariantRecalibrator_INDEL');
    my $get         = $tape->file_retrieve('GATK_GenotypeGVCF');
    my $genotpd     = shift @{$get};

    # need to add a copy because it here.
    ( my $output = $genotpd ) =~ s/_genotyped.vcf$/_recal_INDEL.vcf/g;
    $tape->file_store($output);

    my $cmd = sprintf(
        "java -jar -Xmx%s -Djava.io.tmpdir=%s %s -T ApplyRecalibration "
          . "-R %s %s -input %s %s %s -mode INDEL -o %s\n",
        $opts->{java_xmx},     $opts->{tmp},          $opts->{GATK},
        $opts->{fasta},        $tape->ddash,          $genotpd,
        shift @{$recal_files}, shift @{$recal_files}, $output
    );
    $tape->bundle( \$cmd );
}

##-----------------------------------------------------------

sub GATK_SelectVariants {
	my $tape = shift;
	$tape->pull;

	my $opts = $tape->options;

	my $final_bams = $tape->file_retrieve('GATK_PrintReads');
	my $appy_snp   = $tape->file_retrieve('GATK_ApplyRecalibration_SNP');
	my $appy_indel = $tape->file_retrieve('GATK_ApplyRecalibration_INDEL');

	# get data from retrieve ref
	my $snp_file   = shift @{$appy_snp};
	my $indel_file = shift @{$appy_indel};

	my $sn;
	foreach my $bam ( @{$final_bams} ) {
		chomp $bam;
		next unless ($bam =~ /\.bam$/);
		my $frags = $tape->file_frags($bam);
		$sn .= " -sn " . $frags->{parts}[0];
	}
	
	# make some output files
	(my $output_snp   = $snp_file) =~ s/_recal_SNP.vcf/_cleaned_SNP.vcf/;
	(my $output_indel = $indel_file) =~ s/_recal_INDEL.vcf/_cleaned_INDEL.vcf/;

	# Keep the outputs
	$tape->file_store($output_snp);
	$tape->file_store($output_indel);

	# run commands for both snp and indels
	my @cmds;
	my $snp_cmd = sprintf(
		"java -jar -Djava.io.tmpdir=%s %s -T SelectVariants -R %s "
		."%s %s --variant %s -o %s\n",
		$opts->{tmp}, $opts->{GATK}, $opts->{fasta},
		$tape->ddash, $sn, $snp_file, $output_snp
	);

	my $indel_cmd = sprintf(
		"java -jar -Djava.io.tmpdir=%s %s -T SelectVariants -R %s "
		."%s %s --variant %s -o %s\n",
		$opts->{tmp}, $opts->{GATK}, $opts->{fasta},
		$tape->ddash, $sn, $indel_file, $output_indel
	);
	push @cmds, $snp_cmd, $indel_cmd;

	$tape->bundle(\@cmds);
}

##-----------------------------------------------------------

sub GATK_CombineVariants {
	my $tape = shift;
	$tape->pull;

	my $opts = $tape->options;

	my $select_files = $tape->file_retrieve('GATK_SelectVariants');
	my @variants = map { "--variant $_ " } @{$select_files};
	
	my $output = $opts->{output} . $opts->{ugp_id} . "_Final.vcf";

	my $cmd = sprintf(
		"java -jar -Djava.io.tmpdir=%s %s -T CombineVariants -R %s "
		."%s %s -o %s",
		$opts->{tmp}, $opts->{GATK}, $opts->{fasta}, $tape->ddash,
		join(" ", @variants), $output
	);
	$tape->bundle(\$cmd);
}

##-----------------------------------------------------------
1;