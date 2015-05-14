package GATK;
use Moo::Role;
use IO::File;
use IO::Dir;

#-----------------------------------------------------------
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
    my $self = shift;
    my $itv  = $self->commandline->{interval_list};

    # create, print and store regions.
    my $REGION = IO::File->new( $itv, 'r' )
      or
      $self->ERROR('Interval file not found or not provided on command line.');

    my %regions;
    foreach my $reg (<$REGION>) {
        chomp $reg;
        my @chrs = split /:/, $reg;
        push @{ $regions{ $chrs[0] } }, $reg;
    }

    my @inv_file;
    foreach my $chr ( keys %regions ) {
        my $output_reg = $self->output . "chr$chr" . "_region_file.list";

        if ( -e $output_reg ) {
            push @inv_file, $output_reg;
            next;
        }
        else {
            my $LISTFILE = IO::File->new( $output_reg, 'w' ) if $self->execute;

            foreach my $list ( @{ $regions{$chr} } ) {
                print $LISTFILE "$list\n" if $self->execute;
            }
            push @inv_file, $output_reg;
        }
    }
    my @sort_inv = sort @inv_file;
    return \@sort_inv;
}

##-----------------------------------------------------------

sub _build_indels {
    my $self   = shift;
    my $knowns = $self->options->{known_indels};

    $self->ERROR('Issue building known indels from file') unless ($knowns);

    my $known_vcfs;
    foreach my $vcf ( @{$knowns} ) {
        chomp $vcf;
        next unless ( $vcf =~ /\.vcf$/ );
        $known_vcfs .= "--known $vcf ";
    }
    $self->indels($known_vcfs);
}

##-----------------------------------------------------------

sub _build_dbsnp {
    my $self   = shift;
    my $knowns = $self->options->{known_dbsnp};

    $self->ERROR('Issue building known dbsnp from file') unless ($knowns);

    my $known_vcfs = "--knownSites $knowns";
    $self->dbsnp($known_vcfs);
}

##-----------------------------------------------------------

