
<strong>cApTUrE - vAriant collecTing UGP pipeline</strong>

<strong>VERSION</strong>

This document describes version 1.0.4

<strong>SYNOPSIS</strong>

    ./cApTUrE --config <string> --interval_list <string> --run
    ./cApTUrE --config file.cfg --interval_list exon_regions.list --file sorted_bams.list --run
    ./cApTUrE --clean

<strong>DESCRIPTION</strong>

cApTUrE is a NGS pipeline written in Perl, created for the
<a href="http://weatherby.genetics.utah.edu/UGP/wiki/index.php/Main_Page" target="_blank">Utah Genome Project (UGP)</a>

Currently it incorporates the following tools:
<ul>
	<li>FastQC</li>
	<li>BWA</li>
	<li>SAMtools</li>
	<li>Picard</li>
	<li>GATK 3.0+</li>
</ul>

cApTUrE requires a config file given as the first commandline argument.
And all instructions and requirements are given therein.

GATKs best practices (with some modifications) are followed throughout this pipeline please refer to their site and the UGP wiki for more information.

<strong>INSTALLATION</strong>

<em>Perl Modules:</em>
Modules which cApTUrE requires.
<ul>
	<li>Moo</li>
	<li>MCE</li>
	<li>Config::Std</li>
	<li>IPC::System::Simple</li>
</ul>

<em>External required software:</em>
<ul>
	<li><a href="http://www.bioinformatics.babraham.ac.uk/projects/fastqc/" target="_blank">FastQC</a></li>
	<li><a href="http://bio-bwa.sourceforge.net" target="_blank">BWA</a></li>
	<li><a href="http://samtools.sourceforge.net" target="_blank">SAMtools</a></li>
	<li><a href="http://picard.sourceforge.net" target="_blank">Picard</a></li>
	<li><a href="http://www.broadinstitute.org/gatk/" target="_blank">GATK</a></li>
	<li><a href="http://www.r-project.org/" target="_blank">R</a></li>
</ul>
<strong>CONTENTS</strong>

cApTUrE's file structure:

cApTUrE/data:
<ul>
	<li><em>exon_Region.list</em> - Region file created for the standard UGP pipeline.</li>
	<li><em>exome.analysis.sequence.index</em> - 1000Genomes region file used to download exome data, used with Thousand_genome_recreator.pl.</li> 
	<li><em>capture.cfg</em> - This is the main configure file used to run the UGP pipeline, but can also be used as an example template for future project.
	<li><em>cluster.cfg</em> - This is the main configure file used to run the UGP pipeline on the CHPC cluster.
</ul>
cApTUrE/bin:
<ul>
	<li><em>cApTUrE</em> - main script</li>
</ul>
cApTUrE/bin/capture_tools:
<ul>
	<li><em>RegionMaker</em> - RegionMaker will download the current refseq GRCh37 GFF3 file and create a region file to be used with UnifiedGenotyper to decrease runtime when using a high number of background files.</li>
	<li><em>Thousand_genome_recreator.pl</em> - Will download 1000Genomes data from their site via ftp.</li>
	<li><em>UGP-SCP.pl</em> - Will assist in transfering large sets of fastq file to and from different servers.  Set for UGP and CHPC servers currently.</li>
</ul>

<strong>RUNNING CAPTURE:</strong>

After downloading and installing all dependences, a typical setup and run would follow these steps:

<em>Setting up the config file</em>:

config_creator has been created to help complete new configure files as needed.
Often many of the values in the config file can be set on a per-machine basis, creating essentially a new master file.  Examples of these would be known indel files, VQSR VCFs, BAM background files, and software paths.  Therefore what you will change each run will be the ugp_id, fastq dir, and possibly the run order.

<em>Running cApTUrE:</em>

It is recommend that the unix command <a href="http://www.computerhope.com/unix/screen.htm" target="_blank">screen</a> be used.

When cApTUrE runs it will create a number of log, list, error and report file.  One of these will be PROGRESS.  This file will keep track of each step of the order process, and is one that will be used and reviewed often throughout the pipeline; typically if you have failed runs.  Furthermore, a cmd.log file will be generated which will keep track of the times of each command and the commandlines each used.

Error tracking is usually done by reviewing error, log, progress and report files.

<strong>INCOMPATIBILITIES</strong>

None know, although not tested on Microsoft or OSX.

<strong>BUGS AND LIMITATIONS</strong>

Please report any bugs or feature requests to:
shawn.rynearson@gmail.com

<strong>AUTHOR</strong>
Shawn Rynearson &lt;shawn.rynearson@gmail.com&gt;

<strong>LICENCE AND COPYRIGHT</strong>
Copyright (c) 2013, Shawn Rynearson &lt;shawn.rynearson@gmail.com&gt;
All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

DISCLAIMER OF WARRANTY
BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO
WARRANTY FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE
LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS
AND/OR OTHER PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND
PERFORMANCE OF THE SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE
DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR,
OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN
WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY
AND/OR REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE,
BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR
INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR
THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER
SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF
THE POSSIBILITY OF SUCH DAMAGES.

&nbsp;

&nbsp;
