&nbsp;

<strong>NAME</strong>

cApTUrE - vAriant collecTing UGP pipeline

<strong>VERSION</strong>

This document describes version 0.0.3

<strong>SYNOPSIS</strong>

./cApTUrE configure/capture.cfg -rr 3

<strong>DESCRIPTION</strong>

cApTUrE is a lightweight pipeline written in Perl, created for the
<a href="http://weatherby.genetics.utah.edu/UGP/wiki/index.php/Main_Page" target="_blank">Utah Genome Project (UGP)</a>

Currently it incorporates the following tools:
<ul>
	<li>FastQC</li>
	<li>BWA</li>
	<li>SAMtools</li>
	<li>Picard</li>
	<li>GATK</li>
</ul>

cApTUrE requires a config file given as the first commandline argument.
And all instructions and requirements are given therein.

GATKs best practices (with some modifications) are followed throughout this pipeline please refer to their site and the UGP wiki for more information.

<strong>INSTALLATION</strong>

<em>Perl Modules:</em>
These Modules are included with cApTUrE.
<ul>
	<li>Config::Std</li>
	<li>IPC::System::Simple</li>
	<li>Parallel::ForkManager</li>
	<li>List::MoreUtils</li>
</ul>

<em>External required software:</em>
<ul>
	<li><a href="http://www.bioinformatics.babraham.ac.uk/projects/fastqc/" target="_blank">FastQC</a></li>
	<li><a href="http://bio-bwa.sourceforge.net" target="_blank">BWA</a></li>
	<li><a href="http://samtools.sourceforge.net" target="_blank">SAMtools</a></li>
	<li><a href="http://picard.sourceforge.net" target="_blank">Picard</a></li>
	<li><a href="http://www.broadinstitute.org/gatk/" target="_blank">GATK</a></li>
</ul>
<strong>CONTENTS</strong>

cApTUrE's file structure:

cApTUrE/data:
<ul>
	<li><em>exon_Region.list</em> - Region file created for the standard UGP pipeline.</li>
</ul>
cApTUrE/bin:
<ul>
	<li><em>cApTUrE</em> - main script</li>
</ul>
cApTUrE/bin/configure:
<ul>
	<li><em>capture_master.cfg</em> - This is the main configure file used to run the UGP pipeline, but can also be used as an example template for future project.  This configure is also used to run ResourceAllocator</li>
</ul>
cApTUrE/bin/capture_tools:
<ul>
	<li><em>ResourceAllocator</em> -Take known resource information and reports best fit settings to allow cApTUrE to utilize all memory and cpu. ResourceAllocator will report best cpu and memory suggestions in addition to current config settings. Update option will allow configure file to reflect these changes.</li>
	<li><em>KillcApTUrE</em> - Often when running a large pipeline you will set the job to run in the background, KillcApTUrE allows users to kill all job assocated with their USER id, which will end all instances of cApTUrE, and any child jobs associated with it, i.e. bwa runs, etc.</li>
	<li><em>RegionMaker</em> - RegionMaker will download the current refseq GRCh37 GFF3 file and create a region file to be used with UnifiedGenotyper to decrease runtime when using a high number of background files.</li>
</ul>

<strong>RUNNING CAPTURE:</strong>

After downloading and installing all dependences, a typical setup and run would follow these steps:

<em>Setting up the config file</em>:

Often many of the values in the config file can be set on a per-machine basis, creating essentially a new master file.  Examples of these would be known indel files, VQSR VCFs, BAM background files, and software paths.  Therefore what you will change each run will be the ugp_id, fastq dir, and possibly the run order.  The cpu, and memory setting can change each run and <em>ResourceAllocator</em> will alter these values.

<em>Running cApTUrE:</em>

It is recommend that the unix command <a href="http://www.computerhope.com/unix/screen.htm" target="_blank">screen</a> be used.

When cApTUrE runs it will create a number of log, list, error and report file.  One of these will be progress.log.  This file will keep track of each step of the order process, and is one that will be used and reviewed often throughout the pipeline; typically if you have failed runs.  Also, as cApTUrE work through each step of the pipeline, it will create list files which are collections of BAM and VCF files from the previous steps.  Furthermore, a cmd.log file will be generated which will keep track of the times of each command and the commandlines each used.

Error tracking is usually done by reviewing error, log, progress and report files.

<strong>INCOMPATIBILITIES</strong>

None know, although not tested on Microsoft.

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