sub RealignerTargetCreator {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('RealignerTargetCreator');

    my $single = $self->file_retrieve('bwa_mem');
    my $multi  = $self->file_retrieve('sambamba_merge');

    my $combined;
    ($multi) ? ( $combined = $multi ) : ( $combined = $single );

    # collect known files to transfer to cluster node
    my $kn = join( '* ', @{ $self->options->{known_indels} } );

    my @cmds;
    foreach my $in ( @{$combined} ) {
        my $parts = $self->file_frags($in);

        foreach my $region ( @{ $self->intervals } ) {

            my $reg_parts = $self->file_frags($region);
            my $output =
                $self->output
              . $parts->{parts}[0] . "_"
              . $reg_parts->{parts}[0]
              . '_realign.intervals';

            $self->file_store($output);

            my $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                  . "%s/GenomeAnalysisTK.jar -T RealignerTargetCreator "
                  . "-R %s -I %s --disable_auto_index_creation_and_locking_when_reading_rods "
                  . "--num_threads %s %s -L %s -o %s",
                $opts->{xmx},         $opts->{gc_threads},
                $config->{tmp},       $config->{GATK},
                $config->{fasta},     $in,
                $opts->{num_threads}, $self->indels,
                $region,              $output
            );
            push @cmds, [ $cmd, $in, $region, $kn ];
        }
    }

    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub IndelRealigner {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('IndelRealigner');

    my $single = $self->file_retrieve('bwa_mem');
    my $multi  = $self->file_retrieve('sambamba_merge');

    my $combined;
    if   ($multi) { $combined = $multi }
    else          { $combined = $single }

    my $target = $self->file_retrieve('RealignerTargetCreator');
    ( my $known = $self->indels ) =~ s/--known/-known/g;

    # collect known files to transfer to cluster node
    my $kn = join( '* ', @{ $self->options->{known_indels} } );

    my @cmds;
    foreach my $dep ( @{$combined} ) {
        my $dep_parts = $self->file_frags($dep);

        my @target_region = grep { /$dep_parts->{parts}[0]\_/ } @{$target};
        foreach my $region (@target_region) {

            my $reg_parts = $self->file_frags($region);
            my $sub       = "_realign_" . $reg_parts->{parts}[1] . ".bam";

            # get call region from interval file
            my @intv =
              grep { /$reg_parts->{parts}[1]\_/ } @{ $self->intervals };

            ( my $output = $dep ) =~ s/\.bam/$sub/;
            $self->file_store($output);

            my $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                  . "%s/GenomeAnalysisTK.jar -T IndelRealigner -R %s "
                  . "--disable_auto_index_creation_and_locking_when_reading_rods "
                  . "-I %s -L %s -targetIntervals %s %s -o %s",
                $opts->{xmx},    $opts->{gc_threads}, $config->{tmp},
                $config->{GATK}, $config->{fasta},    $dep,
                $intv[0],        $region,             $known,
                $output
            );
            push @cmds, [ $cmd, $dep, $region, $intv[0], $kn ];
        }
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub BaseRecalibrator {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('BaseRecalibrator');
    my $align  = $self->file_retrieve('IndelRealigner');

    my $known_indels = $self->indels;
    $known_indels =~ s/known/knownSites/g;

    # collect known files to transfer to cluster node
    my $kn = join( '* ',
        @{ $self->options->{known_indels} },
        $self->options->{known_dbsnp} );

    my @cmds;
    foreach my $aln ( @{$align} ) {
        my $file = $self->file_frags($aln);

        ( my $output = $file->{full} ) =~ s/\.bam/_recal_data.table/g;
        $self->file_store($output);

        my $cmd = sprintf(
            "java -jar -Xmx%sg -XX:ParallelGCThreads=%s "
              . "-Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar -T BaseRecalibrator -R %s -I %s "
              . "--num_cpu_threads_per_data_thread %s %s %s "
              . "--disable_auto_index_creation_and_locking_when_reading_rods -o %s",
            $opts->{xmx},                             $opts->{gc_threads},
            $config->{tmp},                           $config->{GATK},
            $config->{fasta},                         $aln,
            $opts->{num_cpu_threads_per_data_thread}, $self->dbsnp,
            $known_indels,                            $output
        );
        push @cmds, [ $cmd, $aln, $kn ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub PrintReads {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('PrintReads');
    my $table  = $self->file_retrieve('BaseRecalibrator');
    my $align  = $self->file_retrieve('IndelRealigner');

    my @cmds;
    foreach my $bam ( @{$align} ) {
        my $recal_t = shift @{$table};

        my $b_frag = $self->file_frags($bam);
        my $r_frag = $self->file_frags($recal_t);

        unless ( $b_frag->{parts}[0] eq $r_frag->{parts}[0] ) {
            $self->ERROR(
                'bam file and recal table not a match review commands');
        }

        ( my $output = $bam ) =~ s/\.bam/_recal.bam/g;
        $self->file_store($output);

        my $cmd = sprintf(
            "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
              . "%s/GenomeAnalysisTK.jar -T PrintReads -R %s -I %s "
              . "--num_cpu_threads_per_data_thread %s "
              . "--disable_auto_index_creation_and_locking_when_reading_rods "
              . "-BQSR %s -o %s",

            #. "--num_cpu_threads_per_data_thread %s -BQSR %s -o %s",
            $opts->{xmx},                             $opts->{gc_threads},
            $config->{tmp},                           $config->{GATK},
            $config->{fasta},                         $bam,
            $opts->{num_cpu_threads_per_data_thread}, $recal_t,
            $output
        );
        push @cmds, [ $cmd, $bam, $recal_t ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub HaplotypeCaller {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('HaplotypeCaller');

    # collect files and stack them.
    my $reads = $self->file_retrieve('PrintReads');
    my @inputs = map { "$_" } @{$reads};

    my @cmds;
    foreach my $bam ( @{$reads} ) {
        my $file = $self->file_frags($bam);

        if ( $self->file_from_command ) {
            my $search;
            foreach my $chr ( @{ $file->{parts} } ) {
                if ( $chr =~ /chr.*/ ) {
                    $search = $chr;
                }
            }

            # get interval
            my @intv = grep { /$search\_/ } @{ $self->intervals };

            foreach my $region (@intv) {

                #foreach my $region ( @{$intv} ) {
                my $name = $file->{parts}[0];
                ( my $output = $region ) =~
                  s/_file.list/_$name.raw.snps.indels.gvcf/;

                $self->file_store($output);

                my $cmd = sprintf(
                    "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                      . "%s/GenomeAnalysisTK.jar -T HaplotypeCaller -R %s "
                      . "--num_cpu_threads_per_data_thread %s "
                      . "--standard_min_confidence_threshold_for_calling %s "
                      . "--standard_min_confidence_threshold_for_emitting %s "
                      . "--emitRefConfidence %s "
                      . "--variant_index_type %s "
                      . "--variant_index_parameter %s "
                      . "--min_base_quality_score %s "
                      . "--disable_auto_index_creation_and_locking_when_reading_rods "
                      . "-I %s -L %s -o %s",
                    $opts->{xmx},
                    $opts->{gc_threads},
                    $config->{tmp},
                    $config->{GATK},
                    $config->{fasta},
                    $opts->{num_cpu_threads_per_data_thread},
                    $opts->{standard_min_confidence_threshold_for_calling},
                    $opts->{standard_min_confidence_threshold_for_emitting},
                    $opts->{emitRefConfidence},
                    $opts->{variant_index_type},
                    $opts->{variant_index_parameter},
                    $opts->{min_base_quality_score},
                    $bam,
                    $region,
                    $output
                );
                push @cmds, [ $cmd, $bam, $region ];
            }
        }
        else {
            my $search;
            foreach my $chr ( @{ $file->{parts} } ) {
                if ( $chr =~ /chr.*/ ) {
                    $search = $chr;
                }
            }

            # get interval
            my @intv = grep { /$search\_/ } @{ $self->intervals };

            my $name = $file->{parts}[0];
            ( my $output = $intv[0] ) =~
              s/_file.list/_$name.raw.snps.indels.gvcf/;

            $self->file_store($output);

            my $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                  . "%s/GenomeAnalysisTK.jar -T HaplotypeCaller -R %s "
                  . "--num_cpu_threads_per_data_thread %s "
                  . "--standard_min_confidence_threshold_for_calling %s "
                  . "--standard_min_confidence_threshold_for_emitting %s "
                  . "--emitRefConfidence %s "
                  . "--variant_index_type %s "
                  . "--variant_index_parameter %s "
                  . "--min_base_quality_score %s "
                  . "--disable_auto_index_creation_and_locking_when_reading_rods "
                  . "-I %s -L %s -o %s",
                $opts->{xmx},
                $opts->{gc_threads},
                $config->{tmp},
                $config->{GATK},
                $config->{fasta},
                $opts->{num_cpu_threads_per_data_thread},
                $opts->{standard_min_confidence_threshold_for_calling},
                $opts->{standard_min_confidence_threshold_for_emitting},
                $opts->{emitRefConfidence},
                $opts->{variant_index_type},
                $opts->{variant_index_parameter},
                $opts->{min_base_quality_score},
                $bam,
                $intv[0],
                $output
            );
            push @cmds, [ $cmd, $bam, $intv[0] ];
        }
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub CatVariants {
    my $self = shift;
    $self->pull;

    my $config = $self->options;

    my $gvcf = $self->file_retrieve('HaplotypeCaller');
    my @iso = grep { /\.gvcf$/ } @{$gvcf};

    my %indiv;
    my $path;
    foreach my $gvcf (@iso) {
        chomp $gvcf;

        my $frags = $self->file_frags($gvcf);

        # make a soft link so catvariants works (needs vcf)
        ( my $vcf = $gvcf ) =~ s/gvcf/vcf/;
        system("ln -s $gvcf $vcf") if ( $self->execute );

        # then make a working version and collect path
        ( my $file = $frags->{name} ) =~ s/gvcf/vcf/;
        $path = $frags->{path};

        my $key = $frags->{parts}[2];
        push @{ $indiv{$key} }, $file;
    }

    my @cmds;
    foreach my $samp ( keys %indiv ) {
        chomp $samp;

        # put the file in correct order.
        my @ordered_list;
        for ( 1 .. 22, 'X', 'Y', 'MT' ) {
            my $chr      = 'chr' . $_;
            my @value    = grep { /$chr\_/ } @{ $indiv{$samp} };
            my $fullPath = $path . $value[0];
            push @ordered_list, $fullPath;
        }

        my $variant = join( " -V ", @ordered_list );
        $variant =~ s/^/-V /;

        ( my $output = $samp ) =~ s/vcf/Cat.vcf/;
        my $pathFile = $path . $output;
        $self->file_store($pathFile);

        my $cmd = sprintf(
            "java -cp %s/GenomeAnalysisTK.jar org.broadinstitute.gatk.tools.CatVariants -R %s "
              . "--variant_index_type LINEAR  "
              . "--variant_index_parameter 128000 --assumeSorted  %s -out %s",
            $config->{GATK}, $config->{fasta}, $variant, $pathFile );
        push @cmds, [ $cmd, @ordered_list ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub CombineGVCF {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('CombineGVCF');

    my $gvcf = $self->file_retrieve('CatVariants');
    my @iso = grep { /\.vcf$/ } @{$gvcf};

    # only need to start combining if have a
    # large collection of gvcfs
    if ( scalar @iso < 200 ) { return }

    my $split = $self->commandline->{split_combine};

    my @cmds;
    if ( $self->commandline->{split_combine} ) {
        my @var;
        push @var, [ splice @iso, 0, $split ] while @iso;

        my $id;
        foreach my $split (@var) {
            my $variants = join( " --variant ", @$split );

            $id++;
            my $output =
              $self->output . $config->{ugp_id} . ".$id.mergeGvcf.vcf";
            $self->file_store($output);

            my $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s %s/GenomeAnalysisTK.jar "
                  . " -T CombineGVCFs -R %s "
                  . "--disable_auto_index_creation_and_locking_when_reading_rods "
                  . "--variant %s -o %s",
                $opts->{xmx}, $opts->{gc_threads}, $config->{GATK},
                $config->{fasta}, $variants, $output );

            push @cmds, [ $cmd, @{$split} ];
        }
    }
    else {
        my $variants = join( " --variant ", @iso );

        my $output = $self->output . $config->{ugp_id} . '_final_mergeGvcf.vcf';
        $self->file_store($output);

        my $cmd = sprintf(
            "java -jar -Xmx%sg -XX:ParallelGCThreads=%s %s/GenomeAnalysisTK.jar "
              . " -T CombineGVCFs -R %s "
              . "--disable_auto_index_creation_and_locking_when_reading_rods "
              . "--variant %s -o %s",
            $opts->{xmx}, $opts->{gc_threads}, $config->{GATK},
            $config->{fasta}, $variants, $output );

        push @cmds, [ $cmd, $variants ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

#sub CombineGVCF_Merge {
#    my $self = shift;
#    $self->pull;
#
#    my $config = $self->options;
#    my $opts   = $self->tool_options('CombineGVCF_Merge');
#
#    my $merged = $self->file_retrieve('CombineGVCF');
#    unless ($merged) { return }
#
#    my $variants = join( " --variant ", @{$merged} );
#
#    # Single merged files dont need a master merge
#    if ( $variants =~ /_final_mergeGvcf.vcf/ ) { return }
#
#    my $output = $self->output . $config->{ugp_id} . '_final_mergeGvcf.vcf';
#    $self->file_store($output);
#
#    my $cmd = sprintf(
#        "java -jar -Xmx%s -XX:ParallelGCThreads=%s %s/GenomeAnalysisTK.jar "
#          . " -T CombineGVCFs -R %s "
#          . "--disable_auto_index_creation_and_locking_when_reading_rods "
#          . "--variant %s -o %s",
#        $opts->{xmx}, $opts->{gc_threads}, $config->{GATK}, $config->{fasta},
#        $variants, $output );
#    $self->bundle( \$cmd );
#}

##-----------------------------------------------------------

sub GenotypeGVCF {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('GenotypeGVCF');

    my @gcated;
    my $data = $self->file_retrieve('CombineGVCF');
    if ($data) {
        @gcated = grep { /mergeGvcf/ } @{$data};
    }
    else {
        $data = $self->file_retrieve('CatVariants');
        @gcated = grep { /gCat.vcf$/ } @{$data};
    }

    # collect the 1k backgrounds.
    my (@backs);
    if ( $config->{backgrounds} ) {

        my $BK = IO::Dir->new( $config->{backgrounds} )
          or $self->ERROR('Could not find/open background directory');

        foreach my $back ( $BK->read ) {
            next unless ( $back =~ /mergeGvcf.vcf$/ );
            chomp $back;
            my $fullpath = $config->{backgrounds} . "/$back";
            push @backs, $fullpath;
        }
        $BK->close;
    }

    # the original backgrounds and the gvcf files
    my $back_variants = join( " --variant ", @backs );
    my $input         = join( " --variant ", @gcated );

    my $intv = $self->intervals;
    my @cmds;
    foreach my $region ( @{$intv} ) {
        ( my $output = $region ) =~ s/_file.list/_genotyped.vcf/;
        $self->file_store($output);

        my $cmd;
        if ($back_variants) {
            $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                  . "%s/GenomeAnalysisTK.jar -T GenotypeGVCFs -R %s "
                  . "--disable_auto_index_creation_and_locking_when_reading_rods --num_threads %s "
                  . "--variant %s --variant %s -L %s -o %s",
                $opts->{xmx},    $opts->{gc_threads}, $config->{tmp},
                $config->{GATK}, $config->{fasta},    $opts->{num_threads},
                $input,          $back_variants,      $region,
                $output
            );
        }
        else {
            $cmd = sprintf(
                "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s "
                  . "%s/GenomeAnalysisTK.jar -T GenotypeGVCFs -R %s "
                  . "--disable_auto_index_creation_and_locking_when_reading_rods "
                  . "--num_threads %s --variant %s -L %s -o %s",
                $opts->{xmx},    $opts->{gc_threads}, $config->{tmp},
                $config->{GATK}, $config->{fasta},    $opts->{num_threads},
                $input,          $region,             $output
            );
        }
        push @cmds, [ $cmd, @gcated, @backs ];
    }
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub CatVariants_Genotype {
    my $self = shift;
    $self->pull;

    my $config = $self->options;

    my $vcf = $self->file_retrieve('GenotypeGVCF');
    my @iso = grep { /genotyped.vcf$/ } @{$vcf};

    my %indiv;
    my $path;
    my @cmds;
    foreach my $file (@iso) {
        chomp $file;

        my $frags = $self->file_frags($file);
        $path = $frags->{path};

        my $key = $frags->{parts}[0];
        push @{ $indiv{$key} }, $file;
    }

    # put the file in correct order.
    my @ordered_list;
    for ( 1 .. 22, 'X', 'Y', 'MT' ) {
        my $chr = 'chr' . $_;
        push @ordered_list, $indiv{$chr}->[0];
    }

    my $variant = join( " -V ", @ordered_list );
    $variant =~ s/^/-V /;

    my $output = $self->output . $config->{ugp_id} . '_cat_genotyped.vcf';
    $self->file_store($output);

    my $cmd = sprintf(
        "java -cp %s/GenomeAnalysisTK.jar org.broadinstitute.gatk.tools.CatVariants -R %s "
          . "--assumeSorted  %s -out %s",
        $config->{GATK}, $config->{fasta}, $variant, $output );

    push @cmds, [ $cmd, @ordered_list ];
    $self->bundle( \@cmds );

    #$self->bundle(\$cmd);
}

##-----------------------------------------------------------

sub VariantRecalibrator_SNP {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('VariantRecalibrator_SNP');

    my $genotpd = $self->file_retrieve('CatVariants_Genotype');

    my $recalFile =
      '-recalFile ' . $self->output . $config->{ugp_id} . '_snp_recal';
    my $tranchFile =
      '-tranchesFile ' . $self->output . $config->{ugp_id} . '_snp_tranches';
    my $rscriptFile =
      '-rscriptFile ' . $self->output . $config->{ugp_id} . '_snp_plots.R';

    $self->file_store($recalFile);
    $self->file_store($tranchFile);

    my $resource = $config->{resource_SNP};
    my $anno     = $config->{use_annotation_SNP};

    my @cmds;
    my $cmd = sprintf(
        "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar "
          . " -T VariantRecalibrator -R %s --minNumBadVariants %s --num_threads %s "
          . "--disable_auto_index_creation_and_locking_when_reading_rods "
          . "-resource:%s -an %s -input %s %s %s %s -mode SNP",
        $opts->{xmx},     $opts->{gc_threads},
        $config->{tmp},   $config->{GATK},
        $config->{fasta}, $opts->{minNumBadVariants},
        $opts->{num_threads}, join( ' -resource:', @$resource ),
        join( ' -an ', @$anno ), @$genotpd,
        $recalFile, $tranchFile,
        $rscriptFile
    );
    push @cmds, [$cmd];
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub VariantRecalibrator_INDEL {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('VariantRecalibrator_INDEL');

    my $genotpd = $self->file_retrieve('CatVariants_Genotype');

    my $recalFile =
      '-recalFile ' . $self->output . $config->{ugp_id} . '_indel_recal';
    my $tranchFile =
      '-tranchesFile ' . $self->output . $config->{ugp_id} . '_indel_tranches';
    my $rscriptFile =
      '-rscriptFile ' . $self->output . $config->{ugp_id} . '_indel_plots.R';

    $self->file_store($recalFile);
    $self->file_store($tranchFile);

    my $resource = $config->{resource_INDEL};
    my $anno     = $config->{use_annotation_INDEL};

    my @cmds;
    my $cmd = sprintf(
        "java -jar -Xmx%sg -XX:ParallelGCThreads=%s -Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar -T VariantRecalibrator "
          . "--disable_auto_index_creation_and_locking_when_reading_rods "
          . "-R %s --minNumBadVariants %s --num_threads %s -resource:%s -an %s -input %s %s %s %s -mode INDEL",
        $opts->{xmx},     $opts->{gc_threads},
        $config->{tmp},   $config->{GATK},
        $config->{fasta}, $opts->{minNumBadVariants},
        $opts->{num_threads}, join( ' -resource:', @$resource ),
        join( ' -an ', @$anno ), @$genotpd,
        $recalFile, $tranchFile,
        $rscriptFile
    );
    push @cmds, [$cmd];
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub ApplyRecalibration_SNP {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('ApplyRecalibration_SNP');

    my $recal_files = $self->file_retrieve('VariantRecalibrator_SNP');
    my $get         = $self->file_retrieve('CatVariants_Genotype');
    my $genotpd     = shift @{$get};

    # need to add a copy because it here.
    ( my $output = $genotpd ) =~ s/_genotyped.vcf$/_recal_SNP.vcf/g;
    $self->file_store($output);

    my @cmds;
    my $cmd = sprintf(
        "java -jar -Xmx%sg -Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar -T ApplyRecalibration "
          . "--disable_auto_index_creation_and_locking_when_reading_rods "
          . "-R %s --ts_filter_level %s --num_threads %s --excludeFiltered -input %s %s %s -mode SNP -o %s",
        $opts->{xmx},             $config->{tmp},
        $config->{GATK},          $config->{fasta},
        $opts->{ts_filter_level}, $opts->{num_threads},
        $genotpd,                 shift @{$recal_files},
        shift @{$recal_files},    $output
    );
    push @cmds, [$cmd];
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub ApplyRecalibration_INDEL {
    my $self = shift;
    $self->pull;

    my $config      = $self->options;
    my $opts        = $self->tool_options('ApplyRecalibration_INDEL');
    my $recal_files = $self->file_retrieve('VariantRecalibrator_INDEL');
    my $get         = $self->file_retrieve('CatVariants_Genotype');
    my $genotpd     = shift @{$get};

    # need to add a copy because it here.
    ( my $output = $genotpd ) =~ s/_genotyped.vcf$/_recal_INDEL.vcf/g;
    $self->file_store($output);

    my @cmds;
    my $cmd = sprintf(
        "java -jar -Xmx%sg -Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar -T ApplyRecalibration "
          . "--disable_auto_index_creation_and_locking_when_reading_rods "
          . "-R %s --ts_filter_level %s --num_threads %s --excludeFiltered -input %s %s %s -mode INDEL -o %s",
        $opts->{xmx},             $config->{tmp},
        $config->{GATK},          $config->{fasta},
        $opts->{ts_filter_level}, $opts->{num_threads},
        $genotpd,                 shift @{$recal_files},
        shift @{$recal_files},    $output
    );
    push @cmds, [$cmd];
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

sub CombineVariants {
    my $self = shift;
    $self->pull;

    my $config = $self->options;
    my $opts   = $self->tool_options('CombineVariants');

    my $snp_files   = $self->file_retrieve('ApplyRecalibration_SNP');
    my $indel_files = $self->file_retrieve('ApplyRecalibration_INDEL');

    my @app_snp = map { "--variant $_ " } @{$snp_files};
    my @app_ind = map { "--variant $_ " } @{$indel_files};

    my $output =
      $config->{output} . $config->{ugp_id} . "_Final+Backgrounds.vcf";
    $self->file_store($output);

    my @cmds;
    my $cmd = sprintf(
        "java -jar -Xmx%sg -Djava.io.tmpdir=%s %s/GenomeAnalysisTK.jar -T CombineVariants -R %s "
          . "--disable_auto_index_creation_and_locking_when_reading_rods "
          . "--num_threads %s --genotypemergeoption %s %s %s -o %s",
        $opts->{xmx},         $config->{tmp},
        $config->{GATK},      $config->{fasta},
        $opts->{num_threads}, $opts->{genotypemergeoption},
        join( " ", @app_snp ), join( " ", @app_ind ),
        $output
    );
    push @cmds, [$cmd];
    $self->bundle( \@cmds );
}

##-----------------------------------------------------------

1;
