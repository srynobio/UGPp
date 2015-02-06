#!/usr/bin/env perl
use strict;
use warnings;

print "removing files...\n";
system("find . -name \"*intervals\" |perl -lane 'print \"rm $_\"'|xargs -I {} -P 10 bash -c {}");
system("find . -name \"*.gvcf\" |perl -lane 'print \"rm $_\"'|xargs -I {} -P 10 bash -c {}");
system("find . -name \"*table\" |perl -lane 'print \"rm $_\"'|xargs -I {} -P 10 bash -c {}");
system("find . -name \"*genotyped*\" |perl -lane 'print \"rm $_\"'|xargs -I {} -P 10 bash -c {}");
print "done!\n";
